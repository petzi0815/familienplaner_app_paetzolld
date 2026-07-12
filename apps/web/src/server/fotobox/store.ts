import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import type BetterSqlite3 from "better-sqlite3";
import { config } from "@/server/config";
import { randomToken } from "@/server/util/hash";

// Persistenz-/Serialisierungs-Helfer für die Fotobox-Queue.

export const FOTOBOX_MEDIA_AREA = "fotobox";
const MIME_EXT: Record<string, string> = {
  "image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png", "image/webp": ".webp",
  "image/heic": ".heic", "image/heif": ".heif", "application/pdf": ".pdf",
};

export function genId(prefix: string): string {
  return `${prefix}_${Date.now().toString(36)}_${randomToken(4)}`;
}

function parseJson(v: unknown): unknown {
  if (typeof v !== "string" || v === "") return null;
  try { return JSON.parse(v); } catch { return v; }
}

type Row = Record<string, unknown>;

/** Media-Zeilen eines Items → API-Shape (mit stabiler URL). */
export function mediaFor(db: BetterSqlite3.Database, itemId: string): Row[] {
  const rows = db.prepare(
    "SELECT * FROM fotobox_item_media WHERE item_id=? ORDER BY ord, id",
  ).all(itemId) as Row[];
  return rows.map((m) => ({
    media_id: m.id,
    url: `/api/v1/media/${m.storage_key}`,
    storage_key: m.storage_key,
    mime_type: m.mime_type,
    filename: m.filename,
    size_bytes: m.size_bytes,
    sha256: m.sha256,
    width: m.width,
    height: m.height,
    order: m.ord,
    created_at_original: m.created_at_original,
  }));
}

/** Flaches DB-Item → verschachteltes API-Shape (wie in der Anforderungs-Doku). */
export function serializeItem(db: BetterSqlite3.Database, row: Row): Row {
  return {
    id: row.id,
    idempotency_key: row.idempotency_key,
    source: row.source,
    status: row.status,
    created_at: row.created_at,
    updated_at: row.updated_at,
    uploaded_by: {
      person: row.uploaded_person,
      display_name: row.uploaded_display_name,
      device_id: row.uploaded_device_id,
      telegram_id: row.uploaded_telegram_id,
    },
    media: mediaFor(db, String(row.id)),
    routing: {
      domain: row.domain,
      intent: row.intent,
      target_resource: row.target_resource,
      target_id: row.target_id,
      confidence: row.confidence,
      preclassified_by: row.preclassified_by,
    },
    telegram_equivalent: parseJson(row.telegram_equivalent),
    labels: parseJson(row.labels) ?? [],
    analysis_hint: parseJson(row.analysis_hint),
    review: {
      required: !!row.review_required,
      reason: row.review_reason,
      question: row.review_question,
    },
    processing: {
      claimed_by: row.claimed_by,
      claimed_until: row.claimed_until,
      attempts: row.attempts,
      last_attempt_at: row.last_attempt_at,
    },
    result: {
      processed_at: row.result_processed_at,
      created_resource: row.result_created_resource,
      created_id: row.result_created_id,
      summary: row.result_summary,
      error: row.result_error,
    },
  };
}

export function getItemRow(db: BetterSqlite3.Database, id: string): Row | undefined {
  return db.prepare("SELECT * FROM fotobox_items WHERE id=?").get(id) as Row | undefined;
}

export function logProc(db: BetterSqlite3.Database, itemId: string, worker: string | null, action: string, detail?: unknown): void {
  try {
    db.prepare("INSERT INTO fotobox_processing_log (item_id, worker, action, detail) VALUES (?,?,?,?)")
      .run(itemId, worker, action, detail == null ? null : JSON.stringify(detail));
  } catch { /* Log darf die Aktion nie kippen */ }
}

export interface SaveMediaInput {
  buf: Buffer;
  mime?: string;
  filename?: string;
  order?: number;
  width?: number | null;
  height?: number | null;
  createdAtOriginal?: string | null;
}

