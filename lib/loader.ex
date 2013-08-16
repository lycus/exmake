defmodule ExMake.Loader do
    @moduledoc """
    Contains logic to load script files.
    """

    @doc """
    Loads script file `file` in directory `dir`. Returns a list of
    `{dir, file, mod}` where `mod` is the name of the module containing
    rules and recipes. Raises `ExMake.LoadError` if loading failed for
    some reason. Raises `ExMake.ScriptError` if an `ExMake.File.recurse`
    directive contained an invalid directory or file name. Raises
    `ExMake.UsageError` if `file` is invalid.

    `dir` must be a path to a directory. `file` must be the name of the
    file to load in `dir`.
    """
    @spec load(Path.t(), Path.t()) :: [{Path.t(), Path.t(), module()}, ...]
    def load(dir, file // "Exmakefile") do
        if String.contains?(file, ["\\", "/"]) do
            raise(ExMake.UsageError[description: "Script file name '#{file}' contains path separator"])
        end

        p = Path.join(dir, file)

        list = try do
            File.cd!(dir, fn() -> Code.load_file(file) end)
        rescue
            ex in [Code.LoadError] ->
                raise(ExMake.LoadError[file: file,
                                       directory: dir,
                                       error: ex,
                                       description: "#{p}: Could not load file"])
            ex in [CompileError] ->
                raise(ExMake.LoadError[file: file,
                                       directory: dir,
                                       error: ex,
                                       description: ex.message()])
        end

        mods = Enum.map(list, fn({x, _}) -> x end)
        cnt = Enum.count(mods, fn(x) -> atom_to_binary(x) |> String.ends_with?(".Exmakefile") end)

        cond do
            cnt == 0 ->
                raise(ExMake.LoadError[file: file,
                                       directory: dir,
                                       error: nil,
                                       description: "#{p}: No module ending in '.Exmakefile' defined"])
            cnt > 1 ->
                raise(ExMake.LoadError[file: file,
                                       directory: dir,
                                       error: nil,
                                       description: "#{p}: #{cnt} modules ending in '.Exmakefile' defined"])
            true -> :ok
        end

        mod = Enum.fetch!(mods, 0)
        rec = mod.__exmake__(:subdirectories)

        Enum.each(rec, fn({sub, file}) ->
            if !String.valid?(sub) do
                raise(ExMake.ScriptError[description: "Subdirectory path must be a string"])
            end

            if !String.valid?(file) do
                raise(ExMake.ScriptError[description: "Subdirectory file must be a string"])
            end

            if String.contains?(sub, ["\\", "/"]) do
                raise(ExMake.ScriptError[description: "Subdirectory path '#{sub}' contains path separator"])
            end

            if String.contains?(file, ["\\", "/"]) do
                raise(ExMake.ScriptError[description: "Subdirectory file '#{file}' contains path separator"])
            end
        end)

        lists = rec |>
                Enum.map(fn({d, f}) -> load(Path.join(dir, d), f) end) |>
                List.flatten()

        [{dir, file, mod} | lists]
    end
end
