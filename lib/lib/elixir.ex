defmodule ExMake.Lib.Elixir do
    use ExMake.Lib

    description "Support for the Elixir programming language."
    license "MIT License"
    version ExMake.Helpers.get_exmake_version_tuple()
    url "https://github.com/lycus/exmake"
    author "Alex Rønne Petersen", "alex@lycus.org"

    on_load args, _ do
        if elixirc = args[:elixirc] || find_exe("elixirc", "ELIXIRC") do
            put("ELIXIRC", elixirc)
        end

        list_put("ELIXIRC_FLAGS")
    end

    defmacro elixirc_flag(flag) do
        quote do: ExMake.Env.list_append("ELIXIRC_FLAGS", unquote(flag))
    end

    defmacro ex(src, mods, opts // []) do
        quote do
            srcs = [unquote(src)] ++ (unquote(opts)[:deps] || [])
            mods = Enum.map(unquote(mods), fn(m) -> m <> ".beam" end)

            rule mods,
                 srcs,
                 [src | _], _, dir do
                opts = unquote(opts)

                flags = Enum.join(opts[:flags] || [], " ")
                output_dir = if s = opts[:output_dir], do: Path.join(dir, s), else: Path.dirname(src)

                shell("${ELIXIRC} ${ELIXIRC_FLAGS} #{flags} -o #{output_dir} #{src}")
            end
        end
    end
end
