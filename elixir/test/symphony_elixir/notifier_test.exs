defmodule SymphonyElixir.NotifierTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias SymphonyElixir.Notifier
  alias SymphonyElixir.TestSupport

  test "notify is best-effort when chat id is missing" do
    previous_token = System.get_env("TELEGRAM_BOT_TOKEN")
    previous_chat_id = System.get_env("TELEGRAM_CHAT_ID")
    on_exit(fn -> TestSupport.restore_env("TELEGRAM_BOT_TOKEN", previous_token) end)
    on_exit(fn -> TestSupport.restore_env("TELEGRAM_CHAT_ID", previous_chat_id) end)

    System.put_env("TELEGRAM_BOT_TOKEN", "token")
    System.delete_env("TELEGRAM_CHAT_ID")

    log =
      capture_log(fn ->
        assert :ok = Notifier.notify("MT-700", "Prepare Complete")
      end)

    assert log =~ "Telegram notification skipped"
    assert log =~ "MT-700"
    assert log =~ "Prepare Complete"
    assert log =~ "missing_telegram_chat_id"
  end
end
