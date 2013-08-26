defmodule ExMake.Lib.CSharp do
    use ExMake.Lib

    description "Support for the C# programming language."
    license "MIT License"
    version ExMake.Helpers.get_exmake_version_tuple()
    url "https://github.com/lycus/exmake"
    author "Alex Rønne Petersen", "alex@lycus.org"

    precious "CSC"

    on_load args, _ do
        put("CSC", args[:csc] || find_exe(["csc", "mcs"], "CSC"))

        text = shell("${CSC} /?", silent: true, ignore: true)

        type = cond do
            String.starts_with?(text, "Microsoft (R) Visual C# Compiler") -> "csc"
            String.starts_with?(text, "Mono C# compiler") -> "mcs"
            true -> "unknown"
        end

        ExMake.Logger.log_result("C# compiler type: #{type}")
        put("CSC_TYPE", type)

        list_put("CSC_FLAGS")
        list_put("CSC_LIBS")
    end

    defmacro csc_flag(flag) do
        quote do: ExMake.Env.list_append("CSC_FLAGS", unquote(flag))
    end

    defmacro csc_lib(dir) do
        quote do: ExMake.Env.list_append("CSC_LIBS", unquote(dir))
    end

    defmacro cs(srcs, tgt, opts // []) do
        quote do
            @exm_csharp_opts unquote(opts)

            dbg = if @exm_csharp_opts[:debug] do
                case get("CSC_TYPE") do
                    "csc" -> [unquote(tgt) <> ".pdb"]
                    "mcs" -> [unquote(tgt) <> ".mdb"]
                    "unknown" -> []
                end
            else
                []
            end

            mods = @exm_csharp_opts[:net_modules] || []
            kf = if k = @exm_csharp_opts[:key_file], do: [k], else: []
            srcs = unquote(srcs) ++ mods ++ kf
            doc = if d = @exm_csharp_opts[:doc_file], do: [d], else: []
            tgts = [unquote(tgt)] ++ doc ++ dbg

            rule tgts,
                 srcs,
                 srcs, [tgt | _], dir do
                flags = Enum.join(@exm_csharp_opts[:flags] || [], " ")
                srcs = Enum.join(srcs, " ")
                mods = (@exm_csharp_opts[:net_modules] || []) |>
                       Enum.map(fn(m) -> "/addmodule:#{Path.join(dir, m)}" end) |>
                       Enum.join(" ")
                kf = if s = @exm_csharp_opts[:key_file], do: "/keyfile:#{Path.join(dir, s)}"
                doc = if s = @exm_csharp_opts[:doc_file], do: "/doc:#{Path.join(dir, s)}"
                libs = list_get("CSC_LIBS") ++ (@exm_csharp_opts[:libs] || []) |>
                       Enum.map(fn(l) -> "/lib:#{Path.join(dir, l)}" end) |>
                       Enum.join(" ")
                dbg = if @exm_csharp_opts[:debug] && get("CSC_TYPE") != "unknown", do: "/debug"

                shell("${CSC} ${CSC_FLAGS} #{flags} -nologo #{libs} #{mods} #{kf} #{doc} #{dbg} /out:#{tgt} -- #{srcs}")
            end
        end
    end
end
