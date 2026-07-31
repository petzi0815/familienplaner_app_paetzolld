import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";
import { hasOpenAI } from "@/server/elisbooks/openai";
import { enrichWine, type WeinVorschlag } from "@/server/wein/enrich";

// Wein-Erfassung, Schritt 1: Etikettenfoto (data-URL), EAN oder Freitext → angereicherter Vorschlag.
// Die KI-Kette (OpenAI Vision → Perplexity-Recherche → OpenAI-Normalisierung) steckt komplett in
// server/wein/enrich.ts; diese Route macht Auth, Eingabeprüfung, Dublettenerkennung und Antwort-Form.
// Speichert NICHTS — die App zeigt den Vorschlag, der Nutzer legt danach über das generische CRUD an.
// Token-gated: ohne OPENAI_API_KEY → 501 (ohne PERPLEXITY_API_KEY läuft es weiter, nur ohne
// Live-Preise/Recherche — das erklärt `hinweise` im Klartext).
// Eigenes Top-Level-Segment mit Bindestrich, damit es NICHT die generische [domain]-Route verdeckt.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 120;

interface DublettenTreffer { id: number; name: string; weingut: string; jahrgang: number | null }

/** Jahrgang als Zahl oder NULL (jahrgangslose Weine: viele Sekte/Champagner). */
function toJahrgang(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) && n > 1000 ? Math.trunc(n) : null;
}

/** „Weingut Name Jahrgang" für die Anzeige der Dublette in der App. */
function titel(t: DublettenTreffer): string {
  return [t.weingut, t.name, t.jahrgang ? String(t.jahrgang) : ""].map((s) => String(s ?? "").trim()).filter(Boolean).join(" ");
}

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  if (!hasOpenAI()) return fail("not_configured", "Die Weinerkennung benötigt OPENAI_API_KEY im Backend (Coolify).", 501);

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const image = String(body.image ?? "").trim();
  const ean = String(body.ean ?? "").trim();
  const text = String(body.text ?? "").trim();
  if (image && !image.startsWith("data:")) return fail("bad_image", "Feld 'image' muss eine data-URL sein.", 400);
  if (!image && !ean && !text) return fail("no_input", "Mindestens eines der Felder 'image', 'ean' oder 'text' ist erforderlich.", 400);

  let roh: WeinVorschlag;
  try {
    roh = await enrichWine({
      image: image || undefined,
      ean: ean || undefined,
      text: text || undefined,
    });
  } catch (e) {
    return fail("enrich_error", "Weinerkennung fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e).slice(0, 200) });
  }

  // `felder` heißt nach außen `vorschlag` (so steht es im API-Vertrag und so liest es die App).
  const vorschlag: Record<string, unknown> = { ...(roh.felder ?? {}) };
  if (ean && !String(vorschlag.ean ?? "").trim()) vorschlag.ean = ean; // gescannte EAN gehört in den Vorschlag
  const preise = roh.preise ?? [];
  const quellen = roh.quellen ?? [];
  const hinweise = [...(roh.hinweise ?? [])];
  const confidence = roh.confidence || "niedrig";

  let dublette: { id: number; titel: string; bewertungen: unknown[] } | null = null;
  try {
    const db = getDb();
    const name = String(vorschlag.name ?? "").trim();
    const weingut = String(vorschlag.weingut ?? "").trim();
    const jahrgang = toJahrgang(vorschlag.jahrgang);
    const eanSuche = String(vorschlag.ean ?? "").trim();

    if (name || eanSuche) {
      // Dublette = derselbe Jahrgang UND ähnlicher Name/Weingut (case-/whitespace-unabhängig),
      // ODER schlicht dieselbe EAN. `jahrgang IS :jahrgang` ist NULL-sicher (jahrgangslose Weine).
      const treffer = db.prepare(
        "SELECT id, name, weingut, jahrgang FROM weine " +
        "WHERE (:ean <> '' AND TRIM(COALESCE(ean,'')) = :ean) " +
        "   OR (:name <> '' AND jahrgang IS :jahrgang AND ( " +
        "         (LOWER(TRIM(name)) = LOWER(:name) AND (:weingut = '' OR TRIM(weingut) = '' OR LOWER(TRIM(weingut)) = LOWER(:weingut))) " +
        "      OR (:weingut <> '' AND LOWER(TRIM(weingut)) = LOWER(:weingut) " +
        "          AND (INSTR(LOWER(TRIM(name)), LOWER(:name)) > 0 OR INSTR(LOWER(:name), LOWER(TRIM(name))) > 0)) " +
        "   )) " +
        // Bester Treffer zuerst: EAN schlägt Namensgleichheit, Namensgleichheit schlägt Teiltreffer.
        "ORDER BY CASE WHEN :ean <> '' AND TRIM(COALESCE(ean,'')) = :ean THEN 0 " +
        "              WHEN LOWER(TRIM(name)) = LOWER(:name) THEN 1 ELSE 2 END, id DESC LIMIT 1",
      ).get({ ean: eanSuche, name, weingut, jahrgang }) as DublettenTreffer | undefined;

      if (treffer) {
        const bewertungen = db.prepare(
          "SELECT owner, sterne, kommentar FROM wein_bewertungen WHERE wein_id=? ORDER BY owner",
        ).all(treffer.id);
        dublette = { id: treffer.id, titel: titel(treffer), bewertungen };
        hinweise.push(`Dieser Wein ist vermutlich schon erfasst: „${titel(treffer)}" (ID ${treffer.id}).`);
      }
    }

    db.prepare("INSERT INTO event_log (actor, action, domain, detail) VALUES (?,?,?,?)")
      .run(auth.actor, "wein_scan", "wein", JSON.stringify({ quelle: image ? "foto" : ean ? "ean" : "text", confidence, dublette: dublette?.id ?? null }));
  } catch (e) {
    // Dublettenprüfung/Audit dürfen den Vorschlag nicht kaputtmachen — nur als Hinweis melden.
    hinweise.push("Dublettenprüfung nicht möglich: " + String((e as Error)?.message ?? e).slice(0, 120));
  }

  return ok({ vorschlag, preise, quellen, confidence, hinweise, dublette });
}
