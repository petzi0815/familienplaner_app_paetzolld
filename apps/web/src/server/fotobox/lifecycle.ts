import type BetterSqlite3 from "better-sqlite3";
import { getAuth, hasRole, type Auth } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { validateItemValues } from "./labels";
import { serializeItem, getItemRow, logProc } from "./store";

// Gemeinsame Bausteine für die Lifecycle-Routen (claim/result/fail/approve/reject).

export function requireAgent(req: Request): { auth: Auth } | { error: Response } {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return { error: auth ? forbidden() : unauthorized() };
  return { auth };
}

export const nowIso = (): string => new Date().toISOString();

/** Validiert Label-Felder, setzt updated_at, schreibt das UPDATE, loggt und gibt das serialisierte Item zurück. */
export function applyItemUpdate(
  db: BetterSqlite3.Database,
  id: string,
  cols: Record<string, unknown>,
  auth: Auth | null,
  action: string,
): Response {
  const violation = validateItemValues(db, cols);
  if (violation) {
    return fail("invalid_value", `Feld '${violation.field}' erlaubt nur (aktive Labels): ${violation.allowed.join(", ")}. Neue Werte via POST /api/v1/fotobox-labels.`, 422, violation);
  }
  cols.updated_at = nowIso();
  const keys = Object.keys(cols);
  db.prepare(`UPDATE fotobox_items SET ${keys.map((k) => `"${k}" = ?`).join(", ")} WHERE id = ?`).run(...keys.map((k) => cols[k] as never), id);
  logProc(db, id, auth?.actor ?? null, action, cols);
  return ok(serializeItem(db, getItemRow(db, id)!));
}
