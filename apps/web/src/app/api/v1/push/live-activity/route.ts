import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";

// iOS-App registriert / entfernt ihre Live-Activity-Tokens (Migration 0018).
//   kind='start'  → push-to-start-Token (eins pro Gerät, startet NEUE Activities)
//   kind='update' → Token einer KONKRET laufenden Activity (Update/Ende), mit activity_id + termin_id
// Analog zu `push/register` — gleicher Agent-Key, gleiche respond-Helfer.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface Body { token?: string; kind?: string; activity_id?: string; termin_id?: number | string; environment?: string }

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: Body;
  try { body = (await req.json()) as Body; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const token = String(body.token ?? "").trim();
  if (!token) return fail("no_token", "Feld 'token' erforderlich.", 400);
  const kind = body.kind === "update" ? "update" : "start";
  const env = body.environment === "sandbox" ? "sandbox" : "production";
  const activityId = String(body.activity_id ?? "").trim() || null;
  const terminIdRaw = Number(body.termin_id);
  const terminId = Number.isFinite(terminIdRaw) && terminIdRaw > 0 ? Math.trunc(terminIdRaw) : null;
  if (kind === "update" && !activityId) return fail("no_activity_id", "Bei kind='update' ist 'activity_id' erforderlich.", 400);
  // owner = Person hinter dem Login-Key (Lars/Elita); bei Oles Shared-Key NULL → Broadcast-Fallback greift.
  const owner = auth.owner ?? null;

  const db = getDb();
  db.prepare(
    "INSERT INTO live_activity_tokens (token, kind, owner, activity_id, termin_id, environment, last_seen) " +
    "VALUES (?,?,?,?,?,?,datetime('now')) " +
    "ON CONFLICT(token) DO UPDATE SET kind=excluded.kind, owner=excluded.owner, activity_id=excluded.activity_id, " +
    "termin_id=excluded.termin_id, environment=excluded.environment, last_seen=datetime('now')",
  ).run(token, kind, owner, activityId, terminId, env);

  // Lokal (in der App) gestartete Activity mitschreiben → der Job startet keine zweite für denselben
  // Termin und kann sie per Update/Ende weiterführen. `ended_at` wird zurückgesetzt, weil eine neu
  // gemeldete Activity per Definition wieder läuft.
  if (kind === "update" && terminId && owner) {
    db.prepare(
      "INSERT INTO termin_live_activities (termin_id, owner, activity_id) VALUES (?,?,?) " +
      "ON CONFLICT(termin_id, owner) DO UPDATE SET activity_id=excluded.activity_id, ended_at=NULL, updated_at=datetime('now')",
    ).run(terminId, owner, activityId);
  }
  return ok({ ok: true, kind });
}

export async function DELETE(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: Body;
  try { body = (await req.json()) as Body; } catch { body = {}; }
  const token = String(body.token ?? "").trim();
  const activityId = String(body.activity_id ?? "").trim();
  if (!token && !activityId) return fail("no_token", "Feld 'token' oder 'activity_id' erforderlich.", 400);
  const db = getDb();
  if (token) db.prepare("DELETE FROM live_activity_tokens WHERE token=?").run(token);
  if (activityId) db.prepare("DELETE FROM live_activity_tokens WHERE activity_id=?").run(activityId);
  return ok({ ok: true });
}
