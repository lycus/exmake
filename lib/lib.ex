defmodule ExMake.Lib do
    @moduledoc """
    Provides various useful functions and macros for constructing libraries.

    This module should be `use`d by all libraries:

        defmodule ExMake.Lib.MyLang do
            use ExMake.Lib

            # ...
        end

    Using this module implicitly imports the following modules:

    * `ExMake.Env`
    * `ExMake.File`
    * `ExMake.Lib`
    * `ExMake.Utils`
    """

    @doc false
    defmacro __using__(_) do
        quote do
            import ExMake.Env
            import ExMake.File
            import ExMake.Lib
            import ExMake.Utils

            @before_compile unquote(__MODULE__)

            @exmake_description ""
            @exmake_version {0, 0, 0}
            @exmake_url ""
            @exmake_on_load nil

            Module.register_attribute(__MODULE__, :exmake_description, [persist: true])
            Module.register_attribute(__MODULE__, :exmake_licenses, [accumulate: true, persist: true])
            Module.register_attribute(__MODULE__, :exmake_version, [persist: true])
            Module.register_attribute(__MODULE__, :exmake_url, [persist: true])
            Module.register_attribute(__MODULE__, :exmake_authors, [accumulate: true, persist: true])
            Module.register_attribute(__MODULE__, :exmake_on_load, [persist: true])
            Module.register_attribute(__MODULE__, :exmake_precious, [accumulate: true, persist: true])
        end
    end

    @doc false
    defmacro __before_compile__(_) do
        quote do
            def __exmake__(:description), do: @exmake_description
            def __exmake__(:licenses), do: Enum.reverse(@exmake_licenses)
            def __exmake__(:version), do: @exmake_version
            def __exmake__(:url), do: @exmake_url
            def __exmake__(:authors), do: Enum.reverse(@exmake_authors)
            def __exmake__(:on_load), do: @exmake_on_load
            def __exmake__(:precious), do: Enum.reverse(@exmake_precious)
        end
    end

    @doc """
    Sets a description for the library. Should be a string.
    """
    defmacro description(description) do
        quote do: @exmake_description unquote(description)
    end

    @doc """
    Adds a license name to the list of licenses. Should be a string.
    """
    defmacro license(license) do
        quote do: @exmake_licenses unquote(license)
    end

    @doc """
    Sets the version tuple of the library. All three version components should be
    non-negative integers.
    """
    defmacro version(tuple) do
        quote do: @exmake_version unquote(tuple)
    end

    @doc """
    Sets the URL to the library's repository. Should be a string.
    """
    defmacro url(url) do
        quote do: @exmake_url unquote(url)
    end

    @doc """
    Adds an author name/email pair to the list of authors. Both name and email should
    be strings.
    """
    defmacro author(author, email) do
        quote do: @exmake_author {unquote(author), unquote(email)}
    end

    @doc """
    Defines a function that gets called when the library is loaded.

    Example:

        defmodule ExMake.Lib.Foo do
            use ExMake.Lib

            on_load args do
                Enum.each(args, fn(arg) ->
                    # ...
                end)
            end
        end

    The first argument to the `on_load` function is a list of terms, as originally
    given to `ExMake.File.load_lib/2` or `ExMake.File.load_lib_qual/2`. The second
    argument is the list of arguments passed via the `--args` option to ExMake. In
    general, libraries should avoid using the second argument - it is primarily
    intended to be used in `configure`-like libraries written by users.

    Note that the `on_load` function will only be called when the environment table
    cache file does not exist. In other words, an `on_load` function should avoid
    having side-effects beyond setting variables in the environment table.
    """
    defmacro on_load(args1_arg, args2_arg, [do: block]) do
        args1_arg = Macro.escape(args1_arg)
        args2_arg = Macro.escape(args2_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            fn_name = :on_load

            @doc false
            def unquote(fn_name)(unquote(args1_arg),
                                 unquote(args2_arg)), do: unquote(block)

            @exmake_on_load {__MODULE__, fn_name}
        end
    end

    @doc """
    Declares an environment variable as precious.

    Example:

        defmodule ExMake.Lib.Foo do
            use ExMake.Lib

            precious "CC"

            on_load _ do
                if cc = args[:cc] || find_exe("cc", "CC") do
                    put("CC", cc)
                end
            end
        end

    This causes the variable to be saved in the configuration cache. This is useful
    to ensure that the same values are used in environment variables when ExMake
    executes configuration checks anew because of a stale cache.

    Note that only environment variables that are actually set will be cached.
    """
    defmacro precious(var) do
        quote do: @exmake_precious unquote(var)
    end
end
