defmodule ExMake.State do
    @moduledoc false

    defstruct config: nil,
              max_jobs: 1,
              jobs: HashSet.new(),
              queue: :queue.new(),
              timing: nil,
              libraries: HashSet.new()

    @type t() :: %ExMake.State{config: ExMake.Config.t() | nil,
                               max_jobs: non_neg_integer(),
                               jobs: Set.t(),
                               queue: :queue.queue({Keyword.t(), term(), pid()}),
                               timing: ExMake.Timer.session() | nil,
                               libraries: Set.t()}
end
