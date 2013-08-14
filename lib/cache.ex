defmodule ExMake.Cache do
    @moduledoc """
    Provides functionality to persist a dependency graph to disk and
    load it back in. This is used to avoid creating the DAG anew on
    every ExMake invocation.
    """

    @doc """
    Checks if the cache files are stale with regards to the
    given script files.

    `files` must be a list of paths to script files. `dir`
    must be the path to the cache directory.
    """
    @spec cache_stale?([Path.t()]) :: boolean()
    def cache_stale?(files, dir // ".exmake") do
        caches = [Path.join(dir, "vertices.dag"),
                  Path.join(dir, "edges.dag"),
                  Path.join(dir, "neighbors.dag")]

        script_time = Enum.map(files, fn(s) -> ExMake.Helpers.last_modified(s) end) |> Enum.max()
        cache_time = Enum.map(caches, fn(c) -> ExMake.Helpers.last_modified(c) end) |> Enum.min()

        script_time > cache_time
    end

    @doc """
    Saves the given graph to the given cache directory.

    `graph` must be a `:digraph` instance. `dir` must be
    the path to the cache directory.
    """
    @spec save_graph(digraph()) :: :ok
    def save_graph(graph, dir // ".exmake") do
        case File.mkdir_p(dir) do
            {:error, r} -> raise(ExMake.CacheError[description: "Could not create cache directory '#{dir}'"])
            _ -> :ok
        end

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
                    ExMake.Logger.debug("Failed to save cache file '#{path}': #{inspect(r)}")
                    raise(ExMake.CacheError[description: "Could not save cache file '#{path}'"])
                _ -> :ok
            end
        end)

        :ok
    end

    @doc """
    Loads a graph from the given cache directory and
    returns it.

    `dir` must be the path to the cache directory.
    """
    @spec load_graph() :: digraph()
    def load_graph(dir // ".exmake") do
        files = [Path.join(dir, "vertices.dag"),
                 Path.join(dir, "edges.dag"),
                 Path.join(dir, "neighbors.dag")]

        # It's intentional that we don't create the
        # directory here. We should only create it if
        # needed in save_graph.
        list = Enum.map(files, fn(path) ->
            case :ets.file2tab(String.to_char_list!(path)) do
                {:error, _} -> raise(ExMake.CacheError[description: "Could not load cache file '#{path}'"])
                {:ok, tab} -> tab
            end
        end)

        [vertices, edges, neighbors] = list

        {:digraph, vertices, edges, neighbors, false}
    end
end
