import fs from "node:fs";
import path from "node:path";
import { config } from "@/server/config";
import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { notFound, unauthorized } from "@/server/http/respond";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Ctx = { params: Promise<{ id: string; mediaId: string }> };

const MIME: Record<string, string> = {
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
  ".webp": "image/webp", ".gif": "image/gif", ".heic": "image/heic", ".pdf": "application/pdf",
};

// GET /api/v1/fotobox-items/{id}/media/{media_id} — Originalbild eines Item-Mediums ausliefern.
export async function GET(req: Request, { params }: Ctx): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const { id, mediaId } = await params;
  const db = getDb();
  const row = db.prepare("SELECT storage_key, mime_type FROM fotobox_item_media WHERE id=? AND item_id=?").get(mediaId, id) as
    | { storage_key: string; mime_type: string | null }
    | undefined;
  if (!row) return notFound("Medium");
  const root = path.resolve(config.mediaDir);
  const file = path.resolve(root, row.storage_key);
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) return notFound("Bilddatei");
  const buf = fs.readFileSync(file);
  const ct = row.mime_type || MIME[path.extname(file).toLowerCase()] || "application/octet-stream";
  return new Response(new Uint8Array(buf), { headers: { "content-type": ct, "cache-control": "private, max-age=86400" } });
}
