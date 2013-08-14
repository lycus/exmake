defexception ExMake.CacheError, description: "" do
    @moduledoc """
    The exception raised if something went wrong when saving
    or loading the cache.

    `description` is the message presented to the user.
    """

    record_type(description: String.t())

    @doc """
    Formats the exception in a user-presentable way.

    `self` is the exception record.
    """
    @spec message(t()) :: String.t()
    def message(self) do
        self.description()
    end
end
