import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { scriptDispatch, isKnownScript } from "@/server/homeassistant/house";

// Szenen-Script starten (bringt alle Raffstores in eine Position). Schreiben = agent+. Nur Allow-List.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!auth) return unauthorized();
  if (!hasRole(auth, "agent")) return forbidden();

  let body: { entity?: string };
  try {
    body = (await req.json()) as { entity?: string };
  } catch {
    return fail("invalid_body", "JSON-Body mit { entity } erwartet.", 400);
  }
  if (!body.entity || !isKnownScript(body.entity)) {
    return fail("invalid_value", "Unbekanntes Script.", 422);
  }
  try {
    await scriptDispatch(body.entity);
    return ok({ ok: true });
  } catch (e) {
    return fail("ha_error", `Script fehlgeschlagen: ${(e as Error).message}`, 502);
  }
}
