import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import type BetterSqlite3 from "better-sqlite3";
import { config } from "@/server/config";
import { log } from "@/server/observability/logger";
import { randomToken } from "@/server/util/hash";
import { resourceByKey } from "@/server/domains/registry";
import { reindexRow } from "@/server/db/fts";
import { hasOpenAI } from "@/server/elisbooks/openai";
import { enrichWine, type GetraenkeArt, type WeinPreis } from "@/server/wein/enrich";

// Hintergrund-Anreicherung für „Wein & Spirituosen": die Flasche steht ab dem Auslösen im Inventar,
// die KI-Kette läuft danach.
//
// WARUM ÜBERHAUPT ENTKOPPELT: die Kette aus `enrich.ts` braucht je Flasche bis zu drei Außenkontakte
// (Vision, Perplexity, Normalisierung) und damit realistisch eine halbe bis anderthalb Minuten. Wer
// im Laden oder vor dem Regal steht, kann nicht nach jeder Flasche so lange warten — also wird
// erfasst und weggestellt, und die Erkennung holt auf. Der Datensatz IST der Warteschlangen-Eintrag
// (`ki_status` auf `weine`, Migration 0024): es kann keinen Queue-Eintrag ohne Flasche und keine
// Flasche ohne Queue-Eintrag geben. Das ist die Zusage „nichts geht verloren".
//
// DREI EINSTIEGE, EINE MECHANIK:
//   einreihen        — legt die Zeile SOFORT an und wartet auf nichts (Route `wein-erfassen`).
//   verarbeiteEinen  — eine Zeile durch die KI-Kette schicken (fire-and-forget bzw. „Erneut versuchen").
//   verarbeiteOffene — Sammellauf mit Stale-Rückholung (Job `wein-anreicherung`, alle 5 Minuten).
//
// KEINE Funktion dieses Moduls wirft: Route und Job müssen immer eine lesbare Antwort bekommen, und
// ein Fehlschlag darf im Sammellauf nie die Flaschen dahinter mitreißen. Gescheitertes landet als
// Klartext in `ki_fehler` und ist in der App sichtbar und wiederholbar.

/**
 * Ergebnis von `einreihen`. `id: 0` heißt: nichts angelegt — warum, steht in `fehler`.
 * `hinweis` ist das Gegenstück für den halben Erfolg (Zeile steht, aber z. B. ohne Foto): der
 * Aufrufer soll das anzeigen, ohne die Erfassung als gescheitert zu behandeln.
 */
export interface EinreihenErgebnis {
  id: number;
  art: GetraenkeArt;
  ki_status: string;
  fehler?: string;
  hinweis?: string;
}

/** Ergebnis einer einzelnen Verarbeitung. */
export interface VerarbeitungErgebnis {
  ok: boolean;
  fehler?: string;
}

/** Eine Zeile im Protokoll eines Sammellaufs. */
export interface LaufEintrag {
  id: number;
  titel: string;
  ok: boolean;
  fehler?: string;
}

export interface AnreicherungsLauf {
  verarbeitet: number;
  fertig: number;
  fehler: number;
  eintraege: LaufEintrag[];
  /**
   * Klartext-Grund, wenn der Lauf gar nicht erst stattgefunden hat (fehlender Schlüssel, bereits
   * laufender Sammellauf). `verarbeitet: 0` ohne `hinweis` heißt schlicht: es war nichts fällig.
   */
  hinweis?: string;
}

// ── Stellschrauben ───────────────────────────────────────────────────────────

/**
 * Zeilen auf 'laeuft', die länger als das hier nicht angefasst wurden, gelten als abgestürzt und
 * werden wieder auf 'offen' gesetzt. DAS ist die wichtigste Eigenschaft der Queue: fällt der
 * Container mitten in einem Lauf aus (Deploy, OOM), stünde die Flasche sonst für immer auf „läuft"
 * und würde von keinem Lauf mehr aufgegriffen — genau der Verlust, den die Queue verhindern soll.
 * 15 Minuten liegen deutlich über dem, was eine Kette selbst im schlimmsten Fall braucht
 * (2 × 90 s OpenAI + 45 s Perplexity), also kann kein noch laufender Versuch versehentlich
 * verdoppelt werden.
 */
const STALE_MINUTEN = 15;

/**
 * Nach einem Fehlschlag wartet die Zeile, bevor der Sammellauf sie erneut anfasst. Ohne Backoff
 * würde der 5-Minuten-Job dieselbe unlesbare Flasche binnen einer Viertelstunde dreimal durch eine
 * kostenpflichtige Kette schicken; mit Backoff verteilen sich die drei Anläufe über anderthalb
 * Stunden und erwischen auch eine kurze Störung beim Anbieter.
 */
const FEHLER_BACKOFF_MINUTEN = 30;

/**
 * So oft versucht es der Sammellauf von sich aus. Danach wartet die Zeile auf einen ausdrücklichen
 * Anstoß aus der App — sonst verbrennt ein dauerhaft unlesbares Etikett jede Nacht Geld, ohne dass
 * sich am Ergebnis etwas ändert.
 */
