defmodule ExMake.Helpers do
    @moduledoc false

    @spec last_modified(Path.t()) :: :file.date_time()
    def last_modified(path) do
        case File.stat(path) do
            {:ok, File.Stat[mtime: mtime]} -> mtime
            {:error, _} -> {{1970, 1, 1}, {0, 0, 0}}
        end
    end

    @spec get_target(digraph(), Path.t()) :: {:digraph.vertex(), Keyword.t()} | nil
    def get_target(graph, target) do
        Enum.find_value(:digraph.vertices(graph), fn(v) ->
            {_, r} = :digraph.vertex(graph, v)

            cond do
                (n = r[:name]) && Path.expand(n) == Path.expand(target) -> {v, r}
                (t = r[:targets]) && Enum.any?(t, fn(p) -> Path.expand(p) == Path.expand(target) end) -> {v, r}
                true -> nil
            end
        end)
    end

    @spec make_presentable(Keyword.t()) :: Keyword.t()
    def make_presentable(rule) do
        rule |>
        Keyword.delete(:recipe) |>
        Keyword.delete(:directory) |>
        Keyword.delete(:real_sources)
    end

    @doc false
    @spec get_exmake_version() :: String.t()
    def get_exmake_version() do
        if Enum.all?(:application.which_applications(), fn({a, _, _}) -> a != :mix end) do
            Mix.loadpaths()
        end

        Mix.project()[:version]
    end

    @spec get_exmake_version_tuple() :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
    def get_exmake_version_tuple() do
        {:ok, ver} = Version.parse(get_exmake_version())

        {ver.major(), ver.minor(), ver.patch()}
    end
end
