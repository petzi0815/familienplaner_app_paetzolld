-- 0017_aufgaben_reminder — Idempotenz-Marker für den „1 Tag vorher"-Push je Aufgabe.
-- Additiv (NOT NULL DEFAULT 0) → sicher auf der geseedeten Prod-DB. Wird beim Abhaken einer
-- WIEDERHOLENDEN Aufgabe zurückgesetzt (nächste Fälligkeit soll wieder erinnern).
ALTER TABLE aufgaben ADD COLUMN reminder_1d_sent INTEGER NOT NULL DEFAULT 0;
