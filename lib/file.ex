defmodule ExMake.File do
    @moduledoc """
    Provides various useful functions and macros for constructing script files.

    This module should be `use`d like so:

        defmodule MyProject.Exmakefile do
            use ExMake.File

            # ...
        end

    Using this module implicitly imports the following modules:

    * `ExMake.File`
    * `ExMake.Utils`
    """

    @doc false
    defmacro __using__(_) do
        quote do
            import ExMake.File
            import ExMake.Utils

            @before_compile unquote(__MODULE__)

            Module.register_attribute(__MODULE__, :subdirectories, [accumulate: true, persist: true])
            Module.register_attribute(__MODULE__, :rules, [accumulate: true, persist: true])
            Module.register_attribute(__MODULE__, :phony_rules, [accumulate: true, persist: true])
        end
    end

    @doc false
    defmacro __before_compile__(_) do
        quote do
            def __exmake__(:subdirectories), do: Enum.reverse(@subdirectories)
            def __exmake__(:rules), do: Enum.reverse(@rules)
            def __exmake__(:phony_rules), do: Enum.reverse(@phony_rules)
        end
    end

    @doc %B"""
    Specifies a directory to recurse into.

    Example:

        defmodule MyProject.Exmakefile do
            use ExMake.File

            recurse "utils"

            rule ["foo.o"],
                 ["foo.c"],
                 [src], [tgt] do
                shell("${CC} -c #{src} -o #{tgt}")
            end

            rule ["my_exe"],
                 ["foo.o", "utils/bar.o"],
                 srcs, [tgt] do
                shell("${CC} #{Enum.join(srcs, " ")} -o #{tgt}")
            end
        end

    And in `utils`:

        defmodule MyProject.Utils.Exmakefile do
            use ExMake.File

            rule ["bar.o"],
                 ["bar.c"],
                 [src], [tgt] do
                shell("${CC} -c #{src} -o #{tgt}")
            end
        end

    This can be used to split script files into multiple directories so that they are
    easier to maintain. It also allows invoking ExMake inside a sub-directory without
    having to build everything from the top-level script file.

    Unlike in other Make-style tools, recursion in ExMake does not mean invoking ExMake
    itself within a sub-directory. Rather, when ExMake is invoked, it collects the full
    list of directories to recurse into and includes all rules in those directories
    into the canonical dependency graph.
    """
    defmacro recurse(dir, file // "Exmakefile") do
        quote do: @subdirectories {unquote(dir), unquote(file)}
    end

    @doc %B"""
    Defines a rule.

    Example:

        defmodule MyProject.Exmakefile do
            use ExMake.File

            rule ["foo.o"],
                 ["foo.c"],
                 [src], [tgt] do
                shell("${CC} -c #{src} -o #{tgt}")
            end
        end

    The first argument to the macro is the list of files that the rule needs in order
    to produce output files. The second argument is the list of files that the rule
    produces when executed. Following those lists are two argument patterns and finally
    the recipe `do` block that performs actual work. The argument patterns work just
    like in any other Elixir function definition. The first argument is the list of
    source files, and the second is the list of output files.

    The list of source files can be both source code files and intermediary files that
    are produced by other rules. In the latter case, ExMake will invoke the necessary
    rules to produce those files.
    """
    defmacro rule(targets, sources, srcs_arg, tgts_arg, [do: block]) do
        srcs_arg = Macro.escape(srcs_arg)
        tgts_arg = Macro.escape(tgts_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            fn_name = :"rule_#{length(@rules) + 1}_line_#{__ENV__.line()}"

            @doc false
            def unquote(fn_name)(unquote(srcs_arg),
                                 unquote(tgts_arg)), do: unquote(block)

            @rules Keyword.put([targets: targets, sources: sources], :recipe, {__MODULE__, fn_name, 2})
        end
    end

    @doc """
    Same as `rule/5`, but receives as a third argument the directory of the
    script file that the rule is defined in.
    """
    defmacro rule(targets, sources, srcs_arg, tgts_arg, dir_arg, [do: block]) do
        srcs_arg = Macro.escape(srcs_arg)
        tgts_arg = Macro.escape(tgts_arg)
        dir_arg = Macro.escape(dir_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            fn_name = :"rule_#{length(@rules) + 1}_line_#{__ENV__.line()}"

            @doc false
            def unquote(fn_name)(unquote(srcs_arg),
                                 unquote(tgts_arg),
                                 unquote(dir_arg)), do: unquote(block)

            @rules Keyword.put([targets: targets, sources: sources], :recipe, {__MODULE__, fn_name, 3})
        end
    end

    @doc """
    Same as `rule/6`, but receives as a fourth argument the list of arguments passed
    to ExMake via the `--args` option, if any.
    """
    defmacro rule(targets, sources, srcs_arg, tgts_arg, dir_arg, args_arg, [do: block]) do
        srcs_arg = Macro.escape(srcs_arg)
        tgts_arg = Macro.escape(tgts_arg)
        dir_arg = Macro.escape(dir_arg)
        args_arg = Macro.escape(args_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            fn_name = :"rule_#{length(@rules) + 1}_line_#{__ENV__.line()}"

            @doc false
            def unquote(fn_name)(unquote(srcs_arg),
                                 unquote(tgts_arg),
                                 unquote(dir_arg),
                                 unquote(args_arg)), do: unquote(block)

            @rules Keyword.put([targets: targets, sources: sources], :recipe, {__MODULE__, fn_name, 4})
        end
    end

    @doc %B"""
    Defines a phony rule.

    Example:

        defmodule MyProject.Exmakefile do
            use ExMake.File

            phony "all",
                  ["foo.o"],
                  _, _ do
            end

            phony "clean",
                  [],
                  _, _, dir do
                Enum.each(Path.wildcard(Path.join(dir, "*.o")), fn(f) -> File.rm!(f) end)
            end

            rule ["foo.o"],
                 ["foo.c"],
                 [src], [tgt] do
                shell("${CC} -c #{src} -o #{tgt}")
            end
        end

    A phony rule is similar to a regular rule, but with the significant difference that
    it has no target files. That is, it acts more as a command or shortcut. In the
    example above, the `all` rule depends on `foo.o` but performs no work itself. This
    means that whenever the `all` rule is invoked, it'll make sure `foo.o` is up to
    date. The `clean` rule, on the other hand, has an empty `sources` list meaning
    that it will always execute when invoked (since there's no way to know if it's up
    to date).

    The first argument to the macro is the name of the phony rule. The second argument
    is the list of files that the rule produces when executed. Following those lists
    are two argument patterns and finally the recipe `do` block that performs actual
    work. The argument patterns work just like in any other Elixir function definition.
    The first argument is the name of the rule, and the second is the list of output
    files.

    The list of source files can be both source code files and intermediary files that
    are produced by other rules. In the latter case, ExMake will invoke the necessary
    rules to produce those files.
    """
    defmacro phony(name, sources, name_arg, srcs_arg, [do: block]) do
        name_arg = Macro.escape(name_arg)
        srcs_arg = Macro.escape(srcs_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            fn_name = :"phony_rule_#{length(@phony_rules) + 1}_line_#{__ENV__.line()}"

            @doc false
            def unquote(fn_name)(unquote(name_arg),
                                 unquote(srcs_arg)), do: unquote(block)

            @phony_rules Keyword.put([name: name, sources: sources], :recipe, {__MODULE__, fn_name, 2})
        end
    end

    @doc """
    Same as `phony/5`, but receives as a third argument the directory of the
    script file that the rule is defined in.
    """
    defmacro phony(name, sources, name_arg, srcs_arg, dir_arg, [do: block]) do
        name_arg = Macro.escape(name_arg)
        srcs_arg = Macro.escape(srcs_arg)
        dir_arg = Macro.escape(dir_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            fn_name = :"phony_rule_#{length(@phony_rules) + 1}_line_#{__ENV__.line()}"

            @doc false
            def unquote(fn_name)(unquote(name_arg),
                                 unquote(srcs_arg),
                                 unquote(dir_arg)), do: unquote(block)

            @phony_rules Keyword.put([name: name, sources: sources], :recipe, {__MODULE__, fn_name, 3})
        end
    end

    @doc """
    Same as `phony/6`, but receives as a fourth argument the list of arguments
    passed to ExMake via the `--args` option, if any.
    """
    defmacro phony(name, sources, name_arg, srcs_arg, dir_arg, args_arg, [do: block]) do
        name_arg = Macro.escape(name_arg)
        srcs_arg = Macro.escape(srcs_arg)
        dir_arg = Macro.escape(dir_arg)
        args_arg = Macro.escape(args_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            fn_name = :"phony_rule_#{length(@phony_rules) + 1}_line_#{__ENV__.line()}"

            @doc false
            def unquote(fn_name)(unquote(name_arg),
                                 unquote(srcs_arg),
                                 unquote(dir_arg),
                                 unquote(args_arg)), do: unquote(block)

            @phony_rules Keyword.put([name: name, sources: sources], :recipe, {__MODULE__, fn_name, 4})
        end
    end
end
