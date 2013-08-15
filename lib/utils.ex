defmodule ExMake.Utils do
    @moduledoc """
    Contains various utilities to assist in writing recipes.

    Automatically imported in all script files.
    """

    @doc """
    Runs a command in the system shell. Returns the output of the command
    as a string. Raises `ExMake.ShellError` if the command returns a
    non-zero exit code.

    Any `${...}` instance in the command string where the `...` matches a
    key in the `ExMake.Env` table will be replaced with the value that
    key maps to.

    Example:

        shell("${CC} -c foo.c -o foo.o")

    `cmd` must be a string containing the command to execute.
    """
    @spec shell(String.t()) :: String.t()
    def shell(cmd) do
        cmd = ExMake.Env.reduce(cmd, fn({k, v}, cmd) ->
            value = if is_binary(v) do
                v
            else
                Enum.join(v, " ")
            end

            String.replace(cmd, "${#{k}}", value)
        end)

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

        if cfg.options()[:loud] && String.strip(text) != "" do
            ExMake.Logger.info(text)
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

    @doc """
    Attempts to find an executable in `PATH` given its name. An
    environment variable name can optionally be given, which, if
    set, will be preferred.

    `name` must be the name of the executable as a string. `var`
    must be an environment variable name as a string.
    """
    @spec find_exe(String.t(), String.t() | nil) :: String.t() | nil
    def find_exe(name, var // "") do
        case System.get_env(var) do
            nil ->
                case :os.find_executable(String.to_char_list!(name)) do
                    false -> nil
                    path -> String.from_char_list!(path)
                end
            path -> path
        end
    end
end
