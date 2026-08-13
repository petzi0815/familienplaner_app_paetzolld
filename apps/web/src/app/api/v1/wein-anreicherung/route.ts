import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, notFound, fail, ok } from "@/server/http/respond";
import { hasOpenAI } from "@/server/elisbooks/openai";
import type { GetraenkeArt } from "@/server/wein/enrich";
import { verarbeiteOffene } from "@/server/wein/anreicherung";

// Warteschlange der Hintergrund-Erkennung (`weine.ki_status`).
//
// POST = abarbeiten: ohne `id` die offenen Zeilen der Reihe nach, mit `id` genau diese eine — auch
// wenn sie ihre drei automatischen Anläufe schon verbraucht hat. Genau das ist der Knopf „Erneut
// versuchen" bzw. „Erneut erkennen lassen": von Hand ausgelöst darf ein hartnäckiges Etikett noch
// einen Versuch bekommen, automatisch nicht (sonst verbrennt es jede Nacht Geld).
//
// GET = nur Zählerstand. Die App fragt ihn regelmäßig ab, solange die Warteschlange nicht leer ist —
// deshalb liefert er BEWUSST keine Einträge: eine Liste alle 10 Sekunden über die Leitung zu
// schicken, nur um „Queue (3)" an ein Segment zu schreiben, wäre Verschwendung.
//
// Der Sammellauf schickt bis zu 10 Flaschen durch die volle KI-Kette → Minuten (maxDuration).
// Eigenes Top-Level-Segment mit Bindestrich, damit es NICHT die generische [domain]-Route verdeckt.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 300;

/** Art-Filter (`?art=`): ungültige Werte werden still ignoriert und der Zähler umfasst dann beide Arten. */
function leseArt(v: string | null): GetraenkeArt | undefined {
  const s = (v ?? "").trim().toLowerCase();
  return s === "wein" || s === "spirituose" ? s : undefined;
}

export async function GET(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "readonly")) return auth ? forbidden() : unauthorized();

  const art = leseArt(new URL(req.url).searchParams.get("art"));
  // Nur die drei Zustände, die Arbeit bedeuten — 'fertig' ist der Normalfall (auch für Bestand und
  // von Hand angelegte Flaschen) und hat in einem Warteschlangen-Zähler nichts zu suchen.
  const zaehler: Record<string, number> = { offen: 0, laeuft: 0, fehler: 0 };
  try {
    const rows = getDb().prepare(
      "SELECT ki_status, COUNT(*) AS n FROM weine WHERE ki_status IN ('offen','laeuft','fehler') " +
      "AND (:art IS NULL OR art = :art) GROUP BY ki_status",
    ).all({ art: art ?? null }) as { ki_status: string; n: number }[];
    for (const r of rows) if (r.ki_status in zaehler) zaehler[r.ki_status] = Number(r.n) || 0;
  } catch (e) {
    // Fehlt die Spalte (Migration 0024 noch nicht angewandt), ist die Antwort „nichts in Arbeit"
    // richtig — und ein 500er auf einem Zähler, der alle 10 Sekunden abgefragt wird, wäre das
    // schlechteste aller Ergebnisse.
    return ok({ ...zaehler, ...(art ? { art } : {}), hinweis: "Warteschlange nicht verfügbar: " + String((e as Error)?.message ?? e).slice(0, 120) });
  }

  return ok({ ...zaehler, ...(art ? { art } : {}) });
}

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  // Wie bei `/wein-scan`: ohne Schlüssel gibt es keine Erkennung. Hier hat das zusätzlich einen
  // handfesten Grund — ein Lauf ohne Schlüssel würde nur `ki_versuche` hochzählen und die Flaschen
  // nach drei Anläufen aus der automatischen Wiederholung nehmen. Lieber gar nicht anfassen.
  if (!hasOpenAI()) return fail("not_configured", "Die Erkennung benötigt OPENAI_API_KEY im Backend (Coolify).", 501);

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { body = {}; } // leerer Body = „alles Offene"

  const hatId = body.id !== undefined && body.id !== null && body.id !== "";
  const nurId = hatId ? Number(body.id) : undefined;
  if (hatId && (!Number.isInteger(nurId) || (nurId as number) <= 0)) return fail("bad_id", "Feld 'id' muss eine Zahl sein.", 400);

  const db = getDb();
  if (nurId !== undefined && !db.prepare("SELECT 1 FROM weine WHERE id=?").get(nurId)) return notFound("Wein");

  let ergebnis: Awaited<ReturnType<typeof verarbeiteOffene>>;
  try {
    ergebnis = await verarbeiteOffene(db, { nurId });
  } catch (e) {
    return fail("anreicherung_error", "Anreicherung fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e).slice(0, 200) });
  }

  try {
    db.prepare("INSERT INTO event_log (actor, action, domain, detail) VALUES (?,?,?,?)")
      .run(auth.actor, "wein_anreicherung", "wein",
        JSON.stringify({ id: nurId ?? null, verarbeitet: ergebnis.verarbeitet, fertig: ergebnis.fertig, fehler: ergebnis.fehler }));
  } catch { /* Audit best effort */ }

  // Sammellauf ohne ein einziges Ergebnis: entweder ist nichts offen oder es läuft schon einer
  // (In-Flight-Guard im Modul). Für die App ist der Klartext hilfreicher als eine leere Liste.
  const hinweise = nurId === undefined && ergebnis.verarbeitet === 0
    ? ["Nichts verarbeitet — die Warteschlange ist leer, oder ein Lauf ist bereits unterwegs."]
    : [];

  return ok({ ...ergebnis, ...(hinweise.length ? { hinweise } : {}) });
}
