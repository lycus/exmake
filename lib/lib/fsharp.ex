defmodule ExMake.Lib.FSharp do
    use ExMake.Lib

    description "Support for the F# programming language."
    license "MIT License"
    version ExMake.Helpers.get_exmake_version_tuple()
    url "https://github.com/lycus/exmake"
    author "Alex Rønne Petersen", "alex@lycus.org"

    precious "FSHARPC"

    on_load args, _ do
        put("FSHARPC", args[:fsharpc] || find_exe(["fsharpc"], "FSHARPC"))

        text = shell("${FSHARPC} --help", silent: true, ignore: true)

        type = cond do
            String.starts_with?(text, "Microsoft (R) F# Compiler") -> "fsc"
            String.starts_with?(text, "F# Compiler") -> "fsharpc"
            true -> "unknown"
        end

        ExMake.Logger.log_result("F# compiler type: #{type}")
        put("FSHARPC_TYPE", type)

        list_put("FSHARPC_FLAGS")
        list_put("FSHARPC_LIBS")
    end

    defmacro fsharpc_flag(flag) do
        quote do: ExMake.Env.list_append("FSHARPC_FLAGS", unquote(flag))
    end

    defmacro fsharpc_lib(dir) do
        quote do: ExMake.Env.list_append("FSHARPC_LIBS", unquote(dir))
    end

    defmacro fs(srcs, tgt, opts // []) do
        quote do
            @exm_fsharp_opts unquote(opts)

            dbg = if @exm_fsharp_opts[:debug] do
                case get("FSHARPC_TYPE") do
                    "fsc" -> [unquote(tgt) <> ".pdb"]
                    "fsharpc" -> [unquote(tgt) <> ".mdb"]
                    "unknown" -> []
                end
            else
                []
            end

            kf = if k = @exm_fsharp_opts[:key_file], do: [k], else: []
            srcs = unquote(srcs) ++ kf
            doc = if d = @exm_fsharp_opts[:doc_file], do: [d], else: []
            tgts = [unquote(tgt)] ++ doc ++ dbg

            rule tgts,
                 srcs,
                 srcs, [tgt | _], dir do
                flags = Enum.join(@exm_fsharp_opts[:flags] || [], " ")
                srcs = if k = @exm_fsharp_opts[:key_file], do: List.delete(srcs, Path.join(dir, k)), else: srcs
                kf = if k, do: "--keyfile:#{Path.join(dir, k)}"
                doc = if s = @exm_fsharp_opts[:doc_file], do: "--doc:#{Path.join(dir, s)}"
                libs = list_get("FSHARPC_LIBS") ++ (@exm_fsharp_opts[:libs] || []) |>
                       Enum.map(fn(l) -> "--lib:#{Path.join(dir, l)}" end) |>
                       Enum.join(" ")
                dbg = if @exm_fsharp_opts[:debug] && get("FSHARPC_TYPE") != "unknown", do: "--debug+"

                shell("${FSHARPC} ${FSHARPC_FLAGS} #{flags} --nologo #{libs} #{kf} #{doc} #{dbg} --out:#{tgt} #{srcs}")
            end
        end
    end
end
