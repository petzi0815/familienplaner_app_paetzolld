// Client-seitiger API-Helfer (Session-Cookie wird automatisch mitgeschickt).

export async function apiGet<T = unknown>(path: string): Promise<T> {
  const r = await fetch(`/api/v1${path}`, { credentials: "include", headers: { accept: "application/json" } });
  if (r.status === 401) { window.location.href = "/login"; throw new Error("unauthorized"); }
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json() as Promise<T>;
}

export async function apiSend<T = unknown>(path: string, method: "POST" | "PATCH" | "DELETE", body?: unknown): Promise<T> {
  const r = await fetch(`/api/v1${path}`, {
    method,
    credentials: "include",
    headers: { "content-type": "application/json" },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const data = (await r.json().catch(() => ({}))) as Record<string, unknown>;
  if (r.status === 401) { window.location.href = "/login"; throw new Error("unauthorized"); }
  if (!r.ok) throw new Error((data.error as { message?: string })?.message ?? `HTTP ${r.status}`);
  return data as T;
}
