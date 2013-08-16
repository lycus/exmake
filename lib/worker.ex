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
    Locates the worker process. Returns the PID if found; otherwise,
    returns `nil`.
    """
    @spec locate() :: pid() | nil
    def locate() do
        Process.whereis(:exmake_worker)
    end

    @doc """
    Instructs the worker process to execute a script file specified by
    the configuration previously handed to the coordinator via the
    `ExMake.Coordinator.set_config/2` function. Returns the exit code
    of the operation.

    `timeout` must be `:infinity` or a millisecond value specifying
    how much time to wait for the operation to complete.
    """
    @spec work(timeout()) :: non_neg_integer()
    def work(timeout // :infinity) do
        code = :gen_server.call(locate(), :work, timeout)

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

        cfg = ExMake.Coordinator.get_config()

        if cfg.options()[:time] do
            ExMake.Coordinator.apply_timer_fn(fn(_) -> ExMake.Timer.create_session("ExMake Build Process") end)

            pass_go = fn(p) -> ExMake.Coordinator.apply_timer_fn(fn(s) -> ExMake.Timer.start_pass(s, p) end) end
            pass_end = fn(p) -> ExMake.Coordinator.apply_timer_fn(fn(s) -> ExMake.Timer.end_pass(s, p) end) end
        else
            # Makes the code below less ugly.
            pass_go = fn(_) -> end
            pass_end = fn(_) -> end
        end

        if cfg.options()[:clear], do: ExMake.Cache.clear_cache()

        file = cfg.options()[:file] || "Exmakefile"

        code = try do
            env_cached = ExMake.Cache.env_cached?()

            if env_cached, do: ExMake.Cache.load_env()

            mods = ExMake.Loader.load(".", file)

            if !env_cached, do: ExMake.Cache.save_env()

            files = Enum.map(mods, fn({d, f, _}) -> Path.join(d, f) end)

            g = if ExMake.Cache.graph_cache_stale?(files) do
                g = construct_graph(mods, pass_go, pass_end)

                # Cache the generated graph.
                ExMake.Cache.save_graph(g)

                g
            else
                ExMake.Cache.load_graph()
            end

            # Now create pruned graphs for each target and process them.
            # We have to do this after loading the cached graph because
            # the exact layout of the pruned graph depends on the target(s)
            # given to ExMake on the command line.
            Enum.each(cfg.targets(), fn(tgt) ->
                pass_go.("Locate Vertex (#{tgt})")

                rule = ExMake.Helpers.get_target(g, tgt)

                pass_end.("Locate Vertex (#{tgt})")

                if !rule, do: raise(ExMake.UsageError[description: "Target '#{tgt}' not found"])

                {v, _} = rule

                pass_go.("Minimize DAG (#{tgt})")

                # Eliminate everything else in the graph.
                reachable = :digraph_utils.reachable([v], g)
                g2 = :digraph_utils.subgraph(g, reachable)

                pass_end.("Minimize DAG (#{tgt})")

                # Process leaves until the graph is empty. If we're running
                # in --question mode, only check staleness of files.
                if cfg.options()[:question] do
                    process_graph_question(g2, pass_go, pass_end)
                else
                    process_graph(g2, pass_go, pass_end)
                end
            end)

            if cfg.options()[:time] do
                ExMake.Coordinator.apply_timer_fn(fn(session) ->
                    ExMake.Logger.info(ExMake.Timer.format_session(ExMake.Timer.finish_session(session)))

                    nil
                end)
            end

            0
        rescue
            [ExMake.StaleError] ->
                # This is only raised in --question mode, and just means
                # that a rule has stale targets. So simply return 1.
                1
            ex ->
                ExMake.Logger.error(inspect(elem(ex, 0)), ex.message())
                ExMake.Logger.debug(Exception.format_stacktrace(System.stacktrace()))
                1
        end

        {:reply, code, nil}
    end

    @spec construct_graph([{Path.t(), Path.t(), module()}, ...], ((atom()) -> :ok), ((atom()) -> :ok)) :: digraph()
    defp construct_graph(mods, pass_go, pass_end) do
        pass_go.("Check Rule Specifications")

        Enum.each(mods, fn({d, f, m}) ->
            Enum.each(m.__exmake__(:rules), fn(spec) ->
                tgts = spec[:targets]
                srcs = spec[:sources]
                loc = "#{Path.join(d, f)}:#{elem(spec[:recipe], 3)}"

                if !is_list(tgts) || Enum.any?(tgts, fn(t) -> !String.valid?(t) end) do
                    raise(ExMake.ScriptError[description: "#{loc}: Invalid target list; must be a list of strings"])
                end

                if !is_list(srcs) || Enum.any?(srcs, fn(s) -> !String.valid?(s) end) do
                    raise(ExMake.ScriptError[description: "#{loc}: Invalid source list; must be a list of strings"])
                end
            end)

            Enum.each(m.__exmake__(:phony_rules), fn(spec) ->
                name = spec[:name]
                srcs = spec[:sources]
                loc = "#{Path.join(d, f)}:#{elem(spec[:recipe], 3)}"

                if !String.valid?(name) do
                    raise(ExMake.ScriptError[description: "#{loc}: Invalid phony rule name; must be a string"])
                end

                if !is_list(srcs) || Enum.any?(srcs, fn(s) -> !is_binary(s) || !String.valid?(s) end) do
                    raise(ExMake.ScriptError[description: "#{loc}: Invalid source list; must be a list of strings"])
                end
            end)
        end)

        pass_end.("Check Rule Specifications")

        pass_go.("Sanitize Rule Paths")

        # Make paths relative to the ExMake invocation directory.
        rules = List.concat(Enum.map(mods, fn({d, _, m}) ->
            Enum.map(m.__exmake__(:rules), fn(spec) ->
                tgts = Enum.map(spec[:targets], fn(f) -> Path.join(d, f) end)
                srcs = Enum.map(spec[:sources], fn(f) -> Path.join(d, f) end)

                [targets: tgts, sources: srcs, recipe: spec[:recipe], directory: d]
            end)
        end))

        pass_end.("Sanitize Rule Paths")

        pass_go.("Sanitize Phony Rule Paths")

        # Do the same for phony rules.
        phony_rules = List.concat(Enum.map(mods, fn({d, _, m}) ->
            Enum.map(m.__exmake__(:phony_rules), fn(spec) ->
                name = Path.join(d, spec[:name])
                srcs = Enum.map(spec[:sources], fn(f) -> Path.join(d, f) end)

                [name: name, sources: srcs, recipe: spec[:recipe], directory: d]
            end)
        end))

        pass_end.("Sanitize Phony Rule Paths")

        pass_go.("Check Rule Target Lists")

        target_names = rules |>
                       Enum.map(fn(x) -> x[:targets] end) |>
                       List.concat()

        target_names = Enum.reduce(target_names, HashSet.new(), fn(n, set) ->
            if Set.member?(set, n) do
                raise(ExMake.ScriptError[description: "Multiple rules mention target '#{n}'"])
            end

            Set.put(set, n)
        end)

        pass_end.("Check Rule Target Lists")

        pass_go.("Check Phony Rule Names")

        Enum.each(phony_rules, fn(p) ->
            if Set.member?(target_names, n = p[:name]) do
                raise(ExMake.ScriptError[description: "Phony rule name '#{n}' conflicts with a rule"])
            end
        end)

        pass_end.("Check Phony Rule Names")

        g = :digraph.new([:acyclic])

        pass_go.("Create DAG Vertices")

        # Add the rules to the graph as vertices.
        Enum.each(rules, fn(r) -> :digraph.add_vertex(g, :digraph.add_vertex(g), r) end)
        Enum.each(phony_rules, fn(r) -> :digraph.add_vertex(g, :digraph.add_vertex(g), r) end)

        pass_end.("Create DAG Vertices")

        vs = :digraph.vertices(g)

        pass_go.("Create DAG Edges")

        # Construct edges from goals to dependencies.
        Enum.each(vs, fn(v) ->
            {_, r} = :digraph.vertex(g, v)

            Enum.each(r[:sources], fn(src) ->
                dep = Enum.find_value(vs, fn(v2) ->
                    {_, r2} = :digraph.vertex(g, v2)

                    cond do
                        (t = r2[:targets]) && src in t -> {v2, r2}
                        (n = r2[:name]) && n == src -> {v2, r2}
                        true -> nil
                    end
                end)

                if dep do
                    {v2, r2} = dep

                    if r[:targets] && (n = r2[:name]) do
                        r = r |>
                            Keyword.delete(:recipe) |>
                            Keyword.delete(:directory) |>
                            inspect()

                        raise(ExMake.ScriptError[description: "Rule #{r} depends on phony rule '#{n}'"])
                    end

                    case :digraph.add_edge(g, v, v2) do
                        {:error, {:bad_edge, path}} ->
                            [r1, r2] = [:digraph.vertex(g, hd(path)), :digraph.vertex(g, List.last(path))] |>
                                       Enum.map(fn(x) -> elem(x, 1) end) |>
                                       Enum.map(fn(x) -> Keyword.delete(x, :recipe) end) |>
                                       Enum.map(fn(x) -> Keyword.delete(x, :directory) end) |>
                                       Enum.map(fn(x) -> inspect(x) end)

                            msg = "Cyclic dependency detected between\n#{r1}\nand\n#{r2}"

                            raise(ExMake.ScriptError[description: msg])
                        _ -> :ok
                    end
                end
            end)
        end)

        pass_end.("Create DAG Edges")

        g
    end

    @spec process_graph(digraph(), ((atom()) -> :ok), ((atom()) -> :ok), non_neg_integer()) :: :ok
    defp process_graph(graph, pass_go, pass_end, n // 0) do
        pass_go.("Compute Leaves (#{n})")

        # Compute the leaf vertices. These have no outgoing edges.
        leaves = Enum.filter(:digraph.vertices(graph), fn(v) -> :digraph.out_degree(graph, v) == 0 end)

        pass_end.("Compute Leaves (#{n})")

        pass_go.("Enqueue Jobs (#{n})")

        # Enqueue jobs for all leaves.
        Enum.each(leaves, fn(v) ->
            {_, r} = :digraph.vertex(graph, v)

            ExMake.Logger.debug("Enqueuing rule: #{inspect(r)}")

            ExMake.Coordinator.enqueue(r)
        end)

        pass_end.("Enqueue Jobs (#{n})")

        pass_go.("Wait for Jobs (#{n})")

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

        pass_end.("Wait for Jobs (#{n})")

        # Process the next 'wave' of leaf nodes, if any.
        if :digraph.no_vertices(graph) == 0, do: :ok, else: process_graph(graph, pass_go, pass_end, n + 1)
    end

    @spec process_graph_question(digraph(), ((atom()) -> :ok), ((atom()) -> :ok), non_neg_integer()) :: :ok
    defp process_graph_question(graph, pass_go, pass_end, n // 0) do
        pass_go.("Compute Leaves (#{n})")

        # Compute the leaf vertices. These have no outgoing edges.
        leaves = Enum.filter(:digraph.vertices(graph), fn(v) -> :digraph.out_degree(graph, v) == 0 end)

        pass_end.("Compute Leaves (#{n})")

        pass_go.("Check Timestamps (#{n})")

        Enum.each(leaves, fn(v) ->
            {_, r} = :digraph.vertex(graph, v)

            stale = if r[:name] do
                ExMake.Logger.warn("'--question' with phony rules is meaningless; they are always considered stale")

                true
            else
                Enum.each(r[:sources], fn(src) ->
                    if !File.exists?(src) do
                        raise(ExMake.UsageError[description: "No rule to make target '#{src}'"])
                    end
                end)

                src_time = Enum.map(r[:sources], fn(src) -> ExMake.Helpers.last_modified(src) end) |> Enum.max()
                tgt_time = Enum.map(r[:targets], fn(tgt) -> ExMake.Helpers.last_modified(tgt) end) |> Enum.min()

                src_time > tgt_time
            end

            if stale, do: raise(ExMake.StaleError[rule: r])

            :digraph.del_vertex(graph, v)
        end)

        pass_end.("Check Timestamps (#{n})")

        if :digraph.no_vertices(graph) == 0, do: :ok, else: process_graph_question(graph, pass_go, pass_end, n + 1)
    end
end
