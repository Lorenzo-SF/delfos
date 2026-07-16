defmodule Delfos.LLM.Breakers do
  @moduledoc """
  Circuit breakers for outbound LLM HTTP calls.

  Each unique host gets its own breaker. Breakers are registered
  as children of `Delfos.Supervisor` so they live for the entire
  application lifetime. If a breaker is not registered, calls
  fall through to a closed circuit (Arrea.CircuitBreaker default).
  """

  alias Arrea.CircuitBreaker

  @doc """
  Returns a stable atom name for the breaker protecting the given URL.
  Falls back to `:delfos_llm_default_breaker` if the URL has no usable host.
  """
  def name_for(url) when is_binary(url) do
    case URI.parse(url).host do
      nil ->
        :delfos_llm_default_breaker

      host ->
        try do
          :"delfos_llm_breaker_#{String.replace(host, ".", "_")}"
        rescue
          ArgumentError -> :delfos_llm_default_breaker
        end
    end
  end

  def name_for(_), do: :delfos_llm_default_breaker

  @doc """
  Ensures the circuit breaker for the given name is running.

  Safe to call from any context. If the breaker is already registered,
  this is a no-op. Otherwise it starts the breaker with `start_link/1`
  (which is supervised if `child_spec/1` is in a supervision tree, or
  a linked process otherwise — `start_link` returns `{:error,
  {:already_started, _}}` when called twice).

  This is the lazy-registration path used by `Delfos.LLM.Client` for
  endpoints whose URL isn't known at boot time.
  """
  @spec ensure_running(atom()) :: :ok | {:error, term()}
  def ensure_running(name) do
    case Registry.lookup(Arrea.CircuitBreaker.Registry, name) do
      [] ->
        case CircuitBreaker.start_link(name: name, threshold: 5, timeout: 60_000) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        :ok
    end
  end

  @doc """
  Starts a circuit breaker under the Delfos supervisor.

  Threshold (consecutive failures to open): 5
  Timeout (ms before half-open probe): 60_000
  """
  def child_spec(name) do
    %{
      id: {CircuitBreaker, name},
      start: {CircuitBreaker, :start_link, [[name: name, threshold: 5, timeout: 60_000]]},
      type: :worker,
      restart: :permanent
    }
  end
end
