defmodule ExMake.Env do
    @moduledoc """
    Provides functions to manipulate the environment table.

    This is a separate table from the system environment in order to
    avoid potential conflicts and unintended influence from the
    external environment.

    In general, avoid changing the environment table in recipes as
    this can interfere with other, unrelated recipes.
    """

    @spec ensure_ets_table() :: :exmake_env
    defp ensure_ets_table() do
        tab = :exmake_env

        _ = try do
            :ets.new(tab, [:public, :named_table])
        rescue
            ArgumentError -> :ok
        end

        tab
    end

    @doc """
    Sets the given key to the given string value.

    `name` and `value` must both be strings.
    """
    @spec put(String.t(), String.t()) :: :ok
    def put(name, value) do
        tab = ensure_ets_table()

        :ets.insert(tab, {name, value})

        :ok
    end

    @doc """
    Gets the value for a given key.

    `name` must be a string.
    """
    @spec get(String.t()) :: String.t() | nil
    def get(name) do
        tab = ensure_ets_table()

        case :ets.lookup(tab, name) do
            [{_, value}] -> value
            [] -> nil
        end
    end

    @doc """
    Deletes the entry for the given key.

    `name` must be a string.
    """
    @spec delete(String.t()) :: :ok
    def delete(name) do
        tab = ensure_ets_table()

        :ets.delete(tab, name)

        :ok
    end

    @doc """
    Appends a value to a list identified by the given key. Raises an
    `ExMake.EnvError` if the value for the given key is not a list.

    `name` and `value` must both be strings.
    """
    @spec list_append(String.t(), String.t()) :: :ok
    def list_append(name, value) do
        tab = ensure_ets_table()

        list = case :ets.lookup(tab, name) do
            [{_, list}] -> list
            [] -> []
        end

        if !is_list(list) do
            raise(ExMake.EnvError[name: name,
                                  description: "Value for key '#{name}' is not a list - cannot append element"])
        end

        :ets.insert(tab, {name, list ++ [value]})

        :ok
    end

    @doc """
    Prepends a value to a list identified by the given key. Raises an
    `ExMake.EnvError` if the value for the given key is not a list.

    `name` and `value` must both be strings.
    """
    @spec list_prepend(String.t(), String.t()) :: :ok
    def list_prepend(name, value) do
        tab = ensure_ets_table()

        list = case :ets.lookup(tab, name) do
            [{_, list}] -> list
            [] -> []
        end

        if !is_list(list) do
            raise(ExMake.EnvError[name: name,
                                  description: "Value for key '#{name}' is not a list - cannot prepend element"])
        end

        :ets.insert(tab, {name, [value | list]})

        :ok
    end

    @doc """
    Gets a list identified by a given key. Raises an `ExMake.EnvError`
    if the value for the given key is not a list.

    `name` must be a string.
    """
    @spec list_get(String.t()) :: [String.t()]
    def list_get(name) do
        tab = ensure_ets_table()

        case :ets.lookup(tab, name) do
            [{_, list}] ->
                if !is_list(list) do
                    raise(ExMake.EnvError[name: name,
                                          description: "Value for key '#{name}' is not a list - cannot retrieve"])
                end

                list
            [] -> []
        end
    end

    @doc """
    Deletes a value from a list identified by the given key. Raises an
    `ExMake.EnvError` if the value for the given key is not a list.

    `name` and `value` must both be strings.
    """
    @spec list_delete(String.t(), String.t() | Regex.t()) :: :ok
    def list_delete(name, value) do
        tab = ensure_ets_table()

        list = case :ets.lookup(tab, name) do
            [{_, list}] -> list
            [] -> []
        end

        if !is_list(list) do
            raise(ExMake.EnvError[name: name,
                                  description: "Value for key '#{name}' is not a list - cannot delete element"])
        end

        list = Enum.reject(list, fn(e) -> if is_binary(value), do: e == value, else: e =~ value end)

        :ets.insert(tab, {name, list})

        :ok
    end

    @doc """
    Performs an `Enum.reduce/3` over the environment table. Note that the
    value component of the key/value pairs iterated over with this function
    can be either a string or a list of strings.

    `acc` can be any term. `fun` must be a function taking the key/value pair
    as its first argument and the accumulator as its second argument. It must
    return the new accumulator.
    """
    @spec reduce(term(), (({String.t(), String.t() | [String.t()]}, term()) -> term())) :: term()
    def reduce(acc, fun) do
        tab = ensure_ets_table()

        :ets.foldl(fun, acc, tab)
    end
end
