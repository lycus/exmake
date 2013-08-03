defmodule ExMake.Utils do
    @moduledoc """
    Contains various utilities to assist in writing recipes.

    Automatically imported in all script files.
    """

    @doc """
    Runs a command in the system shell. Returns the output of the command
    as a string. Raises `ExMake.ShellError` if the command returns a
    non-zero exit code.

    `cmd` must be a string containing the command to execute.
    """
    @spec shell(String.t()) :: String.t()
    def shell(cmd) do
        cmd = Enum.reduce(System.get_env(), cmd, fn({k, v}, cmd) -> String.replace(cmd, "${#{k}}", v) end)

        cfg = ExMake.Coordinator.get_config(ExMake.Coordinator.locate())

        if cfg.options()[:loud] do
            ExMake.Logger.note(cmd)
        end

        port = Port.open({:spawn, String.to_char_list!(cmd)}, [:binary,
                                                               :exit_status,
                                                               :hide,
                                                               :stderr_to_stdout])

        recv = fn(recv, port, acc) ->
            receive do
                {^port, {:data, data}} -> recv.(recv, port, acc <> data)
                {^port, {:exit_status, code}} -> {acc, code}
            end
        end

        {text, code} = recv.(recv, port, "")

        if code != 0 do
            raise(ExMake.ShellError[command: cmd,
                                    output: text,
                                    exit_code: code])
        end

        if cfg.options()[:loud] && text != "" do
            ExMake.Logger.info(cmd)
        end

        text
    end

    @doc """
    Runs a given function while ignoring all errors. The function
    should take no arguments.

    If nothing goes wrong, returns `{:ok, result}` where `result`
    is the value returned by the given function. If a value was
    thrown, returns `{:throw, value}`. If an exception was raised,
    returns `{:rescue, exception}`.
    """
    @spec ignore((() -> term())) :: :ok | {:throw, term()} | {:rescue, tuple()}
    def ignore(fun) do
        try do
            {:ok, fun.()}
        catch
            x -> {:throw, x}
        rescue
            x -> {:rescue, x}
        end
    end
end
