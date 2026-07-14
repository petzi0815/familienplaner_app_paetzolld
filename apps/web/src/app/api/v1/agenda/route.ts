import { agenda } from "@/server/domains/queries";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";

// Vereinheitlichter „Anstehendes"-Feed (Termine + Abfuhr + Reisen + Vorrat + generische reminders).
// Per-User-Sicht (read/notify) über den API-Key-owner. Logik in server/domains/queries.ts.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  const auth = getAuth(req);
  if (!hasRole(auth, "readonly")) return unauthorized();
  const raw = Number(new URL(req.url).searchParams.get("days") ?? "14");
  const days = Number.isFinite(raw) ? raw : 14;
  const data = agenda(days, auth?.owner ?? null);
  return ok({ data, total: data.length });
}
