import { getAuth, hasRole } from "@/server/auth/auth";
import { buildTools, callTool } from "@/server/mcp/tools";
import { log } from "@/server/observability/logger";

// MCP-Server (Streamable HTTP) — im selben Prozess wie die REST-API.
// Auth: derselbe Bearer-Key wie /api/v1 (Rolle >= agent). Kein separater Mechanismus.
// Clients verbinden sich mit  POST <base>/api/mcp  und Header  Authorization: Bearer <API-Key>.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const PROTOCOL = "2025-06-18";
const SERVER_INFO = { name: "familienplaner", version: "1.0.0" };
const JSON_HEADERS = { "content-type": "application/json", "cache-control": "no-store" };

interface RpcMessage { jsonrpc?: string; id?: string | number | null; method?: string; params?: Record<string, unknown> }
const isNotification = (m: RpcMessage) => !("id" in m) || m.id === undefined || m.id === null;
const rpcError = (id: RpcMessage["id"], code: number, message: string) => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });
const rpcOk = (id: RpcMessage["id"], result: unknown) => ({ jsonrpc: "2.0", id, result });

async function handle(msg: RpcMessage, auth: import("@/server/auth/auth").Auth): Promise<object | null> {
  const method = msg.method ?? "";
  const notif = isNotification(msg);

  switch (method) {
    case "initialize":
      return rpcOk(msg.id, {
        protocolVersion: typeof msg.params?.protocolVersion === "string" ? msg.params.protocolVersion : PROTOCOL,
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER_INFO,
        instructions: "Familienplaner-Backend. Zuerst list_resources + resource_schema, dann list/get/create/update/delete. Schreib-Tools unterstützen dry_run. dashboard_today/reminders_due/search/foto_inbox_new für Alltag.",
      });
    case "ping":
      return rpcOk(msg.id, {});
    case "tools/list":
      return rpcOk(msg.id, { tools: buildTools() });
    case "tools/call": {
      const name = String(msg.params?.name ?? "");
      log.info("mcp tools/call", { tool: name, actor: auth.actor });
      const result = await callTool(name, msg.params?.arguments, auth);
      return rpcOk(msg.id, result);
    }
    default:
      if (method.startsWith("notifications/") || notif) return null; // Benachrichtigung — keine Antwort
      return rpcError(msg.id, -32601, `Method not found: ${method}`);
  }
}

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) {
    return Response.json(rpcError(null, -32001, "Authentifizierung erforderlich (Bearer API-Key, Rolle agent)."), { status: 401, headers: JSON_HEADERS });
  }

  let payload: unknown;
  try { payload = await req.json(); } catch { return Response.json(rpcError(null, -32700, "Parse error: ungültiges JSON."), { status: 400, headers: JSON_HEADERS }); }

  // Batch (Array) oder Einzelnachricht.
  if (Array.isArray(payload)) {
    const responses = (await Promise.all(payload.map((m) => handle(m as RpcMessage, auth)))).filter(Boolean);
    if (!responses.length) return new Response(null, { status: 202 });
    return Response.json(responses, { headers: JSON_HEADERS });
  }

  const resp = await handle(payload as RpcMessage, auth);
  if (!resp) return new Response(null, { status: 202 }); // reine Benachrichtigung
  return Response.json(resp, { headers: JSON_HEADERS });
}

// Kein server-initiierter SSE-Stream — GET wird nicht als Stream angeboten.
export function GET(): Response {
  return Response.json(rpcError(null, -32000, "Nur POST (JSON-RPC über Streamable HTTP)."), { status: 405, headers: { ...JSON_HEADERS, allow: "POST" } });
}
