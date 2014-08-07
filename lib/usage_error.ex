defmodule ExMake.UsageError do
    @moduledoc """
    The exception raised if invalid command line arguments are provided.
    """

    defexception [:message]

    @type t() :: %ExMake.UsageError{message: String.t()}
end
