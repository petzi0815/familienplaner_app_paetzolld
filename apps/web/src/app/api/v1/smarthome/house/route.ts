import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, unauthorized } from "@/server/http/respond";
import { houseState } from "@/server/homeassistant/house";

// Kuratierte Haus-Steuerung: Raffstore-Zustände + Szenen-Scripts (Home Assistant).
// Statische v1-Route → überschreibt das generische [domain].
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  return ok(await houseState());
}
