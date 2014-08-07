defmodule ExMake.Timer do
    @moduledoc """
    Provides convenience functions for timing.
    """

    @opaque session() :: {String.t(), non_neg_integer(), non_neg_integer(), Dict.t()}
    @opaque finished_session() :: {String.t(), Dict.t()}

    @doc """
    Creates a timing session. Returns an opaque session object.

    `title` must be a binary containing the title of this timing session.
    """
    @spec create_session(String.t()) :: session()
    def create_session(title) do
        {title, 0, 0, HashDict.new()}
    end

    @doc """
    Starts a pass in the given session. Returns the updated session.

    `session` must be a session object. `name` must be a binary containing the
    name of this timing pass.
    """
    @spec start_pass(session(), String.t()) :: session()
    def start_pass(session, name) do
        {title, time, n, passes} = session
        {title, time, n, Dict.put(passes, name, {n, :erlang.now()})}
    end

    @doc """
    Ends the current timing pass in the given session. Returns the updated
    session.

    `session` must be a session object with an in-progress pass. `name` must be
    the name given to the `start_pass/2` function previously.
    """
    @spec end_pass(session(), String.t()) :: session()
    def end_pass(session, name) do
        {title, time, n, passes} = session
        diff = :timer.now_diff(:erlang.now(), elem(passes[name], 1))
        {title, time + diff, n + 1, Dict.update(passes, name, nil, fn({n, _}) -> {n, diff} end)}
    end

    @doc """
    Ends a given timing session. Returns the finished session object.

    `session` must be a session object with no in-progress passes.
    """
    @spec finish_session(session()) :: finished_session()
    def finish_session(session) do
        {title, time, n, passes} = session
        pairs = for {n, {i, t}} <- Dict.to_list(passes), do: {i, n, t, t / time * 100}
        {title, pairs ++ [{n + 1, "Total", time, 100.0}]}
    end

    @doc """
    Formats a finished session in a user-presentable way. Returns the resulting
    binary containing the formatted session.

    `session` must be a finished session object.
    """
    @spec format_session(finished_session()) :: String.t()
    def format_session(session) do
        {title, passes} = session

        sep = "    ===------------------------------------------------------------------------------------------==="
        head = "                                          #{title}"
        head2 = "        Time                                          Percent    Name"
        sep2 = "        --------------------------------------------- ---------- -------------------------------"

        passes = for {_, name, time, perc} <- Enum.sort(passes) do
            msecs = div(time, 1000)
            secs = div(msecs, 1000)
            mins = div(secs, 60)
            hours = div(mins, 60)
            days = div(hours, 24)

            ftime = "#{days}d | #{hours}h | #{mins}m | #{secs}s | #{msecs}ms | #{time}us"

            :unicode.characters_to_binary(:io_lib.format("        ~-45s ~-10.1f #{name}", [ftime, perc]))
        end

        joined = Enum.join(passes, "\n")

        "\n" <> sep <> "\n" <> head <> "\n" <> sep <> "\n\n" <> head2 <> "\n" <> sep2 <> "\n" <> joined <> "\n"
    end
end
