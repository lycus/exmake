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

    @spec colorize(String.t(), IO.ANSI.ansicode()) :: String.t()
    defp colorize(str, color) do
        emit = IO.ANSI.enabled?() && Application.get_env(:exmake, :exmake_event_pid) == nil && System.get_env("EXMAKE_COLORS") != "0"
        IO.ANSI.format([color, :bright, str], emit) |> IO.iodata_to_binary()
    end

    @spec output(String.t()) :: :ok
    defp output(str) do
        _ = case Application.get_env(:exmake, :exmake_event_pid) do
            nil -> IO.puts(str)
            pid -> send(pid, {:exmake_stdout, str <> "\n"})
        end

        :ok
    end

    @doc false
    @spec info(String.t()) :: :ok
    def info(str) do
        output(str)
    end

    @doc false
    @spec warn(String.t()) :: :ok
    def warn(str) do
        output(colorize("Warning:", :yellow) <> " " <> colorize(str, :white))
    end

    @doc false
    @spec error(String.t()) :: :ok
    def error(prefix \\ "Error", str) do
        output(colorize(prefix <> ":", :red) <> " " <> colorize(str, :white))
    end

    @doc """
    Prints an informational message in `--loud` mode. Returns `:ok`.

    `str` must be a binary containing the message.
    """
    @spec log_info(String.t()) :: :ok
    def log_info(str) do
        if ExMake.Coordinator.get_config().options()[:loud], do: info(str)

        :ok
    end

    @doc """
    Prints a notice in `--loud` mode. Colorized as green and white. Returns
    `:ok`.

    `str` must be a binary containing the message.
    """
    @spec log_note(String.t()) :: :ok
    def log_note(str) do
        if ExMake.Coordinator.get_config().options()[:loud], do: output(colorize(str, :green))

        :ok
    end

    @doc """
    Prints a warning in `--loud` mode. Colorized as yellow and white. Returns
    `:ok`.

    `str` must be a binary containing the message.
    """
    @spec log_warn(String.t()) :: :ok
    def log_warn(str) do
        if ExMake.Coordinator.get_config().options()[:loud], do: warn(str)

        :ok
    end

    @doc """
    Prints a result message in `--loud` mode. Colorized as cyan and white.
    Returns `:ok`.

    `str` must be a binary containing the message.
    """
    @spec log_result(String.t()) :: :ok
    def log_result(str) do
        if ExMake.Coordinator.get_config().options()[:loud], do: output(colorize(str, :cyan))

        :ok
    end

    @doc """
    Prints a debug message if the `EXMAKE_DEBUG` environment variable is set
    to `1`. Colorized as magenta and white. Returns `:ok`.

    `str` must be a binary containing the message.
    """
    @spec log_debug(String.t()) :: :ok
    def log_debug(str) do
        if System.get_env("EXMAKE_DEBUG") == "1" do
            output(colorize("Debug:", :magenta) <> " " <> colorize(str, :white))
        end

        :ok
    end
end
