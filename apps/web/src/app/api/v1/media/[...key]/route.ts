import fs from "node:fs";
import path from "node:path";
import { config } from "@/server/config";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, notFound } from "@/server/http/respond";

// Stabile Media-Auslieferung aus $DATA_DIR/media/<key>. Auth via Session-Cookie (UI) oder Bearer.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MIME: Record<string, string> = {
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
  ".webp": "image/webp", ".gif": "image/gif", ".svg": "image/svg+xml", ".pdf": "application/pdf",
};

export async function GET(req: Request, { params }: { params: Promise<{ key: string[] }> }): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const { key } = await params;
  const rel = key.join("/");
  const root = path.resolve(config.mediaDir);
  const file = path.resolve(root, rel);
  if (!file.startsWith(root + path.sep)) return notFound("Media"); // Path-Traversal-Schutz
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) return notFound("Media");
  const buf = fs.readFileSync(file);
  const ct = MIME[path.extname(file).toLowerCase()] ?? "application/octet-stream";
  return new Response(new Uint8Array(buf), {
    headers: { "content-type": ct, "cache-control": "private, max-age=86400" },
  });
}
