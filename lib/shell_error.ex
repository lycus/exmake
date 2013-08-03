defexception ExMake.ShellError, command: "",
                                output: "",
                                exit_code: 0 do
    @moduledoc """
    The exception raised by `ExMake.Utils.shell/1` if a program does not
    exit with an exit code of zero.

    `command` contains the full command line that was executed. `output`
    contains all `stdout` and `stderr` output of the program. `exit_code`
    contains the exit code of the program.
    """

    record_type(command: String.t(),
                output: String.t(),
                exit_code: integer())

    @doc """
    Formats the exception in a user-presentable way.

    `self` is the exception record.
    """
    @spec message(t()) :: String.t()
    def message(self) do
        "#{self.output()}Command '#{self.command()}' exited with code: #{self.exit_code()}"
    end
end
