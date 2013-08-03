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

        cfg = ExMake.Coordinator.get_config(ExMake.Coordinator.locate())
        file = cfg.options()[:file] || "Exmakefile"

        code = try do
            mods = ExMake.Loader.load(".", file)

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

            g = :digraph.new([:acyclic])

            # Add the rules to the graph as vertices.
            Enum.each(rules, fn(r) -> :digraph.add_vertex(g, :digraph.add_vertex(g), r) end)
            Enum.each(phony_rules, fn(r) -> :digraph.add_vertex(g, :digraph.add_vertex(g), r) end)

            vs = :digraph.vertices(g)

            # Construct edges from goals to dependencies.
            Enum.each(vs, fn(v) ->
                {_, r} = :digraph.vertex(g, v)

                Enum.each(r[:sources], fn(src) ->
                    v2 = Enum.find(vs, fn(v2) ->
                        {_, r2} = :digraph.vertex(g, v2)

                        cond do
                            t = r2[:targets] -> Enum.member?(t, src)
                            n = r2[:name] -> n == src
                            true -> false
                        end
                    end)

                    if v2, do: :digraph.add_edge(g, v, v2)
                end)
            end)

            # Locate the targets we care about.
            tasks = Enum.map(cfg.targets(), fn(tgt) ->
                rule = ExMake.Helpers.get_target(g, tgt)

                if !rule, do: raise(ExMake.UsageError[description: "Target '#{tgt}' not found"])

                ExMake.Logger.debug("Marking requested rule: #{inspect(elem(rule, 1))}")

                rule
            end)

            # Turn them into vertices.
            verts = Enum.map(tasks, fn({v, _}) -> v end)

            # Eliminate everything else in the graph.
            reachable = :digraph_utils.reachable(verts, g)
            g2 = :digraph_utils.subgraph(g, reachable)

            # Process leaves until the graph is empty.
            process_graph(g2)

            0
        rescue
            ex ->
                ExMake.Logger.error(ex.message())
                ExMake.Logger.debug(Exception.format_stacktrace(System.stacktrace()))
                1
        end

        {:reply, code, nil}
    end

    @spec process_graph(digraph()) :: :ok
    defp process_graph(graph) do
        # Compute the leaf vertices. These have no outgoing edges.
        leaves = Enum.filter(:digraph.vertices(graph), fn(v) -> :digraph.out_degree(graph, v) == 0 end)

        # Enqueue jobs for all leaves.
        Enum.each(leaves, fn(v) ->
            {_, r} = :digraph.vertex(graph, v)

            ExMake.Logger.debug("Enqueuing rule: #{inspect(r)}")

            ExMake.Coordinator.enqueue(ExMake.Coordinator.locate(), r)
        end)

        # Wait for all jobs to report back.
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

        # Process the next 'wave' of leaf nodes, if any.
        if :digraph.no_vertices(graph) == 0, do: :ok, else: process_graph(graph)
    end
end
