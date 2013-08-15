defexception ExMake.EnvError, name: "",
                              description: "" do
    @moduledoc """
    The exception raised if something went wrong when accessing
    a particular environment key.

    `name` is the name of the key that caused the error.
    `description` is the message presented to the user.
    """

    record_type(name: String.t(),
                description: String.t())

    @doc """
    Formats the exception in a user-presentable way.

    `self` is the exception record.
    """
    @spec message(t()) :: String.t()
    def message(self) do
        self.description()
    end
end
