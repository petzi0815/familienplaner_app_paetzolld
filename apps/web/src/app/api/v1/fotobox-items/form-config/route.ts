import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, unauthorized } from "@/server/http/respond";
import { formConfig } from "@/server/fotobox/formconfig";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// GET /api/v1/fotobox-items/form-config[?domain=<d>]
// Liefert je Domäne die kontextabhängigen Vorschlagsfelder (mit gültigen Optionen aus der Zielressource)
// — die iOS-Fotobox rendert daraus die Dropdowns, die sich an die gewählte Domäne anpassen.
export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const domain = new URL(req.url).searchParams.get("domain");
  const forms = formConfig(getDb(), domain);
  return ok({ domains: forms });
}
