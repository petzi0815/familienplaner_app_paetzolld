import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { coverDispatch, houseState, COVER_ACTIONS, isKnownCover, type CoverAction } from "@/server/homeassistant/house";

// Raffstore steuern (Höhe/Neigung/auf/zu/stop). Schreiben = agent+. Nur Allow-List-Entitäten.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const ACTIONS = new Set<string>(COVER_ACTIONS);
const NEEDS_VALUE = new Set(["set_position", "set_tilt"]);

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!auth) return unauthorized();
  if (!hasRole(auth, "agent")) return forbidden();

  let body: { entity?: string; action?: string; value?: number };
  try {
    body = (await req.json()) as { entity?: string; action?: string; value?: number };
  } catch {
    return fail("invalid_body", "JSON-Body mit { entity, action } erwartet.", 400);
  }
  if (!body.entity || !isKnownCover(body.entity)) {
    return fail("invalid_value", "Unbekannte Raffstore-Entität.", 422);
  }
  if (!body.action || !ACTIONS.has(body.action)) {
    return fail("invalid_value", "Ungültige Aktion.", 422, { allowed: [...ACTIONS] });
  }
  if (NEEDS_VALUE.has(body.action) && typeof body.value !== "number") {
    return fail("invalid_value", "value (0–100) erforderlich.", 422);
  }
  try {
    await coverDispatch(body.entity, body.action as CoverAction, body.value);
    return ok(await houseState());
  } catch (e) {
    return fail("ha_error", `Aktion fehlgeschlagen: ${(e as Error).message}`, 502);
  }
}
