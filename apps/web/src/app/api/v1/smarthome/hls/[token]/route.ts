import { verifyHlsToken, proxyHls } from "@/server/homeassistant/hls-proxy";

// Öffentlicher HLS-Proxy (AVPlayer kann keinen Auth-Header senden → Schutz = signierter Token im Pfad).
// Der Token kodiert den HA-HLS-Pfad + Ablauf; nur `/api/hls/…`-Pfade werden proxyt.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ token: string }> };

export async function GET(_req: Request, { params }: Ctx): Promise<Response> {
  const { token } = await params;
  const haPath = verifyHlsToken(token);
  if (!haPath) return new Response("invalid or expired token", { status: 403 });
  try {
    return await proxyHls(haPath);
  } catch {
    return new Response("upstream error", { status: 502 });
  }
}