const MAX_VERSUCHE = 3;

/**
 * Deckel je Sammellauf. Jede Flasche kostet bis zu drei Anbieter-Aufrufe; bei einer Serie von
 * 40 Fotos soll nicht ein einziger Lauf 120 Aufrufe auslösen, sondern der 5-Minuten-Job sie über
 * eine gute halbe Stunde abarbeiten.
 */
const MAX_PRO_LAUF = 10;

/** Kurze Pause zwischen zwei Flaschen — sanft gegenüber OpenAI und Perplexity (Rate-Limits). */
const PAUSE_MS = 400;

/** Media-Bereich der Etikettenfotos (identisch zur Registry-Bild-Spalte `foto_key`). */
const MEDIA_AREA = "wein";

const MIME_EXT: Record<string, string> = {
  "image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png",
  "image/webp": ".webp", "image/heic": ".heic",
};
const EXT_MIME: Record<string, string> = {
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
  ".webp": "image/webp", ".heic": "image/heic",
};

const STANDORTE = new Set(["zuhause", "buero"]);

/**
 * Spalten, die die KI schreiben darf — bewusst eine WEISSLISTE und keine Ausschlussliste: kommt
 * morgen eine neue Nutzer-Spalte dazu, ist sie hier automatisch geschützt, während eine
 * Ausschlussliste sie stillschweigend zum Überschreiben freigäbe.
 *
 * NICHT enthalten und damit unantastbar: `bestand`, `standort`, `lagerort`, `notizen`, `foto_key`,
 * `angebrochen_at`, `fuellstand_prozent`, `gekauft_preis`, `gekauft_bei`, `preis_beobachten`. Der
 * Grund ist der Zeitversatz: während die Kette läuft, hat der Nutzer die Flasche längst eingeräumt,
 * angebrochen oder den Kaufpreis nachgetragen — eine Minute später käme die KI und würde es wieder
 * überschreiben. (`notizen` fällt deshalb auch dann weg, wenn `enrichWine` mangels Normalisierung
 * den abgelesenen Etikett-Text dort ablegen würde.)
 *
 * `bester_preis*` fehlt bewusst ebenfalls: die stehen unten aus den GEPRÜFTEN Angeboten, nicht aus
 * einem frei erzählten Feld.
 */
const KI_SPALTEN = [
  // beide Arten
  "name", "weingut", "art", "land", "region", "alkohol", "flaschengroesse_ml", "ean",
  "aromen", "serviertemperatur", "bio", "vegan", "beschreibung", "auszeichnungen",
  "speiseempfehlung", "referenzpreis", "quelle", "ki_confidence",
  // nur Wein
  "jahrgang", "typ", "rebsorten", "lage", "geschmacksrichtung",
  "suesse", "saeure", "tannin", "koerper", "trinkfenster_von", "trinkfenster_bis",
  // nur Spirituose
  "kategorie", "stil", "alter_jahre", "fass", "abgefuellt_jahr", "trinkempfehlung", "cocktails",
] as const;

// ── Kleine Helfer ────────────────────────────────────────────────────────────

const kurz = (e: unknown): string => String((e as Error)?.message ?? e).slice(0, 300);

const pause = (ms: number) => new Promise((res) => setTimeout(res, ms));

/** Getränkeart aus einem beliebigen Wert lesen; ungültige Angaben werden still verworfen. */
function leseArt(v: unknown): GetraenkeArt | null {
  const s = String(v ?? "").trim().toLowerCase();
  return s === "wein" || s === "spirituose" ? s : null;
}

/**
 * Zeile defensiv auf eine Art abbilden: alles, was nicht ausdrücklich 'spirituose' heißt, gilt als
 * Wein — genauso wie in `pricecheck.ts`, damit sich Zeilen aus der Zeit vor Migration 0022 überall
 * gleich verhalten.
 */
const zuArt = (v: unknown): GetraenkeArt => (v === "spirituose" ? "spirituose" : "wein");

/** Anzeigename für Protokolle. Nie leer und nie „undefined" — vor der Erkennung gibt es keinen Namen. */
function titelVon(row: { id: number; name?: string | null; weingut?: string | null }): string {
  const t = [row.weingut?.trim(), row.name?.trim()].filter(Boolean).join(" ").trim();
  return t || `Neue Flasche #${row.id}`;
}

/** Sucheintrag der Zeile aktualisieren (optional — ohne FTS läuft alles unverändert weiter). */
function neuIndizieren(db: BetterSqlite3.Database, id: number): void {
  const res = resourceByKey("weine");
  if (res) reindexRow(db, res, id);
}

/**
 * Etikettenfoto (data-URL) nach `media/wein/` schreiben — bewusst mit derselben Namensbildung und
 * demselben `media_assets`-Eintrag wie `POST /api/v1/media/upload`. Ein zweiter Weg mit eigenen
 * Regeln würde beim Aufräumen, beim Vorschau-Cache und beim Ausliefern sofort auseinanderlaufen.
 */
