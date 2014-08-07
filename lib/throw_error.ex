defmodule ExMake.ThrowError do
    @moduledoc """
    The exception raised by ExMake when an arbitrary value is thrown.

    `value` is the Erlang term that was thrown.
    """

    defexception [:message,
                  :value]

    @type t() :: %ExMake.ThrowError{message: String.t(),
                                    value: term()}
end
