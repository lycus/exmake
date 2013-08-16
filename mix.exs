defmodule ExMake.Mixfile do
    use Mix.Project

    def project() do
        [app: :exmake,
         version: "0.0.0",
         escript_main_module: ExMake.Application,
         escript_path: Path.join("ebin", "exmake"),
         escript_emu_args: "%%! -noshell -noinput +B\n"]
     end

    def application() do
        [applications: [],
         mod: {ExMake.Application, []}]
    end
end
