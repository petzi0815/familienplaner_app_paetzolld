import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, unauthorized } from "@/server/http/respond";
import { groupedUpcoming } from "@/server/abfuhr/abfuhr";

// Kommende Abfuhrtermine je Kategorie gruppiert — für die native iOS-Kalenderansicht.
// GET /api/v1/abfuhr/calendar
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  return ok({ groups: groupedUpcoming(getDb()) });
}
