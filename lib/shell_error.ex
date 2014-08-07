defmodule ExMake.ShellError do
    @moduledoc """
    The exception raised by `ExMake.Utils.shell/2` if a program does not
    exit with an exit code of zero.

    `command` contains the full command line that was executed. `output`
    contains all `stdout` and `stderr` output of the program. `exit_code`
    contains the exit code of the program.
    """

    defexception [:message,
                  :command,
                  :output,
                  :exit_code]

    @type t() :: %ExMake.ShellError{message: String.t(),
                                    command: String.t(),
                                    output: String.t(),
                                    exit_code: integer()}
end
