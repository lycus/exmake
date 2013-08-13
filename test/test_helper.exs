ExUnit.start()

ExMake.Application.start()

defmodule ExMake.Test.Case do
    use ExUnit.CaseTemplate

    using do
        quote do
            import ExMake.Test.Case
        end
    end

    defp generate_file(name, contents) do
        """
        defmodule #{name}.Exmakefile do
            use ExMake.File

            #{contents}
        end
        """
    end

    def create_fixture(path, name, contents, opts // []) do
        p = Path.join("tmp", path)

        File.mkdir_p!(p)

        file = Path.join(p, opts[:file] || "Exmakefile")
        body = if opts[:raw], do: contents, else: generate_file(name, contents)

        File.write!(file, body)

        {p, file}
    end

    def create_file(path, name, contents) do
        p = Path.join(path, name)

        File.write!(p, contents)

        p
    end

    def execute_in(path, args // []) do
        File.cd!(path, fn() ->
            tup = ExMake.Application.parse(args)

            opts = elem(tup, 0)
            rest = elem(tup, 1)

            if Enum.empty?(rest), do: rest = ["all"]

            :application.set_env(:exmake, :exmake_event_pid, self())

            cfg = ExMake.Config[targets: rest,
                                options: opts]

            ExMake.Coordinator.set_config(ExMake.Coordinator.locate(), cfg)
            ExMake.Worker.work(ExMake.Worker.locate())

            recv = fn(recv, acc) ->
                receive do
                    {:exmake_stdout, str} -> recv.(recv, acc <> str)
                    {:exmake_shutdown, code} -> {acc, code}
                end
            end

            {text, code} = recv.(recv, "")

            {String.strip(text), code}
        end)
    end
end
