defexception ExMake.StaleError, rule: [] do
    @moduledoc """
    The exception raised in `--question` mode if a rule has stale targets.

    `rule` is the rule that has stale targets.
    """

    record_type(rule: Keyword.t())

    @doc """
    Formats the exception in a user-presentable way.

    `self` is the exception record.
    """
    @spec message(t()) :: String.t()
    def message(self) do
        "A rule has stale targets: #{inspect(self.rule())}"
    end
end
