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

    The argument to the `on_load` function is a list of terms, as originally given to
    `ExMake.File.load_lib/2` or `ExMake.File.load_lib_qual/2`.
    """
    defmacro on_load(args_arg, [do: block]) do
        args_arg = Macro.escape(args_arg)
        block = Macro.escape(block)

        quote bind_quoted: binding do
            fn_name = :on_load

            @doc false
            def unquote(fn_name)(unquote(args_arg)), do: unquote(block)

            @exmake_on_load {__MODULE__, fn_name}
        end
    end
end
