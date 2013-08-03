defexception ExMake.LoadError, file: "",
                               directory: "",
                               error: nil,
                               description: "" do
    @moduledoc """
    The exception raised by `ExMake.Loader.load/2` if a script file could
    not be loaded.

    `file` is the script file name. `directory` is the directory the file
    is (supposedly) located in. `error` is the underlying exception.
    `description` is the message presented to the user.
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
        self.description()
    end
end
