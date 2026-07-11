import { config } from "@/server/config";
import { resourceByKey } from "@/server/domains/registry";
import { listRows } from "@/server/domains/crud";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, notFound, fail } from "@/server/http/respond";

// Strukturierte Suche über Domänen — nie freies SQL.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface QueryBody {
  resource?: string;
  filters?: Record<string, unknown>;
  search?: string;
  sort?: string;
  limit?: number;
  offset?: number;
}

export async function POST(req: Request): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  let body: QueryBody;
  try { body = (await req.json()) as QueryBody; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const res = body.resource ? resourceByKey(body.resource) : undefined;
  if (!res) return notFound("Ressource (Feld 'resource')");

  const url = new URL(`${config.publicBaseUrl}/api/v1/${res.key}`);
  for (const [k, v] of Object.entries(body.filters ?? {})) url.searchParams.set(k, String(v));
  if (body.search) url.searchParams.set("search", body.search);
  if (body.sort) url.searchParams.set("sort", body.sort);
  if (body.limit != null) url.searchParams.set("limit", String(body.limit));
  if (body.offset != null) url.searchParams.set("offset", String(body.offset));
  return listRows(res, url);
}
