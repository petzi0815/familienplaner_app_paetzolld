import { getDb } from "@/server/db/connection";
import { notFound } from "@/server/http/respond";
import { requireAgent, applyItemUpdate } from "@/server/fotobox/lifecycle";
import { getItemRow } from "@/server/fotobox/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Ctx = { params: Promise<{ id: string }> };

// POST /api/v1/fotobox-items/{id}/approve — Review erledigt: needs_review → pending (Ole soll erneut verarbeiten).
export async function POST(req: Request, { params }: Ctx): Promise<Response> {
  const a = requireAgent(req); if ("error" in a) return a.error;
  const { id } = await params;
  const db = getDb();
  if (!getItemRow(db, id)) return notFound("Fotobox-Item");
  return applyItemUpdate(db, id, {
    status: "pending", review_required: 0, review_reason: null, review_question: null,
    claimed_by: null, claimed_until: null, result_error: null,
  }, a.auth, "approved");
}