/** Speichert ein Medienobjekt auf Platte + fotobox_item_media + media_assets. Gibt das Media-Shape zurück. */
export function saveMedia(db: BetterSqlite3.Database, itemId: string, input: SaveMediaInput): Row {
  const mime = input.mime || "image/jpeg";
  const ext = (path.extname(input.filename ?? "") || MIME_EXT[mime] || ".jpg").toLowerCase().replace(/[^.a-z0-9]/g, "");
  const name = `${itemId}_${Date.now().toString(36)}_${randomToken(3)}${ext}`;
  const dir = path.join(config.mediaDir, FOTOBOX_MEDIA_AREA);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name), input.buf);
  const key = `${FOTOBOX_MEDIA_AREA}/${name}`;
  const sha = crypto.createHash("sha256").update(input.buf).digest("hex");

  try {
    db.prepare("INSERT OR IGNORE INTO media_assets (bereich,storage_key,original_name,mime,bytes,sha256) VALUES (?,?,?,?,?,?)")
      .run(FOTOBOX_MEDIA_AREA, key, input.filename || name, mime, input.buf.length, sha);
  } catch { /* ignore */ }

  const mediaId = genId("med");
  const ord = input.order ?? ((db.prepare("SELECT COALESCE(MAX(ord),0)+1 AS n FROM fotobox_item_media WHERE item_id=?").get(itemId) as { n: number }).n);
  db.prepare(
    "INSERT INTO fotobox_item_media (id,item_id,storage_key,mime_type,filename,size_bytes,sha256,width,height,ord,created_at_original) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
  ).run(mediaId, itemId, key, mime, input.filename ?? name, input.buf.length, sha, input.width ?? null, input.height ?? null, ord, input.createdAtOriginal ?? null);

  return {
    media_id: mediaId, url: `/api/v1/media/${key}`, storage_key: key, mime_type: mime,
    filename: input.filename ?? name, size_bytes: input.buf.length, sha256: sha,
    width: input.width ?? null, height: input.height ?? null, order: ord,
  };
}

/** Liest Bilddaten aus multipart ODER JSON-base64 (wie /foto/upload). */
export async function readUploadBuffer(req: Request): Promise<{ buf: Buffer; mime?: string; filename?: string; extra: Record<string, string> } | { error: Response }> {
  const { fail } = await import("@/server/http/respond");
  const ct = req.headers.get("content-type") ?? "";
  const extra: Record<string, string> = {};
  if (ct.includes("application/json")) {
    let body: Record<string, unknown>;
    try { body = (await req.json()) as Record<string, unknown>; } catch { return { error: fail("bad_json", "Ungültiger JSON-Body.", 400) }; }
    for (const k of ["filename", "mime", "order", "width", "height", "created_at_original"]) if (body[k] != null) extra[k] = String(body[k]);
    let data = String(body.data_base64 ?? body.data_url ?? body.data ?? "");
    if (!data) return { error: fail("no_data", "Feld 'data_base64' (oder 'data_url') erforderlich.", 400) };
    let mime = extra.mime || undefined;
    const m = /^data:([^;]+);base64,([\s\S]*)$/.exec(data);
    if (m) { mime = mime ?? m[1]; data = m[2]; }
    let buf: Buffer;
    try { buf = Buffer.from(data, "base64"); } catch { return { error: fail("bad_base64", "Ungültige Base64-Daten.", 400) }; }
    if (!buf.length) return { error: fail("empty", "Leere Datei.", 400) };
    return { buf, mime, filename: extra.filename, extra };
  }
  let form: FormData;
  try { form = await req.formData(); } catch { return { error: fail("bad_form", "multipart/form-data oder application/json erwartet.", 400) }; }
  for (const k of ["order", "width", "height", "created_at_original"]) { const v = form.get(k); if (v != null) extra[k] = String(v); }
  const file = form.get("file");
  if (!(file instanceof File)) return { error: fail("no_file", "Feld 'file' fehlt.", 400) };
  const buf = Buffer.from(await file.arrayBuffer());
  return { buf, mime: file.type || undefined, filename: file.name, extra };
}
