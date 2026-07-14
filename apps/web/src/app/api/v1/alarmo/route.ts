import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { alarmoStatus, alarmoDispatch, ALARMO_ACTIONS, type AlarmoAction } from "@/server/homeassistant/alarmo";

// Status + Steuerung der „Alarmo"-Alarmanlage (Home Assistant).
// Explizite statische Route → überschreibt das generische `[domain]` (alarmo ist keine DB-Ressource).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const ACTIONS = new Set<string>(ALARMO_ACTIONS);

/** Aktuellen Status lesen. Lesen = jede Auth. Nie-erreichbar/HA-fehlt → 200 mit reachable:false. */
export async function GET(req: Request): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  return ok(await alarmoStatus());
}

/** Scharf/unscharf schalten. Schreiben = agent+. PIN liegt serverseitig → Body enthält nur die Aktion. */
export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!auth) return unauthorized();
  if (!hasRole(auth, "agent")) return forbidden();

  let body: { action?: string };
  try {
    body = (await req.json()) as { action?: string };
  } catch {
    return fail("invalid_body", "JSON-Body mit { action } erwartet.", 400);
  }
  const action = body.action;
  if (!action || !ACTIONS.has(action)) {
    return fail("invalid_value", "action muss arm_away|arm_home|arm_night|arm_vacation|disarm sein.", 422, {
      allowed: [...ACTIONS],
    });
  }
  try {
    return ok(await alarmoDispatch(action as AlarmoAction));
  } catch (e) {
    return fail("ha_error", `Home Assistant nicht erreichbar oder Aktion fehlgeschlagen: ${(e as Error).message}`, 502);
  }
}
