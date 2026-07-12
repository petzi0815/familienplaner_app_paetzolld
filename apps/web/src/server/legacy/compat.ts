// Kompatibilitäts-Schicht für die 1:1 portierten Original-Bereichsseiten.
//
// Die Originalseiten sprechen ihre eigenen `/api/<bereich>`-Endpunkte an (mit Spezialmodi wie
// ?stats, ?matrix, mode=month …). Statt jede Seite umzuverdrahten, spiegeln wir diese Endpunkte
// hier gegen die KONSOLIDIERTE SQLite (`getDb()` — ein Singleton, das NIE geschlossen werden darf).
// Tabellennamen sind in der konsolidierten DB präfixiert (items→samu_items, pflanzen→garten_pflanzen …).
//
// Bilder: Original-`bild_pfade`/`bild_pfad` enthalten bereits Storage-Keys der Form `<bereich>/<datei>`.
// Die Seiten werden minimal so umgestellt, dass sie Bilder über die bestehende, getestete Route
// `/api/v1/media/<key>` laden (kein eigener Bild-Endpunkt nötig).

import { getDb } from "@/server/db/connection";
import { getAuth, hasRole, type Role } from "@/server/auth/auth";

export { getDb };

/**
 * Auth-Guard für Kompat-Routen (spiegelt die v1-Konvention: Lesen = jede Auth, Schreiben = agent+).
 * Gibt eine 401/403-Response zurück, wenn nicht berechtigt — sonst `null` (weiter im Route-Handler).
 */
export function guard(req: Request, min: Role = "readonly"): Response | null {
  const auth = getAuth(req);
  if (hasRole(auth, min)) return null;
  return Response.json(
    { error: { code: auth ? "forbidden" : "unauthorized", message: "Nicht berechtigt." } },
    { status: auth ? 403 : 401 },
  );
}

/** Endpunkte, die externe KI/Netzwerk/Hardware brauchen und (noch) nicht migriert sind → sauberes 501. */
export function notMigrated(feature: string): Response {
  return Response.json(
    { error: { code: "not_migrated", message: `${feature} ist in dieser Version (noch) nicht verfügbar.` } },
    { status: 501 },
  );
}
