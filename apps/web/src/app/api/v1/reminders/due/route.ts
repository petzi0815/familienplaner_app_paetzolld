import { remindersDue } from "@/server/domains/queries";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";

// Fällige Termin-Erinnerungen (aus `termine`): heute im Fenster [date - reminder_days, date],
// noch nicht gesendet, nicht erledigt. Logik in server/domains/queries.ts (auch von MCP genutzt).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  const auth = getAuth(req);
  if (!hasRole(auth, "readonly")) return unauthorized();
  return ok(remindersDue(auth?.owner ?? null));
}
