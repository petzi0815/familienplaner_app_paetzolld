import Link from "next/link";
import { notFound } from "next/navigation";
import { RESOURCES } from "@/server/domains/registry";
import { getDb } from "@/server/db/connection";
import { ResourceBrowser } from "@/components/ResourceBrowser";

export const dynamic = "force-dynamic";

const DOMAIN_TITLE: Record<string, string> = {
  reisen: "Reisen", samu: "Samu", geschenkplaner: "Geschenkplaner", garten: "Garten",
  elisbooks: "Büchersammlung", smarthome: "Smart Home", vorratskammer: "Vorratskammer",
  wunschliste: "Wunschliste", reiniger: "Reiniger", ebooks: "E-Books", termine: "Termine",
  gypsi: "Gypsi", vertraege: "Verträge",
};

export default async function BereichPage({ params }: { params: Promise<{ key: string }> }) {
  const { key } = await params;
  const resources = RESOURCES.filter((r) => r.domain === key);
  if (!resources.length) notFound();

  // Einzel-Ressource → direkt der Browser.
  if (resources.length === 1) {
    const r = resources[0];
    return <ResourceBrowser resource={r.key} label={r.label} image={r.image ?? undefined} download={r.download} actions={r.actions} backHref="/" />;
  }

  // Mehrere Ressourcen → Unterkacheln mit Zählern.
  const db = getDb();
  const count = (table: string) => { try { return (db.prepare(`SELECT COUNT(*) c FROM "${table}"`).get() as { c: number }).c; } catch { return 0; } };

  return (
    <main className="min-h-[100dvh] bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7]">
      <header className="pt-10 pb-3 px-4 safe-area-inset max-w-3xl mx-auto">
        <Link href="/" className="text-[#007AFF] text-sm font-semibold">‹ Übersicht</Link>
        <h1 className="text-2xl font-extrabold text-[#1C1C1E] tracking-tight mt-2">{DOMAIN_TITLE[key] ?? key}</h1>
      </header>
      <div className="max-w-3xl mx-auto px-3 pb-10">
        <div className="grid grid-cols-2 gap-2.5">
          {resources.map((r) => (
            <Link key={r.key} href={`/liste/${r.key}`} className="bg-white rounded-2xl border border-black/5 shadow-sm p-4 active:scale-[0.98] transition flex flex-col justify-between min-h-[84px]">
              <div className="text-[15px] font-bold text-[#1C1C1E] leading-tight">{r.label}</div>
              <div className="text-[12px] text-[#8E8E93] mt-1">{count(r.table)} Einträge ›</div>
            </Link>
          ))}
        </div>
      </div>
    </main>
  );
}
