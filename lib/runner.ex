defmodule ExMake.Runner do
    @moduledoc """
    Encapsulates the processes that are used to actually execute recipes
    in a script file.

    This module is only meant to be consumed by `ExMake.Coordinator`.
    """

    @doc """
    Starts a runner process.

    `coordinator` must be the PID of a coordinator to send a finish notification
    to. It is assumed to be a `:gen_server`. `cfg` must be an `ExMake.Config`
    instance. `rule` must be the keyword list describing the rule. `owner` must
    be a PID pointing to the process that should be notified once the job is done.
    """
    @spec start(pid(), ExMake.Config.t(), Keyword.t(), pid()) :: pid()
    def start(coordinator, cfg, rule, owner) do
        spawn(fn() ->
            result = try do
                {run, arg2} = if rule[:name] do
                    {true, rule[:name]}
                else
                    Enum.each(rule[:sources], fn(src) ->
                        if !File.exists?(src) do
                            raise(ExMake.UsageError[description: "No target to make file '#{src}'"])
                        end
                    end)

                    src_time = Enum.map(rule[:sources], fn(src) -> ExMake.Helpers.last_modified(src) end) |> Enum.max()
                    tgt_time = Enum.map(rule[:targets], fn(tgt) -> ExMake.Helpers.last_modified(tgt) end) |> Enum.min()

                    {src_time > tgt_time, rule[:targets]}
                end

                if run do
                    {m, f, a} = rule[:recipe]

                    rule_args = [rule[:sources], arg2]

                    if a >= 3 do
                        rule_args = rule_args ++ [rule[:directory]]
                    end

                    if a >= 4 do
                        args = cfg.options()[:args] || "" |>
                               String.split(" ") |>
                               Enum.filter(fn(s) -> String.strip(s) == "" end)

                        rule_args = rule_args ++ [args]
                    end

                    apply(m, f, rule_args)
                end

                :ok
            catch
                val -> {:throw, val}
            rescue
                ex -> {:raise, ex}
            end

            :gen_server.call(coordinator, {:done, rule, owner, result}, :infinity)
        end)
    end
end