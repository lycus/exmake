defmodule ExMake.Mixfile do
    use Mix.Project

    def project() do
        args = Enum.join(["%%!",
                          "-noshell",
                          "-noinput",
                          "+B",
                          "-spp true",
                          "\n"],
                         " ")

        [app: :exmake,
         version: "0.3.2",
         build_per_environment: false,
         escript_main_module: ExMake.Application,
         escript_path: Path.join(["_build", "shared", "lib",
                                  "exmake", "ebin", "exmake"]),
         escript_emu_args: args]
     end

    def application() do
        [applications: [],
         mod: {ExMake.Application, []}]
    end
end
