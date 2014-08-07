defmodule ExMake.Helpers do
    @moduledoc false

    @spec last_modified(Path.t()) :: :file.date_time()
    def last_modified(path) do
        case File.stat(path) do
            {:ok, %File.Stat{mtime: mtime}} -> mtime
            {:error, _} -> {{1970, 1, 1}, {0, 0, 0}}
        end
    end

    @spec get_target(:digraph.graph(), Path.t()) :: {:digraph.vertex(), Keyword.t()} | nil
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
    defmacro get_exmake_version() do
        ver = String.strip(File.read!("VERSION"))

        quote do
            unquote(ver)
        end
    end

    @spec get_exmake_version_tuple() :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
    def get_exmake_version_tuple() do
        {:ok, ver} = Version.parse(get_exmake_version())

        {ver.major, ver.minor, ver.patch}
    end

    @doc false
    defmacro get_exmake_license() do
        lic = File.stream!("LICENSE") |>
              Stream.drop(8) |>
              Enum.take(1) |>
              hd() |>
              String.strip()

        quote do
            unquote(lic)
        end
    end
end
