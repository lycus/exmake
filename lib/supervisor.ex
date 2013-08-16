defmodule ExMake.Supervisor do
    @moduledoc """
    Contains the default ExMake supervisor which supervises an `ExMake.Worker`
    process.
    """

    use Supervisor.Behaviour

    @doc """
    Runs the supervisor. Returns `{:ok, pid}` on success.
    """
    @spec start_link() :: {:ok, pid()}
    def start_link() do
        {:ok, _} = :supervisor.start_link(__MODULE__, nil)
    end

    @doc false
    @spec init(nil) :: {:ok, {{:one_for_one, non_neg_integer(), pos_integer()}, [:supervisor.child_spec()]}}
    def init(nil) do
        supervise([worker(ExMake.Worker, [], [restart: :temporary, shutdown: :infinity]),
                   worker(ExMake.Coordinator, [], [restart: :temporary, shutdown: :infinity])],
                  [strategy: :one_for_all])
    end
end
