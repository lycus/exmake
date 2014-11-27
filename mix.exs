defmodule ExMake.Mixfile do
    use Mix.Project

    def project() do
        [app: :exmake,
         version: String.strip(File.read!("VERSION")),
         elixir: "~> 1.0.2",
         build_per_environment: false,
         escript: [main_module: ExMake.Application,
                   path: Path.join(["_build", "shared", "lib", "exmake", "ebin", "exmake"]),
                   emu_args: "-noshell -noinput +B -spp true"]]
    end

    def application() do
        [applications: [],
         mod: {ExMake.Application, []}]
    end
end
