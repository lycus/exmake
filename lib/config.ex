defmodule ExMake.Config do
    @moduledoc """
    Represents the configuration for an invocation of ExMake.

    `targets` is a list of targets to build. `options` is a keyword list
    of global options. `args` is the list of tail arguments given with
    `--args`.

    `options` can contain:

    * `help`: Boolean value indicating whether to print the help message.
    * `version`: Boolean value indicating whether to print the version.
    * `file`: String value indicating which script file to use.
    * `loud`: Boolean value indicating whether to print targets and commands.
    * `question`: Boolean value indicating whether to just perform an up-to-date check.
    * `jobs`: Integer value indicating how many concurrent jobs to run.
    * `time`: Boolean value indicating whether to print timing information.
    * `clear`: Boolean value indicating whther to clear the graph and environment cache.
    """

    defstruct targets: [],
              options: [],
              args: []

    @type t() :: %ExMake.Config{targets: [String.t(), ...],
                                options: Keyword.t(),
                                args: [String.t()]}
end
