import { getDb } from "@/server/db/connection";
import { apnsEnabled } from "@/server/push/apns";
import { config } from "@/server/config";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok } from "@/server/http/respond";

// APNs-Status (admin): konfiguriert? wie viele Geräte?
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "admin")) return unauthorized();
  const devices = (getDb().prepare("SELECT COUNT(*) AS c FROM device_tokens").get() as { c: number }).c;
  return ok({ enabled: apnsEnabled(), bundle_id: config.apns.bundleId, devices });
}
