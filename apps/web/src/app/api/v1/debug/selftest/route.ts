import { config } from "@/server/config";
import { getAuth, hasRole } from "@/server/auth/auth";
import { getDb } from "@/server/db/connection";
import { hasOpenAI, openaiChat } from "@/server/elisbooks/openai";
import { unauthorized, forbidden, ok } from "@/server/http/respond";

// Selbsttest/Diagnose für Claude Code (agent+): zeigt welche Integrationen KONFIGURIERT sind (nur
// Booleans, keine Secrets), ein paar DB-Stände, und optional einen LIVE-OpenAI-Ping (?openai=1) —
// damit sich der Coolify-OpenAI-Key verifizieren lässt, ohne ihn je auszugeben.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

export async function GET(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const url = new URL(req.url);
  const db = getDb();
  const num = (sql: string) => { try { return (db.prepare(sql).get() as { c: number }).c; } catch { return -1; } };

  const integrations = {
    openai: !!config.openaiApiKey,
    home_assistant: !!config.homeAssistant.url && !!config.homeAssistant.token,
    calibre: !!config.calibre.username && !!config.calibre.password,
    telegram: !!config.telegram.botToken,
    apns: !!config.apns.keyP8 && !!config.apns.keyId && !!config.apns.teamId,
    sentry: !!config.sentryDsn,
  };
  const stats = {
    vorrat_aktiv: num("SELECT COUNT(*) c FROM vorrat_lebensmittel WHERE COALESCE(status,'')<>'verbraucht'"),
    vorrat_bald_ablaufend: num("SELECT COUNT(*) c FROM vorrat_lebensmittel WHERE mhd IS NOT NULL AND mhd<>'' AND mhd<=date('now','+14 days') AND COALESCE(status,'')<>'verbraucht'"),
    aufgaben_offen: num("SELECT COUNT(*) c FROM aufgaben WHERE status='offen'"),
    termine: num("SELECT COUNT(*) c FROM termine"),
  };

  let openaiPing: unknown = "übersprungen (mit ?openai=1 live testen)";
  if (url.searchParams.get("openai") === "1") {
    if (!hasOpenAI()) {
      openaiPing = { ok: false, error: "OPENAI_API_KEY nicht gesetzt" };
    } else {
      const t0 = Date.now();
      try {
        const txt = await openaiChat("Antworte mit genau dem Wort: PONG", { maxTokens: 5, temperature: 0 });
        openaiPing = { ok: true, reply: txt.trim().slice(0, 40), ms: Date.now() - t0 };
      } catch (e) {
        openaiPing = { ok: false, error: String((e as Error).message).slice(0, 200), ms: Date.now() - t0 };
      }
    }
  }

  return ok({ commit: config.gitSha, env: config.nodeEnv, integrations, stats, openai_ping: openaiPing });
}
