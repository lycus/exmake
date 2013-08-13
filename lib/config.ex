defrecord ExMake.Config, targets: [],
                         options: [] do
    @moduledoc """
    Represents the configuration for an invocation of ExMake.

    `targets` is a list of targets to build. `options` is a keyword list
    of global options.

    `options` can contain:

    * `help`: Boolean value indicating whether to print the help message.
    * `version`: Boolean value indicating whether to print the version.
    * `file`: String value indicating which script file to use.
    * `loud`: Boolean value indicating whether to print targets and commands.
    * `question`: Boolean value indicating whether to just perform an up-to-date check.
    * `jobs`: Integer value indicating how many concurrent jobs to run.
    * `args`: String value indicating arguments to be passed to rules.
    * `time`: Boolean value indicating whether to print timing information.
    """

    record_type(targets: [String.t(), ...],
                options: Keyword.t())
end
