import { config } from "@/server/config";

// Maschinenlesbare API-Beschreibung. In Phase 0 minimal; ab Phase 2 aus zod-Schemas generiert.
export const runtime = "nodejs";

export function GET(): Response {
  const spec = {
    openapi: "3.1.0",
    info: {
      title: "Familienplaner API",
      version: "0.1.0",
      description:
        "API-first Familienplaner (Paetzold-Stilke). Phase 0 — Fundament. Domänen-Endpunkte folgen in Phase 2/3.",
    },
    servers: [{ url: config.publicBaseUrl }],
    paths: {
      "/healthz": {
        get: { summary: "Liveness-Probe", responses: { "200": { description: "ok" } } },
      },
      "/version": {
        get: { summary: "Version & Git-Commit", responses: { "200": { description: "Version-Info" } } },
      },
      "/api/v1": {
        get: { summary: "API-Index", responses: { "200": { description: "Einstieg/Links" } } },
      },
      "/api/v1/debug/logs": {
        get: {
          summary: "Log-Ringpuffer (admin)",
          security: [{ bearerAuth: [] }],
          parameters: [
            { name: "lines", in: "query", schema: { type: "integer", default: 300 } },
            { name: "grep", in: "query", schema: { type: "string" } },
          ],
          responses: { "200": { description: "Letzte Logzeilen" }, "401": { description: "unauthorized" } },
        },
      },
    },
    components: {
      securitySchemes: {
        bearerAuth: { type: "http", scheme: "bearer", description: "Admin-Token (Phase 0) bzw. API-Key (ab Phase 2)." },
      },
    },
  };
  return Response.json(spec);
}
