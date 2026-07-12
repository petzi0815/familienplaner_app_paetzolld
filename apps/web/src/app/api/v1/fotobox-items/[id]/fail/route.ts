import { getDb } from "@/server/db/connection";
import { fail, notFound } from "@/server/http/respond";
import { requireAgent, applyItemUpdate } from "@/server/fotobox/lifecycle";
import { getItemRow } from "@/server/fotobox/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Ctx = { params: Promise<{ id: string }> };
const s = (v: unknown): string | null => (v == null || v === "" ? null : String(v));

// POST /api/v1/fotobox-items/{id}/fail { error, status?, review_reason?, review_question? }
// Fehlschlag/Review-Bedarf. Default-Status 'failed'; bei status='needs_review' wird review_required gesetzt.
export async function POST(req: Request, { params }: Ctx): Promise<Response> {
  const a = requireAgent(req); if ("error" in a) return a.error;
  const { id } = await params;
  const db = getDb();
  if (!getItemRow(db, id)) return notFound("Fotobox-Item");
  let body: Record<string, unknown> = {};
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const status = s(body.status) ?? "failed";
  const cols: Record<string, unknown> = {
    status,
    result_error: s(body.error ?? body.result_error),
    claimed_by: null,
    claimed_until: null,
  };
  if (status === "needs_review") {
    cols.review_required = 1;
    if (body.review_reason != null) cols.review_reason = s(body.review_reason);
    if (body.review_question != null) cols.review_question = s(body.review_question);
  }
  return applyItemUpdate(db, id, cols, a.auth, "failed");
}
