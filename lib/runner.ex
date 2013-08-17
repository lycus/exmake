defmodule ExMake.Runner do
    @moduledoc """
    Encapsulates the processes that are used to actually execute recipes
    in a script file.

    This module is only meant to be consumed by `ExMake.Coordinator`.
    """

    @doc """
    Starts a runner process.

    `coordinator` must be the PID of a coordinator to send a finish notification
    to. It is assumed to be a `:gen_server`. `rule` must be the keyword list
    describing the rule. `owner` must be a PID pointing to the process that should
    be notified once the job is done.
    """
    @spec start(pid(), Keyword.t(), pid()) :: pid()
    def start(coordinator, rule, owner) do
        spawn(fn() ->
            result = try do
                {run, arg2} = if rule[:name] do
                    Enum.each(rule[:real_sources], fn(src) ->
                        if !File.exists?(src) do
                            raise(ExMake.UsageError[description: "No rule to make target '#{src}'"])
                        end
                    end)

                    {true, rule[:name]}
                else
                    Enum.each(rule[:sources], fn(src) ->
                        if !File.exists?(src) do
                            raise(ExMake.UsageError[description: "No rule to make target '#{src}'"])
                        end
                    end)

                    src_time = Enum.map(rule[:sources], fn(src) -> ExMake.Helpers.last_modified(src) end) |> Enum.max()
                    tgt_time = Enum.map(rule[:targets], fn(tgt) -> ExMake.Helpers.last_modified(tgt) end) |> Enum.min()

                    {src_time > tgt_time, rule[:targets]}
                end

                if run do
                    {m, f, a, _} = rule[:recipe]

                    rule_args = [rule[:sources], arg2]

                    if a >= 3 do
                        rule_args = rule_args ++ [rule[:directory]]
                    end

                    cwd = File.cwd!()

                    apply(m, f, rule_args)

                    if (ncwd = File.cwd!()) != cwd do
                        r = inspect(ExMake.Helpers.make_presentable(rule))
                        msg = "Recipe for rule #{r} changed directory from '#{cwd}' to '#{ncwd}' without changing back"

                        raise(ExMake.ScriptError[description: msg])
                    end
                end

                :ok
            catch
                val -> {:throw, val}
            rescue
                ex -> {:raise, ex}
            end

            if result != :ok do
                ExMake.Logger.debug("Caught #{elem(result, 0)} in runner: #{inspect(elem(result, 1))}")
                ExMake.Logger.debug(Exception.format_stacktrace(System.stacktrace()))

                # If the recipe failed, remove all target files.
                if tgts = rule[:targets], do: Enum.each(tgts, fn(tgt) -> File.rm(tgt) end)
            end

            :gen_server.call(coordinator, {:done, rule, owner, result}, :infinity)
        end)
    end
end
