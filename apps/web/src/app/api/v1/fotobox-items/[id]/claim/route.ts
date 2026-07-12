import { getDb } from "@/server/db/connection";
import { fail, notFound } from "@/server/http/respond";
import { requireAgent, applyItemUpdate, nowIso } from "@/server/fotobox/lifecycle";
import { getItemRow } from "@/server/fotobox/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Ctx = { params: Promise<{ id: string }> };

// POST /api/v1/fotobox-items/{id}/claim { worker, lock_ttl_seconds } — Lock für die Verarbeitung.
export async function POST(req: Request, { params }: Ctx): Promise<Response> {
  const a = requireAgent(req); if ("error" in a) return a.error;
  const { id } = await params;
  const db = getDb();
  const item = getItemRow(db, id); if (!item) return notFound("Fotobox-Item");
  let body: Record<string, unknown> = {};
  try { body = (await req.json()) as Record<string, unknown>; } catch { /* leerer Body ok */ }

  const worker = String(body.worker ?? a.auth.actor ?? "worker");
  const ttl = Math.min(Math.max(Number(body.lock_ttl_seconds ?? 900) || 900, 30), 86400);
  const until = item.claimed_until as string | null;
  if (item.status === "processing" && until && new Date(until).getTime() > Date.now() && item.claimed_by !== worker) {
    return fail("locked", `Item ist bereits von '${String(item.claimed_by)}' gelockt (bis ${until}).`, 409, { claimed_by: item.claimed_by, claimed_until: until });
  }
  const claimedUntil = new Date(Date.now() + ttl * 1000).toISOString();
  return applyItemUpdate(db, id, {
    status: "processing", claimed_by: worker, claimed_until: claimedUntil,
    attempts: Number(item.attempts ?? 0) + 1, last_attempt_at: nowIso(),
  }, a.auth, "claimed");
}
