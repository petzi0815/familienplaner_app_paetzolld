import { NextResponse } from 'next/server';
import { guard } from '@/server/legacy/compat';
import { addBook, updateBook, getAllBooks } from '@/server/legacy/buecher-db';
import { startDownload, downloadStatus, absolutePreview } from '@/server/ebooks/shelfmark';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// E-Book-Download via Shelfmark starten (+ Wunschlisten-Eintrag) ODER nur auf die Wunschliste setzen.
// Body: { release: <vollständiges Release-Objekt aus der Suche>, addOnly?: boolean }
export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const body = await request.json();
    const release = body?.release ?? body;
    const addOnly = !!body?.addOnly;
    if (!release || !release.title) {
      return NextResponse.json({ error: 'Release-Objekt fehlt' }, { status: 400 });
    }

    // Dublettenprüfung (nach Titel).
    const existing = getAllBooks({ q: release.title });
    const isDuplicate = existing.some((b) => b.title.toLowerCase() === String(release.title).toLowerCase());

    const raw = release._raw ?? release;
    const extra = (raw?.extra ?? {}) as Record<string, unknown>;
    const today = new Date().toISOString().split('T')[0];

    // Immer zunächst als 'gesucht' anlegen — erst nach erfolgreichem Download-Start auf 'heruntergeladen'
    // setzen (sonst bleibt bei Netzfehler ein fälschlich als geladen markiertes Buch zurück).
    let bookId: number | null = null;
    if (!isDuplicate) {
      bookId = addBook({
        title: release.title,
        author: release.author ?? (extra.author as string) ?? undefined,
        publisher: release.publisher ?? (extra.publisher as string) ?? undefined,
        year: release.year ?? (extra.year as string) ?? undefined,
        description: release.description ?? (extra.description as string) ?? undefined,
        cover_url: absolutePreview(release.preview ?? (extra.preview as string)) ?? undefined,
        language: release.language ?? (extra.language as string) ?? 'de',
        source_id: release.source_id ?? undefined,
        status: 'gesucht',
        requested_by: 'iOS',
        requested_at: today,
        attempts: 0,
      });
    }

    if (addOnly) {
      return NextResponse.json({
        success: true, action: 'added', bookId, duplicate: isDuplicate,
        message: isDuplicate ? `"${release.title}" ist bereits auf der Wunschliste.` : `"${release.title}" zur Wunschliste hinzugefügt.`,
      });
    }

    // Download an Shelfmark starten (volles Release-Objekt).
    let dl: { status: number; json: unknown };
    try {
      dl = await startDownload(raw as Record<string, unknown>);
    } catch (netErr) {
      return NextResponse.json(
        { success: false, action: 'download_failed', bookId, error: `Shelfmark nicht erreichbar: ${netErr instanceof Error ? netErr.message : 'Fehler'}` },
        { status: 502 },
      );
    }
    if (dl.status < 200 || dl.status >= 300) {
      return NextResponse.json(
        { success: false, action: 'download_failed', bookId, error: `Download-Start fehlgeschlagen: ${dl.status}` },
        { status: 502 },
      );
    }
    if (bookId) updateBook(bookId, { status: 'heruntergeladen', downloaded_at: today, attempts: 1 });
    return NextResponse.json({
      success: true, action: 'downloading', bookId, duplicate: isDuplicate,
      message: `📥 Download gestartet: "${release.title}"`, status: dl.json,
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}

// Download-Status abfragen.
export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { status, json } = await downloadStatus();
    if (status < 200 || status >= 300) {
      return NextResponse.json({ error: `Status-Abfrage fehlgeschlagen: ${status}` }, { status: 502 });
    }
    return NextResponse.json(json);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}
