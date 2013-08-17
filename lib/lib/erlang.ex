defmodule ExMake.Lib.Erlang do
    use ExMake.Lib

    description "Support for the Erlang programming language."
    license "MIT License"
    version ExMake.Helpers.get_exmake_version_tuple()
    url "https://github.com/lycus/exmake"
    author "Alex Rønne Petersen", "alex@lycus.org"

    on_load args, _ do
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
            @exm_erlang_opts unquote(opts)

            src = unquote(src)
            srcs = [src] ++ (@exm_erlang_opts[:headers] || [])
            tgt = (@exm_erlang_opts[:output_dir] || Path.dirname(src)) |>
                  Path.join(Path.rootname(Path.basename(src)) <> ".beam")

            rule [tgt],
                 srcs,
                 [src | _], _, dir do
                flags = Enum.join(@exm_erlang_opts[:flags] || [], " ")
                output_dir = if s = @exm_erlang_opts[:output_dir], do: Path.join(dir, s), else: Path.dirname(src)
                includes = list_get("ERLC_INCLUDES") ++ (@exm_erlang_opts[:includes] || []) |>
                           Enum.map(fn(i) -> "-I #{Path.join(dir, i)}" end) |>
                           Enum.join(" ")

                shell("${ERLC} ${ERLC_FLAGS} #{flags} #{includes} -o #{output_dir} #{src}")
            end
        end
    end
end
