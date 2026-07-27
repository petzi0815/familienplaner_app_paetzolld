-- 0019_ebook_download_verify — echter Download-Zustand für die E-Book-Wunschliste.
--
-- HINTERGRUND: Shelfmark quittiert `POST /api/releases/download` nur mit
--   HTTP 200 {"priority":0,"status":"queued"}
-- — das ist die Annahme in die WARTESCHLANGE, kein abgeschlossener Download. Der eigentliche
-- Ablauf (queued → locating → resolving → downloading → complete|error) läuft danach asynchron
-- und scheitert regelmäßig (z. B. „Destination not writable: /cwa-book-ingest"). Bisher wurde
-- die Annahme sofort als `status='heruntergeladen'` verbucht → Bücher verschwanden aus dem
-- Backlog, obwohl nie eine Datei ankam.
--
-- Diese Spalten trennen „eingereiht" von „bestätigt heruntergeladen". `status` wechselt erst
-- auf 'heruntergeladen', wenn Shelfmark `complete` meldet bzw. das Buch in der Bibliothek
-- (Calibre-Web) auftaucht — siehe server/ebooks/wishlist.ts + Job `buecher-wishlist-verify`.
-- Additiv (alle NULL-able) → sicher auf der geseedeten Prod-DB.

ALTER TABLE ebook_wishlist ADD COLUMN download_state TEXT;      -- NULL | queued | complete | failed
ALTER TABLE ebook_wishlist ADD COLUMN queued_at TEXT;           -- ISO-Zeitpunkt der Einreihung bei Shelfmark
ALTER TABLE ebook_wishlist ADD COLUMN queued_source_id TEXT;    -- Shelfmark-Download-ID (md5) des eingereihten Release
ALTER TABLE ebook_wishlist ADD COLUMN last_error TEXT;          -- letzte Fehlermeldung von Shelfmark (Klartext)
