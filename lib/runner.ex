defmodule ExMake.Runner do
    @moduledoc false

    @spec start(pid(), Keyword.t(), term(), pid()) :: pid()
    def start(coordinator, rule, data, owner) do
        spawn(fn() ->
            result = try do
                {run, args} = cond do
                    # Handle tasks.
                    rule[:name] ->
                        Enum.each(rule[:real_sources], fn(src) ->
                            if !File.exists?(src) do
                                raise(ExMake.UsageError, [description: "No rule to make target '#{src}'"])
                            end
                        end)

                        {true, [rule[:sources], rule[:name]]}
                    # Handle rules.
                    rule[:targets] ->
                        Enum.each(rule[:sources], fn(src) ->
                            if !File.exists?(src) do
                                raise(ExMake.UsageError, [description: "No rule to make target '#{src}'"])
                            end
                        end)

                        src_time = Enum.map(rule[:sources], fn(src) -> ExMake.Helpers.last_modified(src) end) |> Enum.max()
                        tgt_time = Enum.map(rule[:targets], fn(tgt) -> ExMake.Helpers.last_modified(tgt) end) |> Enum.min()

                        {src_time > tgt_time, [rule[:sources], rule[:targets]]}
                    # Handle fallbacks.
                    true ->
                        {true, []}
                end

                if run do
                    {m, f, a, _} = rule[:recipe]

                    # Add the directory as an argument if needed.
                    if a > length(args), do: args = args ++ [rule[:directory]]

                    cwd = File.cwd!()

                    apply(m, f, args)

                    if (ncwd = File.cwd!()) != cwd do
                        r = inspect(ExMake.Helpers.make_presentable(rule))

                        raise(ExMake.ScriptError,
                              [description: "Recipe for rule #{r} changed directory from '#{cwd}' to '#{ncwd}'"])
                    end

                    if tgts = rule[:targets] do
                        Enum.each(tgts, fn(tgt) ->
                            if !File.exists?(tgt) do
                                r = inspect(ExMake.Helpers.make_presentable(rule))

                                raise(ExMake.ScriptError,
                                      [description: "Recipe for rule #{r} did not produce #{tgt} as expected"])
                            end
                        end)
                    end
                end

                :ok
            catch
                val -> {:throw, val, System.stacktrace()}
            rescue
                ex -> {:raise, ex, System.stacktrace()}
            end

            if result != :ok do
                ExMake.Logger.log_debug("Caught #{elem(result, 0)} in runner: #{inspect(elem(result, 1))}")
                ExMake.Logger.log_debug(Exception.format_stacktrace(elem(result, 2)))

                # If the recipe failed, remove all target files.
                if tgts = rule[:targets], do: Enum.each(tgts, fn(tgt) -> File.rm(tgt) end)

                result = Tuple.delete_at(result, 2)
            end

            :gen_server.call(coordinator, {:done, rule, data, owner, result}, :infinity)
        end)
    end
end
