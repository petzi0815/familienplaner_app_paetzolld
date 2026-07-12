import { getDb } from "@/server/db/connection";
import { fail, notFound } from "@/server/http/respond";
import { requireAgent, applyItemUpdate } from "@/server/fotobox/lifecycle";
import { getItemRow } from "@/server/fotobox/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Ctx = { params: Promise<{ id: string }> };
const s = (v: unknown): string | null => (v == null || v === "" ? null : String(v));

// POST /api/v1/fotobox-items/{id}/reject { reason?, status? } — bewusst verwerfen (Default 'ignored').
export async function POST(req: Request, { params }: Ctx): Promise<Response> {
  const a = requireAgent(req); if ("error" in a) return a.error;
  const { id } = await params;
  const db = getDb();
  if (!getItemRow(db, id)) return notFound("Fotobox-Item");
  let body: Record<string, unknown> = {};
  try { body = (await req.json()) as Record<string, unknown>; } catch { /* leerer Body ok */ }
  const cols: Record<string, unknown> = {
    status: s(body.status) ?? "ignored",
    review_required: 0,
    claimed_by: null,
    claimed_until: null,
  };
  if (body.reason != null) cols.review_question = s(body.reason);
  return applyItemUpdate(db, id, cols, a.auth, "rejected");
}