function speichereBild(
  db: BetterSqlite3.Database,
  dataUrl: string,
): { key: string | null; fehler: string | null } {
  const m = /^data:([^;,]+);base64,([\s\S]+)$/.exec(dataUrl.trim());
  if (!m) return { key: null, fehler: "Das Bild muss als data-URL mit base64-Inhalt kommen." };
  const mime = m[1].toLowerCase();
  let buf: Buffer;
  try { buf = Buffer.from(m[2], "base64"); } catch { return { key: null, fehler: "Die Bilddaten sind kein gültiges base64." }; }
  if (!buf.length) return { key: null, fehler: "Das Bild ist leer." };

  const ext = MIME_EXT[mime] ?? ".jpg";
  const name = `up_${Date.now()}_${randomToken(6)}${ext}`;
  const dir = path.join(config.mediaDir, MEDIA_AREA);
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, name), buf);
  } catch (e) {
    return { key: null, fehler: `Das Foto konnte nicht gespeichert werden (${kurz(e)}).` };
  }

  const key = `${MEDIA_AREA}/${name}`;
  try {
    db.prepare(
      "INSERT OR IGNORE INTO media_assets (bereich,storage_key,original_name,mime,bytes,sha256) VALUES (?,?,?,?,?,?)",
    ).run(MEDIA_AREA, key, name, mime, buf.length, crypto.createHash("sha256").update(buf).digest("hex"));
  } catch { /* Asset-Register ist Buchhaltung — die Datei liegt, das Foto funktioniert auch ohne */ }
  return { key, fehler: null };
}

/**
 * Gespeichertes Etikett wieder als data-URL lesen — das ist die Form, die `enrichWine` erwartet.
 * `null`, wenn die Datei fehlt oder der Schlüssel nicht sauber ist; der Aufrufer arbeitet dann mit
 * dem, was sonst noch da ist (EAN), statt zu scheitern.
 */
function bildAlsDataUrl(fotoKey: string | null | undefined): string | null {
  const key = String(fotoKey ?? "").trim();
  if (!key || !/^[a-zA-Z0-9._/-]+$/.test(key)) return null;
  const root = path.resolve(config.mediaDir);
  const datei = path.resolve(root, key);
  if (!datei.startsWith(root + path.sep)) return null; // Path-Traversal-Schutz wie in der Media-Route
  try {
    const buf = fs.readFileSync(datei);
    if (!buf.length) return null;
    const mime = EXT_MIME[path.extname(datei).toLowerCase()] ?? "image/jpeg";
    return `data:${mime};base64,${buf.toString("base64")}`;
  } catch {
    return null;
  }
}

// ── 1) Einreihen ─────────────────────────────────────────────────────────────

export interface EinreihenEingabe {
  /** Etikettenfoto als data-URL (`data:image/jpeg;base64,…`). */
  image?: string;
  ean?: string;
  /** Hinweis des Umschalters in der App — die Erkennung darf ihn später überstimmen. */
  art?: string;
  bestand?: number;
  standort?: string;
  lagerort?: string;
}

/**
 * Flasche SOFORT ins Inventar legen und für die Anreicherung vormerken. Wartet auf nichts — weder
 * auf die KI noch auf einen Netzabruf; wer im Serienmodus fotografiert, darf beim nächsten Auslösen
 * nicht auf die vorige Flasche warten.
 *
 * `bestand` startet bei 1: wer inventarisiert, hat die Flasche in der Hand. 0 wäre der falsche
 * Startwert — die Flasche verschwände sofort aus dem Keller, obwohl sie gerade erfasst wurde.
 */
