import { getDb } from "@/server/db/connection";
import { getColumns } from "@/server/db/introspect";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, notFound, unauthorized, forbidden } from "@/server/http/respond";
import { allowedMap, labelsFor, validateItemValues, targetResourceForDomain } from "@/server/fotobox/labels";
import { serializeItem, getItemRow, logProc } from "@/server/fotobox/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ id: string }> };
type Obj = Record<string, unknown>;
const s = (v: unknown): string | null => (v == null || v === "" ? null : String(v));
const asObj = (v: unknown): Obj => (v && typeof v === "object" && !Array.isArray(v) ? (v as Obj) : {});

function schemaResponse(): Response {
  const db = getDb();
  const cols = getColumns(db, "fotobox_items").map((c) => ({
    name: c.name, type: c.type || "TEXT", required: !!c.notnull && !c.pk && c.dflt == null, primary_key: !!c.pk,
  }));
  return ok({
    resource: "fotobox-items",
    table: "fotobox_items",
    primary_key: "id",
    columns: cols,
    allowed: allowedMap(db),
    domains: labelsFor(db, "domain"), // inkl. target_resource-Mapping (für UI/Agent)
    extend: "Wertebereiche erweiterbar: POST /api/v1/fotobox-labels { field, value, label?, target_resource? }. field ∈ {domain,intent,status,review_reason,target_resource,label_key}.",
    lifecycle: {
      create: "POST /api/v1/fotobox-items (idempotency_key, uploaded_by, routing, review, media[])",
      claim: "POST /api/v1/fotobox-items/{id}/claim { worker, lock_ttl_seconds }",
      result: "POST /api/v1/fotobox-items/{id}/result { created_resource, created_id, summary, status? }",
      fail: "POST /api/v1/fotobox-items/{id}/fail { error, status? }",
      approve: "POST /api/v1/fotobox-items/{id}/approve  (needs_review → pending)",
      reject: "POST /api/v1/fotobox-items/{id}/reject { reason?, status? }",
      add_media: "POST /api/v1/fotobox-items/{id}/media  (multipart file ODER JSON data_base64)",
      get_media: "GET /api/v1/fotobox-items/{id}/media  ·  GET .../media/{media_id}",
    },
  });
}

export async function GET(req: Request, { params }: Ctx): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const { id } = await params;
  if (id === "schema") return schemaResponse();
  const db = getDb();
  const row = getItemRow(db, id);
  if (!row) return notFound("Fotobox-Item");
  return ok(serializeItem(db, row));
}

/** Teil-Update: akzeptiert nested (routing/review/uploaded_by/result) ODER flache Spalten. */
function flattenPatch(body: Obj): Obj {
  const out: Obj = {};
  const rt = asObj(body.routing), rv = asObj(body.review), up = asObj(body.uploaded_by), rs = asObj(body.result);
  const set = (col: string, v: unknown) => { if (v !== undefined) out[col] = v; };
  set("status", body.status);
  set("source", body.source);
  set("domain", rt.domain ?? body.domain);
  set("intent", rt.intent ?? body.intent);
  set("target_resource", rt.target_resource ?? body.target_resource);
  set("target_id", rt.target_id ?? body.target_id);
  set("confidence", rt.confidence ?? body.confidence);
  set("preclassified_by", rt.preclassified_by ?? body.preclassified_by);
  set("uploaded_person", up.person ?? body.uploaded_person);
  set("uploaded_display_name", up.display_name ?? body.uploaded_display_name);
  if (body.analysis_hint !== undefined) out.analysis_hint = body.analysis_hint == null ? null : JSON.stringify(body.analysis_hint);
  if (body.labels !== undefined) out.labels = body.labels == null ? null : JSON.stringify(body.labels);
  if (body.telegram_equivalent !== undefined) out.telegram_equivalent = body.telegram_equivalent == null ? null : JSON.stringify(body.telegram_equivalent);
  if (rv.required !== undefined || body.review_required !== undefined) out.review_required = (rv.required ?? body.review_required) ? 1 : 0;
  set("review_reason", rv.reason ?? body.review_reason);
  set("review_question", rv.question ?? body.review_question);
  set("result_summary", rs.summary ?? body.result_summary);
  set("result_created_resource", rs.created_resource ?? body.result_created_resource);
  set("result_created_id", rs.created_id ?? body.result_created_id);
  set("result_error", rs.error ?? body.result_error);
  return out;
}

export async function PATCH(req: Request, { params }: Ctx): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const { id } = await params;
  const db = getDb();
  const existing = getItemRow(db, id);
  if (!existing) return notFound("Fotobox-Item");
  let body: Obj;
  try { body = (await req.json()) as Obj; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const cols = flattenPatch(body);
  // Normalisieren: '' → null (außer bewusst gesetzte Strings)
  for (const k of Object.keys(cols)) if (cols[k] === "") cols[k] = null;
  // target_resource aus Domain nachziehen, wenn Domain gesetzt aber target_resource nicht mitgegeben.
  if (cols.domain && cols.target_resource === undefined && !existing.target_resource) {
    const tr = targetResourceForDomain(db, String(cols.domain)); if (tr) cols.target_resource = tr;
  }
  if (!Object.keys(cols).length) return fail("empty", "Keine gültigen Felder zum Aktualisieren.", 400);

  const violation = validateItemValues(db, cols);
  if (violation) return fail("invalid_value", `Feld '${violation.field}' erlaubt nur (aktive Labels): ${violation.allowed.join(", ")}. Neue Werte via POST /api/v1/fotobox-labels.`, 422, violation);

  if (new URL(req.url).searchParams.get("dry_run") === "1" || body.dry_run === true) {
    return ok({ dry_run: true, would: { action: "update", resource: "fotobox-items", id, data: cols } });
  }
  cols.updated_at = new Date().toISOString();
  const keys = Object.keys(cols);
  try {
    db.prepare(`UPDATE fotobox_items SET ${keys.map((k) => `"${k}" = ?`).join(", ")} WHERE id = ?`).run(...keys.map((k) => cols[k] as never), id);
  } catch (e) {
    return fail("db_error", "Fehler beim Aktualisieren.", 500, { sqlite: String((e as Error)?.message ?? e) });
  }
  logProc(db, id, auth?.actor ?? null, "patched", cols);
  return ok(serializeItem(db, getItemRow(db, id)!));
}

export async function PUT(req: Request, ctx: Ctx): Promise<Response> { return PATCH(req, ctx); }

export async function DELETE(req: Request, { params }: Ctx): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const { id } = await params;
  const db = getDb();
  if (!getItemRow(db, id)) return notFound("Fotobox-Item");
  if (new URL(req.url).searchParams.get("dry_run") === "1") return ok({ dry_run: true, would: { action: "delete", id } });
  db.prepare("DELETE FROM fotobox_item_media WHERE item_id=?").run(id);
  db.prepare("DELETE FROM fotobox_processing_log WHERE item_id=?").run(id);
  db.prepare("DELETE FROM fotobox_items WHERE id=?").run(id);
  return ok({ deleted: true, id });
}
