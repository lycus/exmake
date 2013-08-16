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

    defmacro erlc_flag(flag) do
        quote do: ExMake.Env.list_append("ERLC_FLAGS", unquote(flag))
    end

    defmacro erlc_include(dir) do
        quote do: ExMake.Env.list_append("ERLC_INCLUDES", unquote(dir))
    end

    defmacro erl(src, opts // []) do
        quote do
            src = unquote(src)
            srcs = [src] ++ (unquote(opts)[:headers] || [])

            rule [Path.rootname(src) <> ".beam"],
                 srcs,
                 [src], _, dir do
                opts = unquote(opts)

                flags = Enum.join(opts[:flags] || [], " ")
                includes = list_get("ERLC_INCLUDES") ++ (opts[:includes] || []) |>
                           Enum.map(fn(i) -> "-I #{Path.join(dir, i)}" end) |>
                           Enum.join(" ")

                shell("${ERLC} ${ERLC_FLAGS} #{flags} #{includes} -o #{Path.dirname(src)} #{src}")
            end
        end
    end
end
