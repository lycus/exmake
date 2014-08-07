defmodule ExMake.Coordinator do
    @moduledoc """
    Encapsulates a coordinator process that stores configuration information
    and kicks off job processes for recipes.
    """

    use GenServer

    @typep request() :: {:set_cfg, ExMake.Config.t()} |
                        {:get_cfg} |
                        {:enqueue, Keyword.t(), term(), pid()} |
                        {:done, Keyword.t(), pid(), :ok | tuple()} |
                        {:apply_timer, ((ExMake.Timer.session()) -> ExMake.Timer.session())} |
                        {:get_libs} |
                        {:add_lib, module()} |
                        {:del_lib, module()} |
                        {:clear_libs}

    @typep reply() :: {:set_cfg} |
                      {:get_cfg, ExMake.Config.t()} |
                      {:enqueue} |
                      {:done} |
                      {:apply_timer} |
                      {:get_libs, [module()]} |
                      {:add_lib} |
                      {:del_lib} |
                      {:clear_libs}

    @doc false
    @spec start_link() :: {:ok, pid()}
    def start_link() do
        {:ok, _} = GenServer.start_link(__MODULE__, %ExMake.State{}, [name: :exmake_coordinator])
    end

    @doc """
    Sets the configuration values for the ExMake application.

    `cfg` must be a valid `ExMake.Config` instance. `timeout` must be
    `:infinity` or a millisecond value specifying how much time to wait for
    the operation to complete.
    """
    @spec set_config(ExMake.Config.t(), timeout()) :: :ok
    def set_config(cfg, timeout \\ :infinity) do
        GenServer.call(:exmake_coordinator, {:set_cfg, cfg}, timeout)
        :ok
    end

    @doc """
    Gets the configuration values used by the ExMake application. Returns
    `nil` if no values have been set yet.

    `timeout` must be `:infinity` or a millisecond value specifying how much
    time to wait for the operation to complete.
    """
    @spec get_config(timeout()) :: ExMake.Config.t() | nil
    def get_config(timeout \\ :infinity) do
        {:get_cfg, cfg} = GenServer.call(:exmake_coordinator, {:get_cfg}, timeout)
        cfg
    end

    @doc """
    Enqueues a job.

    Jobs are executed as soon as there is a free job slot available. Once the
    job has executed, the coordinator will send a message to `owner`:

    * `{:exmake_done, rule, data, :ok}` if the job executed successfully.
    * `{:exmake_done, rule, data, {:throw, value}}` if a value was thrown.
    * `{:exmake_done, rule, data, {:raise, exception}}` if an exception was raised.

    Here, `rule` is the rule originally passed to this function. `data` is the
    arbitrary term passed as the second argument to this function.

    `rule` must be the keyword list describing the rule. `data` can be any
    term to attach to the job. `owner` must be a PID pointing to the process
    that should be notified once the job is done. `timeout` must be `:infinity`
    or a millisecond value specifying how much time to wait for the operation
    to complete.
    """
    @spec enqueue(Keyword.t(), term(), pid(), timeout()) :: :ok
    def enqueue(rule, data \\ nil, owner \\ self(), timeout \\ :infinity) do
        GenServer.call(:exmake_coordinator, {:enqueue, rule, data, owner}, timeout)
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
    def apply_timer_fn(fun, timeout \\ :infinity) do
        GenServer.call(:exmake_coordinator, {:apply_timer, fun}, timeout)
        :ok
    end

    @doc false
    @spec get_libraries(timeout()) :: [module()]
    def get_libraries(timeout \\ :infinity) do
        {:get_libs, libs} = GenServer.call(:exmake_coordinator, {:get_libs}, timeout)
        libs
    end

    @doc false
    @spec add_library(module(), timeout()) :: :ok
    def add_library(module, timeout \\ :infinity) do
        GenServer.call(:exmake_coordinator, {:add_lib, module}, timeout)
        :ok
    end

    @doc false
    @spec remove_library(module(), timeout()) :: :ok
    def remove_library(module, timeout \\ :infinity) do
        GenServer.call(:exmake_coordinator, {:del_lib, module}, timeout)
        :ok
    end

    @doc false
    @spec clear_libraries(timeout()) :: :ok
    def clear_libraries(timeout \\ :infinity) do
        GenServer.call(:exmake_coordinator, {:clear_libs}, timeout)
        :ok
    end

    @doc false
    @spec handle_call(request(), {pid(), term()}, ExMake.State.t()) :: {:reply, reply(), ExMake.State.t()}
    def handle_call(msg, {sender, _}, state) do
        reply = case msg do
            {:set_cfg, cfg} ->
                state = %ExMake.State{state | :config => cfg,
                                              :max_jobs => cfg.options[:jobs] || 1}
                {:set_cfg}
            {:get_cfg} ->
                {:get_cfg, state.config}
            {:enqueue, rule, data, owner} ->
                if Set.size(state.jobs) < state.max_jobs do
                    # If we have a free job slot, just run it right away.
                    job = ExMake.Runner.start(rule, data, owner)
                    state = %ExMake.State{state | :jobs => Set.put(state.jobs, {rule, data, owner, job})}
                else
                    # No free slot, so schedule the job for later. We'll run it
                    # once we get a :done message from some other job.
                    state = %ExMake.State{state | :queue => :queue.in({rule, data, owner}, state.queue)}
                end

                {:enqueue}
            {:done, rule, data, owner, result} ->
                state = %ExMake.State{state | :jobs => Set.delete(state.jobs, {rule, data, owner, sender})}

                send(owner, {:exmake_done, rule, data, result})

                # We have a free job slot, so run a job if one is enqueued.
                case :queue.out(state.queue) do
                    {{:value, {rule, data, owner}}, queue} ->
                        job = ExMake.Runner.start(rule, data, owner)
                        state = %ExMake.State{state | :queue => queue,
                                                      :jobs => Set.put(state.jobs, {rule, data, owner, job})}
                    {:empty, _} -> :ok
                end

                {:done}
            {:apply_timer, fun} ->
                state = %ExMake.State{state | :timing => fun.(state.timing)}
                {:apply_timer}
            {:get_libs} ->
                {:get_libs, Set.to_list(state.libraries)}
            {:add_lib, lib} ->
                state = %ExMake.State{state | :libraries => Set.put(state.libraries, lib)}
                {:add_lib}
            {:del_lib, lib} ->
                state = %ExMake.State{state | :libraries => Set.delete(state.libraries, lib)}
                {:del_lib}
            {:clear_libs} ->
                state = %ExMake.State{state | :libraries => HashSet.new()}
                {:clear_libs}
        end

        {:reply, reply, state}
    end
end