export function einreihen(db: BetterSqlite3.Database, eingabe: EinreihenEingabe): EinreihenErgebnis {
  const art = leseArt(eingabe.art) ?? "wein";
  try {
    const ean = String(eingabe.ean ?? "").replace(/[^0-9]/g, "").slice(0, 20);

    let fotoKey: string | null = null;
    let bildFehler: string | null = null;
    if (eingabe.image) {
      const gespeichert = speichereBild(db, eingabe.image);
      if (gespeichert.key) fotoKey = gespeichert.key;
      else bildFehler = gespeichert.fehler;
    }
    if (!fotoKey && !ean && !bildFehler) {
      return { id: 0, art, ki_status: "offen", fehler: "Ohne Foto und ohne Barcode gibt es nichts zu erfassen." };
    }

    const bestandRoh = Number(eingabe.bestand);
    const bestand = Number.isFinite(bestandRoh) && bestandRoh >= 0 ? Math.trunc(bestandRoh) : 1;
    const standortRoh = String(eingabe.standort ?? "").trim().toLowerCase();
    const standort = STANDORTE.has(standortRoh) ? standortRoh : "zuhause";
    const lagerort = String(eingabe.lagerort ?? "").trim().slice(0, 200) || null;
    const quelle = fotoKey ? "foto" : ean ? "ean" : "manuell";

    // Ohne Foto UND ohne EAN kann die Kette nichts holen — dann steht die Zeile gleich als Fehler in
    // der Queue statt scheinbar zu laufen. Sie bleibt sichtbar, ausfüllbar und verwerfbar; verloren
    // geht auch dieser Fall nicht.
    const kiStatus = bildFehler && !ean ? "fehler" : "offen";
    const kiFehler = kiStatus === "fehler" ? String(bildFehler).slice(0, 300) : null;

    const info = db.prepare(
      "INSERT INTO weine (name, weingut, art, ean, foto_key, quelle, bestand, standort, lagerort, " +
      "ki_status, ki_fehler, ki_queued_at) " +
      "VALUES ('', '', ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))",
    ).run(art, ean || null, fotoKey, quelle, bestand, standort, lagerort, kiStatus, kiFehler);

    const id = Number(info.lastInsertRowid);
    neuIndizieren(db, id);
    log.info("Flasche eingereiht", { id, art, quelle, ki_status: kiStatus });
    // Die Zeile STEHT — ein misslungenes Foto ist deshalb ein Hinweis, kein Fehler: die Erfassung
    // hat stattgefunden, sie ist nur unvollständig.
    return {
      id,
      art,
      ki_status: kiStatus,
      ...(bildFehler ? { hinweis: bildFehler } : {}),
    };
  } catch (e) {
    log.error("Flasche konnte nicht eingereiht werden", { error: kurz(e) });
    return { id: 0, art, ki_status: "offen", fehler: `Die Flasche konnte nicht angelegt werden (${kurz(e)}).` };
  }
}

// ── 2) Eine Zeile verarbeiten ────────────────────────────────────────────────

interface QueueRow {
  id: number;
  name: string | null;
  weingut: string | null;
  jahrgang: number | null;
  art: string | null;
  ean: string | null;
  foto_key: string | null;
  ki_versuche: number | null;
}

interface DublettenTreffer { id: number }

/**
 * Nur die Queue-Spalten auf Fehler setzen — bewusst OHNE `updated_at`: ein misslungener
 * Erkennungsversuch ist keine Änderung an der Flasche und soll die Sortierung „zuletzt geändert"
 * nicht durcheinanderbringen.
 */
function markiereFehler(db: BetterSqlite3.Database, id: number, grund: string): void {
  try {
    db.prepare(
      "UPDATE weine SET ki_status='fehler', ki_fehler=?, ki_versuche=COALESCE(ki_versuche,0)+1, " +
      "ki_queued_at=datetime('now') WHERE id=?",
    ).run(grund.slice(0, 300), id);
  } catch (e) {
    log.error("Fehlerzustand der Anreicherung konnte nicht gespeichert werden", { id, error: kurz(e) });
  }
}

/**
 * In-Flight-Guard je Zeile: die Route stößt fire-and-forget an, der 5-Minuten-Job läuft parallel und
 * der Nutzer kann „Erneut versuchen" drücken. Der Zustand 'laeuft' in der Datenbank hält den
 * Sammellauf schon fern; dieses Set fängt zusätzlich den Fall ab, dass zwei Anstöße auf dieselbe
 * Zeile treffen, bevor der Zustandswechsel überhaupt gelesen wurde — sonst zahlt man dieselbe
 * Erkennung zweimal.
 */
const inArbeit = new Set<number>();

/**
 * Eine Flasche durch die KI-Kette schicken und das Ergebnis in die Zeile schreiben.
 * Wirft NIE — ein Fehlschlag landet als Klartext in `ki_fehler` und ist in der App wiederholbar.
 */
