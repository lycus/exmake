defmodule ExMake.Mixfile do
    use Mix.Project

    def project() do
        [app: :exmake,
         version: "0.1.0",
         escript_main_module: ExMake.Application,
         escript_path: Path.join("ebin", "exmake"),
         escript_emu_args: "%%! -noshell -noinput +B\n",
         test_coverage: [output: "ebin"]]
     end

    def application() do
        [applications: [],
         mod: {ExMake.Application, []}]
    end
end
