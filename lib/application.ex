defmodule ExMake.Application do
    @moduledoc """
    This is the main entry point of the ExMake application.
    """

    use Application

    require ExMake.Helpers

    @doc false
    @spec main([String.t()]) :: no_return()
    def main(args) do
        {opts, rest, inv, tail} = parse(args)

        Enum.each(inv, fn({opt, val}) ->
            ExMake.Logger.error("Invalid value '#{val}' for option '--#{opt}'")
        end)

        if inv != [], do: System.halt(1)

        if opts[:version] do
            ExMake.Logger.info("ExMake - #{ExMake.Helpers.get_exmake_version()}")
            ExMake.Logger.info(ExMake.Helpers.get_exmake_license())
            ExMake.Logger.info("Available under the terms of the MIT License")
            ExMake.Logger.info("")
        end

        if opts[:help] do
            ExMake.Logger.info("Usage: exmake [switches] [--] [targets] [--args args]")
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
            ExMake.Logger.info("    --time, -t                      Print timing information.")
            ExMake.Logger.info("    --clear, -c                     Clear the graph and environment cache.")
            ExMake.Logger.info("    --args, -a <arguments []>       Pass all remaining arguments to libraries.")
            ExMake.Logger.info("")
            ExMake.Logger.info("If '--' is encountered anywhere before '--args', all remaining")
            ExMake.Logger.info("arguments are parsed as if they're target names, even if they")
            ExMake.Logger.info("contain dashes.")
            ExMake.Logger.info("")
        end

        if opts[:help] || opts[:version] do
            System.halt(2)
        end

        if Enum.empty?(rest), do: rest = ["all"]

        cfg = %ExMake.Config{targets: rest,
                             options: opts,
                             args: tail}

        ExMake.Coordinator.set_config(cfg)
        code = ExMake.Worker.work()

        System.halt(code)
    end

    @doc """
    Parses the given command line arguments into an
    `{options, rest, invalid, tail}` tuple and returns it.

    `args` must be a list of binaries containing the command line arguments.
    """
    @spec parse([String.t()]) :: {Keyword.t(), [String.t()], Keyword.t(), [String.t()]}
    def parse(args) do
        {args, t} = Enum.split_while(args, fn(x) -> x != "--args" end)

        # Strip off the --args element, if any.
        if t != [], do: t = tl(t)

        switches = [help: :boolean,
                    version: :boolean,
                    loud: :boolean,
                    question: :boolean,
                    jobs: :integer,
                    time: :boolean,
                    clear: :boolean]

        aliases = [h: :help,
                   v: :version,
                   f: :file,
                   l: :loud,
                   q: :question,
                   j: :jobs,
                   t: :time,
                   c: :clear]

        tup = OptionParser.parse(args, [switches: switches, aliases: aliases])
        i = if tuple_size(tup) >= 3, do: elem(tup, 2), else: []

        {elem(tup, 0), elem(tup, 1), i, t}
    end

    @doc """
    Starts the ExMake application. Returns `:ok` on success.
    """
    @spec start() :: :ok
    def start() do
        :ok = Application.start(:exmake)
    end

    @doc """
    Stops the ExMake application. Returns `:ok` on success.
    """
    @spec stop() :: :ok
    def stop() do
        :ok = Application.stop(:exmake)
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
