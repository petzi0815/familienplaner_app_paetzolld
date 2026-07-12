import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, unauthorized } from "@/server/http/respond";
import { nextPerCategory, upcoming } from "@/server/abfuhr/abfuhr";

// Nächster Abfuhrtermin je Kategorie (Restmüll, Gelbe Tonne, Bio, Papier) + kommende Termine.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const db = getDb();
  return ok({ next: nextPerCategory(db), upcoming: upcoming(db, 20) });
}
