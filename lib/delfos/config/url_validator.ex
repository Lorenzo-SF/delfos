defmodule Delfos.Config.URLValidator do
  @moduledoc """
  Validates URLs for LLM providers.

  SE-4 (S16): the LLM URL was previously accepted as-is from the
  config file. A malicious or misconfigured config could point at
  `http://embedding.evil.com` and exfiltrate source code via the
  embed API. We now enforce:

    * Local URLs (localhost, 127.0.0.1, ::1) are always allowed
      (cleartext OK for local dev servers like llama-server).
    * Non-local URLs must use HTTPS.
    * Schemes other than http/https are rejected.

  Use `validate!/1` to raise, or `validate/1` to return :ok | {:error, ...}.
  """

  @local_hosts ~w(localhost 127.0.0.1 ::1 0.0.0.0)

  @spec validate(String.t()) :: :ok | {:error, String.t()}
  def validate(url) when is_binary(url) and url != "" do
    case URI.parse(url) do
      %URI{scheme: nil} ->
        {:error, "URL has no scheme: #{url} (must be http:// or https://)"}

      %URI{scheme: scheme} when scheme not in ["http", "https"] ->
        {:error, "URL has invalid scheme '#{scheme}': only http and https are allowed"}

      %URI{host: nil} ->
        {:error, "URL has no host: #{url}"}

      %URI{host: host} when host in @local_hosts ->
        :ok

      %URI{scheme: "http", host: host} ->
        {:error, "Non-local URL '#{host}' must use HTTPS (got http://)"}

      %URI{scheme: "https"} ->
        :ok

      _ ->
        {:error, "Invalid URL: #{url}"}
    end
  end

  def validate(_), do: {:error, "URL must be a non-empty string"}

  @doc """
  Like `validate/1` but raises on failure.
  """
  def validate!(url) do
    case validate(url) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "URL validation failed: #{reason}"
    end
  end
end
