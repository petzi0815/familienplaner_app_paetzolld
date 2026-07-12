import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { parseAbfuhrICS, fetchAhaICS } from "@/server/abfuhr/abfuhr";

// Online-Sync mit aha-region.de: fährt das 3-Schritt-Formular für die konfigurierte Adresse
// (abfuhr_config.aha_*) und importiert die Jahres-ICS — kein jährliches manuelles Hochladen nötig.
// POST /api/v1/abfuhr/sync-aha
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 40;

interface Cfg { aha_gemeinde: string | null; aha_von: string | null; aha_strasse: string | null; aha_hausnr: string | null; aha_hausnraddon: string | null; aha_ics_url: string | null }

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const db = getDb();
  const cfg = db.prepare("SELECT aha_gemeinde, aha_von, aha_strasse, aha_hausnr, aha_hausnraddon, aha_ics_url FROM abfuhr_config WHERE id=1").get() as Cfg | undefined;

  let ics = "";
  try {
    if (cfg?.aha_gemeinde && cfg.aha_strasse) {
      ics = await fetchAhaICS({
        gemeinde: cfg.aha_gemeinde, von: cfg.aha_von ?? cfg.aha_gemeinde.slice(0, 1),
        strasse: cfg.aha_strasse, hausnr: cfg.aha_hausnr ?? "", hausnraddon: cfg.aha_hausnraddon ?? "",
      });
    } else if (cfg?.aha_ics_url) {
      const r = await fetch(cfg.aha_ics_url, { headers: { accept: "text/calendar,*/*" } });
      ics = await r.text();
    } else {
      return fail("not_configured", "Keine aha-Adresse konfiguriert (abfuhr_config.aha_*).", 400);
    }
  } catch (e) {
    return fail("fetch_error", "aha-Abruf fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e) });
  }
  if (!ics.includes("BEGIN:VEVENT")) return fail("no_ics", "aha-Antwort ist kein gültiges ICS.", 502);

  const events = parseAbfuhrICS(ics);
  const upsert = db.prepare(
    `INSERT INTO abfuhr_termine (kategorie, datum, summary, uid, quelle) VALUES (?,?,?,?, 'aha')
     ON CONFLICT(uid) DO UPDATE SET kategorie=excluded.kategorie, datum=excluded.datum, summary=excluded.summary`,
  );
  let upserted = 0;
  const tx = db.transaction(() => { for (const e of events) { if (upsert.run(e.kategorie, e.datum, e.summary, e.uid).changes > 0) upserted++; } });
  tx();
  db.prepare("UPDATE abfuhr_config SET letzter_sync=datetime('now') WHERE id=1").run();
  return ok({ source: "aha-region.de", parsed: events.length, upserted });
}
