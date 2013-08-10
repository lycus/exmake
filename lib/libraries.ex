defmodule ExMake.Libraries do
    @moduledoc """
    Contains functions to manage the loading of 'libraries'; that is, modules
    that script files can `use` and call macros/functions in.

    By convention, such modules begin with `ExMake.Lib.` and are followed by
    some named describing what the module contains, e.g. `ExMake.Lib.C`.

    By default, ExMake looks for libraries in:

    * `/usr/local/lib/exmake`
    * `/usr/lib/exmake`
    * `/lib/exmake`

    Additionally, if the `HOME` environment variable is defined, it will look
    in `$HOME/.exmake`.

    The `EXMAKE_PATH` environment variable can be set to a colon-separated
    list of paths to use. When it is set, the above paths will not be considered.
    """

    @doc """
    Returns a list of paths to search for libraries in.
    """
    @spec search_paths() :: [Path.t()]
    def search_paths() do
        if s = System.get_env("EXMAKE_PATH") do
            ExMake.Logger.debug("Using EXMAKE_PATH: #{s}")

            Enum.filter(String.split(s, ":"), fn(s) -> s != "" end)
        else
            p = [Path.join(["/usr", "local", "lib", "exmake"]),
                 Path.join(["/usr", "lib", "exmake"]),
                 Path.join(["/lib", "exmake"])]

            if s = System.get_env("HOME") do
                p = [Path.join(s, ".exmake")] ++ p
            end

            p
        end
    end

    @doc """
    Adds a given path to the global code path such that script files can
    load libraries from it.

    Returns `:ok` on success or `:error` if something went wrong (e.g. the
    path doesn't exist).
    """
    @spec append_path(Path.t()) :: :ok | :error
    def append_path(path) do
        case Code.append_path(path) do
            true -> :ok
            {:error, r} ->
                ExMake.Logger.debug("Could not add code path #{path}: #{r}")
                :error
        end
    end
end
