import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, unauthorized } from "@/server/http/respond";
import { cameraList } from "@/server/homeassistant/cameras";

// Kuratierte Kameraliste (Home Assistant). Lesen = jede Auth.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  return ok(cameraList());
}
