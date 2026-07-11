import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, notFound } from "@/server/http/respond";

// Download eines Reise-Dokuments (BLOB) — auth via Session-Cookie (UI) oder Bearer.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const { id } = await params;
  const row = getDb().prepare("SELECT name, mime_type, file_data FROM reisen_trip_docs WHERE id=?").get(id) as
    | { name: string; mime_type: string | null; file_data: Buffer | null }
    | undefined;
  if (!row || !row.file_data) return notFound("Dokument");
  const filename = (row.name || `dokument-${id}`).replace(/[^a-z0-9._ -]/gi, "_");
  return new Response(new Uint8Array(row.file_data), {
    headers: {
      "content-type": row.mime_type || "application/octet-stream",
      "content-disposition": `inline; filename="${filename}"`,
      "cache-control": "private, max-age=3600",
    },
  });
}
