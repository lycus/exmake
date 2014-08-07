defmodule ExMake.Supervisor do
    @moduledoc """
    Contains the default ExMake supervisor which supervises the following
    singleton processes:

    * `ExMake.Worker`
    * `ExMake.Coordinator`
    """

    use Supervisor

    @doc false
    @spec start_link() :: {:ok, pid()}
    def start_link() do
        {:ok, _} = Supervisor.start_link(__MODULE__, nil, [])
    end

    @doc false
    @spec init(nil) :: {:ok, {{:one_for_all, non_neg_integer(), pos_integer()}, [Supervisor.Spec.spec()]}}
    def init(nil) do
        supervise([worker(ExMake.Worker, [], [restart: :temporary, shutdown: :infinity]),
                   worker(ExMake.Coordinator, [], [restart: :temporary, shutdown: :infinity])],
                  [strategy: :one_for_all])
    end
end