export async function verarbeiteEinen(db: BetterSqlite3.Database, id: number): Promise<VerarbeitungErgebnis> {
  if (inArbeit.has(id)) return { ok: false, fehler: "Diese Flasche wird gerade schon erkannt." };

  let row: QueueRow | undefined;
  try {
    row = db.prepare(
      "SELECT id, name, weingut, jahrgang, art, ean, foto_key, ki_versuche FROM weine WHERE id=?",
    ).get(id) as QueueRow | undefined;
  } catch (e) {
    return { ok: false, fehler: `Die Flasche konnte nicht gelesen werden (${kurz(e)}).` };
  }
  if (!row) return { ok: false, fehler: "Eintrag nicht gefunden." };

  // Ohne Schlüssel gäbe es gar keinen Versuch: die Zeile bleibt unverändert stehen (kein 'fehler',
  // kein verbrauchter Anlauf) und wird abgearbeitet, sobald der Schlüssel in Coolify nachgetragen
  // ist — genauso wie der Preischeck es hält.
  if (!hasOpenAI()) {
    return { ok: false, fehler: "Die Erkennung benötigt OPENAI_API_KEY im Backend (Coolify)." };
  }

  const art = zuArt(row.art);
  const ean = String(row.ean ?? "").replace(/[^0-9]/g, "");
  const bild = bildAlsDataUrl(row.foto_key);
  if (!bild && !ean) {
    markiereFehler(db, id, "Weder Etikettenfoto noch Barcode vorhanden — bitte von Hand ausfüllen.");
    return { ok: false, fehler: "Weder Etikettenfoto noch Barcode vorhanden." };
  }

  inArbeit.add(id);
  try {
    // `ki_queued_at` wandert mit: daran hängt die Stale-Rückholung. Eine Zeile, die hier hängen
    // bleibt (Container weg), ist so nach 15 Minuten automatisch wieder 'offen'.
    try {
      db.prepare("UPDATE weine SET ki_status='laeuft', ki_queued_at=datetime('now') WHERE id=?").run(id);
    } catch (e) {
      return { ok: false, fehler: `Der Zustand konnte nicht gesetzt werden (${kurz(e)}).` };
    }

    let felder: Record<string, unknown> = {};
    let preise: WeinPreis[] = [];
    let hinweise: string[] = [];
    try {
      const roh = await enrichWine({ image: bild ?? undefined, ean: ean || undefined, art });
      felder = roh.felder ?? {};
      preise = roh.preise ?? [];
      hinweise = roh.hinweise ?? [];
    } catch (e) {
      // `enrichWine` degradiert eigentlich selbst — das hier fängt nur den Totalausfall ab.
      const grund = `Erkennung fehlgeschlagen (${kurz(e)}).`;
      markiereFehler(db, id, grund);
      return { ok: false, fehler: grund };
    }

    // ── Nur Weissliste, und nur gefüllte Werte ──
    const sets: string[] = [];
    const werte: unknown[] = [];
    for (const spalte of KI_SPALTEN) {
      const v = (felder as Record<string, unknown>)[spalte];
      if (v === undefined || v === null) continue;
      sets.push(`"${spalte}"=?`);
      werte.push(v);
    }

    // ── Angebote: Historie + bester Preis an die Zeile ──
    // Anders als beim interaktiven Scan gibt es hier keinen zweiten Schritt, in dem der Nutzer den
    // Vorschlag bestätigt — was die Recherche gefunden hat, muss also gleich hier landen, sonst ist
    // es weg.
    const bester = preise.length ? preise.reduce((a, b) => (b.preis < a.preis ? b : a)) : null;
    if (bester) {
      sets.push('"bester_preis"=?', '"bester_preis_haendler"=?', '"bester_preis_url"=?');
      werte.push(bester.preis, bester.haendler, bester.url ?? null);
      // Die (bezahlte) Preisrecherche hat gerade stattgefunden → Prüfmarke setzen, sonst stünde die
      // frisch erfasste Flasche in der kommenden Nacht sofort wieder ganz vorn im Preischeck.
      sets.push("\"preis_geprueft_at\"=datetime('now')");
    }

    // ── Dublette: nur MARKIEREN, niemals zusammenführen ──
    // Zusammenführen wäre unumkehrbar und träfe genau die Fälle, in denen zwei Flaschen bewusst
    // getrennt stehen (anderer Jahrgang, andere Größe, Geschenk). Der Nutzer entscheidet.
    const dublette = sucheDublette(db, {
      id,
      art: leseArt(felder.art) ?? art,
      name: String(felder.name ?? row.name ?? "").trim(),
      weingut: String(felder.weingut ?? row.weingut ?? "").trim(),
      jahrgang: zuJahrgang(felder.jahrgang ?? row.jahrgang),
      ean: String(felder.ean ?? ean ?? "").trim(),
    });
    if (dublette) {
      sets.push('"dublette_von"=?');
      werte.push(dublette);
    }

    // ── Zustand ──
    // Ohne Namen UND ohne Erzeuger ist die Erkennung fachlich gescheitert, auch wenn technisch alles
    // lief: die Zeile bliebe sonst als „Wird erkannt …" ohne Inhalt im Bestand stehen und wäre aus
    // der Queue verschwunden, wo der Nutzer sie hätte ausfüllen können.
    const nameNeu = String(felder.name ?? row.name ?? "").trim();
    const weingutNeu = String(felder.weingut ?? row.weingut ?? "").trim();
    const erkannt = !!(nameNeu || weingutNeu);
    const grund = erkannt
      ? null
      : (hinweise.join(" ").trim()
        || "Weder Etikett noch Barcode ergaben einen Namen — bitte von Hand ausfüllen.").slice(0, 300);

    if (erkannt) {
      // `ki_versuche` zurück auf 0: die Zahl zählt AUFEINANDERFOLGENDE Fehlschläge, denn nur so
      // bleibt die Grenze „automatisch höchstens dreimal" auch nach einer späteren Neu-Erkennung
      // wieder brauchbar.
      // `updated_at` nur hier — ein Fehlversuch ist keine Änderung an der Flasche und soll die
      // Sortierung „zuletzt geändert" nicht anfassen (gleiche Regel wie in `markiereFehler`).
      sets.push("\"ki_status\"='fertig'", '"ki_fehler"=NULL', '"ki_versuche"=0', "\"updated_at\"=datetime('now')");
    } else {
      sets.push("\"ki_status\"='fehler'", '"ki_fehler"=?', '"ki_versuche"=COALESCE(ki_versuche,0)+1');
      werte.push(grund);
    }
    sets.push("\"ki_queued_at\"=datetime('now')");

    const insPreis = db.prepare(
      "INSERT INTO wein_preise (wein_id, preis, haendler, url, quelle) VALUES (?,?,?,?,'perplexity')",
    );
    const updZeile = db.prepare(`UPDATE weine SET ${sets.join(", ")} WHERE id=?`);
    const schreiben = db.transaction(() => {
      for (const p of preise) insPreis.run(id, p.preis, p.haendler, p.url ?? null);
      updZeile.run(...werte, id);
    });
    try {
      schreiben();
    } catch (e) {
      // Die (bezahlten) Aufrufe sind gelaufen — das Ergebnis ist verloren, aber die Zeile darf nicht
      // auf 'laeuft' hängen bleiben. Eigener try/catch in `markiereFehler`, damit ein zweiter
      // Fehlschlag (Platte voll, Volume read-only) hier keinen Throw erzeugt.
      const text = `Das Erkennungsergebnis konnte nicht gespeichert werden (${kurz(e)}).`;
      log.error("Wein-Anreicherung nicht speicherbar", { id, error: kurz(e) });
      markiereFehler(db, id, text);
      return { ok: false, fehler: text };
    }

    neuIndizieren(db, id);
    if (!erkannt) {
      log.warn("Wein-Anreicherung ohne Ergebnis", { id, grund });
      return { ok: false, fehler: grund ?? undefined };
    }
    log.info("Wein-Anreicherung fertig", { id, titel: [weingutNeu, nameNeu].filter(Boolean).join(" "), preise: preise.length, dublette });
    return { ok: true };
  } catch (e) {
    // Sicherheitsnetz: was hier ankommt, hätte oben gefangen werden müssen — die Zeile darf trotzdem
    // nicht auf 'laeuft' stehen bleiben.
    const text = `Erkennung abgebrochen (${kurz(e)}).`;
    log.error("Wein-Anreicherung abgebrochen", { id, error: kurz(e) });
    markiereFehler(db, id, text);
    return { ok: false, fehler: text };
  } finally {
    inArbeit.delete(id);
  }
}

