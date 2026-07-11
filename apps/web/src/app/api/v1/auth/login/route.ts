import { config } from "@/server/config";
import { signSession, SESSION_COOKIE, SESSION_TTL_MS } from "@/server/auth/session";
import { fail } from "@/server/http/respond";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  let body: { password?: string };
  try { body = (await req.json()) as { password?: string }; } catch { body = {}; }
  const pw = String(body.password ?? "");
  if (!config.adminPassword) return fail("not_configured", "ADMIN_PASSWORD ist nicht gesetzt.", 500);
  if (pw !== config.adminPassword) return fail("invalid", "Falsches Passwort.", 401);

  const token = signSession({ u: "familie", exp: Date.now() + SESSION_TTL_MS });
  const secure = config.nodeEnv === "production" ? "; Secure" : "";
  const cookie = `${SESSION_COOKIE}=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${Math.floor(SESSION_TTL_MS / 1000)}${secure}`;
  return Response.json({ ok: true, role: "admin" }, { headers: { "cache-control": "no-store", "set-cookie": cookie } });
}
