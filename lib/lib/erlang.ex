defmodule ExMake.Lib.Erlang do
    use ExMake.Lib

    description "Support for the Erlang programming language."
    license "MIT License"
    version ExMake.Helpers.get_exmake_version_tuple()
    url "https://github.com/lycus/exmake"
    author "Alex Rønne Petersen", "alex@lycus.org"

    on_load args do
        if erlc = args[:erlc] || find_exe("erlc", "ERLC") do
            put("ERLC", erlc)
        end

        list_put("ERLC_FLAGS")
        list_put("ERLC_INCLUDES")
    end

    defmacro erlang_flag(flag) do
        quote do: ExMake.Env.list_append("ERLC_FLAGS", unquote(flag))
    end

    defmacro erlang_include(dir) do
        quote do: ExMake.Env.list_append("ERLC_INCLUDES", unquote(dir))
    end

    defmacro erlang(src, opts // []) do
        quote do
            src = unquote(src)

            rule [Path.rootname(src) <> ".beam"],
                 [src],
                 [src], _ do
                flags = Enum.join(unquote(opts)[:flags] || [], " ")
                includes = list_get("ERLC_INCLUDES") ++ (unquote(opts)[:includes] || []) |>
                           Enum.map(fn(i) -> "-I #{i}" end) |>
                           Enum.join(" ")

                shell("${ERLC} ${ERLC_FLAGS} #{flags} #{includes} -o #{Path.dirname(src)} #{src}")
            end
        end
    end
end
