defmodule Delfos.Parsers.HCLParser do
  @moduledoc """
  Parser para Terraform HCL (.tf, .hcl).

  Extrae los bloques top-level de HCL que son relevantes para
  el análisis de infraestructura como código:
  - resource  (aws_s3_bucket "name")
  - module    (module "vpc")
  - variable  (variable "region")
  - output    (output "endpoint")
  - provider  (provider "aws")
  - data      (data "aws_ami" "ubuntu")
  - locals    (locals block)

  El tipo de recurso (aws_s3_bucket, google_compute_instance, etc.)
  se preserva en el qualified_name para que la búsqueda semántica sea
  precisa al buscar "S3 bucket" o "EC2 instance".
  """

  @todo_re ~r{#\s*(TODO|FIXME|HACK)\b.*}i

  def parse(_path, content) do
    lines = String.split(content, "\n")

    %{
      symbols: extract_symbols(lines),
      docs: [],
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
      # resource "aws_s3_bucket" "my_bucket" {
      m = Regex.run(~r/^resource\s+"([\w]+)"\s+"([\w-]+)"/, line) ->
        type = Enum.at(m, 1)
        name = Enum.at(m, 2)
        [build("resource", name, "#{type}.#{name}", lineno, %{"resource_type" => type})]

      # module "name" {
      m = Regex.run(~r/^module\s+"([\w-]+)"/, line) ->
        [build("module", Enum.at(m, 1), Enum.at(m, 1), lineno, %{})]

      # variable "name" {
      m = Regex.run(~r/^variable\s+"([\w-]+)"/, line) ->
        [build("variable", Enum.at(m, 1), Enum.at(m, 1), lineno, %{})]

      # output "name" {
      m = Regex.run(~r/^output\s+"([\w-]+)"/, line) ->
        [build("output", Enum.at(m, 1), Enum.at(m, 1), lineno, %{})]

      # provider "aws" {
      m = Regex.run(~r/^provider\s+"([\w-]+)"/, line) ->
        [build("provider", Enum.at(m, 1), Enum.at(m, 1), lineno, %{})]

      # data "aws_ami" "ubuntu" {
      m = Regex.run(~r/^data\s+"([\w]+)"\s+"([\w-]+)"/, line) ->
        type = Enum.at(m, 1)
        name = Enum.at(m, 2)
        [build("data", name, "data.#{type}.#{name}", lineno, %{"data_type" => type})]

      # locals {
      String.starts_with?(line, "locals {") or line == "locals {" ->
        [build("locals", "locals", "locals", lineno, %{})]

      # terraform { — bloque de configuración
      String.starts_with?(line, "terraform {") ->
        [build("config", "terraform", "terraform", lineno, %{})]

      true ->
        []
    end
  end

  defp build(kind, name, qualified, lineno, meta) do
    %{
      name: name,
      qualified_name: qualified,
      kind: kind,
      line_start: lineno,
      language: "terraform",
      visibility: "public",
      metadata: meta
    }
  end

  defp extract_todos(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> Regex.match?(@todo_re, line) end)
    |> Enum.map(fn {line, no} -> %{line: no, text: String.trim(line)} end)
  end
end
