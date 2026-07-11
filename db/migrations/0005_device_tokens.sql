-- 0005_device_tokens — APNs-Geräte-Tokens der iOS-App (für Push).
CREATE TABLE IF NOT EXISTS device_tokens (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  token        TEXT NOT NULL UNIQUE,               -- APNs-Device-Token (hex)
  platform     TEXT NOT NULL DEFAULT 'ios',
  environment  TEXT NOT NULL DEFAULT 'production',  -- production | sandbox
  user_label   TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen    TEXT
);
