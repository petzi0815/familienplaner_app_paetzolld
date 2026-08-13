-- 0025_garten_bildleichen — kaputte Bilddateien des Garten-Bereichs bereinigen.
--
-- BEFUND: In `seed/media/garten/` lagen sieben Dateien mit der Endung .jpg, die keine Bilder sind.
-- Sechs enthielten wörtlich eine S3-Fehlerantwort („<?xml … <Error><Code>AccessDenied</Code>"),
-- eine eine HTML-Seite, und `samen_7_ref.jpg` war 0 Byte gross. Es sind fehlgeschlagene Downloads
-- aus der ursprünglichen Migration, die unter dem Zieldateinamen abgelegt wurden, statt den Fehler
-- zu melden. Angezeigt haben sie nie etwas. Gefunden wurden sie erst, als der neue
-- Vorschaubild-Erzeuger (Migration der Bild-Performance) an ihnen scheiterte.
--
-- ZWEI UNTERSCHIEDLICHE FÄLLE, deshalb zwei unterschiedliche Antworten:
--
--  1) Die sechs Fehlerseiten sind VERWAIST — sie stehen nur in `media_assets` (dem
--     Bestandsverzeichnis der Dateien); keine Pflanze und keine Saat verweist auf sie. Ihre
--     Verwaltungszeilen werden gelöscht, die Dateien sind aus dem Repo entfernt.
--
--  2) `samen_7_ref.jpg` hängt an einer echten Zeile (`garten_samen` id 7, „thymian thymus
--     vulgaris"). Neben ihr lag `samen_7_ref_source.txt` mit der Bitte, das Bild nachzuladen, und
--     drei Quellenvorschlägen — es war also nie ein eigenes Foto, sondern ein bewusst offen
--     gelassenes REFERENZBILD. Es ist jetzt von der dort erstgenannten Quelle nachgeladen
--     (Wikimedia Commons, Kurt Stüber, CC BY-SA 3.0; Urheber und Lizenz stehen in der
--     Textdatei daneben, weil die Lizenz das verlangt). Der Verweis in `bild_pfade` bleibt
--     deshalb bestehen — hier gibt es nichts zu entfernen, nur die Verwaltungszeile stimmt nicht
--     mehr (sie führt 0 Byte) und wird berichtigt.
--
-- Bewusst NICHT geschehen: für die sechs verwaisten Dateien Ersatzbilder besorgen. Sie zeigen
-- nichts an, niemand vermisst sie, und irgendein Bild an einer Stelle abzulegen, an der einmal ein
-- fehlgeschlagener Download stand, erzeugt nur den Anschein von Bestand.

-- ── 1) Verwaltungszeilen der sechs verwaisten Fehlerseiten entfernen ──
-- Namentlich, nicht per Muster: ein '%garten%' würde die 60 intakten Bilder mitnehmen.
DELETE FROM media_assets WHERE storage_key IN (
  'garten/1_kuechenschelle.jpg',
  'garten/2_hauswurz.jpg',
  'garten/3_thymian.jpg',
  'garten/4_sedum.jpg',
  'garten/5_blaukissen.jpg',
  'garten/6_katzenp.jpg'
);

-- ── 2) Verwaltungszeile des wiederhergestellten Referenzbildes berichtigen ──
-- Werte der tatsächlich abgelegten Datei (640x480, JPEG-Qualität 85).
UPDATE media_assets
   SET mime   = 'image/jpeg',
       bytes  = 79018,
       sha256 = '39ae515d6e8691d8f15e9186f5acf20f07527313828309fc6c2c6ca7a27d05c4'
 WHERE storage_key = 'garten/samen_7_ref.jpg';
