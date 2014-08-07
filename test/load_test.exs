Code.require_file("test_helper.exs", __DIR__)

defmodule ExMake.Test.LoadTest do
    use ExMake.Test.Case

    test "no module" do
        {p, _} = create_fixture("no_module", "NoModule", "", raw: true)
        {t, c} = execute_in(p)

        assert c == 1
        assert t == "ExMake.LoadError: ./Exmakefile: No module ending in '.Exmakefile' defined"
    end

    test "too many modules" do
        c = """
        defmodule TooManyModules1.Exmakefile do
        end

        defmodule TooManyModules2.Exmakefile do
        end
        """

        {p, _} = create_fixture("too_many_modules", "TooManyModules", c, raw: true)
        {t, c} = execute_in(p)

        assert c == 1
        assert t == "ExMake.LoadError: ./Exmakefile: 2 modules ending in '.Exmakefile' defined"
    end

    test "single module" do
        s = """
        task "all",
             [] do
        end
        """

        {p, _} = create_fixture("single_module", "SingleModule", s)
        {t, c} = execute_in(p)

        assert c == 0
        assert t == ""
    end

    test "custom file name" do
        s = """
        task "all",
             [] do
        end
        """

        {p, _} = create_fixture("custom_file_name", "CustomFileName", s, file: "foo.exmake")
        {t, c} = execute_in(p, ["-f", "foo.exmake"])

        assert c == 0
        assert t == ""
    end

    test "invalid file" do
        {p, _} = create_fixture("invalid_file", "InvalidFile", "", file: "invalid_file.exmake")
        {t, c} = execute_in(p)

        assert c == 1
        assert t == "ExMake.LoadError: ./Exmakefile: Could not load file"
    end

    test "compile error" do
        {p, _} = create_fixture("compile_error", "CompileError", "a + b")
        {t, c} = execute_in(p)

        assert c == 1
        assert t =~ ~r/ExMake.LoadError: .*Exmakefile:4: undefined function a\/0/
    end
end
