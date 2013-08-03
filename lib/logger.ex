defmodule ExMake.Logger do
    @moduledoc """
    Provides logging facilities.

    If the `:exmake_event_pid` application configuration key is set for the
    `:exmake` application, log messages will be sent as `{:exmake_stdout, msg}`
    (where `msg` is a binary) to that PID instead of being printed to standard
    output.

    Note also that if `:exmake_event_pid` is set, the current terminal is
    not ANSI-compatible, or the `EXMAKE_COLORS` environment variable is set to
    `0`, colored output will be disabled.
    """

    @spec colorize(String.t(), String.t()) :: String.t()
    defp colorize(str, color) do
        emit = IO.ANSI.terminal?() && :application.get_env(:exmake, :exmake_event_pid) == :undefined && System.get_env("EXMAKE_COLORS") != "0"
        IO.ANSI.escape_fragment("%{#{color}, bright}#{str}%{reset}", emit)
    end

    @spec output(String.t()) :: :ok
    defp output(str) do
        _ = case :application.get_env(:exmake, :exmake_event_pid) do
            {:ok, pid} -> pid <- {:exmake_stdout, str <> "\n"}
            :undefined -> IO.puts(str)
        end

        :ok
    end

    @doc """
    Prints an informational message. Returns `:ok`.

    `str` must be a binary containing the message.
    """
    @spec info(String.t()) :: :ok
    def info(str) do
        output(str)
    end

    @doc """
    Prints a notice. Colorized as green and white. Returns `:ok`.

    `str` must be a binary containing the message.
    """
    @spec note(String.t()) :: :ok
    def note(str) do
        output(colorize(str, "green"))
    end

    @doc """
    Prints a warning message. Colorized as yellow and white. Returns `:ok`.

    `str` must be a binary containing the message.
    """
    @spec warn(String.t()) :: :ok
    def warn(str) do
        output(colorize("Warning:", "yellow") <> " " <> colorize(str, "white"))
    end

    @doc """
    Prints an error message. Colorized as red and white. Returns `:ok`.

    `str` must be a binary containing the message.
    """
    @spec error(String.t()) :: :ok
    def error(str) do
        output(colorize("Error:", "red") <> " " <> colorize(str, "white"))
    end

    @doc """
    Prints a debug message if the `EXMAKE_DEBUG` environment variable is set
    to `1`. Colorized as magenta and white. Returns `:ok`.

    `str` must be a binary containing the message.
    """
    @spec debug(String.t()) :: :ok
    def debug(str) do
        if System.get_env("EXMAKE_DEBUG") == "1" do
            output(colorize("Debug:", "magenta") <> " " <> colorize(str, "white"))
        end
    end
end
