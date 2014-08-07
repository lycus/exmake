defmodule ExMake.ScriptError do
    @moduledoc """
    The exception raised if a rule in a script file is invalid.
    """

    defexception [:message]

    @type t() :: %ExMake.ScriptError{message: String.t()}
end
