import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, created, notFound, unauthorized, forbidden } from "@/server/http/respond";
import { mediaFor, saveMedia, getItemRow, logProc, readUploadBuffer } from "@/server/fotobox/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;
type Ctx = { params: Promise<{ id: string }> };

// GET  /api/v1/fotobox-items/{id}/media — Medien eines Items auflisten.
export async function GET(req: Request, { params }: Ctx): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const { id } = await params;
  const db = getDb();
  if (!getItemRow(db, id)) return notFound("Fotobox-Item");
  const media = mediaFor(db, id);
  return ok({ data: media, total: media.length });
}

// POST /api/v1/fotobox-items/{id}/media — Bild anhängen (multipart 'file' ODER JSON data_base64).
export async function POST(req: Request, { params }: Ctx): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  const { id } = await params;
  const db = getDb();
  if (!getItemRow(db, id)) return notFound("Fotobox-Item");

  const read = await readUploadBuffer(req);
  if ("error" in read) return read.error;
  const { buf, mime, filename, extra } = read;
  const media = saveMedia(db, id, {
    buf, mime, filename,
    order: extra.order != null ? Number(extra.order) : undefined,
    width: extra.width != null ? Number(extra.width) : null,
    height: extra.height != null ? Number(extra.height) : null,
    createdAtOriginal: extra.created_at_original ?? null,
  });
  db.prepare("UPDATE fotobox_items SET updated_at=? WHERE id=?").run(new Date().toISOString(), id);
  logProc(db, id, auth.actor, "media_added", { media_id: media.media_id });
  return created(media);
}
