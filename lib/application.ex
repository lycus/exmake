defmodule ExMake.Application do
    @moduledoc """
    This is the main entry point of the ExMake application.
    """

    use Application.Behaviour

    @doc """
    Runs ExMake from the command line. Returns via `System.halt/1`.

    `args` must be a list of strings containing the command line arguments.
    """
    @spec main([String.t()]) :: no_return()
    def main(args) do
        {opts, rest} = parse(args)

        if opts[:version] do
            ExMake.Logger.info("ExMake - 0.1.0")
            ExMake.Logger.info("Copyright (C) 2013 The Lycus Foundation")
            ExMake.Logger.info("Available under the terms of the MIT License")
            ExMake.Logger.info("")
        end

        if opts[:help] do
            ExMake.Logger.info("Usage: exmake [switches] [targets]")
            ExMake.Logger.info("")
            ExMake.Logger.info("The default target is 'all'.")
            ExMake.Logger.info("")
            ExMake.Logger.info("Switches:")
            ExMake.Logger.info("")
            ExMake.Logger.info("    --help, -h                      Print this help text.")
            ExMake.Logger.info("    --version, -v                   Print the program version.")
            ExMake.Logger.info("    --file, -f <file [Exmakefile]>  Use the specified script file.")
            ExMake.Logger.info("    --loud, -l                      Print targets and commands.")
            ExMake.Logger.info("    --question, -q                  Exit with 0 if everything is up to date; otherwise, 1.")
            ExMake.Logger.info("    --jobs, -j <jobs [1]>           Run the specified number of concurrent jobs.")
            ExMake.Logger.info("    --args, -a <arguments []>       Specify arguments to pass to rules.")
            ExMake.Logger.info("")
        end

        if opts[:help] || opts[:version] do
            System.halt(2)
        end

        start()

        if Enum.empty?(rest), do: rest = ["all"]

        cfg = ExMake.Config[targets: rest,
                            options: opts]

        ExMake.Coordinator.set_config(ExMake.Coordinator.locate(), cfg)
        code = ExMake.Worker.work(ExMake.Worker.locate())

        System.halt(code)
    end

    @doc """
    Parses the given command line arguments into an `{options, rest}` pair
    and returns it.

    `args` must be a list of binaries containing the command line arguments.
    """
    @spec parse([String.t()]) :: {Keyword.t(), [String.t()]}
    def parse(args) do
        OptionParser.parse(args, [switches: [help: :boolean,
                                             version: :boolean,
                                             loud: :boolean,
                                             question: :boolean,
                                             jobs: :integer],
                                  aliases: [h: :help,
                                            v: :version,
                                            f: :file,
                                            l: :loud,
                                            q: :question,
                                            j: :jobs,
                                            a: :args]])
    end

    @doc """
    Starts the ExMake application. Returns `:ok` on success.
    """
    @spec start() :: :ok
    def start() do
        :ok = Application.Behaviour.start(:exmake)
    end

    @doc """
    Stops the ExMake application. Returns `:ok` on success.
    """
    @spec stop() :: :ok
    def stop() do
        :ok = :application.stop(:exmake)
    end

    @doc false
    @spec start(:normal | {:takeover, node()} | {:failover, node()}, []) :: {:ok, pid(), nil}
    def start(_, []) do
        {:ok, pid} = ExMake.Supervisor.start_link()
        {:ok, pid, nil}
    end

    @doc false
    @spec stop(nil) :: :ok
    def stop(nil) do
        :ok
    end
end
