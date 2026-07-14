import type BetterSqlite3 from "better-sqlite3";

// Backfill fehlender E-Book-Wunschlisten-Cover aus Google Books (per ISBN, sonst Titel/Autor).
// Google-Thumbnails kommen teils als http → auf https zwingen (iOS-ATS). Ersetzt auch kaputte
// Shelfmark-Cover (self-signed Host, lädt nicht in der App).

interface Row { id: number; title: string; author: string | null; isbn: string | null; cover_url: string | null }

async function googleCover(isbn: string | null, title: string, author: string | null): Promise<string | null> {
  const tryQuery = async (q: string): Promise<string | null> => {
    try {
      const r = await fetch(`https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&country=DE&maxResults=1`, {
        signal: AbortSignal.timeout(8000),
      });
      if (!r.ok) return null;
      const j = (await r.json()) as { items?: { volumeInfo?: { imageLinks?: Record<string, string> } }[] };
      const links = j.items?.[0]?.volumeInfo?.imageLinks;
      const thumb = links?.thumbnail ?? links?.smallThumbnail;
      return typeof thumb === "string" && thumb ? thumb.replace(/^http:/, "https:") : null;
    } catch {
      return null;
    }
  };
  const cleanIsbn = (isbn ?? "").replace(/[^0-9Xx]/g, "");
  if (cleanIsbn.length >= 10) { const c = await tryQuery(`isbn:${cleanIsbn}`); if (c) return c; }
  const t = title.trim();
  if (!t) return null;
  return tryQuery(author && author.trim() ? `intitle:${t} inauthor:${author.trim()}` : `intitle:${t}`);
}

const MISSING_WHERE =
  "(cover_url IS NULL OR cover_url='' OR cover_url LIKE '%bookdl.yagemi%') AND (COALESCE(isbn,'')<>'' OR COALESCE(title,'')<>'')";

export function countMissingCovers(db: BetterSqlite3.Database): number {
  return (db.prepare(`SELECT COUNT(*) c FROM ebook_wishlist WHERE ${MISSING_WHERE}`).get() as { c: number }).c;
}

let enriching = false; // In-Flight-Guard: Boot-One-Shot + Cron + manueller Lauf dürfen sich nicht überlappen.

/** Füllt fehlende/kaputte Cover (max `limit` pro Lauf, sanft ggü. Google Books). */
export async function enrichMissingCovers(db: BetterSqlite3.Database, limit = 200): Promise<{ processed: number; updated: number }> {
  if (enriching) return { processed: 0, updated: 0 };
  enriching = true;
  try {
    const rows = db.prepare(
      `SELECT id,title,author,isbn,cover_url FROM ebook_wishlist WHERE ${MISSING_WHERE} ORDER BY id LIMIT ?`,
    ).all(limit) as Row[];
    const upd = db.prepare("UPDATE ebook_wishlist SET cover_url=?, updated_at=datetime('now') WHERE id=?");
    let updated = 0;
    for (const r of rows) {
      const cover = await googleCover(r.isbn, r.title, r.author);
      if (cover) { upd.run(cover, r.id); updated++; }
      await new Promise((res) => setTimeout(res, 150));
    }
    return { processed: rows.length, updated };
  } finally {
    enriching = false;
  }
}
