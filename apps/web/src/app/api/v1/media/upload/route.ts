import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { config } from "@/server/config";
import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { randomToken } from "@/server/util/hash";
import { resourceByKey, pkOf } from "@/server/domains/registry";
import { reindexRow } from "@/server/db/fts";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";

// Bild-/Datei-Upload per API. Zwei Wege:
//  - multipart/form-data: Felder area, file (+ optional resource, id)
//  - application/json:     { area, filename?, mime?, data_base64|data_url, resource?, id? }
// Optional resource+id → das Bild wird direkt an den Datensatz gehängt (Bild-Spalte gesetzt/ergänzt).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MIME_EXT: Record<string, string> = {
  "image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png", "image/webp": ".webp",
  "image/gif": ".gif", "image/heic": ".heic", "application/pdf": ".pdf",
};
const sanitizeArea = (a: unknown) => String(a ?? "uploads").replace(/[^a-z0-9_-]/gi, "") || "uploads";

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();

  const ct = req.headers.get("content-type") ?? "";
  let area = "uploads";
  let buf: Buffer;
  let filenameHint = "";
  let mime: string | undefined;
  let resource: string | undefined;
  let recordId: string | undefined;

  if (ct.includes("application/json")) {
    let body: Record<string, unknown>;
    try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
    area = sanitizeArea(body.area);
    resource = body.resource ? String(body.resource) : undefined;
    recordId = body.id != null ? String(body.id) : undefined;
    mime = body.mime ? String(body.mime) : undefined;
    filenameHint = body.filename ? String(body.filename) : "";
    let data = String(body.data_base64 ?? body.data_url ?? body.data ?? "");
    if (!data) return fail("no_data", "Feld 'data_base64' (oder 'data_url') erforderlich.", 400);
    const m = /^data:([^;]+);base64,([\s\S]*)$/.exec(data);
    if (m) { mime = mime ?? m[1]; data = m[2]; }
    try { buf = Buffer.from(data, "base64"); } catch { return fail("bad_base64", "Ungültige Base64-Daten.", 400); }
    if (!buf.length) return fail("empty", "Leere Datei.", 400);
  } else {
    let form: FormData;
    try { form = await req.formData(); } catch { return fail("bad_form", "multipart/form-data oder application/json erwartet.", 400); }
    area = sanitizeArea(form.get("area"));
    resource = form.get("resource") ? String(form.get("resource")) : undefined;
    recordId = form.get("id") != null ? String(form.get("id")) : undefined;
    const file = form.get("file");
    if (!(file instanceof File)) return fail("no_file", "Feld 'file' fehlt.", 400);
    buf = Buffer.from(await file.arrayBuffer());
    filenameHint = file.name;
    mime = file.type || undefined;
  }

  const ext = (path.extname(filenameHint) || MIME_EXT[mime ?? ""] || ".bin").toLowerCase().replace(/[^.a-z0-9]/g, "");
  const name = `up_${Date.now()}_${randomToken(6)}${ext}`;
  const dir = path.join(config.mediaDir, area);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name), buf);
  const key = `${area}/${name}`;

  const db = getDb();
  try {
    db.prepare("INSERT OR IGNORE INTO media_assets (bereich,storage_key,original_name,mime,bytes,sha256) VALUES (?,?,?,?,?,?)")
      .run(area, key, filenameHint || name, mime ?? "application/octet-stream", buf.length, crypto.createHash("sha256").update(buf).digest("hex"));
  } catch { /* ignore */ }

  // Optional: direkt an einen Datensatz anhängen.
  let attached: { resource: string; id: string; column: string } | undefined;
  if (resource && recordId != null) {
    const res = resourceByKey(resource);
    if (!res) return fail("bad_resource", `Unbekannte Ressource '${resource}'.`, 400, { storage_key: key, url: `/api/v1/media/${key}` });
    if (!res.image) return fail("no_image_column", `Ressource '${resource}' hat keine Bild-Spalte.`, 400, { storage_key: key, url: `/api/v1/media/${key}` });
    const row = db.prepare(`SELECT * FROM "${res.table}" WHERE "${pkOf(res)}"=?`).get(recordId) as Record<string, unknown> | undefined;
    if (!row) return fail("record_not_found", `${res.label} #${recordId} nicht gefunden.`, 404, { storage_key: key, url: `/api/v1/media/${key}` });
    if (res.image.multi) {
      let arr: string[] = [];
      try { const p = JSON.parse(String(row[res.image.col] ?? "[]")); arr = Array.isArray(p) ? p : []; } catch { arr = []; }
      arr.push(key);
      db.prepare(`UPDATE "${res.table}" SET "${res.image.col}"=? WHERE "${pkOf(res)}"=?`).run(JSON.stringify(arr), recordId);
    } else {
      db.prepare(`UPDATE "${res.table}" SET "${res.image.col}"=? WHERE "${pkOf(res)}"=?`).run(key, recordId);
    }
    reindexRow(db, res, recordId);
    db.prepare("INSERT INTO event_log (actor, action, domain, entity_id, detail) VALUES (?,?,?,?,?)").run(auth.actor, "media_attach", res.key, recordId, key);
    attached = { resource: res.key, id: recordId, column: res.image.col };
  }

  return ok({ storage_key: key, url: `/api/v1/media/${key}`, bytes: buf.length, mime: mime ?? null, attached });
}