/** Jahrgang als Zahl oder NULL (jahrgangslose Weine: viele Sekte/Champagner). */
function zuJahrgang(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) && n > 1000 ? Math.trunc(n) : null;
}

/**
 * Dublettensuche — dieselbe Abfrage wie in `POST /api/v1/wein-scan`, nur zusätzlich um die eigene
 * Zeile bereinigt (sonst fände sich jede Flasche über ihre eigene EAN selbst).
 *
 * Dublette = derselbe Jahrgang UND ähnlicher Name/Erzeuger (case-/whitespace-unabhängig), ODER
 * schlicht dieselbe EAN. `jahrgang IS :jahrgang` ist NULL-sicher. Die Namenssuche ist auf die
 * Getränkeart eingegrenzt (ein Whisky „Reserva" und ein Wein „Reserva" sind keine Dublette), der
 * EAN-Zweig bleibt art-übergreifend: ein Barcode gehört zu genau einer Flasche.
 *
 * `null` bei jedem Problem — eine misslungene Dublettensuche darf die Erkennung nicht scheitern lassen.
 */
function sucheDublette(
  db: BetterSqlite3.Database,
  p: { id: number; art: GetraenkeArt; name: string; weingut: string; jahrgang: number | null; ean: string },
): number | null {
  if (!p.name && !p.ean) return null;
  try {
    const treffer = db.prepare(
      "SELECT id FROM weine " +
      "WHERE id <> :id AND ( " +
      "     (:ean <> '' AND TRIM(COALESCE(ean,'')) = :ean) " +
      "  OR (:name <> '' AND art = :art AND jahrgang IS :jahrgang AND ( " +
      "        (LOWER(TRIM(name)) = LOWER(:name) AND (:weingut = '' OR TRIM(weingut) = '' OR LOWER(TRIM(weingut)) = LOWER(:weingut))) " +
      "     OR (:weingut <> '' AND LOWER(TRIM(weingut)) = LOWER(:weingut) " +
      "         AND (INSTR(LOWER(TRIM(name)), LOWER(:name)) > 0 OR INSTR(LOWER(:name), LOWER(TRIM(name))) > 0)) " +
      "  )) " +
      ") " +
      // Bester Treffer zuerst: EAN schlägt Namensgleichheit, Namensgleichheit schlägt Teiltreffer.
      "ORDER BY CASE WHEN :ean <> '' AND TRIM(COALESCE(ean,'')) = :ean THEN 0 " +
      "              WHEN LOWER(TRIM(name)) = LOWER(:name) THEN 1 ELSE 2 END, id DESC LIMIT 1",
    ).get({ id: p.id, ean: p.ean, name: p.name, weingut: p.weingut, jahrgang: p.jahrgang, art: p.art }) as DublettenTreffer | undefined;
    return treffer?.id ?? null;
  } catch (e) {
    log.warn("Dublettensuche der Anreicherung fehlgeschlagen", { id: p.id, error: kurz(e) });
    return null;
  }
}

