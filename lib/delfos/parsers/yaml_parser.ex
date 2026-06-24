defmodule Delfos.Parsers.YAMLParser do
  @moduledoc """
  Parser para YAML de configuración como código (.yaml, .yml).

  Detecta el tipo de fichero y extrae entidades relevantes:

  - Kubernetes: kind (Deployment, Service, ConfigMap, etc.) + nombre
  - Helm values: top-level keys de values.yaml
  - GitHub Actions: nombre del workflow + jobs
  - GitLab CI: stages + jobs
  - Docker Compose: services + volumes
  - YAML genérico: top-level keys con valor no-escalar (objetos/listas)

  No parsea YAML completo (evita dependencia externa). Usa regex sobre
  líneas, que es suficiente para los patrones estables de estos formatos.
  """

  def parse(path, content) do
    lines = String.split(content, "\n")
    doc_type = detect_type(content, path)

    %{
      symbols: extract_symbols(lines, doc_type),
      docs: [],
      todos: [],
      line_count: length(lines)
    }
  end

  # ---------------------------------------------------------------------------
  # Detección de tipo de documento YAML
  # ---------------------------------------------------------------------------

  defp detect_type(content, path) do
    filename = Path.basename(path)

    cond do
      String.contains?(content, "apiVersion:") ->
        :kubernetes

      String.contains?(content, "helm.sh/chart") or filename == "values.yaml" ->
        :helm

      String.contains?(content, "runs-on:") or
          String.contains?(path, ".github/workflows") ->
        :github_actions

      String.contains?(content, "stages:") and String.contains?(content, "script:") ->
        :gitlab_ci

      String.contains?(content, "services:") and
          (String.contains?(content, "image:") or String.contains?(content, "build:")) ->
        :docker_compose

      true ->
        :generic
    end
  end

  # ---------------------------------------------------------------------------
  # Extractores por tipo
  # ---------------------------------------------------------------------------

  defp extract_symbols(lines, :kubernetes) do
    # Extraer kind + metadata.name de cada documento YAML del fichero
    # (puede haber múltiples documentos separados por ---)
    lines
    |> Enum.with_index(1)
    |> Enum.reduce({nil, nil, []}, fn {line, lineno}, {kind, name, acc} ->
      stripped = String.trim(line)

      new_kind =
        case Regex.run(~r/^kind:\s+(\w+)$/, stripped) do
          [_, k] -> k
          _ -> kind
        end

      new_name =
        if String.starts_with?(stripped, "name:") and name == nil do
          case Regex.run(~r/^name:\s+(.+)$/, stripped) do
            [_, n] -> String.trim(n)
            _ -> name
          end
        else
          name
        end

      # Cuando tenemos ambos, crear el símbolo
      {new_kind, new_name, acc} =
        if new_kind != kind or new_name != name do
          if new_kind && new_name && (new_kind != kind or new_name != name) do
            sym =
              build("resource", new_name, "#{new_kind}/#{new_name}", lineno, %{
                "k8s_kind" => new_kind
              })

            {new_kind, new_name, [sym | acc]}
          else
            {new_kind, new_name, acc}
          end
        else
          {new_kind, new_name, acc}
        end

      {new_kind, new_name, acc}
    end)
    |> elem(2)
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.qualified_name)
  end

  defp extract_symbols(lines, :github_actions) do
    # Extraer nombre del workflow + jobs
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)

      cond do
        # job names bajo jobs: (2 espacios de indentación)
        Regex.match?(~r/^  \w[\w-]*:\s*$/, line) ->
          job = String.trim(line) |> String.trim_trailing(":")

          if job not in ["steps", "with", "env", "strategy", "outputs", "needs"] do
            [build("job", job, "job/#{job}", lineno, %{"type" => "job"})]
          else
            []
          end

        # name: workflow name (top level, sin indentación)
        true ->
          workflow_name(line, stripped, lineno)
      end
    end)
  end

  defp extract_symbols(lines, :gitlab_ci) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)

      cond do
        # stages: lista
        Regex.match?(~r/^  - /, line) and String.contains?(line, ":") ->
          []

        # job (clave top-level sin indentación, no es una keyword de CI)
        Regex.match?(~r/^\w[\w-]*:\s*$/, line) ->
          name = stripped |> String.trim_trailing(":")
          ci_keywords = ~w(stages variables cache default workflow include)

          if name not in ci_keywords do
            [build("job", name, "job/#{name}", lineno, %{"type" => "ci_job"})]
          else
            []
          end

        true ->
          []
      end
    end)
  end

  defp extract_symbols(lines, :docker_compose) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce({nil, []}, fn {line, lineno}, {section, acc} ->
      stripped = String.trim(line)

      new_section =
        case Regex.run(~r/^(services|volumes|networks|configs|secrets):\s*$/, stripped) do
          [_, s] -> s
          _ -> section
        end

      new_acc =
        if section in ["services", "volumes", "networks"] and
             Regex.match?(~r/^  \w[\w-]*:\s*$/, line) do
          name = stripped |> String.trim_trailing(":")

          sym =
            build(section |> String.trim_trailing("s"), name, "#{section}/#{name}", lineno, %{
              "compose_section" => section
            })

          [sym | acc]
        else
          acc
        end

      {new_section, new_acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp extract_symbols(lines, :helm) do
    # Extraer top-level keys de values.yaml
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      if Regex.match?(~r/^\w[\w-]*:/, line) do
        m = Regex.run(~r/^([\w-]+):/, line)

        if m do
          name = Enum.at(m, 1)
          # Saltar comentarios y campos simples sin sub-estructura
          [build("config", name, name, lineno, %{"helm_key" => true})]
        else
          []
        end
      else
        []
      end
    end)
    |> Enum.take(30)
  end

  defp extract_symbols(lines, :generic) do
    # Top-level keys con sub-estructura (valor no es escalar)
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      if Regex.match?(~r/^\w[\w-]*:\s*$/, line) do
        name = String.trim(line) |> String.trim_trailing(":")
        [build("config", name, name, lineno, %{})]
      else
        []
      end
    end)
    |> Enum.take(20)
  end

  # ---------------------------------------------------------------------------
  # Builder
  # ---------------------------------------------------------------------------

  defp build(kind, name, qualified, lineno, meta) do
    %{
      name: name,
      qualified_name: qualified,
      kind: kind,
      line_start: lineno,
      language: "config",
      visibility: "public",
      metadata: meta
    }
  end

  defp workflow_name(line, stripped, lineno) do
    if not String.starts_with?(line, " "),
      do: extract_workflow_name(stripped, lineno),
      else: []
  end

  defp extract_workflow_name(stripped, lineno) do
    case Regex.run(~r/^name:\s+(.+)$/, stripped) do
      [_, value] -> [build("workflow", value, value, lineno, %{"type" => "workflow"})]
      _ -> []
    end
  end
end
