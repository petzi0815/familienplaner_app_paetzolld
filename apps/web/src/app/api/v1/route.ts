import { config } from "@/server/config";

// API-Wurzel: kurzer, maschinenlesbarer Einstieg. Offen.
export const runtime = "nodejs";

export function GET(): Response {
  return Response.json({
    name: "Familienplaner API",
    version: "v1",
    status: "phase-0",
    docs: `${config.publicBaseUrl}/api/v1/docs`,
    openapi: `${config.publicBaseUrl}/api/v1/openapi.json`,
    capabilities: `${config.publicBaseUrl}/api/v1/agent/capabilities`,
    health: `${config.publicBaseUrl}/healthz`,
    versionEndpoint: `${config.publicBaseUrl}/version`,
  });
}