// ── 3) Sammellauf ────────────────────────────────────────────────────────────

/**
 * In-Flight-Guard für die Sammelläufe: der 5-Minuten-Job und ein manueller „Alle jetzt
 * verarbeiten"-Klick dürfen sich nicht überlappen (sonst doppelte Kosten). Ein Aufruf mit `nurId`
 * läuft absichtlich immer — das ist eine bewusste Nutzeraktion.
 */
let laufend = false;

/**
 * Zeilen, die auf 'laeuft' hängen geblieben sind, zurück auf 'offen' holen. `ki_queued_at` bleibt
 * dabei stehen, damit die Flasche ihren Platz in der Reihenfolge behält (älteste zuerst) und nicht
 * durch den Absturz nach hinten rutscht.
 *
 * `julianday(...)` statt eines Textvergleichs, weil `ki_queued_at` je nach Schreibweg
 * 'YYYY-MM-DD HH:MM:SS' (SQLite) oder ISO mit 'T'/'Z' (JS) enthalten kann — als Text verglichen
 * sortieren sich die beiden Formen falsch. Unlesbare Werte ergeben NULL und gelten als abgelaufen.
 */
export function holeStaleZurueck(db: BetterSqlite3.Database): number {
  try {
    const info = db.prepare(
      "UPDATE weine SET ki_status='offen' WHERE ki_status='laeuft' " +
      "AND (ki_queued_at IS NULL OR ki_queued_at='' OR julianday(ki_queued_at) IS NULL " +
      "     OR julianday(ki_queued_at) <= julianday('now') - ?)",
    ).run(STALE_MINUTEN / 1440);
    const n = Number(info.changes ?? 0);
    if (n) log.warn("Steckengebliebene Anreicherungen zurückgeholt", { anzahl: n });
    return n;
  } catch (e) {
    log.error("Stale-Rückholung fehlgeschlagen", { error: kurz(e) });
    return 0;
  }
}

/**
 * Was steht als Nächstes an: alles Offene, dazu Fehlversuche unterhalb der Versuchsgrenze, deren
 * Backoff abgelaufen ist. Älteste zuerst, damit über mehrere Läufe jede Flasche drankommt.
 *
 * Eigene, öffentliche Funktion, weil der Trockenlauf des Jobs genau das braucht: zählen, was fällig
 * wäre, OHNE einen einzigen kostenpflichtigen Aufruf auszulösen.
 */
export function faelligeAnreicherungen(
  db: BetterSqlite3.Database,
  limit: number = MAX_PRO_LAUF,
): { id: number; titel: string }[] {
  try {
    const rows = db.prepare(
      "SELECT id, name, weingut FROM weine " +
      "WHERE ki_status='offen' " +
      "   OR (ki_status='fehler' AND COALESCE(ki_versuche,0) < ? " +
      "       AND (ki_queued_at IS NULL OR ki_queued_at='' OR julianday(ki_queued_at) IS NULL " +
      "            OR julianday(ki_queued_at) <= julianday('now') - ?)) " +
      "ORDER BY COALESCE(julianday(ki_queued_at), 0) ASC, id ASC LIMIT ?",
      // `as` muss auf DERSELBEN Zeile wie der Aufruf stehen — TypeScript erlaubt vor `as` keinen
      // Zeilenumbruch (TS1434), anders als vor einem Punkt in einer Aufrufkette.
    ).all(MAX_VERSUCHE, FEHLER_BACKOFF_MINUTEN / 1440, Math.max(1, Math.min(limit, MAX_PRO_LAUF))) as {
      id: number; name: string | null; weingut: string | null;
    }[];
    return rows.map((r) => ({ id: r.id, titel: titelVon(r) }));
  } catch (e) {
    log.error("Fällige Anreicherungen konnten nicht ermittelt werden", { error: kurz(e) });
    return [];
  }
}

/** Zählerstand für die App (Segment „Queue (n)") — ohne die ganze Liste zu laden. */
export function zaehleQueue(
  db: BetterSqlite3.Database,
  art?: string,
): { offen: number; laeuft: number; fehler: number } {
  const leer = { offen: 0, laeuft: 0, fehler: 0 };
  try {
    const a = leseArt(art);
    const row = db.prepare(
      "SELECT COALESCE(SUM(ki_status='offen'),0) AS offen, " +
      "       COALESCE(SUM(ki_status='laeuft'),0) AS laeuft, " +
      "       COALESCE(SUM(ki_status='fehler'),0) AS fehler " +
      "FROM weine" + (a ? " WHERE art=?" : ""),
    ).get(...(a ? [a] : [])) as { offen: number; laeuft: number; fehler: number } | undefined;
    return row ? { offen: Number(row.offen), laeuft: Number(row.laeuft), fehler: Number(row.fehler) } : leer;
  } catch (e) {
    // Vor Migration 0024 gibt es die Spalte nicht — dann ist die Queue schlicht leer statt ein 500er.
    log.warn("Queue-Zähler nicht lesbar", { error: kurz(e) });
    return leer;
  }
}

