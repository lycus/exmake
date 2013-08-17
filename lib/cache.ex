defmodule ExMake.Cache do
    @moduledoc """
    Provides functionality to persist dependency graphs, environment
    tables, and compiled script modules to disk and load them back in.
    This is used to avoid a lot of the startup overhead that most
    traditional Make-style tools suffer from.
    """

    @spec ensure_cache_dir(Path.t()) :: :ok
    defp ensure_cache_dir(dir) do
        case File.mkdir_p(dir) do
            {:error, r} ->
                ExMake.Logger.debug("Failed to create cache directory '#{dir}': #{inspect(r)}")
                raise(ExMake.CacheError[description: "Could not create cache directory '#{dir}'"])
            _ -> :ok
        end
    end

    @spec get_cache_files(Path.t()) :: [Path.t(), ...]
    defp get_cache_files(dir) do
        [Path.join(dir, "vertices.dag"),
         Path.join(dir, "edges.dag"),
         Path.join(dir, "neighbors.dag"),
         Path.join(dir, "table.env"),
         Path.join(dir, "manifest.lst")]
    end

    @spec get_manifest_list(Path.t()) :: [Path.t()]
    defp get_manifest_list(dir) do
        case File.read(Path.join(dir, "manifest.lst")) do
            {:ok, lines} ->
                String.split(lines, "\n") |>
                Enum.filter(fn(x) -> x != "" end)
            _ -> []
        end
    end

    @spec get_beam_files(Path.t()) :: [Path.t()]
    defp get_beam_files(dir) do
        Path.wildcard(Path.join([dir, "**", "*.beam"]))
    end

    @doc """
    Removes all cached files from the given directory
    if they exist.

    `dir` must be the path to the cache directory.
    """
    @spec clear_cache(Path.t()) :: :ok
    def clear_cache(dir // ".exmake") do
        Enum.each(get_cache_files(dir) ++ get_beam_files(dir), fn(f) -> File.rm(f) end)
    end

    @doc """
    Checks if the cache files are stale with regards to the
    script files in the manifest.

    `dir` must be the path to the cache directory.
    """
    @spec cache_stale?(Path.t()) :: boolean()
    def cache_stale?(dir // ".exmake") do
        case get_manifest_list(dir) do
            [] -> true
            files ->
                caches = get_cache_files(dir) ++ get_beam_files(dir)

                script_time = Enum.map(files, fn(s) -> ExMake.Helpers.last_modified(s) end) |> Enum.max()
                cache_time = Enum.map(caches, fn(c) -> ExMake.Helpers.last_modified(c) end) |> Enum.min()

                script_time > cache_time
        end
    end

    @doc """
    Saves the `:exmake_env` table to the environment
    table cache file in the given cache directory. Raises
    `ExMake.CacheError` if something went wrong.

    `table` must be an ETS table ID. `dir` must be the
    path to the cache directory.
    """
    @spec save_env(Path.t()) :: :ok
    def save_env(dir // ".exmake") do
        ensure_cache_dir(dir)

        # Ensure that the table has been created.
        ExMake.Env.put("EXMAKE_STAMP", inspect(:erlang.now()))

        path = Path.join(dir, "table.env")

        case :ets.tab2file(:exmake_env, String.to_char_list!(path)) do
            {:error, r} ->
                ExMake.Logger.debug("Failed to save environment cache file '#{path}': #{inspect(r)}")
                raise(ExMake.CacheError[description: "Could not save environment cache file '#{path}'"])
            _ -> :ok
        end
    end

    @doc """
    Loads the environment table cache file from the
    given cache directory. It is expected that the
    table has the name `:exmake_env`. Raises
    `ExMake.CacheError` if something went wrong.

    `dir` must be the path to the cache directory.
    """
    @spec load_env(Path.t()) :: :exmake_env
    def load_env(dir // ".exmake") do
        path = Path.join(dir, "table.env")

        # If the table exists, kill it, then reload from cache.
        try do
            :ets.delete(:exmake_env)
        rescue
            ArgumentError -> :ok
        end

        case :ets.file2tab(String.to_char_list!(path)) do
            {:error, r} ->
                ExMake.Logger.debug("Failed to load environment cache file '#{path}': #{inspect(r)}")
                raise(ExMake.CacheError[description: "Could not load environment cache file '#{path}'"])
            {:ok, tab} -> tab
        end
    end

    @doc """
    Saves the given graph to the given cache directory.
    Raises `ExMake.CacheError` if something went wrong.

    `graph` must be a `:digraph` instance. `dir` must be
    the path to the cache directory.
    """
    @spec save_graph(digraph(), Path.t()) :: :ok
    def save_graph(graph, dir // ".exmake") do
        ensure_cache_dir(dir)

        # We really shouldn't be exploiting knowledge about
        # the representation of digraph, but since the API
        # doesn't provide save/load functions, we can't do
        # it any other way.
        {_, vertices, edges, neighbors, _} = graph

        pairs = [{vertices, Path.join(dir, "vertices.dag")},
                 {edges, Path.join(dir, "edges.dag")},
                 {neighbors, Path.join(dir, "neighbors.dag")}]

        Enum.each(pairs, fn({tab, path}) ->
            case :ets.tab2file(tab, String.to_char_list!(path)) do
                {:error, r} ->
                    ExMake.Logger.debug("Failed to save graph cache file '#{path}': #{inspect(r)}")
                    raise(ExMake.CacheError[description: "Could not save graph cache file '#{path}'"])
                _ -> :ok
            end
        end)
    end

    @doc """
    Loads a graph from the given cache directory and
    returns it. Raises `ExMake.CacheError` if something
    went wrong.

    `dir` must be the path to the cache directory.
    """
    @spec load_graph(Path.t()) :: digraph()
    def load_graph(dir // ".exmake") do
        files = [Path.join(dir, "vertices.dag"),
                 Path.join(dir, "edges.dag"),
                 Path.join(dir, "neighbors.dag")]

        # It's intentional that we don't create the
        # directory here. We should only create it if
        # needed in save_graph.
        list = Enum.map(files, fn(path) ->
            case :ets.file2tab(String.to_char_list!(path)) do
                {:error, r} ->
                    ExMake.Logger.debug("Failed to load graph cache file '#{path}': #{inspect(r)}")
                    raise(ExMake.CacheError[description: "Could not load graph cache file '#{path}'"])
                {:ok, tab} -> tab
            end
        end)

        [vertices, edges, neighbors] = list

        {:digraph, vertices, edges, neighbors, false}
    end

    @doc """
    Writes the manifest file to the cache with the
    given files. Raises `ExMake.CacheError` if something
    went wrong.

    `files` must be a list of files that are to be
    considered part of the cache manifest. `dir` must
    be the path to the cache directory.
    """
    @spec save_manifest([Path.t()], Path.t()) :: :ok
    def save_manifest(files, dir // ".exmake") do
        ensure_cache_dir(dir)

        path = Path.join(dir, "manifest.lst")
        data = Enum.join(files, "\n") <> "\n"

        case File.write(path, data) do
            {:error, r} ->
                ExMake.Logger.debug("Failed to save manifest file '#{path}': #{inspect(r)}")
                raise(ExMake.CacheError[description: "Could not save manifest file '#{path}'"])
            :ok -> :ok
        end
    end

    @doc """
    Saves the given list of modules to the given
    cache directory.

    `mods` must be a list of `{mod, bin}` pairs, where
    `mod` is the module name and `bin` is the bytecode.
    `dir` must be the path to the cache directory.
    """
    @spec save_mods([{module(), binary()}], Path.t()) :: :ok
    def save_mods(mods, dir // ".exmake") do
        ensure_cache_dir(dir)

        Enum.each(mods, fn({mod, bin}) ->
            path = Path.join(dir, atom_to_binary(mod) <> ".beam")

            case File.write(path, bin) do
                {:error, r} ->
                    ExMake.Logger.debug("Failed to save cached module '#{path}': #{inspect(r)}")
                    raise(ExMake.CacheError[description: "Could not save cached module '#{path}'"])
                :ok -> :ok
            end
        end)
    end

    @doc """
    Loads all modules in the given cache directory.

    `dir` must be the path to the cache directory.
    """
    @spec load_mods(Path.t()) :: :ok
    def load_mods(dir // ".exmake") do
        Enum.each(get_beam_files(dir), fn(beam) ->
            path = Path.rootname(beam)

            case :code.load_abs(String.to_char_list!(path)) do
                {:error, r} ->
                    ExMake.Logger.debug("Failed to load cached module '#{beam}': #{inspect(r)}")
                    raise(ExMake.CacheError[description: "Could not load cached module '#{beam}'"])
                _ -> :ok
            end
        end)
    end
end
