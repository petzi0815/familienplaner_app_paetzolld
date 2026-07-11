// Einheitliche HTTP-Antworten für die v1-API.
const NOSTORE = { "cache-control": "no-store" };

export function ok(data: unknown, init?: ResponseInit): Response {
  return Response.json(data, { ...init, headers: { ...NOSTORE, ...(init?.headers ?? {}) } });
}

export function created(data: unknown): Response {
  return Response.json(data, { status: 201, headers: NOSTORE });
}

export function fail(code: string, message: string, status = 400, details?: unknown): Response {
  return Response.json({ error: { code, message, details } }, { status, headers: NOSTORE });
}

export function listResponse(data: unknown[], total: number, extra?: Record<string, unknown>): Response {
  return Response.json(
    { data, total, ...(extra ?? {}) },
    { headers: { ...NOSTORE, "x-total-count": String(total) } },
  );
}

export const unauthorized = () => fail("unauthorized", "Authentifizierung erforderlich (Bearer API-Key oder Login).", 401);
export const forbidden = () => fail("forbidden", "Keine Berechtigung für diese Aktion.", 403);
export const notFound = (what = "Ressource") => fail("not_found", `${what} nicht gefunden.`, 404);
