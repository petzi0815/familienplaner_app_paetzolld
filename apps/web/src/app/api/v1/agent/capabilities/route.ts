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
      media_upload: "POST /api/v1/media/upload — JSON { area, data_base64|data_url, filename?, mime?, resource?, id? } ODER multipart (area, file). Mit resource+id wird das Bild direkt am Datensatz gesetzt/ergänzt.",
      reisen_doc_download: "GET /api/v1/files/reisen-docs/{id}  (BLOB)",
      reisen_doc_upload: "POST /api/v1/files/reisen-docs  (multipart: trip_id, name, file)",
      foto_upload: "POST /api/v1/foto/upload — multipart (bereich, notiz?, file) ODER JSON (bereich?, data_base64). Legt foto_inbox-Eintrag status='neu' an.",
      foto_inbox_workflow: "Agent: GET /api/v1/foto-inbox?status=neu&sort=id:asc → Bild via url/media laden + analysieren → PATCH /api/v1/foto-inbox/{id} { status:'zugeordnet', analyse, zugeordnet_resource, zugeordnet_id } (Bild via /api/v1/media/upload {resource,id} an den Zieldatensatz hängen). PATCH auf status='zugeordnet' löst automatisch einen Push an die iOS-App aus.",
      fotobox: "Strukturierte Foto-Queue (Kanal neben Telegram). Wertebereiche (domain/intent/status/review_reason/target_resource) dynamisch aus fotobox_labels — GET /api/v1/fotobox-items/schema liefert die aktiven allowed-Werte + domain→target_resource-Mapping. Erweitern: POST /api/v1/fotobox-labels { field, value, label?, target_resource? }.",
      fotobox_workflow: "Ole-Worker: (1) GET /api/v1/fotobox-items?status=pending&sort=created_at:asc&limit=20 → (2) POST /api/v1/fotobox-items/{id}/claim { worker:'ole', lock_ttl_seconds:900 } (409 = schon gelockt) → (3) Medien via item.media[].url laden → (4) GET /api/v1/<target_resource>/schema (allowed beachten) → (5) Payload bauen, riskant erst ?dry_run=1 → (6) echten Write in die Zielressource → (7) POST /api/v1/fotobox-items/{id}/result { created_resource, created_id, summary }. Unsicher: POST .../fail { status:'needs_review', error, review_reason, review_question }.",
      push_send: "POST /api/v1/push/send { title, body, data? } — Alert-Push an alle iOS-Geräte (nur wenn APNs konfiguriert).",
      mcp: "POST /api/mcp — MCP-Server (Streamable HTTP) im selben Backend. Gleicher Bearer-Key wie hier (Rolle >= agent). Tools: list_resources, resource_schema, list_records, get_record, create_record, update_record, delete_record, search, dashboard_today, reminders_due, foto_inbox_new, list_jobs, run_job, send_push. Für MCP-fähige Agenten die bevorzugte Anbindung.",
    },
    domains: [...new Set(RESOURCES.map((r) => r.domain))],
    resources,
  });
}
