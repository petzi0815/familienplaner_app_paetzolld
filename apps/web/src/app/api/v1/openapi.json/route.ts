import { config } from "@/server/config";
import { RESOURCES } from "@/server/domains/registry";

// OpenAPI 3.1 — generiert aus der Ressourcen-Registry + Spezial-Endpunkten.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(): Response {
  const sec = [{ bearerAuth: [] }];
  const okResp = { "200": { description: "OK" } };
  const idParam = [{ name: "id", in: "path", required: true, schema: { type: "string" } }];
  const listParams = [
    { name: "search", in: "query", schema: { type: "string" }, description: "Volltext (LIKE über Text-Spalten)" },
    { name: "limit", in: "query", schema: { type: "integer", default: 100 } },
    { name: "offset", in: "query", schema: { type: "integer", default: 0 } },
    { name: "sort", in: "query", schema: { type: "string" }, description: "spalte:asc|desc" },
  ];

  const paths: Record<string, unknown> = {};
  for (const r of RESOURCES) {
    const tag = r.domain;
    const list: Record<string, unknown> = {
      get: { tags: [tag], summary: `${r.label} — Liste`, security: sec, parameters: listParams, responses: okResp },
    };
    if (!r.readonly) list.post = { tags: [tag], summary: `${r.label} — Anlegen`, security: sec, responses: { "201": { description: "Erstellt" } } };
    paths[`/api/v1/${r.key}`] = list;

    const item: Record<string, unknown> = {
      get: { tags: [tag], summary: `${r.label} — Detail`, security: sec, parameters: idParam, responses: okResp },
    };
    if (!r.readonly) {
      item.patch = { tags: [tag], summary: `${r.label} — Ändern`, security: sec, parameters: idParam, responses: okResp };
      item.delete = { tags: [tag], summary: `${r.label} — Löschen (?dry_run=1)`, security: sec, parameters: idParam, responses: okResp };
    }
    paths[`/api/v1/${r.key}/{id}`] = item;
    paths[`/api/v1/${r.key}/schema`] = { get: { tags: [tag], summary: `${r.label} — Schema`, security: sec, responses: okResp } };
  }

  // Spezial-Endpunkte
  paths["/api/v1/agent/capabilities"] = { get: { tags: ["agent"], summary: "Fähigkeiten & API-Index", security: sec, responses: okResp } };
  paths["/api/v1/agent/query"] = { post: { tags: ["agent"], summary: "Strukturierte Domänen-Suche", security: sec, responses: okResp } };
  paths["/api/v1/agent/action"] = { post: { tags: ["agent"], summary: "Validierte Aktion (dry_run)", security: sec, responses: okResp } };
  paths["/api/v1/search"] = { get: { tags: ["agent"], summary: "Cross-Domain-Suche", security: sec, parameters: [{ name: "q", in: "query", required: true, schema: { type: "string" } }], responses: okResp } };
  paths["/api/v1/dashboard/today"] = { get: { tags: ["agent"], summary: "Tageszustand", security: sec, responses: okResp } };
  paths["/api/v1/reminders/due"] = { get: { tags: ["termine"], summary: "Fällige Erinnerungen", security: sec, responses: okResp } };
  paths["/api/v1/reminders/{id}/sent"] = { post: { tags: ["termine"], summary: "Erinnerung als gesendet markieren", security: sec, parameters: idParam, responses: okResp } };
  paths["/api/v1/config"] = {
    get: { tags: ["system"], summary: "Settings lesen (admin)", security: sec, responses: okResp },
    put: { tags: ["system"], summary: "Settings setzen (admin)", security: sec, responses: okResp },
  };
  paths["/api/v1/auth/login"] = { post: { tags: ["auth"], summary: "Login (Familien-Passwort)", responses: okResp } };
  paths["/api/v1/auth/me"] = { get: { tags: ["auth"], summary: "Aktueller Auth-Status", responses: okResp } };
  // Fotobox-Lifecycle (die CRUD/Schema-Pfade kommen aus der Registry-Schleife oben).
  paths["/api/v1/fotobox-items/form-config"] = { get: { tags: ["fotobox"], summary: "Kontextabhängige Vorschlagsfelder je Domäne (für die iOS-Picker)", security: sec, parameters: [{ name: "domain", in: "query", schema: { type: "string" }, description: "auf eine Domäne einschränken" }], responses: okResp } };
  paths["/api/v1/fotobox-items/{id}/claim"] = { post: { tags: ["fotobox"], summary: "Item für Verarbeitung locken (409 wenn belegt)", security: sec, parameters: idParam, responses: { ...okResp, "409": { description: "Bereits gelockt" } } } };
  paths["/api/v1/fotobox-items/{id}/result"] = { post: { tags: ["fotobox"], summary: "Verarbeitungsergebnis zurückschreiben (Default status=done)", security: sec, parameters: idParam, responses: okResp } };
  paths["/api/v1/fotobox-items/{id}/fail"] = { post: { tags: ["fotobox"], summary: "Fehlschlag/Review (status failed|needs_review|duplicate)", security: sec, parameters: idParam, responses: okResp } };
  paths["/api/v1/fotobox-items/{id}/approve"] = { post: { tags: ["fotobox"], summary: "Review erledigt: needs_review → pending", security: sec, parameters: idParam, responses: okResp } };
  paths["/api/v1/fotobox-items/{id}/reject"] = { post: { tags: ["fotobox"], summary: "Item verwerfen (Default status=ignored)", security: sec, parameters: idParam, responses: okResp } };
  paths["/api/v1/fotobox-items/{id}/media"] = {
    get: { tags: ["fotobox"], summary: "Medien eines Items auflisten", security: sec, parameters: idParam, responses: okResp },
    post: { tags: ["fotobox"], summary: "Bild anhängen (multipart 'file' ODER JSON data_base64)", security: sec, parameters: idParam, responses: { "201": { description: "Erstellt" } } },
  };
  paths["/api/v1/fotobox-items/{id}/media/{media_id}"] = { get: { tags: ["fotobox"], summary: "Originalbild eines Item-Mediums", security: sec, parameters: [...idParam, { name: "media_id", in: "path", required: true, schema: { type: "string" } }], responses: okResp } };
  paths["/api/v1/foto/upload"] = { post: { tags: ["foto"], summary: "Foto in den (einfachen) Foto-Eingang laden", security: sec, responses: { "201": { description: "Erstellt" } } } };

  paths["/healthz"] = { get: { tags: ["system"], summary: "Liveness", responses: okResp } };
  paths["/version"] = { get: { tags: ["system"], summary: "Version/Commit", responses: okResp } };

  const domains = [...new Set(RESOURCES.map((r) => r.domain)), "agent", "auth", "system"];
  const spec = {
    openapi: "3.1.0",
    info: {
      title: "Familienplaner API",
      version: "2.0.0",
      description: "API-first Familienplaner (Paetzold-Stilke). Alle Bereiche via generischem CRUD + agentenfreundliche Endpunkte. Auth: Bearer API-Key oder Session-Cookie.",
    },
    servers: [{ url: config.publicBaseUrl }],
    tags: domains.map((d) => ({ name: d })),
    paths,
    components: {
      securitySchemes: {
        bearerAuth: { type: "http", scheme: "bearer", description: "API-Key (Rolle agent/admin) oder Admin-Passwort." },
      },
    },
  };
  return Response.json(spec);
}
