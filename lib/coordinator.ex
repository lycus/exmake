defmodule ExMake.Coordinator do
    @moduledoc """
    Encapsulates a coordinator process that stores configuration information
    and kicks off job processes for recipes.
    """

    use GenServer.Behaviour

    @typep request() :: {:set_cfg, ExMake.Config.t()} |
                        {:get_cfg} |
                        {:enqueue, Keyword.t(), pid()} |
                        {:done, Keyword.t(), pid(), :ok | tuple()} |
                        {:apply_timer, ((ExMake.Timer.session()) -> ExMake.Timer.session())}

    @typep reply() :: {:set_cfg} |
                      {:get_cfg, ExMake.Config.t()} |
                      {:enqueue} |
                      {:done} |
                      {:apply_timer}

    @doc """
    Starts a coordinator process linked to the parent process. Returns
    `{:ok, pid}` on success.
    """
    @spec start_link() :: {:ok, pid()}
    def start_link() do
        tup = {:ok, pid} = :gen_server.start_link(__MODULE__, ExMake.State[], [])
        Process.register(pid, :exmake_coordinator)
        tup
    end

    @doc """
    Locates the coordinator process. Returns the PID if found; otherwise,
    returns `nil`.
    """
    @spec locate() :: pid() | nil
    def locate() do
        Process.whereis(:exmake_coordinator)
    end

    @doc """
    Sets the configuration values for the ExMake application.

    `cfg` must be a valid `ExMake.Config` instance. `timeout` must be
    `:infinity` or a millisecond value specifying how much time to wait for
    the operation to complete.
    """
    @spec set_config(ExMake.Config.t(), timeout()) :: :ok
    def set_config(cfg, timeout // :infinity) do
        :gen_server.call(locate(), {:set_cfg, cfg}, timeout)
        :ok
    end

    @doc """
    Gets the configuration values used by the ExMake application. Returns
    `nil` if no values have been set yet.

    `timeout` must be `:infinity` or a millisecond value specifying how much
    time to wait for the operation to complete.
    """
    @spec get_config(timeout()) :: ExMake.Config.t() | nil
    def get_config(timeout // :infinity) do
        {:get_cfg, cfg} = :gen_server.call(locate(), {:get_cfg}, timeout)
        cfg
    end

    @doc """
    Enqueues a job.

    Jobs are executed as soon as there is a free job slot available. Once the
    job has executed, the coordinator will send a message to `owner`:

    * `{:exmake_done, rule, :ok}` if the job executed successfully.
    * `{:exmake_done, rule, {:throw, value}}` if a value was thrown.
    * `{:exmake_done, rule, {:raise, exception}}` if an exception was raised.

    Here, `rule` is the rule originally passed to this function.

    `rule` must be the keyword list describing the rule. `owner` must be a PID
    pointing to the process that should be notified once the job is done.
    `timeout` must be `:infinity` or a millisecond value specifying how much
    time to wait for the operation to complete.
    """
    @spec enqueue(Keyword.t(), pid(), timeout()) :: :ok
    def enqueue(rule, owner // self(), timeout // :infinity) do
        :gen_server.call(locate(), {:enqueue, rule, owner}, timeout)
        :ok
    end

    @doc """
    Applies a given function on the `ExMake.Timer` session object. The function
    receives the session object as its only parameter and must return a new session
    object.

    `fun` must be the function to apply on the session object. `timeout` must be
    `:infinity` or a millisecond value specifying how much time to wait for the
    operation to complete.
    """
    @spec apply_timer_fn(((ExMake.Timer.session()) -> ExMake.Timer.session()), timeout()) :: :ok
    def apply_timer_fn(fun, timeout // :infinity) do
        :gen_server.call(locate(), {:apply_timer, fun}, timeout)
        :ok
    end

    @doc false
    @spec handle_call(request(), {pid(), term()}, ExMake.State.t()) :: {:reply, reply(), ExMake.State.t()}
    def handle_call(msg, {sender, _}, state) do
        reply = case msg do
            {:set_cfg, cfg} ->
                state = state.config(cfg).max_jobs(cfg.options[:jobs] || 1)
                {:set_cfg}
            {:get_cfg} ->
                {:get_cfg, state.config()}
            {:enqueue, rule, owner} ->
                if Set.size(state.jobs()) < state.max_jobs() do
                    # If we have a free job slot, just run it right away.
                    job = ExMake.Runner.start(self(), rule, owner)
                    state = state.jobs(Set.put(state.jobs(), {rule, owner, job}))
                else
                    # No free slot, so schedule the job for later. We'll run it
                    # once we get a :done message from some other job.
                    state = state.queue(:queue.in({rule, owner}, state.queue()))
                end

                {:enqueue}
            {:done, rule, owner, result} ->
                state = state.jobs(Set.delete(state.jobs(), {rule, owner, sender}))

                # We have a free job slot, so run a job if one is enqueued.
                case :queue.out(state.queue()) do
                    {{:value, {rule, owner}}, queue} ->
                        job = ExMake.Runner.start(self(), rule, owner)
                        state = state.queue(queue).jobs(Set.put(state.jobs(), {rule, owner, job}))
                    {:empty, _} -> :ok
                end

                owner <- {:exmake_done, rule, result}

                {:done}
            {:apply_timer, fun} ->
                state = state.timing(fun.(state.timing()))
                {:apply_timer}
        end

        {:reply, reply, state}
    end
end
