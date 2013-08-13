defmodule ExMake.Worker do
    @moduledoc """
    Encapsulates a worker process that executes a script file and returns
    the exit code for the execution. Can be supervised by an OTP supervisor.
    """

    use GenServer.Behaviour

    @doc """
    Starts a worker process linked to the parent process. Returns `{:ok, pid}`
    on success.
    """
    @spec start_link() :: {:ok, pid()}
    def start_link() do
        tup = {:ok, pid} = :gen_server.start_link(__MODULE__, nil, [])
        Process.register(pid, :exmake_worker)
        tup
    end

    @doc """
    Locates a worker process. Returns the PID if found; otherwise,
    returns `nil`.
    """
    @spec locate() :: pid() | nil
    def locate() do
        Process.whereis(:exmake_worker)
    end

    @doc """
    Instructs the given worker process to execute a script file specified
    by the given configuration. Returns the exit code of the operation.

    `pid` must be the PID of an `ExMake.Worker` process. `timeout` must be
    `:infinity` or a millisecond value specifying how much time to wait
    for the operation to complete.
    """
    @spec work(pid(), timeout()) :: non_neg_integer()
    def work(pid, timeout // :infinity) do
        code = :gen_server.call(pid, :work, timeout)

        _ = case :application.get_env(:exmake, :exmake_event_pid) do
            {:ok, pid} -> pid <- {:exmake_shutdown, code}
            :undefined -> :ok
        end

        code
    end

    @doc false
    @spec handle_call(:work, {pid(), term()}, nil) :: {:reply, non_neg_integer(), nil}
    def handle_call(:work, _, nil) do
        Enum.each(ExMake.Libraries.search_paths(), fn(x) -> ExMake.Libraries.append_path(x) end)

        coord = ExMake.Coordinator.locate()
        cfg = ExMake.Coordinator.get_config(coord)

        if cfg.options()[:time] do
            ExMake.Coordinator.apply_timer_fn(coord, fn(_) -> ExMake.Timer.create_session("ExMake Build Process") end)

            pass_go = fn(p) -> ExMake.Coordinator.apply_timer_fn(coord, fn(s) -> ExMake.Timer.start_pass(s, p) end) end
            pass_end = fn(p) -> ExMake.Coordinator.apply_timer_fn(coord, fn(s) -> ExMake.Timer.end_pass(s, p) end) end
        else
            # Makes the code below less ugly.
            pass_go = fn(_) -> end
            pass_end = fn(_) -> end
        end

        file = cfg.options()[:file] || "Exmakefile"

        code = try do
            mods = ExMake.Loader.load(".", file)

            pass_go.(:sanitize_paths)

            # Make paths relative to the ExMake invocation directory.
            rules = List.concat(Enum.map(mods, fn({d, _, m}) ->
                Enum.map(m.__exmake__(:rules), fn(spec) ->
                    tgts = Enum.map(spec[:targets], fn(f) -> Path.join(d, f) end)
                    srcs = Enum.map(spec[:sources], fn(f) -> Path.join(d, f) end)

                    [targets: tgts, sources: srcs, recipe: spec[:recipe], directory: d]
                end)
            end))

            # Do the same for phony rules.
            phony_rules = List.concat(Enum.map(mods, fn({d, _, m}) ->
                Enum.map(m.__exmake__(:phony_rules), fn(spec) ->
                    name = Path.join(d, spec[:name])
                    srcs = Enum.map(spec[:sources], fn(f) -> Path.join(d, f) end)

                    [name: name, sources: srcs, recipe: spec[:recipe], directory: d]
                end)
            end))

            pass_end.(:sanitize_paths)

            g = :digraph.new([:acyclic])

            pass_go.(:create_vertices)

            # Add the rules to the graph as vertices.
            Enum.each(rules, fn(r) -> :digraph.add_vertex(g, :digraph.add_vertex(g), r) end)
            Enum.each(phony_rules, fn(r) -> :digraph.add_vertex(g, :digraph.add_vertex(g), r) end)

            pass_end.(:create_vertices)

            vs = :digraph.vertices(g)

            pass_go.(:create_edges)

            # Construct edges from goals to dependencies.
            Enum.each(vs, fn(v) ->
                {_, r} = :digraph.vertex(g, v)

                Enum.each(r[:sources], fn(src) ->
                    v2 = Enum.find(vs, fn(v2) ->
                        {_, r2} = :digraph.vertex(g, v2)

                        cond do
                            t = r2[:targets] -> src in t
                            n = r2[:name] -> n == src
                            true -> false
                        end
                    end)

                    if v2, do: :digraph.add_edge(g, v, v2)
                end)
            end)

            pass_end.(:create_edges)

            pass_go.(:locate_targets)

            # Locate the targets we care about.
            tasks = Enum.map(cfg.targets(), fn(tgt) ->
                rule = ExMake.Helpers.get_target(g, tgt)

                if !rule, do: raise(ExMake.UsageError[description: "Target '#{tgt}' not found"])

                ExMake.Logger.debug("Marking requested rule: #{inspect(elem(rule, 1))}")

                rule
            end)

            pass_end.(:locate_targets)

            # Turn them into vertices.
            verts = Enum.map(tasks, fn({v, _}) -> v end)

            pass_go.(:minimize_graph)

            # Eliminate everything else in the graph.
            reachable = :digraph_utils.reachable(verts, g)
            g2 = :digraph_utils.subgraph(g, reachable)

            pass_end.(:minimize_graph)

            # Process leaves until the graph is empty.
            process_graph(coord, g2, pass_go, pass_end)

            if cfg.options()[:time] do
                ExMake.Coordinator.apply_timer_fn(coord, fn(session) ->
                    ExMake.Logger.info(ExMake.Timer.format_session(ExMake.Timer.finish_session(session)))

                    nil
                end)
            end

            0
        rescue
            ex ->
                ExMake.Logger.error(ex.message())
                ExMake.Logger.debug(Exception.format_stacktrace(System.stacktrace()))
                1
        end

        {:reply, code, nil}
    end

    @spec process_graph(pid(), digraph(), ((atom()) -> :ok), ((atom()) -> :ok), non_neg_integer()) :: :ok
    defp process_graph(coord, graph, pass_go, pass_end, n // 0) do
        pass_go.(:"compute_leaves_#{n}")

        # Compute the leaf vertices. These have no outgoing edges.
        leaves = Enum.filter(:digraph.vertices(graph), fn(v) -> :digraph.out_degree(graph, v) == 0 end)

        pass_end.(:"compute_leaves_#{n}")

        pass_go.(:"enqueue_jobs_#{n}")

        # Enqueue jobs for all leaves.
        Enum.each(leaves, fn(v) ->
            {_, r} = :digraph.vertex(graph, v)

            ExMake.Logger.debug("Enqueuing rule: #{inspect(r)}")

            ExMake.Coordinator.enqueue(coord, r)
        end)

        pass_end.(:"enqueue_jobs_#{n}")

        pass_go.(:"wait_jobs_#{n}")

        # Wait for all jobs to report back. This is not the most optimal
        # approach as we may end up waiting for one job to finish while,
        # say, 3 other jobs are ready to be enqueued. This really should
        # be optimized at some point.
        Enum.each(leaves, fn(v) ->
            {ex, rule} = receive do
                {:exmake_done, r, :ok} -> {nil, r}
                {:exmake_done, r, {:throw, val}} -> {ExMake.ThrowError[value: val], r}
                {:exmake_done, r, {:raise, ex}} -> {ex, r}
            end

            ExMake.Logger.debug("Job done for rule: #{inspect(rule)}")

            if ex, do: raise(ex)

            # Note that v doesn't necessarily match the message we just
            # received. It doesn't matter, however, as we just need to
            # remove it from the graph and receive length(leaves) "done"
            # messages in the process.
            :digraph.del_vertex(graph, v)
        end)

        pass_end.(:"wait_jobs_#{n}")

        # Process the next 'wave' of leaf nodes, if any.
        if :digraph.no_vertices(graph) == 0, do: :ok, else: process_graph(coord, graph, pass_go, pass_end, n + 1)
    end
end
