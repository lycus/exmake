defmodule ExMake.Lib.ExMake do
    use ExMake.Lib

    description "Support for building ExMake libraries."
    license "MIT License"
    version ExMake.Helpers.get_exmake_version_tuple()
    url "https://github.com/lycus/exmake"
    author "Alex Rønne Petersen", "alex@lycus.org"

    defmacro exm_lib(src, mods, opts // []) do
        quote do
            @exm_exmake_opts unquote(opts)

            src = unquote(src)
            srcs = [src] ++ (@exm_exmake_opts[:deps] || [])
            mods = unquote(mods) |>
                   Enum.map(fn(m) -> m <> ".beam" end) |>
                   Enum.map(fn(m) -> (@exm_exmake_opts[:output_dir] || Path.dirname(src)) |>
                                     Path.join(m) end)

            rule mods,
                 srcs,
                 [src | _], _, dir do
                output_dir = if s = @exm_exmake_opts[:output_dir], do: Path.join(dir, s), else: Path.dirname(src)

                Enum.each(Code.compile_string(File.read!(src), src), fn({mod, code}) ->
                    File.write!(Path.join(output_dir, atom_to_binary(mod) <> ".beam"), code)
                end)
            end
        end
    end
end
