-- 0010_per_user_owner — Per-User-Login-Keys: owner-Spalten für Geräte-Zuordnung + gezielte Push.
-- Additiv & nullable → sicher auf der geseedeten Prod-DB; Legacy-Zeilen (Ole/alt) bleiben owner=NULL.
ALTER TABLE api_keys      ADD COLUMN owner TEXT;  -- 'lars' | 'elita' | NULL (Ole/Legacy)
ALTER TABLE device_tokens ADD COLUMN owner TEXT;  -- welchem Nutzer gehört dieses Gerät
ALTER TABLE foto_inbox    ADD COLUMN owner TEXT;   -- wer hat das Foto hochgeladen
CREATE INDEX IF NOT EXISTS idx_device_tokens_owner ON device_tokens(owner);
