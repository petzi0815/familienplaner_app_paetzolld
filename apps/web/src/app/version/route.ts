import { config } from "@/server/config";

// Deploy-Verifikation: commit == gepushter Kurz-SHA (Coolify liefert SOURCE_COMMIT). Offen.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(): Response {
  return Response.json(
    {
      name: "familienplaner",
      commit: config.gitSha,
      environment: config.sentryEnvironment,
      time: new Date().toISOString(),
    },
    { headers: { "cache-control": "no-store" } },
  );
}
