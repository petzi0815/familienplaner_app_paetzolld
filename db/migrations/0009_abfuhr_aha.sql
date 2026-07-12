-- 0009_abfuhr_aha — aha-region.de Auto-Sync-Parameter (aufgelöst für Wilhelm-Hanebuth-Weg 7).
-- Der Sync-Endpunkt fährt das 3-Schritt-Formular von aha-region.de (Straße→ladeort→ICS) und
-- importiert die Termine automatisch — kein jährliches manuelles ICS-Hochladen nötig.
ALTER TABLE abfuhr_config ADD COLUMN aha_gemeinde TEXT;
ALTER TABLE abfuhr_config ADD COLUMN aha_von TEXT;
ALTER TABLE abfuhr_config ADD COLUMN aha_strasse TEXT;
ALTER TABLE abfuhr_config ADD COLUMN aha_hausnr TEXT;
ALTER TABLE abfuhr_config ADD COLUMN aha_hausnraddon TEXT;

UPDATE abfuhr_config
SET aha_gemeinde='Burgwedel',
    aha_von='W',
    aha_strasse='63338@Wilhelm-Hanebuth-Weg / Großburgwedel@Großburgwedel',
    aha_hausnr='7',
    aha_hausnraddon=''
WHERE id=1;
