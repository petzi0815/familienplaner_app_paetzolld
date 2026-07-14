import { getDb } from "@/server/db/connection";
import { log } from "@/server/observability/logger";
import { getAllBooks, updateBook, type Book } from "@/server/legacy/buecher-db";
import { searchReleases, startDownload, absolutePreview, type ShelfmarkRelease } from "@/server/ebooks/shelfmark";

// E-Book-Wunschliste periodisch/ manuell via Shelfmark prüfen und herunterladen.
// Bester Treffer: bevorzugt deutsch + epub + bekannter Verlag.

function pickBest(releases: ShelfmarkRelease[]): ShelfmarkRelease | null {
  if (!releases.length) return null;
  const score = (r: ShelfmarkRelease) => {
    let s = 0;
    if ((r.language ?? "").toLowerCase().includes("de")) s += 4;
    if ((r.format ?? "").toLowerCase() === "epub") s += 2;
    if (r.publisher && r.publisher.toLowerCase() !== "unknown") s += 1;
    return s;
  };
  return [...releases].sort((a, b) => score(b) - score(a))[0];
}

export interface CheckResult { id: number; title: string; found: boolean; downloaded: boolean; message: string }

/** Ein Wunschlisten-Buch via Shelfmark suchen + (bester Treffer) herunterladen; attempts/last_attempt vermerken. */
export async function checkAndDownload(book: Book): Promise<CheckResult> {
  const today = new Date().toISOString().split("T")[0];
  const query = [book.title, book.author].filter(Boolean).join(" ").trim() || book.title;
  const attempts = (book.attempts ?? 0) + 1;
  let found = false, downloaded = false, message = "";
  try {
    const { results } = await searchReleases(query);
    const best = pickBest(results);
    if (!best) {
      message = "kein Treffer";
    } else {
      found = true;
      const { status } = await startDownload((best._raw ?? best) as Record<string, unknown>);
      if (status >= 200 && status < 300) {
        // Erst persistieren, DANN als geladen markieren → Antwort stimmt mit DB überein.
        updateBook(book.id, {
          status: "heruntergeladen",
          downloaded_at: today,
          source_id: best.source_id ?? undefined,
          cover_url: book.cover_url || absolutePreview(best.preview) || undefined,
          attempts,
          last_attempt: today,
        });
        downloaded = true;
        message = "Download gestartet";
      } else {
        message = `Download fehlgeschlagen (${status})`;
      }
    }
  } catch (e) {
    // Interne Host-/Netzfehler NICHT an den Client durchreichen (kein Synology-Host-Leak) — nur loggen.
    log.error("Wunschliste-Check fehlgeschlagen", { id: book.id, error: e instanceof Error ? e.message : String(e) });
    message = "Shelfmark nicht erreichbar";
  }
  if (!downloaded) updateBook(book.id, { attempts, last_attempt: today });
  return { id: book.id, title: book.title, found, downloaded, message };
}

let retrying = false;

/** Alle „gesucht"-Bücher (max `limit`) prüfen + laden. In-Flight-Guard gegen Überlappung (manuell + Cron). */
export async function retryAll(limit = 80): Promise<{ checked: number; downloaded: number }> {
  if (retrying) return { checked: 0, downloaded: 0 };
  retrying = true;
  try {
    const books = getAllBooks({ status: "gesucht" }).slice(0, limit);
    let downloaded = 0;
    for (const b of books) {
      const r = await checkAndDownload(b);
      if (r.downloaded) downloaded++;
      await new Promise((res) => setTimeout(res, 300)); // sanft ggü. Shelfmark
    }
    return { checked: books.length, downloaded };
  } finally {
    retrying = false;
  }
}

export function pendingCount(): number {
  return getAllBooks({ status: "gesucht" }).length;
}

/** Erfolgreich heruntergeladene Bücher aus der Wunschliste entfernen. */
export function cleanupDownloaded(): number {
  return getDb().prepare("DELETE FROM ebook_wishlist WHERE status='heruntergeladen'").run().changes;
}
