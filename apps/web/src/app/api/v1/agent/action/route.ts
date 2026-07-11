import { resourceByKey } from "@/server/domains/registry";
import { createRow, updateRow, deleteRow } from "@/server/domains/crud";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, notFound, fail } from "@/server/http/respond";

// Validierte Aktionen mit Dry-Run — der Agent kann vor riskanten Aktionen eine Vorschau holen.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface ActionBody {
  action?: "create" | "update" | "delete";
  resource?: string;
  id?: string | number;
  data?: Record<string, unknown>;
  dry_run?: boolean;
}

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: ActionBody;
  try { body = (await req.json()) as ActionBody; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const res = body.resource ? resourceByKey(body.resource) : undefined;
  if (!res) return notFound("Ressource (Feld 'resource')");
  const dry = body.dry_run === true;

  switch (body.action) {
    case "create":
      return createRow(res, body.data ?? {}, auth, dry);
    case "update":
      if (body.id == null) return fail("missing_id", "Feld 'id' erforderlich für update.", 400);
      return updateRow(res, String(body.id), body.data ?? {}, auth, dry);
    case "delete":
      if (body.id == null) return fail("missing_id", "Feld 'id' erforderlich für delete.", 400);
      return deleteRow(res, String(body.id), auth, dry);
    default:
      return fail("bad_action", "Feld 'action' muss create|update|delete sein.", 400);
  }
}
