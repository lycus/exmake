defmodule ExMake.LoadError do
    @moduledoc """
    The exception raised by `ExMake.Loader.load/2` if a script file could
    not be loaded.

    `file` is the script file name. `directory` is the directory the file
    is (supposedly) located in. `error` is the underlying exception.
    """

    defexception [:message,
                  :file,
                  :directory,
                  :error]

    @type t() :: %ExMake.LoadError{message: String.t(),
                                   file: Path.t(),
                                   directory: Path.t(),
                                   error: Exception.t() | nil}
end
