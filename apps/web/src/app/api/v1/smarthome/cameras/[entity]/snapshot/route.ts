import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, fail } from "@/server/http/respond";
import { cameraSnapshot, isKnownCamera } from "@/server/homeassistant/cameras";

// Aktueller Schnappschuss einer Kamera (Backend proxyt mit HA-Token → Client bekommt nur das JPEG).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ entity: string }> };

export async function GET(req: Request, { params }: Ctx): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const { entity } = await params;
  if (!isKnownCamera(entity)) return fail("invalid_value", "Unbekannte Kamera.", 422);
  try {
    const { bytes, contentType } = await cameraSnapshot(entity);
    return new Response(bytes, {
      status: 200,
      headers: { "content-type": contentType, "cache-control": "no-store" },
    });
  } catch (e) {
    return fail("ha_error", `Schnappschuss nicht verfügbar: ${(e as Error).message}`, 502);
  }
}
