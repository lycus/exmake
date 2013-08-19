defmodule ExMake.Lib.Elixir do
    use ExMake.Lib

    description "Support for the Elixir programming language."
    license "MIT License"
    version ExMake.Helpers.get_exmake_version_tuple()
    url "https://github.com/lycus/exmake"
    author "Alex Rønne Petersen", "alex@lycus.org"

    precious "ELIXIRC"

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
            @exm_elixir_opts unquote(opts)

            src = unquote(src)
            srcs = [src] ++ (@exm_elixir_opts[:deps] || [])
            mods = unquote(mods) |>
                   Enum.map(fn(m) -> m <> ".beam" end) |>
                   Enum.map(fn(m) -> (@exm_erlang_opts[:output_dir] || Path.dirname(src)) |>
                                     Path.join(m) end)

            rule mods,
                 srcs,
                 [src | _], _, dir do
                flags = Enum.join(@exm_elixir_opts[:flags] || [], " ")
                output_dir = if s = @exm_elixir_opts[:output_dir], do: Path.join(dir, s), else: Path.dirname(src)

                shell("${ELIXIRC} ${ELIXIRC_FLAGS} #{flags} -o #{output_dir} #{src}")
            end
        end
    end
end
