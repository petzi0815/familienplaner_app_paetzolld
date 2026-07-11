import { getDb } from "@/server/db/connection";
import { columnNames } from "@/server/db/introspect";
import { RESOURCES, resourceByKey, pkOf, type Resource } from "@/server/domains/registry";
import { listRows, getRow, createRow, updateRow, deleteRow, schemaOf } from "@/server/domains/crud";
import { searchAll, dashboardToday, remindersDue } from "@/server/domains/queries";
import { JOBS, jobByName } from "@/server/jobs/registry";
import { runJob } from "@/server/jobs/runner";
import { sendPush, apnsEnabled } from "@/server/push/apns";
import type { Auth } from "@/server/auth/auth";

// MCP-Tools = dünner Adapter über dieselben Funktionen wie die REST-API (Single Source of Truth).
// Wenige generische Tools statt hunderter Einzel-Tools: `resource` + Discovery decken alle Ressourcen ab.

export interface McpToolResult { content: { type: "text"; text: string }[]; isError?: boolean }
export interface McpTool { name: string; description: string; inputSchema: Record<string, unknown> }

const resourceKeys = () => RESOURCES.map((r) => r.key);
const writableKeys = () => RESOURCES.filter((r) => !r.readonly).map((r) => r.key);

const str = (v: unknown) => (v == null ? "" : String(v));
const asObj = (v: unknown): Record<string, unknown> => (v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

/** Response (aus crud/http) → MCP-Ergebnis. Gleiche JSON-Form wie die REST-API. */
async function fromResponse(resp: Response): Promise<McpToolResult> {
  let body: unknown = null;
  try { body = await resp.json(); } catch { /* leer */ }
  return { content: [{ type: "text", text: JSON.stringify(body, null, 2) }], isError: resp.status >= 400 };
}
function data(value: unknown): McpToolResult {
  return { content: [{ type: "text", text: JSON.stringify(value, null, 2) }] };
}
function toolError(message: string): McpToolResult {
  return { content: [{ type: "text", text: JSON.stringify({ error: { code: "tool_error", message } }, null, 2) }], isError: true };
}

function resolve(args: Record<string, unknown>): Resource | McpToolResult {
  const key = str(args.resource);
  const res = resourceByKey(key);
  if (!res) return toolError(`Unbekannte Ressource '${key}'. Verfügbar via list_resources. Gültig: ${resourceKeys().join(", ")}`);
  return res;
}
const isErr = (v: Resource | McpToolResult): v is McpToolResult => "content" in v;

/** Tool-Definitionen (dynamisch: `resource`-Enum kommt aus der Registry). */
export function buildTools(): McpTool[] {
  const resourceEnum = { type: "string", enum: resourceKeys(), description: "Ressourcen-Schlüssel (z.B. termine, geschenk-geschenke, foto-inbox)." };
  const writableEnum = { type: "string", enum: writableKeys() };
  return [
    {
      name: "list_resources",
      description: "Alle verfügbaren Ressourcen (Lebensbereiche) mit Spalten und Schreibschutz auflisten. Zuerst aufrufen, um zu wissen, was existiert.",
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
    },
    {
      name: "resource_schema",
      description: "Spalten, Typen, Pflichtfelder und erlaubte Werte (Enums) einer Ressource. Vor create_record aufrufen, um gültige Werte zu kennen.",
      inputSchema: { type: "object", properties: { resource: resourceEnum }, required: ["resource"], additionalProperties: false },
    },
    {
      name: "list_records",
      description: "Datensätze einer Ressource lesen — mit Spaltenfiltern, Volltext (search), Sortierung (sort='spalte:asc|desc') und Pagination.",
      inputSchema: {
        type: "object",
        properties: {
          resource: resourceEnum,
          filters: { type: "object", description: "Exakte Spaltenfilter {spalte: wert}.", additionalProperties: true },
          search: { type: "string", description: "Volltext über Textspalten." },
          sort: { type: "string", description: "z.B. 'date:asc'." },
          limit: { type: "integer", minimum: 1, maximum: 1000, default: 100 },
          offset: { type: "integer", minimum: 0, default: 0 },
        },
        required: ["resource"], additionalProperties: false,
      },
    },
    {
      name: "get_record",
      description: "Einen Datensatz per ID holen.",
      inputSchema: { type: "object", properties: { resource: resourceEnum, id: { type: "string" } }, required: ["resource", "id"], additionalProperties: false },
    },
    {
      name: "create_record",
      description: "Neuen Datensatz anlegen. dry_run=true validiert nur (kein Schreiben). Erst resource_schema prüfen. Nur beschreibbare Ressourcen.",
      inputSchema: {
        type: "object",
        properties: { resource: writableEnum, data: { type: "object", description: "Feld/Wert-Paare gemäß resource_schema.", additionalProperties: true }, dry_run: { type: "boolean", default: false } },
        required: ["resource", "data"], additionalProperties: false,
      },
    },
    {
      name: "update_record",
      description: "Bestehenden Datensatz teilweise ändern (nur angegebene Felder). dry_run=true = Vorschau.",
      inputSchema: {
        type: "object",
        properties: { resource: writableEnum, id: { type: "string" }, data: { type: "object", additionalProperties: true }, dry_run: { type: "boolean", default: false } },
        required: ["resource", "id", "data"], additionalProperties: false,
      },
    },
    {
      name: "delete_record",
      description: "Datensatz löschen. dry_run=true = Vorschau ohne Löschen. Nur nach ausdrücklicher Absicht verwenden.",
      inputSchema: {
        type: "object",
        properties: { resource: writableEnum, id: { type: "string" }, dry_run: { type: "boolean", default: false } },
        required: ["resource", "id"], additionalProperties: false,
      },
    },
    {
      name: "search",
      description: "Ressourcenübergreifende Volltextsuche über alle Lebensbereiche.",
      inputSchema: {
        type: "object",
        properties: { q: { type: "string" }, domains: { type: "string", description: "Optional: kommagetrennte Domains als Filter (z.B. 'reisen,garten')." } },
        required: ["q"], additionalProperties: false,
      },
    },
    { name: "dashboard_today", description: "Kompakter Tageszustand: anstehende Termine, fällige Erinnerungen, nächste Reise, offene Garten-Aufgaben, bald ablaufende Lebensmittel, Foto-Inbox-Zähler.", inputSchema: { type: "object", properties: {}, additionalProperties: false } },
    { name: "reminders_due", description: "Heute fällige Termin-Erinnerungen (noch nicht gesendet).", inputSchema: { type: "object", properties: {}, additionalProperties: false } },
    {
      name: "foto_inbox_new",
      description: "Neue, noch nicht zugeordnete Fotos aus dem Foto-Eingang (status='neu'). Workflow: Foto laden → analysieren → update_record(foto-inbox, id, {status:'zugeordnet', ...}) löst automatisch einen Push aus.",
      inputSchema: { type: "object", properties: { limit: { type: "integer", minimum: 1, maximum: 200, default: 50 } }, additionalProperties: false },
    },
    { name: "list_jobs", description: "Alle Hintergrund-Jobs (Cron) mit letztem Lauf.", inputSchema: { type: "object", properties: {}, additionalProperties: false } },
    {
      name: "run_job",
      description: "Einen Job manuell auslösen. dry_run=true = Vorschau ohne Senden/Schreiben.",
      inputSchema: { type: "object", properties: { name: { type: "string", enum: JOBS.map((j) => j.name) }, dry_run: { type: "boolean", default: false } }, required: ["name"], additionalProperties: false },
    },
    {
      name: "send_push",
      description: "Push-Benachrichtigung an alle registrierten iOS-Geräte senden (nur wenn APNs konfiguriert).",
      inputSchema: { type: "object", properties: { title: { type: "string" }, body: { type: "string" }, data: { type: "object", additionalProperties: true } }, additionalProperties: false },
    },
  ];
}

/** Führt ein Tool aus. `auth` stammt aus der bereits geprüften MCP-Anfrage (Rolle >= agent). */
export async function callTool(name: string, rawArgs: unknown, auth: Auth): Promise<McpToolResult> {
  const args = asObj(rawArgs);
  try {
    switch (name) {
      case "list_resources": {
        const db = getDb();
        return data(RESOURCES.map((r) => ({ key: r.key, domain: r.domain, label: r.label, readonly: !!r.readonly, primary_key: pkOf(r), image: r.image ?? null, columns: columnNames(db, r.table) })));
      }
      case "resource_schema": {
        const res = resolve(args); if (isErr(res)) return res;
        return fromResponse(schemaOf(res));
      }
      case "list_records": {
        const res = resolve(args); if (isErr(res)) return res;
        const u = new URL("http://mcp.local/");
        if (args.search != null) u.searchParams.set("search", str(args.search));
        if (args.sort != null) u.searchParams.set("sort", str(args.sort));
        if (args.limit != null) u.searchParams.set("limit", str(args.limit));
        if (args.offset != null) u.searchParams.set("offset", str(args.offset));
        for (const [k, v] of Object.entries(asObj(args.filters))) u.searchParams.set(k, str(v));
        return fromResponse(listRows(res, u));
      }
      case "get_record": {
        const res = resolve(args); if (isErr(res)) return res;
        return fromResponse(getRow(res, str(args.id)));
      }
      case "create_record": {
        const res = resolve(args); if (isErr(res)) return res;
        return fromResponse(createRow(res, asObj(args.data), auth, args.dry_run === true));
      }
      case "update_record": {
        const res = resolve(args); if (isErr(res)) return res;
        return fromResponse(updateRow(res, str(args.id), asObj(args.data), auth, args.dry_run === true));
      }
      case "delete_record": {
        const res = resolve(args); if (isErr(res)) return res;
        return fromResponse(deleteRow(res, str(args.id), auth, args.dry_run === true));
      }
      case "search": {
        const q = str(args.q).trim();
        if (!q) return toolError("Parameter 'q' erforderlich.");
        const domains = args.domains ? new Set(str(args.domains).split(",").map((s) => s.trim()).filter(Boolean)) : undefined;
        return data(searchAll(q, domains));
      }
      case "dashboard_today": return data(dashboardToday());
      case "reminders_due": return data(remindersDue());
      case "foto_inbox_new": {
        const res = resourceByKey("foto-inbox")!;
        const u = new URL("http://mcp.local/");
        u.searchParams.set("status", "neu");
        u.searchParams.set("sort", "id:asc");
        u.searchParams.set("limit", str(args.limit ?? 50));
        return fromResponse(listRows(res, u));
      }
      case "list_jobs": {
        const db = getDb();
        return data(JOBS.map((j) => ({ name: j.name, schedule: j.schedule, description: j.description, topic: j.topic, last_run: db.prepare("SELECT id,started_at,finished_at,status,affected_rows,dry_run FROM job_runs WHERE name=? ORDER BY id DESC LIMIT 1").get(j.name) ?? null })));
      }
      case "run_job": {
        const jobName = str(args.name);
        if (!jobByName(jobName)) return toolError(`Unbekannter Job '${jobName}'. Verfügbar: ${JOBS.map((j) => j.name).join(", ")}`);
        const outcome = await runJob(jobName, { dryRun: args.dry_run === true });
        return data(outcome);
      }
      case "send_push": {
        if (!apnsEnabled()) return toolError("APNs ist nicht konfiguriert (Server-Env fehlt).");
        const title = str(args.title).trim();
        const body = str(args.body).trim();
        if (!title && !body) return toolError("Feld 'title' oder 'body' erforderlich.");
        const result = await sendPush({ title, body, data: asObj(args.data) });
        return data(result);
      }
      default:
        return toolError(`Unbekanntes Tool '${name}'.`);
    }
  } catch (e) {
    return toolError(String((e as Error)?.message ?? e));
  }
}
