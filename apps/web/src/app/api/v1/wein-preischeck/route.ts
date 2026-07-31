import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, notFound, fail, ok } from "@/server/http/respond";
import { runPreischeck } from "@/server/wein/pricecheck";

// Preisüberwachung manuell anstoßen — für EINEN Wein (`wein_id`) oder für die beobachteten Weine
// (`alle: true`, dieselbe Logik wie der nächtliche Job `wein-preischeck`).
// `dry_run: true` recherchiert und rechnet, schreibt aber weder Preise noch Bestpreis in die DB.
//
// Antwort: `treffer` = ein Ergebnis JE GEPRÜFTEM WEIN (mit Angeboten, bestem Preis und Rabatt),
// `rabatte` = die Teilmenge davon, die die eingestellte Rabattschwelle erreicht. Der Push passiert
// bewusst nur im Job — ein manuelles Prüfen soll nicht die ganze Familie anpiepen.
//
// Die Recherche läuft je Wein über Perplexity + OpenAI → ein Sammellauf dauert Minuten (maxDuration).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 300;

const wahr = (v: unknown): boolean => v === true || v === 1 || v === "1" || v === "true";

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { body = {}; } // leerer Body erlaubt

  const alle = wahr(body.alle);
  const dryRun = wahr(body.dry_run);
  const hatId = body.wein_id !== undefined && body.wein_id !== null && body.wein_id !== "";
  const weinId = hatId ? Number(body.wein_id) : undefined;

  if (!alle && !hatId) return fail("no_target", "Feld 'wein_id' oder 'alle: true' erforderlich.", 400);
  if (hatId && (!Number.isInteger(weinId) || (weinId as number) <= 0)) return fail("bad_id", "Feld 'wein_id' muss eine Zahl sein.", 400);

  const db = getDb();
  if (weinId !== undefined && !db.prepare("SELECT 1 FROM weine WHERE id=?").get(weinId)) return notFound("Wein");

  let ergebnis: Awaited<ReturnType<typeof runPreischeck>>;
  try {
    ergebnis = await runPreischeck(db, { alle, weinId, dryRun });
  } catch (e) {
    return fail("preischeck_error", "Preisprüfung fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e).slice(0, 200) });
  }

  try {
    db.prepare("INSERT INTO event_log (actor, action, domain, detail) VALUES (?,?,?,?)")
      .run(auth.actor, "wein_preischeck", "wein",
        JSON.stringify({ wein_id: weinId ?? null, alle, dry_run: dryRun, geprueft: ergebnis.geprueft, rabatte: ergebnis.rabatte.length }));
  } catch { /* Audit best effort */ }

  // Sammellauf ohne ein einziges Ergebnis: entweder war nichts fällig oder es läuft schon einer
  // (In-Flight-Guard im Modul). Für die App ist der Klartext hilfreicher als eine leere Liste.
  const hinweise = !weinId && ergebnis.geprueft === 0
    ? ["Kein Wein geprüft — es ist gerade keiner fällig, oder eine Sammelprüfung läuft bereits."]
    : [];

  return ok({
    geprueft: ergebnis.geprueft,
    treffer: ergebnis.ergebnisse,
    rabatte: ergebnis.rabatte,
    dry_run: dryRun,
    ...(hinweise.length ? { hinweise } : {}),
  });
}
