defmodule Delfos.Config.LLMDiscoveryCandilTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Delfos.Config.LLMDiscovery

  defmodule FakeHealth do
    @moduledoc false
    def probe(_url, _opts \\ []), do: %{reachable: false, error: "no health"}
  end

  defmodule FakeCandil do
    @moduledoc false

    def start_engine(engine, model) do
      :ets.insert(:fake_candil_started, {engine.alias, {engine, model}})
      {:ok, self()}
    end

    def download_engine(_engine), do: :ok

    def download_model(_model), do: {:ok, "/tmp/fake-model.gguf"}
  end

  setup do
    tmp =
      Path.expand(
        System.unique_integer([:positive]) |> to_string(),
        "/tmp/delfos_disc_candil_test"
      )

    File.mkdir_p!(tmp)
    Application.put_env(:delfos, :config_dir, tmp)
    Application.put_env(:delfos, :candil_health, FakeHealth)
    Application.put_env(:delfos, :candil, FakeCandil)
    Application.put_env(:delfos, :candil_config, FakeCandilConfig)

    :ets.new(:fake_candil_engines, [:named_table, :public, read_concurrency: true])
    :ets.new(:fake_candil_models, [:named_table, :public, read_concurrency: true])
    :ets.new(:fake_candil_started, [:named_table, :public, read_concurrency: true])
    :ets.delete_all_objects(:fake_candil_engines)
    :ets.delete_all_objects(:fake_candil_models)
    :ets.delete_all_objects(:fake_candil_started)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.delete_env(:delfos, :config_dir)
      Application.delete_env(:delfos, :candil_health)
      Application.delete_env(:delfos, :candil)
      Application.delete_env(:delfos, :candil_config)
    end)

    :ok
  end

  test "start_via_candil/1 registers engine and model and calls Candil.start_engine/2" do
    ep = %{
      role: :llm,
      url: "http://127.0.0.1:8080",
      host: "127.0.0.1",
      port: 8080,
      provider: :local,
      model: "Qwen2.5-Coder-3B-Instruct",
      api_key: "sk-test",
      extra_args: ["--n-gpu-layers", "0"],
      gguf_path: "/tmp/delfos_fake_model_#{System.unique_integer()}.gguf",
      llama_server_path: nil,
      download_precompiled: true,
      launcher: nil
    }

    File.write!(ep.gguf_path, "fake")

    assert :ok = LLMDiscovery.start_via_candil(ep)

    engines = :ets.tab2list(:fake_candil_engines)
    assert [{_, engine}] = engines
    assert engine.alias == :llm_engine
    assert engine.port == 8080
    assert engine.start_args == ["--n-gpu-layers", "0"]

    models = :ets.tab2list(:fake_candil_models)
    assert [{_, model}] = models
    assert model.alias == :llm_model
    assert model.filename == Path.basename(ep.gguf_path)
    assert model.engine == :llm_engine

    started = :ets.tab2list(:fake_candil_started)
    assert length(started) == 1
  end
end

defmodule FakeCandilConfig do
  @moduledoc false

  def register_engine(engine) do
    :ets.insert(:fake_candil_engines, {engine.alias, engine})
    :ok
  end

  def register_model(model) do
    :ets.insert(:fake_candil_models, {model.alias, model})
    :ok
  end

  def get_engine(alias) do
    case :ets.lookup(:fake_candil_engines, alias) do
      [{^alias, engine}] -> {:ok, engine}
      [] -> {:error, :not_found}
    end
  end

  def get_model(alias) do
    case :ets.lookup(:fake_candil_models, alias) do
      [{^alias, model}] -> {:ok, model}
      [] -> {:error, :not_found}
    end
  end
end
