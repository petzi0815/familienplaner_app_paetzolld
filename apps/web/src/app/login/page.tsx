"use client";

import { useState } from "react";

export default function LoginPage() {
  const [pw, setPw] = useState("");
  const [err, setErr] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setErr("");
    const r = await fetch("/api/v1/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ password: pw }),
    });
    if (r.ok) {
      const next = new URLSearchParams(window.location.search).get("next") || "/";
      window.location.href = next.startsWith("/") ? next : "/";
    } else {
      setErr("Falsches Passwort.");
      setLoading(false);
    }
  }

  return (
    <main className="min-h-[100dvh] flex items-center justify-center bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7] px-6">
      <form onSubmit={submit} className="w-full max-w-sm bg-white rounded-3xl shadow-sm border border-black/5 p-7">
        <div className="text-4xl mb-3">🏡</div>
        <h1 className="text-xl font-extrabold text-[#1C1C1E] tracking-tight">Familie Paetzold-Stilke</h1>
        <p className="text-[#8E8E93] text-xs font-medium mb-5">Bitte anmelden</p>
        <input
          type="password"
          autoFocus
          value={pw}
          onChange={(e) => setPw(e.target.value)}
          placeholder="Familien-Passwort"
          className="w-full rounded-2xl bg-[#F2F2F7] border border-black/5 px-4 py-3 text-[15px] outline-none focus:ring-2 focus:ring-[#007AFF]/40"
        />
        {err && <p className="text-[#FF3B30] text-xs font-medium mt-2">{err}</p>}
        <button
          type="submit"
          disabled={loading || !pw}
          className="w-full mt-4 rounded-2xl bg-[#007AFF] text-white font-bold py-3 text-[15px] active:scale-[0.98] transition disabled:opacity-50"
        >
          {loading ? "…" : "Anmelden"}
        </button>
      </form>
    </main>
  );
}
