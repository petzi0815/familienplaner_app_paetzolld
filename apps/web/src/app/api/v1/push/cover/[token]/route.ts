import { fetchImage, verifyCoverToken } from "@/server/push/cover";

// ÖFFENTLICHE Route (bewusst ohne getAuth): die iOS-Notification-Service-Extension lädt das
// Cover eines Rich-Push ohne Bearer-Token. Schutz = signierter, kurzlebiger Token im Pfad
// (HMAC über Quell-URL + Ablauf mit SESSION_SECRET) — gleiches Muster wie der HLS-Proxy.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(_req: Request, { params }: { params: Promise<{ token: string }> }): Promise<Response> {
  const { token } = await params;
  const source = verifyCoverToken(token);
  if (!source) return new Response("gone", { status: 410 });
  const img = await fetchImage(source);
  if (!img) return new Response("not found", { status: 404 });
  return new Response(new Uint8Array(img.bytes), {
    status: 200,
    headers: {
      "content-type": img.contentType,
      "content-length": String(img.bytes.length),
      // Der Token trägt seine eigene Lebensdauer → für dessen Gültigkeit cachebar.
      "cache-control": "public, max-age=86400, immutable",
    },
  });
}
