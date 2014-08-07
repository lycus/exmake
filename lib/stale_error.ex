defmodule ExMake.StaleError do
    @moduledoc """
    The exception raised in `--question` mode if a rule has stale targets.

    `rule` is the rule that has stale targets.
    """

    defexception [:message,
                  :rule]

    @type t() :: %ExMake.StaleError{message: String.t(), rule: Keyword.t()}
end
