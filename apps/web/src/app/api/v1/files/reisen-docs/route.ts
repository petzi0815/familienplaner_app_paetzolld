import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { reindexRow } from "@/server/db/fts";
import { resourceByKey } from "@/server/domains/registry";
import { unauthorized, forbidden, fail, created } from "@/server/http/respond";

// Upload eines Reise-Dokuments als BLOB. multipart: trip_id, name?, doc_type?, file.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let form: FormData;
  try { form = await req.formData(); } catch { return fail("bad_form", "multipart/form-data erwartet.", 400); }
  const tripId = Number(form.get("trip_id"));
  const file = form.get("file");
  if (!tripId) return fail("no_trip", "Feld 'trip_id' erforderlich.", 400);
  if (!(file instanceof File)) return fail("no_file", "Feld 'file' fehlt.", 400);

  const buf = Buffer.from(await file.arrayBuffer());
  const name = String(form.get("name") || file.name);
  const docType = String(form.get("doc_type") || "sonstig");
  const db = getDb();
  const info = db.prepare(
    "INSERT INTO reisen_trip_docs (trip_id, name, doc_type, mime_type, file_data, file_size, created_at) VALUES (?,?,?,?,?,?,datetime('now'))",
  ).run(tripId, name, docType, file.type || "application/octet-stream", buf, buf.length);
  const id = Number(info.lastInsertRowid);
  db.prepare("INSERT INTO event_log (actor, action, domain, entity_id) VALUES (?,?,?,?)").run(auth.actor, "upload", "reisen-docs", String(id));
  const res = resourceByKey("reisen-docs"); if (res) reindexRow(db, res, id);
  return created({ id, trip_id: tripId, name, bytes: buf.length, download: `/api/v1/files/reisen-docs/${id}` });
}
