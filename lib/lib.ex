defmodule ExMake.Lib do
    @moduledoc """
    Provides various useful functions and macros for constructing libraries.

    This module should be `use`d by all libraries:

        defmodule ExMake.Lib.MyLang do
            use ExMake.Lib

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

            @description ""
            @version {0, 0, 0}
            @url ""

            Module.register_attribute(__MODULE__, :description, [persist: true])
            Module.register_attribute(__MODULE__, :licenses, [accumulate: true, persist: true])
            Module.register_attribute(__MODULE__, :version, [persist: true])
            Module.register_attribute(__MODULE__, :url, [persist: true])
            Module.register_attribute(__MODULE__, :authors, [accumulate: true, persist: true])
        end
    end

    @doc false
    defmacro __before_compile__(_) do
        quote do
            def __exmake__(:description), do: @description
            def __exmake__(:licenses), do: Enum.reverse(@licenses)
            def __exmake__(:version), do: @version
            def __exmake__(:url), do: @url
            def __exmake__(:authors), do: Enum.reverse(@authors)
        end
    end

    @doc """
    Sets a description for the library. Should be a string.
    """
    defmacro description(description) do
        quote do: @description unquote(description)
    end

    @doc """
    Adds a license name to the list of licenses. Should be a string.
    """
    defmacro license(license) do
        quote do: @licenses unquote(license)
    end

    @doc """
    Sets the version of the library. All components should be non-negative integers.
    """
    defmacro version(major, minor, patch) do
        quote do: @version {unquote(major), unquote(minor), unquote(patch)}
    end

    @doc """
    Sets the URL to the library's repository. Should be a string.
    """
    defmacro url(url) do
        quote do: @url unquote(url)
    end

    @doc """
    Adds an author name/email pair to the list of authors. Both name and email should
    be strings.
    """
    defmacro author(author, email) do
        quote do: @author {unquote(author), unquote(email)}
    end
end
