defexception ExMake.ThrowError, value: nil do
    @moduledoc """
    The exception raised by ExMake when an arbitrary value is thrown.

    `value` is the Erlang term that was thrown.
    """

    record_type(file: Path.t(),
                directory: Path.t(),
                error: tuple() | nil,
                description: String.t())

    @doc """
    Formats the exception in a user-presentable way.

    `self` is the exception record.
    """
    @spec message(t()) :: String.t()
    def message(self) do
        "Erlang term was thrown: #{inspect(self.value())}"
    end
end
