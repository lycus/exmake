defmodule ExMake.Lib.Host do
    use ExMake.Lib

    description "Host operating system and architecture detection."
    license "MIT License"
    version ExMake.Helpers.get_exmake_version_tuple()
    url "https://github.com/lycus/exmake"
    author "Alex Rønne Petersen", "alex@lycus.org"

    on_load _, _ do
        # http://en.wikipedia.org/wiki/Uname#Examples
        {os, fmt} = case :os.type() do
            {:unix, :aix} -> {"aix", "elf"}
            {:unix, :darwin} -> {"osx", "macho"}
            {:unix, :dragonfly} -> {"dragonflybsd", "elf"}
            {:unix, :freebsd} -> {"freebsd", "elf"}
            {:unix, :gnu} -> {"hurd", "elf"}
            {:unix, :"gnu/kfreebsd"} -> {"kfreebsd", "elf"}
            {:unix, :haiku} -> {"haiku", "elf"}
            {:unix, :"hp-ux"} -> {"hpux", "elf"}
            {:unix, :irix64} -> {"irix", "elf"}
            {:unix, :linux} -> {"linux", "elf"}
            {:unix, :netbsd} -> {"netbsd", "elf"}
            {:unix, :openbsd} -> {"openbsd", "elf"}
            {:unix, :plan9} -> {"plan9", "elf"}
            {:unix, :qnx} -> {"qnx", "elf"}
            {:unix, :sunos} -> {"solaris", "elf"}
            {:unix, :unixware} -> {"unixware", "elf"}
            {:win32, _} -> {"windows", "pe"}
            {x, y} ->
               ExMake.Logger.log_warn("Unknown host operating system '#{x}/#{y}'; assuming binary format is 'elf'")

               {"unknown", "elf"}
        end

        ExMake.Logger.log_result("Host operating system: #{os}")
        put("HOST_OS", os)

        ExMake.Logger.log_result("Host binary format: #{fmt}")
        put("HOST_FORMAT", fmt)

        sys_arch = :erlang.system_info(:system_architecture) |>
                   String.from_char_list!() |>
                   String.split() |>
                   Enum.first()

        re = fn(re) -> Regex.match?(re, sys_arch) end

        # http://wiki.debian.org/Multiarch/Tuples
        # TODO: There are more than these in the wild.
        arch = cond do
            re.(%r/^aarch64(_eb)?$/) -> "aarch64"
            re.(%r/^alpha$/) -> "alpha"
            re.(%r/^arm(eb)?$/) -> "arm"
            re.(%r/^hppa$/) -> "hppa"
            re.(%r/^i386$/) -> "i386"
            re.(%r/^ia64$/) -> "ia64"
            re.(%r/^m68k$/) -> "m68k"
            re.(%r/^mips(el)?$/) -> "mips"
            re.(%r/^mips64(el)?$/) -> "mips64"
            re.(%r/^powerpc$/) -> "ppc"
            re.(%r/^ppc64$/) -> "ppc64"
            re.(%r/^s390$/) -> "s390"
            re.(%r/^s390x$/) -> "s390x"
            re.(%r/^sh4$/) -> "sh4"
            re.(%r/^sparc$/) -> "sparc"
            re.(%r/^sparc64$/) -> "sparc64"
            re.(%r/^x86_64$/) -> "amd64"
            true ->
                ExMake.Logger.log_warn("Unknown host architecture '#{sys_arch}'")

                "unknown"
        end

        ExMake.Logger.log_result("Host architecture: #{arch}")
        put("HOST_ARCH", arch)

        endian = case <<1234 :: [size(32), native()]>> do
            <<1234 :: [size(32), big()]>> -> "big"
            <<1234 :: [size(32), little()]>> -> "little"
        end

        ExMake.Logger.log_result("Host endianness: #{endian}")
        put("HOST_ENDIAN", endian)
    end

    def host_binary_patterns() do
        case get("HOST_FORMAT") do
            "elf" ->
                [obj: "~ts.o",
                 stlib: "lib~ts.a",
                 shlib: "lib~ts.so",
                 exe: "~ts"]
            "macho" ->
                [obj: "~ts.o",
                 stlib: "lib~ts.a",
                 shlib: "lib~ts.dylib",
                 exe: "~ts"]
            "pe" ->
                [obj: "~ts.obj",
                 stlib: "lib~ts.a",
                 shlib: "~ts.dll",
                 implib: "~ts.lib",
                 exe: "~ts"]
        end
    end
end
