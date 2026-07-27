-- 0020_ebook_cover_url_fix — kaputte Shelfmark-Cover-URLs reparieren.
--
-- `absolutePreview()` hat `config.shelfmark.baseUrl` (endet auf „/api") mit dem von Shelfmark
-- gelieferten Pfad („/api/covers/<md5>?url=…") verkettet → gespeichert wurde
--   https://<host>/api/api/covers/…   (HTTP 404)
-- statt
--   https://<host>/api/covers/…       (HTTP 200, image/jpeg)
-- Damit war das Cover in der App UND im Push-Anhang tot. Der Erzeuger ist gefixt; diese
-- Migration zieht den Bestand nach. Rein textuell, betrifft nur Zeilen mit dem doppelten Präfix.

UPDATE ebook_wishlist
   SET cover_url = replace(cover_url, '/api/api/covers/', '/api/covers/'),
       updated_at = datetime('now')
 WHERE cover_url LIKE '%/api/api/covers/%';
