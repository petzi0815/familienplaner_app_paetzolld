import { resourceByKey } from "@/server/domains/registry";
import { getRow, updateRow, deleteRow, schemaOf, createRow } from "@/server/domains/crud";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, notFound, fail, ok } from "@/server/http/respond";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ domain: string; id: string }> };

async function resolve(req: Request, params: Ctx["params"]) {
  const { domain, id } = await params;
  const res = resourceByKey(domain);
  return { res, id };
}

export async function GET(req: Request, { params }: Ctx): Promise<Response> {
  const { res, id } = await resolve(req, params);
  if (!res) return notFound("Ressource");
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  if (id === "schema") return schemaOf(res); // GET /api/v1/<domain>/schema
  return getRow(res, id);
}

async function readBody(req: Request): Promise<Record<string, unknown> | null> {
  try { return (await req.json()) as Record<string, unknown>; } catch { return null; }
}
const isDry = (req: Request, body: Record<string, unknown>) =>
  new URL(req.url).searchParams.get("dry_run") === "1" || body.dry_run === true;

// POST /api/v1/<domain>/import — Bulk-Import (ID-erhaltend) für Migration/Backfills.
export async function POST(req: Request, { params }: Ctx): Promise<Response> {
  const { res, id } = await resolve(req, params);
  if (!res) return notFound("Ressource");
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  if (id !== "import") return fail("not_supported", "POST wird nur auf /import unterstützt.", 405);
  const body = await readBody(req);
  const items = Array.isArray(body) ? body : (body?.items as unknown[]);
  if (!Array.isArray(items)) return fail("bad_body", "Erwartet Array oder { items: [...] }.", 400);
  const dryRun = new URL(req.url).searchParams.get("dry_run") === "1";
  let okCount = 0; const errors: unknown[] = [];
  for (const item of items) {
    const r = createRow(res, item as Record<string, unknown>, auth, dryRun);
    if (r.status < 400) okCount++; else errors.push({ item, status: r.status });
  }
  return ok({ imported: okCount, failed: errors.length, dry_run: dryRun, errors: errors.slice(0, 20) });
}

export async function PATCH(req: Request, { params }: Ctx): Promise<Response> {
  const { res, id } = await resolve(req, params);
  if (!res) return notFound("Ressource");
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const body = await readBody(req);
  if (!body) return fail("bad_json", "Ungültiger JSON-Body.", 400);
  return updateRow(res, id, body, auth, isDry(req, body));
}

export async function PUT(req: Request, ctx: Ctx): Promise<Response> {
  return PATCH(req, ctx); // Legacy-Kompatibilität (einige Alt-Routen nutzten PUT)
}

export async function DELETE(req: Request, { params }: Ctx): Promise<Response> {
  const { res, id } = await resolve(req, params);
  if (!res) return notFound("Ressource");
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const dryRun = new URL(req.url).searchParams.get("dry_run") === "1";
  return deleteRow(res, id, auth, dryRun);
}
