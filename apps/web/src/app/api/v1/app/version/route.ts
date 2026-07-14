import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, ok, fail } from "@/server/http/respond";

// Neuester iOS-Build (TestFlight) für das In-App-Update-Banner.
// GET (readonly): aktuellste bekannte Buildnummer + optionaler TestFlight-Link.
// POST (agent): CI meldet nach dem TestFlight-Upload die tatsächliche Buildnummer.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function setting(key: string): string | null {
  const row = getDb().prepare("SELECT value FROM app_settings WHERE key=?").get(key) as { value: string } | undefined;
  return row?.value ?? null;
}
function putSetting(key: string, value: string): void {
  getDb().prepare(
    "INSERT INTO app_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=datetime('now')",
  ).run(key, value);
}

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const latest = Number(setting("ios_latest_build") ?? "0");
  return ok({
    latest_build: Number.isFinite(latest) ? latest : 0,
    testflight_url: setting("ios_testflight_url"),
  });
}

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!auth) return unauthorized();
  if (!hasRole(auth, "agent")) return forbidden();
  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const n = Number((body as { latest_build?: unknown }).latest_build);
  if (!Number.isFinite(n) || n <= 0) return fail("invalid", "latest_build (positive Zahl) erforderlich.");
  putSetting("ios_latest_build", String(Math.floor(n)));
  const tf = (body as { testflight_url?: unknown }).testflight_url;
  if (typeof tf === "string" && tf) putSetting("ios_testflight_url", tf);
  return ok({ ok: true, latest_build: Math.floor(n) });
}
