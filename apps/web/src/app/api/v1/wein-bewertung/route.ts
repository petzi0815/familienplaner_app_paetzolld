import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, notFound, fail, ok } from "@/server/http/respond";

// Persönliche Weinbewertung (1–5 Sterne + Kommentar) — genau EINE je Wein und Person.
// Die Person kommt primär aus dem Per-User-API-Key (auth.owner = 'lars'|'elita'); `owner` im Body
// ist nur Fallback für Ole/Shared-Key. UPSERT auf UNIQUE(wein_id, owner) → erneutes Bewerten
// überschreibt die eigene Bewertung, statt eine zweite anzulegen.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const PERSONEN = ["lars", "elita"] as const;

interface Bewertung { owner: string; sterne: number; kommentar: string }

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const weinId = Number(body.wein_id);
  if (!Number.isInteger(weinId) || weinId <= 0) return fail("bad_id", "Feld 'wein_id' (Zahl) erforderlich.", 400);

  const sterne = Number(body.sterne);
  if (!Number.isInteger(sterne) || sterne < 1 || sterne > 5) {
    return fail("invalid_value", "Feld 'sterne' erlaubt nur: 1, 2, 3, 4, 5.", 422, { column: "sterne", allowed: [1, 2, 3, 4, 5] });
  }

  const owner = String(auth.owner ?? body.owner ?? "").trim().toLowerCase();
  if (!(PERSONEN as readonly string[]).includes(owner)) {
    return fail(
      "no_owner",
      "Bewerten erfordert eine Person: entweder einen persönlichen API-Key (Lars/Elita) oder das Feld 'owner' mit 'lars' bzw. 'elita'.",
      400,
      { column: "owner", allowed: [...PERSONEN] },
    );
  }

  const kommentar = String(body.kommentar ?? "").trim();
  const db = getDb();

  try {
    if (!db.prepare("SELECT 1 FROM weine WHERE id=?").get(weinId)) return notFound("Wein");

    db.prepare(
      "INSERT INTO wein_bewertungen (wein_id, owner, sterne, kommentar) VALUES (?,?,?,?) " +
      "ON CONFLICT(wein_id, owner) DO UPDATE SET sterne=excluded.sterne, kommentar=excluded.kommentar, updated_at=datetime('now')",
    ).run(weinId, owner, sterne, kommentar);

    const bewertung = db.prepare("SELECT * FROM wein_bewertungen WHERE wein_id=? AND owner=?").get(weinId, owner);
    const alle = db.prepare("SELECT owner, sterne, kommentar FROM wein_bewertungen WHERE wein_id=? ORDER BY owner").all(weinId) as Bewertung[];
    const schnitt = alle.length ? Math.round((alle.reduce((a, b) => a + Number(b.sterne || 0), 0) / alle.length) * 10) / 10 : null;

    try {
      db.prepare("INSERT INTO event_log (actor, action, domain, entity_id) VALUES (?,?,?,?)")
        .run(auth.actor, "wein_bewertung", "wein", String(weinId));
    } catch { /* Audit best effort */ }

    return ok({ bewertung, schnitt, bewertungen: alle });
  } catch (e) {
    return fail("db_error", "Bewertung konnte nicht gespeichert werden.", 500, { detail: String((e as Error)?.message ?? e).slice(0, 200) });
  }
}
