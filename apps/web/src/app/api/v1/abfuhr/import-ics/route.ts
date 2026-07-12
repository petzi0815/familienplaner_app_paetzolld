import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { parseAbfuhrICS } from "@/server/abfuhr/abfuhr";

// ICS-Upload → Abfuhrtermine importieren (idempotent per UID).
// POST /api/v1/abfuhr/import-ics  — Body: { ics: "<ICS-Text>" }  ODER text/calendar Rohtext.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();

  let ics = "";
  const ct = req.headers.get("content-type") ?? "";
  if (ct.includes("application/json")) {
    let body: Record<string, unknown>;
    try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
    ics = String(body.ics ?? "");
  } else {
    ics = await req.text();
  }
  if (!ics.includes("BEGIN:VEVENT")) return fail("no_ics", "Kein gültiges ICS (BEGIN:VEVENT fehlt).", 400);

  const events = parseAbfuhrICS(ics);
  if (!events.length) return fail("empty", "Keine Termine in der ICS gefunden.", 400);

  const db = getDb();
  const upsert = db.prepare(
    `INSERT INTO abfuhr_termine (kategorie, datum, summary, uid, quelle)
     VALUES (?,?,?,?,?)
     ON CONFLICT(uid) DO UPDATE SET kategorie=excluded.kategorie, datum=excluded.datum, summary=excluded.summary`,
  );
  let inserted = 0;
  const tx = db.transaction(() => {
    for (const e of events) {
      const info = upsert.run(e.kategorie, e.datum, e.summary, e.uid, (req.headers.get("x-source") === "aha" ? "aha" : "ics"));
      if (info.changes > 0) inserted++;
    }
  });
  tx();

  const byCat = db.prepare("SELECT kategorie, COUNT(*) c FROM abfuhr_termine GROUP BY kategorie").all() as { kategorie: string; c: number }[];
  return ok({ parsed: events.length, upserted: inserted, by_category: byCat });
}
