defmodule ExMake.Worker do
    @moduledoc """
    Encapsulates a worker process that executes a script file and returns
    the exit code for the execution. Can be supervised by an OTP supervisor.
    """

    use GenServer.Behaviour

    @doc false
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
    def work(timeout \\ :infinity) do
        code = :gen_server.call(locate(), :work, timeout)

        _ = case :application.get_env(:exmake, :exmake_event_pid) do
            {:ok, pid} -> send(pid, {:exmake_shutdown, code})
            :undefined -> :ok
        end

        code
    end

    @doc false
    @spec handle_call(:work, {pid(), term()}, nil) :: {:reply, non_neg_integer(), nil}
    def handle_call(:work, _, nil) do
        ExMake.Coordinator.clear_libraries()

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

        file = cfg.options()[:file] || "Exmakefile"

        Process.put(:exmake_jobs, 0)

        code = try do
            File.cd!(Path.dirname(file))

            pass_go.("Set Library Paths")

            Enum.each(ExMake.Libraries.search_paths(), fn(x) -> ExMake.Libraries.append_path(x) end)

            pass_end.("Set Library Paths")

            # Slight optimization: If we're clearing the
            # cache, then it's definitely stale.
            stale = if cfg.options()[:clear] do
                pass_go.("Clear Build Cache")

                ExMake.Cache.clear_cache()

                pass_end.("Clear Build Cache")

                true
            else
                pass_go.("Check Cache Timestamps")

                stale = ExMake.Cache.cache_stale?()

                pass_end.("Check Cache Timestamps")

                stale
            end

            {g, f} = if stale do
                # If the cache is stale and the configuration
                # files exist, we should still load them and
                # attempt to use them since we'll be running
                # all sorts of configuration logic again.
                if ExMake.Cache.config_cached?() do
                    pass_go.("Load Configuration Cache")

                    {args, vars} = ExMake.Cache.load_config()

                    Enum.each(vars, fn({k, v}) -> if !System.get_env(k), do: System.put_env(k, v) end)

                    if cfg.args() == [], do: ExMake.Coordinator.set_config(cfg = cfg.args(args))

                    pass_end.("Load Configuration Cache")
                end

                pass_go.("Load Script Files")

                mods = ExMake.Loader.load(".", file)

                pass_end.("Load Script Files")

                pass_go.("Save Module Cache")

                ExMake.Cache.save_mods(Enum.map(mods, fn({_, _, m, c}) -> {m, c} end))

                pass_end.("Save Module Cache")

                pass_go.("Save Environment Cache")

                ExMake.Cache.save_env()

                pass_end.("Save Environment Cache")

                g = construct_graph(Enum.map(mods, fn({d, f, m, _}) -> {d, f, m} end), pass_go, pass_end)

                pass_go.("Save Graph Cache")

                # Cache the generated graph.
                ExMake.Cache.save_graph(g)

                pass_end.("Save Graph Cache")

                # We only care about the fallbacks in the entry
                # point script, and don't need to check anything.
                f = elem(hd(mods), 2).__exmake__(:fallbacks)

                pass_go.("Save Fallback Cache")

                ExMake.Cache.save_fallbacks(f)

                pass_end.("Save Fallback Cache")

                pass_go.("Save Configuration Cache")

                vars = ExMake.Coordinator.get_libraries() |>
                       Enum.map(fn(m) -> m.__exmake__(:precious) end) |>
                       Enum.concat() |>
                       Enum.map(fn(v) -> {v, System.get_env(v)} end) |>
                       Enum.filter(fn({_, v}) -> v end)

                ExMake.Cache.save_config(cfg.args(), vars)

                pass_end.("Save Configuration Cache")

                pass_go.("Check Manifest Specifications")

                manifest_files = Enum.concat(Enum.map(mods, fn({d, _, m, _}) ->
                    Enum.map(m.__exmake__(:manifest), fn(file) ->
                        if !String.valid?(file) do
                            raise(ExMake.ScriptError, [description: "Manifest file must be a string"])
                        end

                        Path.join(d, file)
                    end)
                end))

                pass_end.("Check Manifest Specifications")

                pass_go.("Save Cache Manifest")

                manifest_mods = Enum.map(mods, fn({d, f, _, _}) -> Path.join(d, f) end)

                ExMake.Cache.append_manifest(manifest_mods ++ manifest_files)

                pass_end.("Save Cache Manifest")

                {g, f}
            else
                pass_go.("Load Module Cache")

                ExMake.Cache.load_mods()

                pass_end.("Load Module Cache")

                pass_go.("Load Environment Cache")

                ExMake.Cache.load_env()

                pass_end.("Load Environment Cache")

                pass_go.("Load Graph Cache")

                g = ExMake.Cache.load_graph()

                pass_end.("Load Graph Cache")

                pass_go.("Load Fallback Cache")

                f = ExMake.Cache.load_fallbacks()

                pass_end.("Load Fallback Cache")

                {g, f}
            end

            tgts = Enum.map(cfg.targets(), fn(tgt) ->
                pass_go.("Locate Vertex (#{tgt})")

                rule = ExMake.Helpers.get_target(g, tgt)

                pass_end.("Locate Vertex (#{tgt})")

                {tgt, rule}
            end)

            bad = Enum.find(tgts, fn({_, r}) -> !r end)

            if bad do
                # Process fallbacks serially if we have any.
                Enum.each(f, fn(r) ->
                    ExMake.Coordinator.enqueue(r, nil)

                    receive do
                        {:exmake_done, _, _, _} -> :ok
                    end
                end)

                raise(ExMake.UsageError, [description: "Target '#{elem(bad, 0)}' not found"])
            end

            # Now create pruned graphs for each target and process them.
            # We have to do this after loading the cached graph because
            # the exact layout of the pruned graph depends on the target(s)
            # given to ExMake on the command line.
            Enum.each(tgts, fn({tgt, rule}) ->
                {v, _} = rule

                pass_go.("Minimize DAG (#{tgt})")

                # Eliminate everything else in the graph.
                reachable = :digraph_utils.reachable([v], g)
                g2 = :digraph_utils.subgraph(g, reachable)

                pass_end.("Minimize DAG (#{tgt})")

                # Process leaves until the graph is empty. If we're running
                # in --question mode, only check staleness of files.
                if cfg.options()[:question] do
                    process_graph_question(tgt, g2, pass_go, pass_end)
                else
                    pass_go.("Prepare DAG (#{tgt})")

                    # Transform the labels into {rule, status} tuples.
                    Enum.each(:digraph.vertices(g2), fn(v) ->
                        {_, r} = :digraph.vertex(g2, v)

                        :digraph.add_vertex(g2, v, {r, :pending})
                    end)

                    pass_end.("Prepare DAG (#{tgt})")

                    process_graph(tgt, g2, pass_go, pass_end)
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
                ExMake.Logger.log_debug(Exception.format_stacktrace(System.stacktrace()))

                # Wait for all remaining jobs to stop.
                if (n = Process.get(:exmake_jobs)) > 0 do
                    ExMake.Logger.log_debug("Waiting for #{n} jobs to exit")

                    Enum.each(1 .. n, fn(_) ->
                        receive do
                            {:exmake_done, _, _, _} -> :ok
                        end
                    end)
                end

                1
        end

        File.cd!("..")

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
                    raise(ExMake.ScriptError, [description: "#{loc}: Invalid target list; must be a list of strings"])
                end

                if !is_list(srcs) || Enum.any?(srcs, fn(s) -> !String.valid?(s) end) do
                    raise(ExMake.ScriptError, [description: "#{loc}: Invalid source list; must be a list of strings"])
                end
            end)

            Enum.each(m.__exmake__(:tasks), fn(spec) ->
                name = spec[:name]
                srcs = spec[:sources]
                loc = "#{Path.join(d, f)}:#{elem(spec[:recipe], 3)}"

                if !String.valid?(name) do
                    raise(ExMake.ScriptError, [description: "#{loc}: Invalid task name; must be a string"])
                end

                if !is_list(srcs) || Enum.any?(srcs, fn(s) -> !is_binary(s) || !String.valid?(s) end) do
                    raise(ExMake.ScriptError, [description: "#{loc}: Invalid source list; must be a list of strings"])
                end
            end)
        end)

        pass_end.("Check Rule Specifications")

        pass_go.("Sanitize Rule Paths")

        # Make paths relative to the ExMake invocation directory.
        rules = Enum.concat(Enum.map(mods, fn({d, _, m}) ->
            Enum.map(m.__exmake__(:rules), fn(spec) ->
                tgts = Enum.map(spec[:targets], fn(f) -> Path.join(d, f) end)
                srcs = Enum.map(spec[:sources], fn(f) -> Path.join(d, f) end)

                [targets: tgts, sources: srcs, recipe: spec[:recipe], directory: d]
            end)
        end))

        pass_end.("Sanitize Rule Paths")

        pass_go.("Sanitize Task Paths")

        # Do the same for tasks.
        tasks = Enum.concat(Enum.map(mods, fn({d, _, m}) ->
            Enum.map(m.__exmake__(:tasks), fn(spec) ->
                name = Path.join(d, spec[:name])
                srcs = Enum.map(spec[:sources], fn(f) -> Path.join(d, f) end)

                [name: name, sources: srcs, recipe: spec[:recipe], directory: d]
            end)
        end))

        pass_end.("Sanitize Task Paths")

        pass_go.("Check Rule Target Lists")

        target_names = rules |>
                       Enum.map(fn(x) -> x[:targets] end) |>
                       Enum.concat()

        target_names = Enum.reduce(target_names, HashSet.new(), fn(n, set) ->
            if Set.member?(set, n) do
                raise(ExMake.ScriptError, [description: "Multiple rules mention target '#{n}'"])
            end

            Set.put(set, n)
        end)

        pass_end.("Check Rule Target Lists")

        pass_go.("Check Task Names")

        task_names = Enum.reduce(tasks, HashSet.new(), fn(p, set) ->
            n = p[:name]

            if Set.member?(target_names, n) do
                raise(ExMake.ScriptError, [description: "Task name '#{n}' conflicts with a rule"])
            end

            Set.put(set, n)
        end)

        pass_end.("Check Task Names")

        pass_go.("Determine Task Sources")

        tasks = Enum.map(tasks, fn(r) ->
            srcs = Set.difference(HashSet.new(r[:sources]), task_names)

            Keyword.put(r, :real_sources, srcs)
        end)

        pass_end.("Determine Task Sources")

        pass_go.("Create DAG")

        g = :digraph.new([:acyclic])

        pass_end.("Create DAG")

        pass_go.("Create DAG Vertices")

        # Add the rules to the graph as vertices.
        Enum.each(rules, fn(r) -> :digraph.add_vertex(g, :digraph.add_vertex(g), r) end)
        Enum.each(tasks, fn(r) -> :digraph.add_vertex(g, :digraph.add_vertex(g), r) end)

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
                        r = inspect(ExMake.Helpers.make_presentable(r))

                        raise(ExMake.ScriptError, [description: "Rule #{r} depends on task '#{n}'"])
                    end

                    case :digraph.add_edge(g, v, v2) do
                        {:error, {:bad_edge, path}} ->
                            [r1, r2] = [:digraph.vertex(g, hd(path)), :digraph.vertex(g, List.last(path))] |>
                                       Enum.map(fn(x) -> elem(x, 1) end) |>
                                       Enum.map(fn(x) -> ExMake.Helpers.make_presentable(x) end) |>
                                       Enum.map(fn(x) -> inspect(x) end)

                            raise(ExMake.ScriptError,
                                  [description: "Cyclic dependency detected between\n#{r1}\nand\n#{r2}"])
                        _ -> :ok
                    end
                end
            end)
        end)

        pass_end.("Create DAG Edges")

        g
    end

    @spec process_graph(String.t(), digraph(), ((atom()) -> :ok), ((atom()) -> :ok), non_neg_integer()) :: :ok
    defp process_graph(target, graph, pass_go, pass_end, n \\ 0) do
        verts = :digraph.vertices(graph)

        if verts != [] do
            pass_go.("Compute Leaves (#{target} - #{n})")

            # Compute the leaf vertices. These have no outgoing edges
            # and have a status of :pending.
            leaves = Enum.filter(verts, fn(v) ->
                :digraph.out_degree(graph, v) == 0 && elem(elem(:digraph.vertex(graph, v), 1), 1) == :pending
            end)

            pass_end.("Compute Leaves (#{target} - #{n})")

            pass_go.("Enqueue Jobs (#{target} - #{n})")

            # Enqueue jobs for all leaves.
            Enum.each(leaves, fn(v) ->
                {_, {r, _}} = :digraph.vertex(graph, v)

                ExMake.Logger.log_debug("Enqueuing rule: #{inspect(r)}")

                ExMake.Coordinator.enqueue(r, v)

                :digraph.add_vertex(graph, v, {r, :processing})

                Process.put(:exmake_jobs, Process.get(:exmake_jobs) + 1)
            end)

            pass_end.("Enqueue Jobs (#{target} - #{n})")

            pass_go.("Wait for Job (#{target} - #{n})")

            {ex, v, rule} = receive do
                {:exmake_done, r, v, :ok} -> {nil, v, r}
                {:exmake_done, r, v, {:throw, val}} -> {ExMake.ThrowError[value: val], v, r}
                {:exmake_done, r, v, {:raise, ex}} -> {ex, v, r}
            end

            ExMake.Logger.log_debug("Job done for rule: #{inspect(rule)}")

            Process.put(:exmake_jobs, Process.get(:exmake_jobs) - 1)

            if ex, do: raise(ex)

            :digraph.del_vertex(graph, v)

            pass_end.("Wait for Job (#{target} - #{n})")

            process_graph(target, graph, pass_go, pass_end, n + 1)
        else
            # The graph has been reduced to nothing, so we're done.
            :ok
        end
    end

    @spec process_graph_question(String.t(), digraph(), ((atom()) -> :ok), ((atom()) -> :ok), non_neg_integer()) :: :ok
    defp process_graph_question(target, graph, pass_go, pass_end, n \\ 0) do
        pass_go.("Compute Leaves (#{target} - #{n})")

        # Compute the leaf vertices. These have no outgoing edges.
        leaves = Enum.filter(:digraph.vertices(graph), fn(v) -> :digraph.out_degree(graph, v) == 0 end)

        pass_end.("Compute Leaves (#{target} - #{n})")

        pass_go.("Check Timestamps (#{target} - #{n})")

        Enum.each(leaves, fn(v) ->
            {_, r} = :digraph.vertex(graph, v)

            stale = if r[:name] do
                ExMake.Logger.warn("'--question' with tasks is meaningless; they are always considered stale")

                true
            else
                Enum.each(r[:sources], fn(src) ->
                    if !File.exists?(src) do
                        raise(ExMake.UsageError, [description: "No rule to make target '#{src}'"])
                    end
                end)

                src_time = Enum.map(r[:sources], fn(src) -> ExMake.Helpers.last_modified(src) end) |> Enum.max()
                tgt_time = Enum.map(r[:targets], fn(tgt) -> ExMake.Helpers.last_modified(tgt) end) |> Enum.min()

                src_time > tgt_time
            end

            if stale, do: raise(ExMake.StaleError, [rule: r])

            :digraph.del_vertex(graph, v)
        end)

        pass_end.("Check Timestamps (#{target} - #{n})")

        if :digraph.no_vertices(graph) == 0, do: :ok, else: process_graph_question(target, graph, pass_go, pass_end, n + 1)
    end
end
