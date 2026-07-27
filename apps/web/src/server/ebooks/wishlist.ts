import { getDb } from "@/server/db/connection";
import { log } from "@/server/observability/logger";
import { updateBook, type Book } from "@/server/legacy/buecher-db";
import { searchReleases, startDownload, absolutePreview, downloadStates, activityHistory, type ShelfmarkRelease } from "@/server/ebooks/shelfmark";
import { calibreEnabled, listBooks } from "@/server/ebooks/calibre";
import { signedCoverUrl } from "@/server/push/cover";

// E-Book-Wunschliste periodisch/manuell via Shelfmark prüfen und herunterladen.
//
// WICHTIG — Zwei-Stufen-Modell (siehe Migration 0019):
//   1. `checkAndDownload` sucht + reiht bei Shelfmark EIN. Shelfmark quittiert das mit
//      `200 {"status":"queued"}`. Das Buch bleibt `status='gesucht'` und bekommt
//      `download_state='queued'` — es verschwindet also NICHT aus dem Backlog.
//   2. `verifyQueued` (Job `buecher-wishlist-verify`) verfolgt den Ausgang. Erst wenn Shelfmark
//      `complete` meldet — oder das Buch nachweislich in der Bibliothek (Calibre-Web) liegt —
//      wird `status='heruntergeladen'` gesetzt. Fehler/„nie bestätigt" → zurück ins Backlog
//      mit `last_error`.
// Vorher wurde die bloße Annahme in die Warteschlange als „heruntergeladen" verbucht; Bücher
// galten damit als erledigt, obwohl bei Shelfmark jeder Download scheiterte.

const today = () => new Date().toISOString().split("T")[0];
const nowIso = () => new Date().toISOString();

/** Einheitlicher Text, wenn Shelfmark selbst nicht antwortet (bewusst ohne internen Hostnamen). */
export const SHELFMARK_UNREACHABLE = "Shelfmark nicht erreichbar";

// ── Titel-/Autor-Abgleich ────────────────────────────────────────────────────
// Die Shelfmark-Suche (Anna's Archive) liefert zu einem Titel auch lose Verwandtes. Ohne
// Abgleich könnte der „beste" Treffer ein völlig anderes Buch sein (z. B. „Der Schwarm" →
// „[Perry Rhodan – Der Schwarm 06]"). Lieber im Backlog lassen als das Falsche laden.

