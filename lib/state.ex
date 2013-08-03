defrecord ExMake.State, config: nil,
                        graph: nil,
                        max_jobs: 1,
                        jobs: HashSet.new(),
                        queue: :queue.new() do
    @moduledoc """
    Represents the state of an `ExMake.Coordinator` process.

    `config` is the `ExMake.Config` instance representing the current
    configuration. `graph` is the directed acyclic graph representing the
    dependency graph. `max_jobs` is the maximum number of jobs the
    coordinator will run concurrently. `jobs` is the list of executing
    jobs. `queue` is the queue of jobs to be executed.
    """

    record_type(config: ExMake.Config.t() | nil,
                graph: digraph() | nil,
                max_jobs: non_neg_integer(),
                jobs: Set.t(),
                queue: queue())
end
