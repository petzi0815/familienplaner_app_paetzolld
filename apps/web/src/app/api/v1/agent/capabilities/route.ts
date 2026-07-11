import { config } from "@/server/config";
import { RESOURCES, pkOf } from "@/server/domains/registry";
import { getDb } from "@/server/db/connection";
import { columnNames } from "@/server/db/introspect";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";

// Maschinenlesbarer API-Index für den Agenten „Ole".
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "agent")) return unauthorized();
  const db = getDb();
  const resources = RESOURCES.map((r) => ({
    key: r.key,
    domain: r.domain,
    label: r.label,
    readonly: !!r.readonly,
    endpoint: `/api/v1/${r.key}`,
    primary_key: pkOf(r),
    image: r.image ?? null,
    columns: columnNames(db, r.table),
  }));
  return ok({
    base: `${config.publicBaseUrl}/api/v1`,
    auth: "Header: Authorization: Bearer <API-Key>",
    conventions: {
      list: "GET /<key>?<spalte>=<wert>&search=<text>&sort=<spalte>:asc|desc&limit=&offset=",
      get: "GET /<key>/{id}",
      create: "POST /<key>  (JSON-Body)",
      update: "PATCH /<key>/{id}",
      delete: "DELETE /<key>/{id}",
      schema: "GET /<key>/schema",
      import: "POST /<key>/import  (Array oder {items:[...]})",
      dry_run: "?dry_run=1 oder body.dry_run=true — Vorschau ohne Ausführung (create/update/delete)",
    },
    special: {
      query: "POST /api/v1/agent/query  { resource, filters, search, sort, limit, offset }",
      action: "POST /api/v1/agent/action  { action:create|update|delete, resource, id?, data?, dry_run? }",
      search: "GET /api/v1/search?q=<text>&domains=<a,b>",
      today: "GET /api/v1/dashboard/today",
      reminders_due: "GET /api/v1/reminders/due",
      reminder_sent: "POST /api/v1/reminders/{id}/sent",
      jobs: "GET /api/v1/jobs",
      job_run: "POST /api/v1/jobs/{name}/run  (?dry_run=1)",
    },
    domains: [...new Set(RESOURCES.map((r) => r.domain))],
    resources,
  });
}
