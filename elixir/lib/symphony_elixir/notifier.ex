defmodule SymphonyElixir.Notifier do
  @moduledoc """
  Sends external notifications for orchestrator gate transitions.
  """

  require Logger

  @spec notify(String.t() | nil, String.t() | nil) :: :ok
  def notify(issue_identifier, state_name) do
    case telegram_credentials() do
      {:ok, token, chat_id} ->
        send_telegram_message(token, chat_id, issue_identifier, state_name)

      {:error, reason} ->
        Logger.warning("Telegram notification skipped for issue=#{inspect(issue_identifier)} state=#{inspect(state_name)} reason=#{inspect(reason)}")
    end

    :ok
  end

  defp send_telegram_message(token, chat_id, issue_identifier, state_name) do
    payload = %{
      chat_id: chat_id,
      text: "🧹 #{format_message_field(issue_identifier)}: moved to #{format_message_field(state_name)}. Review results in workspace."
    }

    url = "https://api.telegram.org/bot#{token}/sendMessage"

    case Req.post(url, json: payload, connect_options: [timeout: 10_000], receive_timeout: 10_000) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Telegram notification failed for issue=#{inspect(issue_identifier)} state=#{inspect(state_name)} status=#{status} body=#{inspect(body)}")

      {:error, reason} ->
        Logger.warning("Telegram notification request error for issue=#{inspect(issue_identifier)} state=#{inspect(state_name)} error=#{inspect(reason)}")
    end
  rescue
    exception ->
      Logger.warning("Telegram notification crashed for issue=#{inspect(issue_identifier)} state=#{inspect(state_name)} error=#{Exception.message(exception)}")
  end

  defp telegram_credentials do
    token = System.get_env("TELEGRAM_BOT_TOKEN")
    chat_id = System.get_env("TELEGRAM_CHAT_ID")

    cond do
      is_nil(token) or token == "" -> {:error, :missing_telegram_bot_token}
      is_nil(chat_id) or chat_id == "" -> {:error, :missing_telegram_chat_id}
      true -> {:ok, token, chat_id}
    end
  end

  defp format_message_field(value) when is_binary(value) and byte_size(value) > 0, do: value
  defp format_message_field(_value), do: "unknown"
end
