defmodule ExMake.EnvError do
    @moduledoc """
    The exception raised if something went wrong when accessing
    a particular environment key.

    `name` is the name of the key that caused the error.
    """

    defexception [:message,
                  :name]

    @type t() :: %ExMake.EnvError{message: String.t(),
                                  name: String.t()}
end
