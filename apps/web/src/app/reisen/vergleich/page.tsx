'use client';
import { useState, useEffect } from 'react';
import Link from 'next/link';

interface Trip { id: number; title: string; destination: string; start_date: string; end_date: string; status: string; rating: number; hotel: string; cost_total: number; currency: string; participants: string; highlights: string; cover_image: string; tags: string; transport: string; }

export default function CompareTrips() {
  const [trips, setTrips] = useState<Trip[]>([]);
  const [sel, setSel] = useState<number[]>([]);

  useEffect(() => { fetch('/api/v1/reisen?limit=200', { credentials: 'include' }).then(r => r.json()).then(d => setTrips(d.data || [])).catch(() => {}); }, []);

  const selected = trips.filter(t => sel.includes(t.id));
  const toggle = (id: number) => setSel(prev => prev.includes(id) ? prev.filter(x => x !== id) : prev.length < 3 ? [...prev, id] : prev);
  const days = (t: Trip) => t.start_date && t.end_date ? Math.ceil((new Date(t.end_date).getTime() - new Date(t.start_date).getTime()) / 86400000) : 0;
  const fmtDate = (d: string) => d ? new Date(d + 'T12:00:00').toLocaleDateString('de-DE', { month: 'short', year: 'numeric' }) : '-';

  return (
    <main className="min-h-[100dvh] bg-gradient-to-br from-[#F2F2F7] via-[#E5E5EA] to-[#F2F2F7] pb-8">
      <header className="sticky top-0 z-50 bg-white/80 backdrop-blur-xl border-b border-black/5">
        <div className="max-w-4xl mx-auto px-4 py-3 flex items-center gap-3">
          <Link href="/reisen" className="text-blue-500 text-sm font-semibold">← Zurück</Link>
          <h1 className="text-lg font-extrabold text-[#1C1C1E] flex-1">🔄 Reise-Vergleich</h1>
        </div>
      </header>

      <div className="max-w-4xl mx-auto px-4 mt-4 space-y-4">
        {/* Trip Selector */}
        <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 p-4 shadow-sm">
          <h2 className="text-sm font-bold text-[#1C1C1E] mb-2">Reisen auswählen (max. 3)</h2>
          <div className="flex flex-wrap gap-2">
            {trips.map(t => (
              <button key={t.id} onClick={() => toggle(t.id)} className={`text-xs px-3 py-1.5 rounded-xl font-semibold transition ${sel.includes(t.id) ? 'bg-blue-500 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
                {t.destination || t.title} {t.start_date ? `(${fmtDate(t.start_date)})` : ''}
              </button>
            ))}
          </div>
        </div>

        {/* Comparison Table */}
        {selected.length >= 2 && (
          <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 shadow-sm overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-gray-100">
                    <th className="p-3 text-left text-xs text-[#8E8E93] font-semibold w-24">Merkmal</th>
                    {selected.map(t => (
                      <th key={t.id} className="p-3 text-center">
                        {t.cover_image && <img src={t.cover_image} alt="" className="w-full h-16 object-cover rounded-lg mb-1" />}
                        <Link href={`/reisen/${t.id}`} className="text-sm font-bold text-blue-600">{t.destination || t.title}</Link>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {[
                    { label: '📅 Zeitraum', fn: (t: Trip) => `${fmtDate(t.start_date)}${t.end_date ? ' – ' + fmtDate(t.end_date) : ''}` },
                    { label: '⏱️ Dauer', fn: (t: Trip) => days(t) ? `${days(t)} Tage` : '-' },
                    { label: '⭐ Bewertung', fn: (t: Trip) => t.rating ? '⭐'.repeat(t.rating) : '-' },
                    { label: '🏨 Hotel', fn: (t: Trip) => t.hotel || '-' },
                    { label: '💰 Kosten', fn: (t: Trip) => t.cost_total ? `${t.cost_total.toLocaleString('de-DE')} ${t.currency || 'EUR'}` : '-' },
                    { label: '👥 Teilnehmer', fn: (t: Trip) => t.participants || '-' },
                    { label: '🚗 Transport', fn: (t: Trip) => t.transport || '-' },
                    { label: '✨ Highlights', fn: (t: Trip) => t.highlights || '-' },
                    { label: '🏷️ Tags', fn: (t: Trip) => t.tags || '-' },
                  ].map(row => (
                    <tr key={row.label} className="border-b border-gray-50 hover:bg-gray-50/50">
                      <td className="p-3 text-xs text-[#8E8E93] font-semibold">{row.label}</td>
                      {selected.map(t => (
                        <td key={t.id} className="p-3 text-center text-xs text-[#1C1C1E]">{row.fn(t)}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {selected.length < 2 && (
          <div className="text-center text-[#8E8E93] text-sm py-8">Wähle mindestens 2 Reisen zum Vergleichen</div>
        )}
      </div>
    </main>
  );
}
