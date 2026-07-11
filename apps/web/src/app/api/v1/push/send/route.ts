import { getAuth, hasRole } from "@/server/auth/auth";
import { sendPush } from "@/server/push/apns";
import { getDb } from "@/server/db/connection";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";

// Push an alle registrierten Geräte senden (Agent „Ole" / Admin).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: { title?: string; body?: string; data?: Record<string, unknown>; sound?: string | null; badge?: number };
  try { body = (await req.json()) as typeof body; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const title = String(body.title ?? "").trim();
  const text = String(body.body ?? "").trim();
  if (!title && !text) return fail("empty", "Feld 'title' oder 'body' erforderlich.", 400);
  const result = await sendPush({ title, body: text, data: body.data, sound: body.sound, badge: body.badge });
  getDb().prepare("INSERT INTO event_log (actor, action, domain, detail) VALUES (?,?,?,?)")
    .run(auth.actor, "push_send", "push", JSON.stringify({ title, sent: result.sent, total: result.total }));
  return ok(result);
}