function normalize(s: string | null | undefined): string {
  return (s ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "") // kombinierende Akzente nach NFD entfernen
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/** Enthält die Wortfolge `hay` die Wortfolge `needle` am Stück? (Wortgrenzen-treu, kein Teilstring.) */
function containsWords(hay: string[], needle: string[]): boolean {
  if (!needle.length || needle.length > hay.length) return false;
  for (let i = 0; i <= hay.length - needle.length; i++) {
    if (needle.every((t, j) => hay[i + j] === t)) return true;
  }
  return false;
}

/**
 * Passt `candidate` zum gewünschten Titel? Der eine Titel enthält den anderen als Wortfolge
 * (fängt Untertitel wie „Die Riesinnen: Roman" ab), sonst ≥75 % der markanten Wörter (min. 3).
 * Bewusst wortgrenzen-treu statt Teilstring — sonst würde „Dune" auf „Dunelmensis" passen.
 */
export function titleMatches(wanted: string, candidate: string | null | undefined): boolean {
  const w = normalize(wanted);
  const c = normalize(candidate);
  if (!w || !c) return false;
  const wt = w.split(" ");
  const ct = c.split(" ");
  if (containsWords(ct, wt) || containsWords(wt, ct)) return true;
  // Notnagel für abweichende Schreibweisen/Untertitel. Bewusst streng: kurze Titel müssen über die
  // Wortfolge oben passen, sonst würde „Junge Frau mit Katze" auf „Junge Frau, am Fenster stehend"
  // matchen (2 von 3 markanten Wörtern) und ein fremdes Buch als Beleg durchgehen.
  const words = wt.filter((t) => t.length > 3);
  if (words.length < 3) return false;
  const cs = new Set(ct);
  const hits = words.filter((t) => cs.has(t)).length;
  return hits / words.length >= 0.75;
}

/** Autor-Abgleich: ohne gewünschten Autor immer wahr, sonst muss ein markanter Namensteil vorkommen. */
function authorMatches(wanted: string | null | undefined, candidate: string | null | undefined): boolean {
  const w = normalize(wanted);
  if (!w) return true;
  const c = normalize(candidate);
  if (!c) return false;
  const cs = new Set(c.split(" "));
  const parts = w.split(" ").filter((t) => t.length > 3);
  return parts.length ? parts.some((p) => cs.has(p)) : true;
}

/** Bester Treffer: muss zum Titel passen; darunter bevorzugt deutsch + epub + bekannter Verlag. */
function pickBest(releases: ShelfmarkRelease[], book: Book): ShelfmarkRelease | null {
  const fitting = releases.filter((r) => titleMatches(book.title, r.title));
  if (!fitting.length) return null;
  const score = (r: ShelfmarkRelease) => {
    let s = 0;
    if ((r.language ?? "").toLowerCase().includes("de")) s += 4;
    if ((r.format ?? "").toLowerCase() === "epub") s += 2;
    if (r.publisher && r.publisher.toLowerCase() !== "unknown") s += 1;
    // Autor schlägt alles andere: ein Treffer mit passendem Autor ist immer besser als ein
    // deutsches epub vom falschen Autor (z. B. „Der Schwarm" → Perry-Rhodan-Heftroman).
    if (authorMatches(book.author, r.author)) s += 8;
    return s;
  };
  return [...fitting].sort((a, b) => score(b) - score(a))[0];
}

// ── Bibliothek als Endkontrolle (Calibre-Web) ────────────────────────────────
// Ein Shelfmark-Download landet über den Ingest-Ordner in Calibre-Web. Damit ist die Bibliothek
// die eigentliche Wahrheit für „wirklich heruntergeladen" — dauerhaft und unabhängig davon, ob
// Shelfmark neu gestartet wurde.

/**
 * Suchbegriffe für Calibre-Web. WICHTIG: CWA sucht `lower(title) LIKE '%begriff%'` — der ganze
 * Begriff muss also wörtlich im Bibliothekstitel stecken. Wunschlisten-Titel stammen aber aus
 * Anna's Archive und sind oft 300 Zeichen lang („… / aus dem Zamonischen übertr., ill. …") oder
 * enthalten Tippfehler. Ein solcher Begriff trifft NIE. Deshalb gestaffelt: kurzer Titelanfang,
 * noch kürzerer Titelanfang, zuletzt der Nachname des Autors (dann filtert `titleMatches`).
 */
function calibreQueries(title: string, author?: string | null): string[] {
  const head = title.split(/[:–—/(\[|·]/)[0].replace(/\s+/g, " ").trim();
  const words = head.split(" ").filter(Boolean);
  const out = [words.slice(0, 5).join(" "), words.slice(0, 3).join(" ")];
  // Autor-Nachname: längstes Wort aus dem ersten Namensteil (Feld ist teils „Moers, Walter [Moers, Walter]unknown").
  const surname = (author ?? "")
    .split(/[,\[\]()]/)[0]
    .split(/\s+/)
    .filter((t) => /^[\p{L}-]{4,}$/u.test(t))
    .sort((a, b) => b.length - a.length)[0];
  if (surname) out.push(surname);
  return [...new Set(out.filter((q) => q.length >= 3))];
}

/** Liegt das Buch in Calibre-Web? Wirft bei Netz-/Login-Fehler (Aufrufer wertet das als „unbekannt"). */
async function calibreHas(title: string, author?: string | null): Promise<boolean> {
  if (!title.trim()) return false;
  for (const search of calibreQueries(title, author)) {
    const { rows } = await listBooks({ search, limit: 50 });
    if (rows.some((b) => titleMatches(title, b.title) && authorMatches(author, b.authors))) return true;
  }
  return false;
}

// ── Stufe 1: suchen + einreihen ──────────────────────────────────────────────

export interface CheckResult {
  id: number;
  title: string;
  found: boolean;
  /** An Shelfmark übergeben. NICHT „heruntergeladen" — das bestätigt erst `verifyQueued`. */
  queued: boolean;
  /** Bleibt hier immer false; nur der Verify-Job setzt „heruntergeladen". */
  downloaded: boolean;
  message: string;
}

/** Ein Wunschlisten-Buch via Shelfmark suchen + in die Warteschlange geben. */
export async function checkAndDownload(book: Book): Promise<CheckResult> {
  const stamp = today();
  const query = [book.title, book.author].filter(Boolean).join(" ").trim() || book.title;
  const attempts = (book.attempts ?? 0) + 1;
  let found = false, queued = false, message = "";
  try {
    const { results } = await searchReleases(query);
    const best = pickBest(results, book);
    if (!best) {
      message = results.length ? `${results.length} Treffer, aber keiner passt zum Titel` : "kein Treffer";
    } else {
      found = true;
      const { status, json } = await startDownload((best._raw ?? best) as Record<string, unknown>);
      if (status >= 200 && status < 300) {
        // NUR eingereiht — Status bleibt 'gesucht', bis Shelfmark den Abschluss meldet.
        updateBook(book.id, {
          download_state: "queued",
          queued_source_id: best.source_id ?? null,
          queued_at: nowIso(),
          last_error: null,
          source_id: best.source_id ?? undefined,
          cover_url: book.cover_url || absolutePreview(best.preview) || undefined,
          attempts,
          last_attempt: stamp,
        });
        queued = true;
        const q = (json as { status?: string } | null)?.status;
        message = q && q !== "queued" ? `an Shelfmark übergeben (${q})` : "in der Warteschlange bei Shelfmark";
      } else {
        message = `Download-Start abgelehnt (${status})`;
      }
    }
  } catch (e) {
    // Interne Host-/Netzfehler NICHT an den Client durchreichen (kein Synology-Host-Leak) — nur loggen.
    log.error("Wunschliste-Check fehlgeschlagen", { id: book.id, error: e instanceof Error ? e.message : String(e) });
    message = SHELFMARK_UNREACHABLE;
  }
  if (!queued) updateBook(book.id, { attempts, last_attempt: stamp, last_error: message });
  return { id: book.id, title: book.title, found, queued, downloaded: false, message };
}

let retrying = false;

/** Alle offenen „gesucht"-Bücher (max `limit`) suchen + einreihen. In-Flight-Guard gegen Überlappung. */
export async function retryAll(limit = 80): Promise<{ checked: number; queued: number; unreachable: number }> {
  if (retrying) return { checked: 0, queued: 0, unreachable: 0 };
  retrying = true;
  try {
    const books = openBooks().slice(0, limit);
    let queued = 0, unreachable = 0;
    for (const b of books) {
      const r = await checkAndDownload(b);
      if (r.queued) queued++;
      if (r.message === SHELFMARK_UNREACHABLE) unreachable++;
      await new Promise((res) => setTimeout(res, 300)); // sanft ggü. Shelfmark
    }
    return { checked: books.length, queued, unreachable };
  } finally {
    retrying = false;
  }
}

/** „gesucht"-Bücher, die NICHT bereits bei Shelfmark in der Warteschlange hängen. */
function openBooks(): Book[] {
  return getDb()
    .prepare("SELECT * FROM ebook_wishlist WHERE status='gesucht' AND COALESCE(download_state,'')<>'queued' ORDER BY requested_at DESC, created_at DESC")
    .all() as Book[];
}

export function pendingCount(): number {
  return openBooks().length;
}

export function queuedCount(): number {
  return (getDb().prepare("SELECT COUNT(*) c FROM ebook_wishlist WHERE download_state='queued'").get() as { c: number }).c;
}

// ── Stufe 2: Ausgang verfolgen ───────────────────────────────────────────────

/** Ein eingereihter Download gilt nach dieser Zeit ohne Rückmeldung als gescheitert. */
const STALE_HOURS = 6;

/**
 * Erkennt den Rechte-/Ablagefehler des Shelfmark-Ingest-Ordners
 * („Destination not writable: /cwa-book-ingest ([Errno 13] Permission denied…)").
 * Dieser Fall soll sofort auffallen — er blockiert JEDEN Download, bis auf der Synology
 * die Ordnerrechte wieder stimmen. Deshalb eigener Push-Text statt einer Sammelmeldung.
 */
export function isDestinationError(reason: string | null | undefined): boolean {
  const r = (reason ?? "").toLowerCase();
  return r.includes("not writable") || r.includes("permission denied") || r.includes("errno 13");
}

/** Ein abgeschlossener Vorgang — Grundlage für die (reiche) Push-Meldung. */
export interface VerifyOutcome {
  id: number;
  title: string;
  owner: string | null;
  reason: string;
  author: string | null;
  /** Klappentext, auf Push-Länge gekürzt. */
  description: string | null;
  /** Signierte, ohne Auth abrufbare Cover-URL für den Bildanhang (null = kein Bild). */
  coverUrl: string | null;
}

/** Klappentext auf eine im Push lesbare Länge bringen (an der Satzgrenze, sonst hart). */
function shortDescription(raw: string | null | undefined, max = 420): string | null {
  const t = (raw ?? "").replace(/\s+/g, " ").trim();
  if (!t) return null;
  if (t.length <= max) return t;
  const cut = t.slice(0, max);
  const stop = Math.max(cut.lastIndexOf(". "), cut.lastIndexOf("! "), cut.lastIndexOf("? "));
  return (stop > max * 0.5 ? cut.slice(0, stop + 1) : cut.trimEnd() + " …");
}

/** Alles zusammentragen, was die Push-Mitteilung reich macht. */
function outcomeOf(b: Book, reason: string): VerifyOutcome {
  return {
    id: b.id,
    title: b.title,
    owner: ownerOf(b.requested_by),
    reason,
    author: b.author?.trim() || null,
    description: shortDescription(b.description),
    coverUrl: signedCoverUrl(b.cover_url),
  };
}

export interface VerifyResult {
  checked: number;
  downloaded: number;
  failed: number;
  pending: number;
  messages: string[];
  /** Bestätigte Downloads dieses Laufs (für „Buch ist da"-Push). */
  done: VerifyOutcome[];
  /** Gescheiterte Downloads dieses Laufs (für Fehler-Push). */
  failures: VerifyOutcome[];
  /** Shelfmark war nicht erreichbar — nichts wurde bewertet. */
  unreachable: boolean;
}

/** `requested_by` → Push-Zielperson. Unbekannt/„Manuell" → null = Broadcast an die Familie. */
function ownerOf(requestedBy: string | null | undefined): string | null {
  const v = (requestedBy ?? "").trim().toLowerCase();
  return v === "lars" || v === "elita" ? v : null;
}

/** Eingereihte Downloads gegen Shelfmark (und ersatzweise die Bibliothek) abgleichen. */
export async function verifyQueued(opts: { dryRun?: boolean } = {}): Promise<VerifyResult> {
  const rows = getDb().prepare("SELECT * FROM ebook_wishlist WHERE download_state='queued'").all() as Book[];
  const out: VerifyResult = { checked: rows.length, downloaded: 0, failed: 0, pending: 0, messages: [], done: [], failures: [], unreachable: false };
  if (!rows.length) return out;

  let states: Awaited<ReturnType<typeof downloadStates>>;
  try {
    states = await downloadStates();
  } catch (e) {
    log.error("Shelfmark-Status nicht abrufbar", { error: e instanceof Error ? e.message : String(e) });
    out.messages.push("Shelfmark nicht erreichbar — Zustand unverändert");
    out.pending = rows.length;
    out.unreachable = true;
    return out;
  }

  const stamp = today();
  for (const b of rows) {
    const info = b.queued_source_id ? states.get(b.queued_source_id) : undefined;

    const markDone = (why: string) => {
      out.downloaded++;
      out.messages.push(`✅ ${b.title} — ${why}`);
      out.done.push(outcomeOf(b, why));
      if (!opts.dryRun) {
        updateBook(b.id, { status: "heruntergeladen", downloaded_at: stamp, download_state: "complete", last_error: null });
      }
    };
    const markFailed = (why: string) => {
      out.failed++;
      out.messages.push(`⚠️ ${b.title} — ${why}`);
      out.failures.push(outcomeOf(b, why));
      if (!opts.dryRun) {
        // Gescheitert heißt gescheitert: KEIN 'heruntergeladen', das Buch bleibt im Backlog.
        updateBook(b.id, { status: "gesucht", downloaded_at: null, download_state: "failed", last_error: why });
      }
    };

    if (info?.phase === "complete") { markDone("Shelfmark meldet abgeschlossen"); continue; }
    if (info?.terminal) { markFailed(info.message || `Shelfmark: ${info.phase}`); continue; }
    if (info) { out.pending++; continue; } // noch unterwegs (queued/locating/resolving/downloading)

    // Shelfmark kennt den Download nicht (mehr) — z. B. nach einem Neustart der Instanz.
    // Gegenprobe in der Bibliothek, sonst nach STALE_HOURS als gescheitert werten.
    let inLibrary: boolean | null = null;
    if (calibreEnabled()) {
      try { inLibrary = await calibreHas(b.title, b.author); }
      catch { inLibrary = null; }
    }
    if (inLibrary === true) { markDone("in der Bibliothek gefunden"); continue; }

    const ageH = b.queued_at ? (Date.now() - new Date(b.queued_at).getTime()) / 3_600_000 : Infinity;
    if (ageH >= STALE_HOURS) markFailed("Shelfmark hat den Download nie bestätigt");
    else out.pending++;
  }
  return out;
}

// ── Reparatur: Altbestand gegenprüfen ────────────────────────────────────────

export interface RepairResult {
  possible: boolean;
  reason?: string;
  checked: number;
  kept: number;
  reset: number;
  skipped: number;
  messages: string[];
}

/**
 * Alle als „heruntergeladen" markierten Wunschbücher gegenprüfen und unbestätigte zurück ins
 * Backlog legen. Wahrheitsquelle ist die BIBLIOTHEK (Calibre-Web); zusätzlich zählt ein
 * `complete` in Shelfmarks Historie als Bestätigung. Ohne erreichbare Bibliothek wird NICHTS
 * geändert (lieber nichts tun als korrekte Einträge zurücksetzen).
 * Bereits bestätigte Zeilen (`download_state='complete'`) werden übersprungen → idempotent.
 */
export async function repairUnverifiedDownloads(opts: { dryRun?: boolean } = {}): Promise<RepairResult> {
  const out: RepairResult = { possible: false, checked: 0, kept: 0, reset: 0, skipped: 0, messages: [] };
  if (!calibreEnabled()) {
    out.reason = "Bibliothek (Calibre-Web) nicht konfiguriert — ohne sie ist keine Gegenprüfung möglich";
    out.messages.push(out.reason);
    return out;
  }
  // Erreichbarkeit einmal vorab prüfen, damit ein Ausfall nicht als „nirgends gefunden" durchschlägt.
  try {
    await listBooks({ limit: 1 });
  } catch (e) {
    out.reason = `Bibliothek nicht erreichbar (${e instanceof Error ? e.message : "Fehler"}) — nichts geändert`;
    out.messages.push(out.reason);
    return out;
  }
  out.possible = true;

  const completedTitles = await activityHistory()
    .then((h) => h.filter((e) => e.finalStatus === "complete"))
    .catch(() => []);

  const rows = getDb()
    .prepare("SELECT * FROM ebook_wishlist WHERE status='heruntergeladen' AND COALESCE(download_state,'')<>'complete' ORDER BY id")
    .all() as Book[];
  out.checked = rows.length;

  for (const b of rows) {
    const viaShelfmark = completedTitles.some(
      (e) => (b.source_id && e.sourceId === b.source_id) || titleMatches(b.title, e.title),
    );
    let viaLibrary: boolean | null = null;
    if (!viaShelfmark) {
      try { viaLibrary = await calibreHas(b.title, b.author); }
      catch { viaLibrary = null; }
    }

    if (viaShelfmark || viaLibrary === true) {
      out.kept++;
      out.messages.push(`✅ ${b.title} — bestätigt (${viaShelfmark ? "Shelfmark-Historie" : "Bibliothek"})`);
      if (!opts.dryRun) updateBook(b.id, { download_state: "complete" });
      continue;
    }
    if (viaLibrary === null) {
      out.skipped++;
      out.messages.push(`… ${b.title} — Bibliothek antwortete nicht, unverändert`);
      continue;
    }
    out.reset++;
    out.messages.push(`↩️ ${b.title} — nirgends belegt, zurück ins Backlog`);
    if (!opts.dryRun) {
      updateBook(b.id, {
        status: "gesucht",
        downloaded_at: null,
        download_state: "failed",
        last_error: "Download nie bestätigt (weder in der Bibliothek noch bei Shelfmark) — zurück ins Backlog",
      });
    }
  }
  return out;
}

/** Bestätigt heruntergeladene Bücher aus der Wunschliste entfernen (nur verifizierte). */
export function cleanupDownloaded(): number {
  return getDb()
    .prepare("DELETE FROM ebook_wishlist WHERE status='heruntergeladen' AND COALESCE(download_state,'')='complete'")
    .run().changes;
}
