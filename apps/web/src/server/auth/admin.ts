import { config } from "@/server/config";

/**
 * P0-Minimalgate für admin-geschützte Endpunkte (z.B. /api/v1/debug/logs):
 * Bearer-Token == ADMIN_PASSWORD. Die vollständige Auth (rollenbasierte API-Keys
 * in der DB + Session-Login) folgt in Phase 2 und ersetzt diese Funktion.
 */
export function isAdminRequest(req: Request): boolean {
  const pw = config.adminPassword;
  if (!pw) return false;
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.toLowerCase().startsWith("bearer ") ? auth.slice(7).trim() : "";
  return token.length > 0 && token === pw;
}

export function unauthorized(): Response {
  return Response.json(
    { error: { code: "unauthorized", message: "Admin-Token erforderlich (Bearer ADMIN_PASSWORD)." } },
    { status: 401, headers: { "cache-control": "no-store" } },
  );
}
