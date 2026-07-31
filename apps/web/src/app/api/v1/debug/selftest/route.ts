import { config } from "@/server/config";
import { getAuth, hasRole } from "@/server/auth/auth";
import { getDb } from "@/server/db/connection";
import { hasOpenAI, openaiChat } from "@/server/elisbooks/openai";
import { hasPerplexity, perplexityAsk } from "@/server/wein/perplexity";
import { unauthorized, forbidden, ok } from "@/server/http/respond";

// Selbsttest/Diagnose für Claude Code (agent+): zeigt welche Integrationen KONFIGURIERT sind (nur
// Booleans, keine Secrets), ein paar DB-Stände, und optional einen LIVE-Ping gegen OpenAI (?openai=1)
// bzw. Perplexity (?perplexity=1) — damit sich die Coolify-Keys verifizieren lassen, ohne sie je
// auszugeben.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
// Der Perplexity-Ping ist eine LIVE-Websuche und darf laut Client bis zu 45 s brauchen; mit beiden
// Pings in einem Aufruf reichten 30 s nicht.
export const maxDuration = 60;

export async function GET(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const url = new URL(req.url);
  const db = getDb();
  const num = (sql: string) => { try { return (db.prepare(sql).get() as { c: number }).c; } catch { return -1; } };

  const integrations = {
    openai: !!config.openaiApiKey,
    perplexity: !!config.perplexityApiKey,
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
    ebooks_gesucht: num("SELECT COUNT(*) c FROM ebook_wishlist WHERE status='gesucht'"),
    ebooks_warteschlange: num("SELECT COUNT(*) c FROM ebook_wishlist WHERE download_state='queued'"),
    ebooks_geladen: num("SELECT COUNT(*) c FROM ebook_wishlist WHERE status='heruntergeladen'"),
  };

  // Geräte je Zielperson — OHNE Tokens. Ein owner-adressierter Push erreicht NUR die Geräte dieser
  // Person (Broadcast-Fallback greift nur bei 0 Geräten); ohne diese Übersicht fällt eine falsche
  // Adressierung erst auf, wenn jemand sagt „bei mir kam nichts an".
  const push_geraete = Object.fromEntries(
    (getDb().prepare("SELECT COALESCE(owner,'(ohne owner)') o, COUNT(*) c FROM device_tokens GROUP BY o").all() as { o: string; c: number }[])
      .map((r) => [r.o, r.c]),
  );

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

  // Perplexity ist der zweite KI-Anbieter (Live-Websuche für die Wein-Preisrecherche). Ohne Ping
  // sieht man nur, DASS ein Key gesetzt ist — nicht, ob er im Container gültig ist.
  let perplexityPing: unknown = "übersprungen (mit ?perplexity=1 live testen)";
  if (url.searchParams.get("perplexity") === "1") {
    if (!hasPerplexity()) {
      perplexityPing = { ok: false, error: "PERPLEXITY_API_KEY nicht gesetzt" };
    } else {
      const t0 = Date.now();
      try {
        // Bewusst über denselben Client/dasselbe Modell wie im Produktivpfad — ein Ping, der einen
        // anderen Weg nimmt, beweist nichts. Kurze Frage + kleines Token-Budget halten ihn billig.
        const a = await perplexityAsk("Antworte mit genau dem Wort: PONG", { maxTokens: 16 });
        perplexityPing = { ok: true, reply: a.text.trim().slice(0, 40), quellen: a.citations.length, ms: Date.now() - t0 };
      } catch (e) {
        perplexityPing = { ok: false, error: String((e as Error).message).slice(0, 200), ms: Date.now() - t0 };
      }
    }
  }

  return ok({ commit: config.gitSha, env: config.nodeEnv, integrations, stats, push_geraete, openai_ping: openaiPing, perplexity_ping: perplexityPing });
}
