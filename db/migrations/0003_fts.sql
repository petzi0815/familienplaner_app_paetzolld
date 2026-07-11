-- 0003_fts — Einheitlicher FTS5-Volltextindex über alle Ressourcen.
-- Befüllt/gepflegt aus dem generischen CRUD (server/db/fts.ts): resource+entity_id verweisen
-- auf die Quelle, title = Anzeigename, content = durchsuchbarer Text.
CREATE VIRTUAL TABLE IF NOT EXISTS fts_index USING fts5(
  resource UNINDEXED,
  entity_id UNINDEXED,
  title UNINDEXED,
  content
);
