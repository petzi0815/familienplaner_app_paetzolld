-- Trigramm-FTS für tippfehlertolerante Suche (Substring-Treffer + fuzzy via Trigramm-Overlap/bm25).
-- Ergänzt fts_index (Prefix-/Exakt-Suche); zusammen ergeben sie exakte + tolerante Treffer.
CREATE VIRTUAL TABLE IF NOT EXISTS fts_trgm USING fts5(
  resource UNINDEXED,
  entity_id UNINDEXED,
  title UNINDEXED,
  content,
  tokenize = 'trigram case_sensitive 0'
);
