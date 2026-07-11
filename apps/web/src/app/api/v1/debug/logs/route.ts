import { tail, size } from "@/server/observability/ringbuffer";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized } from "@/server/http/respond";

// Log-Ringpuffer (admin). Primäre Debug-Quelle ohne Coolify-Terminal.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "admin")) return unauthorized();
  const { searchParams } = new URL(req.url);
  const lines = Number(searchParams.get("lines") ?? "300") || 300;
  const grep = searchParams.get("grep") ?? undefined;
  return Response.json(
    { total: size(), lines: tail(lines, grep) },
    { headers: { "cache-control": "no-store" } },
  );
}
