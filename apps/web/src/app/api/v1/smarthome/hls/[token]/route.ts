import { verifyHlsToken, proxyHls } from "@/server/homeassistant/hls-proxy";

// Öffentlicher HLS-Proxy (AVPlayer kann keinen Auth-Header senden → Schutz = signierter Token im Pfad).
// Der Token kodiert den HA-HLS-Pfad + Ablauf; nur `/api/hls/…`-Pfade werden proxyt.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ token: string }> };

export async function GET(request: Request, { params }: Ctx): Promise<Response> {
  const { token } = await params;
  const haPath = verifyHlsToken(token);
  if (!haPath) return new Response("invalid or expired token", { status: 403 });
  // Low-Latency-HLS: die `_HLS_*`-Parameter (msn/part/skip …), die AVPlayer für den blockierenden
  // Playlist-Reload anhängt, an Home Assistant durchreichen → niedrige Latenz statt „aufgelöstem" HLS.
  const hls: string[] = [];
  for (const [k, v] of new URL(request.url).searchParams) {
    if (k.startsWith("_HLS_")) hls.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
  }
  try {
    return await proxyHls(haPath, hls.length ? hls.join("&") : undefined);
  } catch {
    return new Response("upstream error", { status: 502 });
  }
}
