import { getAuth } from "@/server/auth/auth";
import { ok } from "@/server/http/respond";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  const auth = getAuth(req);
  return ok(auth ? { authenticated: true, role: auth.role, actor: auth.actor, owner: auth.owner ?? null } : { authenticated: false });
}
