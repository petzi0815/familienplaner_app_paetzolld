import { config } from "@/server/config";
import { getDb } from "@/server/db/connection";
import { log } from "@/server/observability/logger";

/**
 * Benachrichtigungs-Adapter. Standardmäßig AUS: ohne TELEGRAM_BOT_TOKEN wird nur geloggt
 * (Master-Prompt: Jobs dürfen erst senden, wenn die Zielkonfiguration vorhanden ist).
 * Topic → Telegram-Thread aus app_settings `telegram.topic.<topic>`.
 */
export async function notify(topic: string, message: string): Promise<void> {
  const token = config.telegram.botToken;
  if (!token || !config.telegram.familyChatId) {
    log.info("notify (deaktiviert — nur Log)", { topic, preview: message.slice(0, 160) });
    return;
  }
  let threadId: string | undefined;
  try {
    threadId = (getDb().prepare("SELECT value FROM app_settings WHERE key=?").get(`telegram.topic.${topic}`) as { value: string } | undefined)?.value;
  } catch { /* ignore */ }
  try {
    await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ chat_id: config.telegram.familyChatId, message_thread_id: threadId ? Number(threadId) : undefined, text: message }),
    });
  } catch (e) {
    log.error("Telegram-Send fehlgeschlagen", { error: String(e) });
  }
}