/**
 * Sammellauf: Steckengebliebenes zurückholen und die fälligen Flaschen abarbeiten.
 *
 * `nurId` ist der ausdrückliche Anstoß aus der App („Erneut versuchen", „Erneut erkennen lassen"):
 * er ignoriert Versuchsgrenze, Backoff und den Sammellauf-Guard — der Nutzer steht davor und hat
 * gerade selbst entschieden, dass es diesen Versuch wert ist.
 *
 * `dryRun` löst KEINEN kostenpflichtigen Aufruf aus, sondern meldet nur, was fällig wäre.
 * Wirft nie — Job und Route bekommen immer eine lesbare Antwort.
 */
export async function verarbeiteOffene(
  db: BetterSqlite3.Database,
  opts: { limit?: number; nurId?: number; dryRun?: boolean } = {},
): Promise<AnreicherungsLauf> {
  const leer: AnreicherungsLauf = { verarbeitet: 0, fertig: 0, fehler: 0, eintraege: [] };

  // ── Einzelfall: sofort, ohne Guard und ohne Grenzen ──
  if (opts.nurId) {
    const id = Number(opts.nurId);
    if (!Number.isFinite(id) || id <= 0) return { ...leer, hinweis: "Ungültige ID." };
    const titel = titelVonId(db, id);
    if (opts.dryRun) {
      return { ...leer, eintraege: [{ id, titel, ok: true }], hinweis: `Trockenlauf — „${titel}" würde jetzt erkannt.` };
    }
    const e = await verarbeiteEinen(db, id);
    return {
      verarbeitet: 1,
      fertig: e.ok ? 1 : 0,
      fehler: e.ok ? 0 : 1,
      eintraege: [{ id, titel, ok: e.ok, ...(e.fehler ? { fehler: e.fehler } : {}) }],
    };
  }

  // Erst aufräumen: das ist reine Buchhaltung, kostet nichts und muss auch dann passieren, wenn
  // gleich mangels Schlüssel gar nicht gearbeitet wird.
  holeStaleZurueck(db);

  const faellig = faelligeAnreicherungen(db, opts.limit ?? MAX_PRO_LAUF);
  if (opts.dryRun) {
    return {
      ...leer,
      eintraege: faellig.map((f) => ({ id: f.id, titel: f.titel, ok: true })),
      // Beschriftung muss auch bei 1 und bei 0 stimmen — „1 Flaschen" wäre genauso falsch wie „0 Flasche".
      hinweis: faellig.length
        ? `Trockenlauf — ${faellig.length === 1 ? "1 Flasche wäre" : `${faellig.length} Flaschen wären`} jetzt an der Reihe.`
        : "Trockenlauf — es ist nichts fällig.",
    };
  }

  // Schlüssel EINMAL vorab prüfen (vor dem Guard, damit ein No-Op keinen Sammellauf blockiert):
  // sonst stiege jede Flasche einzeln aus und der Lauf meldete am Ende „10 verarbeitet", obwohl
  // nichts geprüft wurde.
  if (!hasOpenAI()) {
    return { ...leer, hinweis: "Die Erkennung benötigt OPENAI_API_KEY im Backend (Coolify)." };
  }
  if (laufend) return { ...leer, hinweis: "Es läuft bereits eine Anreicherung." };
  if (!faellig.length) return leer;

  laufend = true;
  try {
    const eintraege: LaufEintrag[] = [];
    for (let i = 0; i < faellig.length; i++) {
      const f = faellig[i];
      const e = await verarbeiteEinen(db, f.id);
      // Titel NACH dem Lauf holen — vorher stand dort nur der Platzhalter.
      eintraege.push({ id: f.id, titel: titelVonId(db, f.id), ok: e.ok, ...(e.fehler ? { fehler: e.fehler } : {}) });
      if (i < faellig.length - 1) await pause(PAUSE_MS); // nur ZWISCHEN zwei Anbieter-Aufrufen
    }
    const fertig = eintraege.filter((e) => e.ok).length;
    return { verarbeitet: eintraege.length, fertig, fehler: eintraege.length - fertig, eintraege };
  } catch (e) {
    log.error("Sammellauf der Wein-Anreicherung abgebrochen", { error: kurz(e) });
    return { ...leer, hinweis: `Sammellauf abgebrochen (${kurz(e)}).` };
  } finally {
    laufend = false;
  }
}

/** Anzeigename einer Zeile — nie leer, damit Protokoll und Push auch vor der Erkennung lesbar sind. */
function titelVonId(db: BetterSqlite3.Database, id: number): string {
  try {
    const r = db.prepare("SELECT id, name, weingut FROM weine WHERE id=?").get(id) as
      { id: number; name: string | null; weingut: string | null } | undefined;
    return r ? titelVon(r) : `Flasche #${id}`;
  } catch {
    return `Flasche #${id}`;
  }
}
