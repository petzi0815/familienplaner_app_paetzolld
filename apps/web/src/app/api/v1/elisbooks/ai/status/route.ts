import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, unauthorized } from "@/server/http/respond";
import { hasOpenAI, openaiChat } from "@/server/elisbooks/openai";

// Debug: prüft, ob OPENAI_API_KEY im Backend gesetzt ist. Mit ?test=1 ein winziger Live-Call (verifiziert den Key).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: Request): Promise<Response> {
  if (!hasRole(getAuth(req), "agent")) return unauthorized();
  const configured = hasOpenAI();
  const wantTest = new URL(req.url).searchParams.get("test") === "1";
  const endpoints = [
    "/api/v1/elisbooks/ai/shelf-ocr",
    "/api/v1/elisbooks/ai/recommendations",
    "/api/v1/elisbooks/ai/metadata-cleaner",
    "/api/v1/elisbooks/ai/metadata-enhancer",
  ];
  if (!configured) return ok({ configured: false, note: "OPENAI_API_KEY nicht gesetzt — KI-Endpunkte liefern 501.", endpoints });
  if (!wantTest) return ok({ configured: true, note: "OPENAI_API_KEY gesetzt. ?test=1 für einen Live-Check.", endpoints });
  try {
    const text = await openaiChat("Antworte nur mit dem Wort: ok", { model: "gpt-4o", maxTokens: 5 });
    return ok({ configured: true, live_test: { ok: /ok/i.test(text), reply: text.trim().slice(0, 40) }, endpoints });
  } catch (e) {
    return ok({ configured: true, live_test: { ok: false, error: String((e as Error)?.message ?? e).slice(0, 200) }, endpoints });
  }
}
