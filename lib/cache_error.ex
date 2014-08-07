defmodule ExMake.CacheError do
    @moduledoc """
    The exception raised if something went wrong when saving
    or loading the cache.
    """

    defexception [:message]

    @type t() :: %ExMake.CacheError{message: String.t()}
end
