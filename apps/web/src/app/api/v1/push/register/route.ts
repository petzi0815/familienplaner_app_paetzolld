import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";

// iOS-App registriert / entfernt ihr APNs-Device-Token.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: { token?: string; environment?: string; user_label?: string };
  try { body = (await req.json()) as typeof body; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const token = String(body.token ?? "").trim();
  if (!token) return fail("no_token", "Feld 'token' erforderlich.", 400);
  const env = body.environment === "sandbox" ? "sandbox" : "production";
  // owner = Person hinter dem Login-Key (Lars/Elita); bei Oles Shared-Key NULL → Broadcast-Fallback greift.
  getDb().prepare(
    "INSERT INTO device_tokens (token, environment, user_label, owner, last_seen) VALUES (?,?,?,?,datetime('now')) " +
    "ON CONFLICT(token) DO UPDATE SET environment=excluded.environment, user_label=excluded.user_label, owner=excluded.owner, last_seen=datetime('now')",
  ).run(token, env, body.user_label ?? auth.actor, auth.owner ?? null);
  return ok({ ok: true });
}

export async function DELETE(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: { token?: string };
  try { body = (await req.json()) as typeof body; } catch { body = {}; }
  const token = String(body.token ?? "").trim();
  if (!token) return fail("no_token", "Feld 'token' erforderlich.", 400);
  getDb().prepare("DELETE FROM device_tokens WHERE token=?").run(token);
  return ok({ ok: true });
}
