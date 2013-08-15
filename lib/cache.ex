defmodule ExMake.Cache do
    @moduledoc """
    Provides functionality to persist a dependency graph to disk and
    load it back in. This is used to avoid creating the DAG anew on
    every ExMake invocation.
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

    @doc """
    Checks if the cache files are stale with regards to the
    given script files.

    `files` must be a list of paths to script files. `dir`
    must be the path to the cache directory.
    """
    @spec graph_cache_stale?([Path.t()], Path.t()) :: boolean()
    def graph_cache_stale?(files, dir // ".exmake") do
        caches = [Path.join(dir, "vertices.dag"),
                  Path.join(dir, "edges.dag"),
                  Path.join(dir, "neighbors.dag")]

        script_time = Enum.map(files, fn(s) -> ExMake.Helpers.last_modified(s) end) |> Enum.max()
        cache_time = Enum.map(caches, fn(c) -> ExMake.Helpers.last_modified(c) end) |> Enum.min()

        script_time > cache_time
    end

    @doc """
    Checks if the cache directory contains a cached
    environment table file.
    """
    @spec env_cached?(Path.t()) :: boolean()
    def env_cached?(dir // ".exmake") do
        File.exists?(Path.join(dir, "table.env"))
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
        ExMake.Env.put("EXMAKE_STAMP", :erlang.now())

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

        :ok
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
end
