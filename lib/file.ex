defmodule ExMake.File do
    @moduledoc """
    Provides various useful functions and macros for constructing script files.

    This module should be `use`d like so:

        defmodule MyProject.Exmakefile do
            use ExMake.File

            # ...
        end

    Using this module implicitly imports the following modules:

    * `File`
    * `IO`
    * `Path`
    * `System`
    * `ExMake.Env`
    * `ExMake.File`
    * `ExMake.Utils`

    A general note pertaining to the macros in this module: Avoid generating
    source and target file lists based on external factors such as system
    environment variables. The dependency graph that is generated based on
    a script file is cached, so if external factors influence the graph's
    layout, ExMake won't pick up the changes. It is, however, acceptable to
    base the layout on files declared with `manifest/1`.
    """

    @doc false
    defmacro __using__(_) do
        quote do
            import File
            import IO
            import Path
            import System
            import ExMake.Env
            import ExMake.File
            import ExMake.Utils

            @before_compile unquote(__MODULE__)

            Module.register_attribute(__MODULE__, :exmake_subdirectories, [accumulate: true, persist: true])
            Module.register_attribute(__MODULE__, :exmake_rules, [accumulate: true, persist: true])
            Module.register_attribute(__MODULE__, :exmake_tasks, [accumulate: true, persist: true])
            Module.register_attribute(__MODULE__, :exmake_fallbacks, [accumulate: true, persist: true])
            Module.register_attribute(__MODULE__, :exmake_manifest, [accumulate: true, persist: true])
        end
    end

    @doc false
    defmacro __before_compile__(_) do
        quote do
            def __exmake__(:subdirectories), do: Enum.reverse(@exmake_subdirectories)
            def __exmake__(:rules), do: Enum.reverse(@exmake_rules)
            def __exmake__(:tasks), do: Enum.reverse(@exmake_tasks)
            def __exmake__(:fallbacks), do: Enum.reverse(@exmake_fallbacks)
            def __exmake__(:manifest), do: Enum.reverse(@exmake_manifest)
        end
    end

    @doc """
    Similar to `load_lib/2`, but only `require`s the library instead of `import`ing it.
    """
    defmacro load_lib_qual(lib, args \\ []) do
        # Keep in sync with ExMake.Lib.require_lib/1.
        lib_mod = Module.concat(ExMake.Lib, Macro.expand_once(lib, __ENV__))

        quote do
            {:module, _} = Code.ensure_loaded(unquote(lib_mod))

            if !Enum.member?(ExMake.Coordinator.get_libraries(), unquote(lib_mod)) do
                case unquote(lib_mod).__exmake__(:on_load) do
                    {m, f} ->
                        cargs = ExMake.Coordinator.get_config().args()

                        apply(m, f, [unquote(args), cargs])
                    _ -> :ok
                end

                ExMake.Coordinator.add_library(unquote(lib_mod))

                require unquote(lib_mod)
            end
        end
    end

    @doc """
    Loads a library. A list of arguments can be given if the library needs it. The library
    is `import`ed after being loaded.

    `lib` must be the library name, e.g. `C` to load the C compiler module. Note that it
    must be a compile-time value. `args` must be a list of arbitrary terms.
    """
    defmacro load_lib(lib, args \\ []) do
        lib_mod = Module.concat(ExMake.Lib, Macro.expand_once(lib, __ENV__))

        quote do
            load_lib_qual(unquote(lib), unquote(args))

            import unquote(lib_mod)
        end
    end

    @doc """
    Declares a file that is part of the cached manifest.

    Example:

        # ExMake cannot see that the script file
        # depends on the my_file.exs file.
        Code.require_file "my_file.exs", __DIR__

        defmodule MyProject.Exmakefile do
            use ExMake.File

            # Declare that if my_file.exs changes
            # the cache should be invalidated.
            manifest "my_file.exs"

            # ...
        end

    This is useful to tell ExMake about non-script files that should be considered
    part of the manifest used to determine whether the cache should be invalidated.
    Such non-script files are typically not referenced directly (via `recurse/2`)
    and so ExMake is not aware that if they change, the behavior of the entire
    build can change. When those files are declared with this macro, ExMake will
    correctly invalidate the cache if they change, forcing a new evaluation of the
    script file(s).
    """
    defmacro manifest(file) do
        quote do: @exmake_manifest unquote(file)
    end

    @doc ~S"""
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
    easier to maintain. It also allows invoking ExMake inside a subdirectory without
    having to build everything from the top-level script file.

    Unlike in other Make-style tools, recursion in ExMake does not mean invoking ExMake
    itself within a subdirectory. Rather, when ExMake is invoked, it collects the full
    list of directories to recurse into and includes all rules in those directories
    into the canonical dependency graph.
    """
    defmacro recurse(dir, file \\ "Exmakefile") do
        quote do: @exmake_subdirectories {unquote(dir), unquote(file)}
    end

    @doc ~S"""
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
    produces when executed. Following those lists are three argument patterns and
    finally the recipe `do` block that performs actual work. The argument patterns work
    just like in any other Elixir function definition. The first argument is the list of
    source files, the second is the list of output files, and the third is the directory
    of the script file that the rule is defined in.

    The list of source files can be both source code files and intermediary files that
    are produced by other rules. In the latter case, ExMake will invoke the necessary
    rules to produce those files.
    """
    defmacro rule(targets, sources, srcs_arg \\ (quote do: _), tgts_arg \\ (quote do: _),
                  dir_arg \\ (quote do: _), [do: block]) do
        srcs_arg = Macro.escape(srcs_arg)
        tgts_arg = Macro.escape(tgts_arg)
        dir_arg = Macro.escape(dir_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            line = __ENV__.line()
            fn_name = :"rule_#{length(@exmake_rules) + 1}_line_#{line}"

            @doc false
            def unquote(fn_name)(unquote(srcs_arg),
                                 unquote(tgts_arg),
                                 unquote(dir_arg)), do: unquote(block)

            @exmake_rules Keyword.put([targets: targets, sources: sources], :recipe, {__MODULE__, fn_name, line})
        end
    end

    @doc ~S"""
    Defines a task.

    Example:

        defmodule MyProject.Exmakefile do
            use ExMake.File

            task "all",
                 ["foo.o"] do
            end

            task "clean",
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

    A task is similar to a regular rule, but with the significant difference that it
    has no target files. That is, it acts more as a command or shortcut. In the
    example above, the `all` task depends on `foo.o` but performs no work itself. This
    means that whenever the `all` task is invoked, it'll make sure `foo.o` is up to
    date. The `clean` task, on the other hand, has an empty `sources` list meaning
    that it will always execute when invoked (since there's no way to know if it's up
    to date).

    The first argument to the macro is the name of the task. The second argument is
    the list of files that the task depends on. Following those lists are three argument
    patterns and finally the recipe `do` block that performs actual work. The argument
    patterns work just like in any other Elixir function definition. The first argument
    is the name of the task, the second is the list of source files, and the third is
    the directory of the script file that the task is defined in.

    The list of source files can be both source code files and intermediary files that
    are produced by other rules. In the latter case, ExMake will invoke the necessary
    rules to produce those files.
    """
    defmacro task(name, sources, name_arg \\ (quote do: _), srcs_arg \\ (quote do: _),
                  dir_arg \\ (quote do: _), [do: block]) do
        name_arg = Macro.escape(name_arg)
        srcs_arg = Macro.escape(srcs_arg)
        dir_arg = Macro.escape(dir_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            line = __ENV__.line()
            fn_name = :"task_#{length(@exmake_tasks) + 1}_line_#{line}"

            @doc false
            def unquote(fn_name)(unquote(name_arg),
                                 unquote(srcs_arg),
                                 unquote(dir_arg)), do: unquote(block)

            @exmake_tasks Keyword.put([name: name, sources: sources], :recipe, {__MODULE__, fn_name, line})
        end
    end

    @doc ~S"""
    Defines a fallback task.

    Example:

        defmodule MyProject.Exmakefile do
            use ExMake.File

            fallback do
                IO.puts "The primary tasks of this build script are:"
                IO.puts "all - build everything; default if no other task is mentioned"
                IO.puts "clean - clean up intermediate and output files"
            end

            task "all",
                 ["foo.o"] do
            end

            task "clean",
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

    This defines a fallback task that is executed if a target mentioned on the command
    line is unknown to ExMake. There can be multiple fallback tasks, in which case they
    are executed in the order they were defined. They are always executed serially. Only
    the fallback tasks in the entry point build script are executed.

    The first argument to the macro is an argument pattern. The last argument is the
    `do` block that performs actual work. The argument pattern works just like in any
    other Elixir function definition. The argument is the directory of the script file
    that the fallback task is defined in.

    In the case where some targets mentioned on the command line *do* exist, even one
    target that doesn't exist will make ExMake discard all mentioned targets and only
    execute fallbacks.

    Fallback tasks cannot be invoked explicitly.
    """
    defmacro fallback(dir_arg \\ (quote do: _), [do: block]) do
        dir_arg = Macro.escape(dir_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            line = __ENV__.line()
            fn_name = :"fallback_#{length(@exmake_fallbacks) + 1}_line_#{line}"

            @doc false
            def unquote(fn_name)(unquote(dir_arg)), do: unquote(block)

            @exmake_fallbacks Keyword.put([], :recipe, {__MODULE__, fn_name, line})
        end
    end
end
