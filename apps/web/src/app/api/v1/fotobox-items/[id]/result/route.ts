import { getDb } from "@/server/db/connection";
import { fail, notFound } from "@/server/http/respond";
import { requireAgent, applyItemUpdate, nowIso } from "@/server/fotobox/lifecycle";
import { getItemRow } from "@/server/fotobox/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Ctx = { params: Promise<{ id: string }> };
const s = (v: unknown): string | null => (v == null || v === "" ? null : String(v));

// POST /api/v1/fotobox-items/{id}/result { created_resource, created_id, summary, status?, target_id? }
// Ole meldet das Verarbeitungsergebnis zurück (Default-Status 'done').
export async function POST(req: Request, { params }: Ctx): Promise<Response> {
  const a = requireAgent(req); if ("error" in a) return a.error;
  const { id } = await params;
  const db = getDb();
  if (!getItemRow(db, id)) return notFound("Fotobox-Item");
  let body: Record<string, unknown> = {};
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const cols: Record<string, unknown> = {
    status: s(body.status) ?? "done",
    result_processed_at: nowIso(),
    result_created_resource: s(body.created_resource ?? body.result_created_resource),
    result_created_id: s(body.created_id ?? body.result_created_id),
    result_summary: s(body.summary ?? body.result_summary),
    result_error: null,
    claimed_by: null,
    claimed_until: null,
  };
  if (body.target_id != null) cols.target_id = s(body.target_id);
  if (body.target_resource != null) cols.target_resource = s(body.target_resource);
  return applyItemUpdate(db, id, cols, a.auth, "result");
}
