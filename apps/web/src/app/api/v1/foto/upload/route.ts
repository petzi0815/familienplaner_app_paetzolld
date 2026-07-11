import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { config } from "@/server/config";
import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { randomToken } from "@/server/util/hash";
import { resourceByKey } from "@/server/domains/registry";
import { reindexRow } from "@/server/db/fts";
import { unauthorized, forbidden, fail, created } from "@/server/http/respond";

// Foto in den Foto-Eingang hochladen. multipart/form-data (iOS: bereich, notiz?, aufgenommen_am?, quelle?, file)
// ODER application/json { bereich?, notiz?, quelle?, aufgenommen_am?, filename?, mime?, data_base64|data_url }.
// Legt einen foto_inbox-Eintrag (status='neu') an → der Agent holt, analysiert und ordnet später zu.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const AREA = "foto-inbox";
const MIME_EXT: Record<string, string> = {
  "image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png", "image/webp": ".webp", "image/heic": ".heic", "image/heif": ".heif",
};

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();

  const ct = req.headers.get("content-type") ?? "";
  let buf: Buffer;
  let filenameHint = "";
  let mime: string | undefined;
  const fields: Record<string, string> = {};

  if (ct.includes("application/json")) {
    let body: Record<string, unknown>;
    try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
    for (const k of ["bereich", "notiz", "quelle", "aufgenommen_am", "filename", "mime"]) if (body[k] != null) fields[k] = String(body[k]);
    mime = fields.mime || undefined;
    filenameHint = fields.filename || "";
    let data = String(body.data_base64 ?? body.data_url ?? body.data ?? "");
    if (!data) return fail("no_data", "Feld 'data_base64' (oder 'data_url') erforderlich.", 400);
    const m = /^data:([^;]+);base64,([\s\S]*)$/.exec(data);
    if (m) { mime = mime ?? m[1]; data = m[2]; }
    try { buf = Buffer.from(data, "base64"); } catch { return fail("bad_base64", "Ungültige Base64-Daten.", 400); }
    if (!buf.length) return fail("empty", "Leere Datei.", 400);
  } else {
    let form: FormData;
    try { form = await req.formData(); } catch { return fail("bad_form", "multipart/form-data oder application/json erwartet.", 400); }
    for (const k of ["bereich", "notiz", "quelle", "aufgenommen_am"]) { const v = form.get(k); if (v != null) fields[k] = String(v); }
    const file = form.get("file");
    if (!(file instanceof File)) return fail("no_file", "Feld 'file' fehlt.", 400);
    buf = Buffer.from(await file.arrayBuffer());
    filenameHint = file.name;
    mime = file.type || undefined;
  }

  const ext = (path.extname(filenameHint) || MIME_EXT[mime ?? ""] || ".jpg").toLowerCase().replace(/[^.a-z0-9]/g, "");
  const name = `foto_${Date.now()}_${randomToken(6)}${ext}`;
  const dir = path.join(config.mediaDir, AREA);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name), buf);
  const key = `${AREA}/${name}`;

  const db = getDb();
  try {
    db.prepare("INSERT OR IGNORE INTO media_assets (bereich,storage_key,original_name,mime,bytes,sha256) VALUES (?,?,?,?,?,?)")
      .run(AREA, key, filenameHint || name, mime ?? "image/jpeg", buf.length, crypto.createHash("sha256").update(buf).digest("hex"));
  } catch { /* ignore */ }

  const info = db.prepare(
    "INSERT INTO foto_inbox (storage_key, bereich, status, notiz, quelle, bytes, mime, aufgenommen_am) VALUES (?,?, 'neu', ?,?,?,?,?)",
  ).run(key, fields.bereich ?? null, fields.notiz ?? null, fields.quelle ?? "api", buf.length, mime ?? "image/jpeg", fields.aufgenommen_am ?? null);
  const id = Number(info.lastInsertRowid);
  db.prepare("INSERT INTO event_log (actor, action, domain, entity_id, detail) VALUES (?,?,?,?,?)").run(auth.actor, "foto_upload", "foto", String(id), fields.bereich ?? null);
  const res = resourceByKey("foto-inbox"); if (res) reindexRow(db, res, id);

  const row = db.prepare("SELECT * FROM foto_inbox WHERE id=?").get(id) as Record<string, unknown>;
  return created({ ...row, url: `/api/v1/media/${key}` });
}
