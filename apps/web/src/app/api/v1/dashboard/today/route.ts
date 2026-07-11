import { dashboardToday } from "@/server/domains/queries";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";

// Kompakter Tageszustand für „Ole" + Dashboard. Logik in server/domains/queries.ts (auch von MCP genutzt).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  return ok(dashboardToday());
}
