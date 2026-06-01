defmodule Delfos.Parsers.DartParser do
  @moduledoc """
  Parser para Dart / Flutter.

  Extrae:
  - class (con detección de widget type y state management)
  - function / method (sync y async)
  - enum
  - typedef
  - extension
  - mixin

  La detección de framework (StatelessWidget, StatefulWidget, BLoC, Riverpod,
  GetX, Provider) se añade al metadata del símbolo para que FrameworkContext
  pueda enriquecer los prompts LLM con el stack correcto.
  """

  @todo_re ~r{//\s*(TODO|FIXME|HACK|XXX)\b.*}i

  def parse(_path, content) do
    lines = String.split(content, "\n")

    %{
      symbols: extract_symbols(lines),
      docs: extract_docs(content),
      todos: extract_todos(lines),
      line_count: length(lines)
    }
  end

  defp extract_symbols(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      stripped = String.trim(line)
      classify(stripped, lineno)
    end)
  end

  defp classify(line, lineno) do
    cond do
      # class con herencia/mixins
      m = Regex.run(~r/^(?:abstract\s+)?class\s+(\w+)(?:\s+extends\s+([\w<>?]+))?/, line) ->
        name = Enum.at(m, 1)
        parent = Enum.at(m, 2)
        widget_type = classify_widget(name, parent, line)

        meta =
          if widget_type, do: %{"widget_type" => widget_type, "framework" => "flutter"}, else: %{}

        [build("class", name, lineno, "public", meta)]

      # mixin
      m = Regex.run(~r/^mixin\s+(\w+)/, line) ->
        [build("mixin", Enum.at(m, 1), lineno, "public", %{})]

      # extension
      m = Regex.run(~r/^extension\s+(\w+)\s+on/, line) ->
        [build("extension", Enum.at(m, 1), lineno, "public", %{})]

      # enum
      m = Regex.run(~r/^enum\s+(\w+)/, line) ->
        [build("enum", Enum.at(m, 1), lineno, "public", %{})]

      # typedef
      m = Regex.run(~r/^typedef\s+(\w+)/, line) ->
        [build("type", Enum.at(m, 1), lineno, "public", %{})]

      # función / método async
      m =
          Regex.run(
            ~r/^(?:static\s+)?(?:Future<[^>]*>|Stream<[^>]*>|void|[\w<>?]+)\s+(\w+)\s*\(/,
            line
          ) ->
        name = Enum.at(m, 1)
        visibility = if String.starts_with?(name, "_"), do: "private", else: "public"
        is_async = String.contains?(line, "async")
        meta = if is_async, do: %{"async" => true}, else: %{}
        [build("function", name, lineno, visibility, meta)]

      # factory constructor
      m = Regex.run(~r/factory\s+(\w+)\s*[\.(]/, line) ->
        [build("function", Enum.at(m, 1), lineno, "public", %{"factory" => true})]

      true ->
        []
    end
  end

  defp classify_widget(name, parent, line) do
    cond do
      parent in ["StatelessWidget", nil] and String.contains?(line, "StatelessWidget") ->
        "stateless_widget"

      parent in ["StatefulWidget", nil] and String.contains?(line, "StatefulWidget") ->
        "stateful_widget"

      String.contains?(line, "State<") ->
        "widget_state"

      String.contains?(line, "ChangeNotifier") ->
        "provider_notifier"

      String.contains?(line, "Bloc") or String.contains?(line, "Cubit") ->
        "bloc"

      String.contains?(line, "Riverpod") or String.contains?(line, "Notifier") ->
        "riverpod_notifier"

      String.ends_with?(name || "", "Widget") ->
        "widget"

      true ->
        nil
    end
  end

  defp build(kind, name, lineno, visibility, meta) do
    %{
      name: name,
      qualified_name: name,
      kind: kind,
      line_start: lineno,
      language: "dart",
      visibility: visibility,
      metadata: meta
    }
  end

  defp extract_docs(content) do
    ~r{///\s*(.*)}
    |> Regex.scan(content)
    |> Enum.map(fn [_, doc] -> String.trim(doc) end)
    |> Enum.filter(&(String.length(&1) > 10))
  end

  defp extract_todos(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(@todo_re, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end
end
