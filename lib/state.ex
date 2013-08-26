defrecord ExMake.State, config: nil,
                        max_jobs: 1,
                        jobs: HashSet.new(),
                        queue: :queue.new(),
                        timing: nil,
                        libraries: HashSet.new() do
    @moduledoc false

    record_type(config: ExMake.Config.t() | nil,
                max_jobs: non_neg_integer(),
                jobs: Set.t(),
                queue: queue(),
                timing: ExMake.Timer.session() | nil,
                libraries: Set.t())
end
