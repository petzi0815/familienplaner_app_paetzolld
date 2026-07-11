"use client";

export function LogoutButton() {
  async function logout() {
    await fetch("/api/v1/auth/logout", { method: "POST" });
    window.location.href = "/login";
  }
  return (
    <button
      onClick={logout}
      className="text-[#8E8E93] text-xs font-semibold px-3 py-1.5 rounded-full bg-white/70 border border-black/5 active:scale-95 transition"
    >
      Abmelden
    </button>
  );
}
