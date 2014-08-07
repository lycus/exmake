defmodule ExMake.Loader do
    @moduledoc """
    Contains logic to load script files.
    """

    @doc """
    Loads script file `file` in directory `dir`. Returns a list of
    `{dir, file, mod, bin}` where `mod` is the name of the module containing
    rules and recipes and `bin` is the bytecode of the module. Raises
    `ExMake.LoadError` if loading failed for some reason. Raises
    `ExMake.ScriptError` if an `ExMake.File.recurse` directive contained
    an invalid directory or file name. Raises `ExMake.UsageError` if `file`
    is invalid.

    `dir` must be a path to a directory. `file` must be the name of the
    file to load in `dir`.
    """
    @spec load(Path.t(), Path.t()) :: [{Path.t(), Path.t(), module(), binary()}, ...]
    def load(dir, file \\ "Exmakefile") do
        p = Path.join(dir, file)

        list = try do
            File.cd!(dir, fn() -> Code.load_file(file) end)
        rescue
            ex in [Code.LoadError] ->
                raise(ExMake.LoadError,
                      [message: "#{p}: Could not load file",
                       file: file,
                       directory: dir,
                       error: ex])
            ex in [CompileError] ->
                raise(ExMake.LoadError,
                      [message: Exception.message(ex),
                       file: file,
                       directory: dir,
                       error: ex])
        end

        cnt = Enum.count(list, fn({x, _}) -> Atom.to_string(x) |> String.ends_with?(".Exmakefile") end)

        cond do
            cnt == 0 ->
                raise(ExMake.LoadError,
                      [message: "#{p}: No module ending in '.Exmakefile' defined",
                       file: file,
                       directory: dir,
                       error: nil])
            cnt > 1 ->
                raise(ExMake.LoadError,
                      [message: "#{p}: #{cnt} modules ending in '.Exmakefile' defined",
                       file: file,
                       directory: dir,
                       error: nil])
            true -> :ok
        end

        {mod, bin} = Enum.fetch!(list, 0)
        rec = mod.__exmake__(:subdirectories)

        Enum.each(rec, fn({sub, file}) ->
            if !String.valid?(sub) do
                raise(ExMake.ScriptError, [message: "Subdirectory path must be a string"])
            end

            if !String.valid?(file) do
                raise(ExMake.ScriptError, [message: "Subdirectory file must be a string"])
            end
        end)

        lists = rec |>
                Enum.map(fn({d, f}) -> load(Path.join(dir, d), f) end) |>
                List.flatten()

        [{dir, file, mod, bin} | lists]
    end
end
