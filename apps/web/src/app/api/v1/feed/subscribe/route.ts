import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";
import { getOrCreateFamilyToken } from "@/server/feed/tokens";
import { config } from "@/server/config";

// Liefert die Abo-URL des Familien-Kalender-Feeds (legt den Token bei Bedarf an).
// Vom iOS-„Kalender abonnieren"-Button + Einstellungen genutzt.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const token = getOrCreateFamilyToken();
  const url = `${config.publicBaseUrl}/api/feed/${token}/familienplaner.ics`;
  return ok({ url, webcal: url.replace(/^https?:\/\//, "webcal://"), scope: "family" });
}
