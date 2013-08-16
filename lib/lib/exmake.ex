defmodule ExMake.Lib.ExMake do
    use ExMake.Lib

    description "Support for building ExMake libraries."
    license "MIT License"
    version ExMake.Helpers.get_exmake_version_tuple()
    url "https://github.com/lycus/exmake"
    author "Alex Rønne Petersen", "alex@lycus.org"

    defmacro exm_lib(src, mods) do
        quote do
            src = unquote(src)
            mods = Enum.map(unquote(mods), fn(m) -> "Elixir." <> m <> ".beam" end)

            rule mods,
                 [src],
                 [src], _, dir do
                Enum.each(Code.compile_string(File.read!(src), src), fn({mod, code}) ->
                    File.write!(Path.join(dir, atom_to_binary(mod) <> ".beam"), code)
                end)
            end
        end
    end
end
