import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, ok } from "@/server/http/respond";
import { rotateFamilyToken } from "@/server/feed/tokens";
import { config } from "@/server/config";

// Rotiert den Familien-Feed-Token (admin). Bestehende Abo-Links werden ungültig.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function POST(req: Request): Response {
  const auth = getAuth(req);
  if (!auth) return unauthorized();
  if (!hasRole(auth, "admin")) return forbidden();
  const token = rotateFamilyToken();
  const url = `${config.publicBaseUrl}/api/feed/${token}/familienplaner.ics`;
  return ok({ url, webcal: url.replace(/^https?:\/\//, "webcal://") });
}
