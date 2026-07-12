import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { parseAbfuhrICS } from "@/server/abfuhr/abfuhr";

// Online-Sync mit aha-region.de: holt die ICS von der in abfuhr_config hinterlegten URL und importiert sie
// (idempotent per UID) — damit man nicht jedes Jahr manuell hochladen muss. Body optional { url } überschreibt.
// POST /api/v1/abfuhr/sync-aha
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: Record<string, unknown> = {};
  try { body = (await req.json()) as Record<string, unknown>; } catch { /* leerer Body ok */ }

  const db = getDb();
  const cfg = db.prepare("SELECT aha_ics_url FROM abfuhr_config WHERE id=1").get() as { aha_ics_url: string | null } | undefined;
  const url = String(body.url ?? cfg?.aha_ics_url ?? "");
  if (!url) return fail("no_url", "Keine aha-ICS-URL konfiguriert. URL in abfuhr_config.aha_ics_url setzen (oder im Body übergeben).", 400);
  if (body.url) db.prepare("UPDATE abfuhr_config SET aha_ics_url=?, aktualisiert_am=datetime('now') WHERE id=1").run(String(body.url));

  let ics = "";
  try {
    const r = await fetch(url, { headers: { accept: "text/calendar,*/*" } });
    if (!r.ok) return fail("fetch_error", `ICS-Abruf fehlgeschlagen (HTTP ${r.status}).`, 502);
    ics = await r.text();
  } catch (e) {
    return fail("fetch_error", "ICS-Abruf fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e) });
  }
  if (!ics.includes("BEGIN:VEVENT")) return fail("no_ics", "Antwort ist kein gültiges ICS.", 502);

  const events = parseAbfuhrICS(ics);
  const upsert = db.prepare(
    `INSERT INTO abfuhr_termine (kategorie, datum, summary, uid, quelle) VALUES (?,?,?,?, 'aha')
     ON CONFLICT(uid) DO UPDATE SET kategorie=excluded.kategorie, datum=excluded.datum, summary=excluded.summary`,
  );
  let upserted = 0;
  const tx = db.transaction(() => { for (const e of events) { if (upsert.run(e.kategorie, e.datum, e.summary, e.uid).changes > 0) upserted++; } });
  tx();
  db.prepare("UPDATE abfuhr_config SET letzter_sync=datetime('now') WHERE id=1").run();
  return ok({ url, parsed: events.length, upserted });
}
