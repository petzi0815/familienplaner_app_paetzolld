import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, unauthorized, fail } from "@/server/http/respond";
import { cameraHlsUrl, isKnownCamera } from "@/server/homeassistant/cameras";

// Live-HLS-URL einer Kamera (HA mintet sie via WebSocket). Der Client spielt die URL direkt (AVPlayer).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ entity: string }> };

export async function GET(req: Request, { params }: Ctx): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const { entity } = await params;
  if (!isKnownCamera(entity)) return fail("invalid_value", "Unbekannte Kamera.", 422);
  try {
    const url = await cameraHlsUrl(entity);
    return ok({ url });
  } catch (e) {
    return fail("ha_error", `Live-Stream nicht verfügbar: ${(e as Error).message}`, 502);
  }
}
