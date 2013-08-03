defexception ExMake.UsageError, description: "" do
    @moduledoc """
    The exception raised if invalid command line arguments are provided.

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
