import { resourceByKey } from "@/server/domains/registry";
import { listRows, createRow } from "@/server/domains/crud";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, notFound, fail } from "@/server/http/respond";

// Generisches CRUD für alle Registry-Ressourcen. Lesen: jede Auth. Schreiben: Agent/Admin.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request, { params }: { params: Promise<{ domain: string }> }): Promise<Response> {
  const { domain } = await params;
  const res = resourceByKey(domain);
  if (!res) return notFound("Ressource");
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  return listRows(res, new URL(req.url));
}

export async function POST(req: Request, { params }: { params: Promise<{ domain: string }> }): Promise<Response> {
  const { domain } = await params;
  const res = resourceByKey(domain);
  if (!res) return notFound("Ressource");
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const dryRun = new URL(req.url).searchParams.get("dry_run") === "1" || body.dry_run === true;
  return createRow(res, body, auth, dryRun);
}
