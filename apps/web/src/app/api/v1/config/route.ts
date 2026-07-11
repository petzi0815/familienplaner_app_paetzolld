import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, ok, fail } from "@/server/http/respond";

// Runtime-Config (app_settings). GET/PUT nur Admin. Ermöglicht Änderungen an der App via API.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  const auth = getAuth(req);
  if (!hasRole(auth, "admin")) return auth ? forbidden() : unauthorized();
  const rows = getDb().prepare("SELECT key, value FROM app_settings ORDER BY key").all() as { key: string; value: string }[];
  const settings: Record<string, string> = {};
  for (const r of rows) settings[r.key] = r.value;
  return ok({ settings });
}

export async function PUT(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "admin")) return auth ? forbidden() : unauthorized();
  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const entries = Object.entries(body ?? {}).filter(([k]) => k !== "dry_run");
  if (!entries.length) return fail("empty", "Keine Settings angegeben.", 400);
  const db = getDb();
  const stmt = db.prepare("INSERT INTO app_settings (key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=datetime('now')");
  const tx = db.transaction(() => { for (const [k, v] of entries) stmt.run(k, typeof v === "string" ? v : JSON.stringify(v)); });
  tx();
  db.prepare("INSERT INTO event_log (actor, action, domain, detail) VALUES (?,?,?,?)").run(auth.actor, "config", "system", JSON.stringify(entries.map(([k]) => k)));
  return ok({ ok: true, updated: entries.map(([k]) => k) });
}
