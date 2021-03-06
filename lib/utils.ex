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

    `cmd` must be a string containing the command to execute. `opts` must
    be a list of Boolean options (`:silent` and `:ignore`).
    """
    @spec shell(String.t(), Keyword.t()) :: String.t()
    def shell(cmd, opts \\ []) do
        silent = opts[:silent] || false
        ignore = opts[:ignore] || false

        cmd = ExMake.Env.reduce(cmd, fn({k, v}, cmd) ->
            value = if is_binary(v) do
                v
            else
                Enum.join(v, " ")
            end

            String.replace(cmd, "${#{k}}", value)
        end)

        if !silent do
            ExMake.Logger.log_note(cmd)
        end

        port = Port.open({:spawn, String.to_char_list(cmd)}, [:binary,
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

        if code != 0 && !ignore do
            out = if String.strip(text) != "", do: "\n#{text}", else: ""

            raise(ExMake.ShellError,
                  [message: "Command '#{cmd}' exited with code: #{code}#{out}",
                   command: cmd,
                   output: text,
                   exit_code: code])
        end

        if String.strip(text) != "" && !silent do
            ExMake.Logger.log_info(text)
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
    @spec ignore((() -> term())) :: {:ok, term()} | {:throw, term()} | {:rescue, tuple()}
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
    set, will be preferred. Raises `ExMake.ScriptError` if the
    executable could not be found.

    `name` must be the name of the executable as a string, or a
    list of names. `var` must be an environment variable name as
    a string. `opts` must be a list of Boolean options (`:silent`
    and `:ignore`).
    """
    @spec find_exe(String.t() | [String.t()], String.t(), Keyword.t()) :: String.t() | nil
    def find_exe(name, var \\ "", opts \\ []) do
        silent = opts[:silent] || false
        ignore = opts[:ignore] || false

        if s = System.get_env(var), do: name = s

        names = if is_list(name), do: name, else: [name]

        exe = Enum.find_value(names, fn(name) ->
            case :os.find_executable(String.to_char_list(name)) do
                false -> nil
                path -> List.to_string(path)
            end
        end)

        var_desc = if var == "", do: "", else: " ('#{var}'#{if s, do: " = '#{s}'", else: ""})"

        if !exe && !ignore do
            list = Enum.join(Enum.map(names, fn(s) -> "'#{s}'" end), ", ")

            raise(ExMake.ScriptError, [message: "Could not locate program #{list}#{var_desc}"])
        end

        if !silent do
            ExMake.Logger.log_result("Located program '#{exe}'#{var_desc}")
        end

        exe
    end

    @doc """
    Formats a string according to `:io_lib.format/2` and returns
    the resulting string as a binary.

    Please note that you should usually use the `~ts` modifier
    rather than `~s` as the latter will not handle UTF-8 strings
    correctly. The same goes for `~tc` and `~c`.

    `str` must be the format string as a binary. `args` must be
    a list of terms to pass to the formatting function.
    """
    @spec format(String.t(), [term()]) :: String.t()
    def format(str, args) do
        :io_lib.format(str, args) |> IO.iodata_to_binary()
    end
end
