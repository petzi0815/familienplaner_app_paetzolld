import { searchAll } from "@/server/domains/queries";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok, fail } from "@/server/http/respond";

// Cross-Domain-Volltextsuche — FTS5 (mit LIKE-Fallback). Logik in server/domains/queries.ts (auch von MCP genutzt).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const url = new URL(req.url);
  const q = (url.searchParams.get("q") ?? "").trim();
  if (!q) return fail("missing_q", "Query-Parameter 'q' erforderlich.", 400);
  const domainFilter = url.searchParams.get("domains");
  const domains = domainFilter ? new Set(domainFilter.split(",").map((s) => s.trim())) : undefined;
  return ok(searchAll(q, domains));
}
