'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';

const CAT_EMOJI: Record<string, string> = { event: '🎪', kultur: '🏛️', natur: '🌿', aktivitaet: '🏊', gastro: '🍽️', sport: '⚽', shopping: '🛍️' };
const CAT_COLOR: Record<string, string> = { event: 'from-purple-400 to-pink-500', kultur: 'from-amber-400 to-orange-500', natur: 'from-green-400 to-emerald-600', aktivitaet: 'from-blue-400 to-cyan-500', gastro: 'from-orange-400 to-red-500' };

function TipCard({ tip: t }: { tip: any }) {
  const [open, setOpen] = useState(false);
  const cat = t.category || 'event';
  return (
    <div className={`rounded-2xl overflow-hidden border shadow-sm ${t.is_event ? 'bg-purple-50/60 border-purple-200/40' : 'bg-white/70 border-gray-200/40'}`}>
      <button onClick={() => setOpen(!open)} className="w-full text-left p-3.5 flex items-start gap-3 transition">
        {t.image_url ? (
          <img src={t.image_url} alt={t.title} className="w-14 h-14 rounded-xl object-cover flex-shrink-0" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
        ) : (
          <div className={`w-14 h-14 rounded-xl bg-gradient-to-br ${CAT_COLOR[cat] || 'from-gray-200 to-gray-300'} flex items-center justify-center flex-shrink-0 text-2xl`}>{CAT_EMOJI[cat] || '💡'}</div>
        )}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5 mb-0.5">
            {t.is_event ? <span className="text-[10px] bg-purple-200 text-purple-800 px-1.5 py-0.5 rounded-full font-bold">EVENT</span> : null}
            <h4 className="text-sm font-bold text-[#1C1C1E] leading-tight truncate">{t.title}</h4>
          </div>
          <p className="text-[11px] text-[#636366] line-clamp-2">{t.description}</p>
          <div className="flex flex-wrap gap-1 mt-1.5">
            {t.location && <span className="text-[10px] bg-blue-50 text-blue-600 px-1.5 py-0.5 rounded-full">📍 {t.location}</span>}
            {t.date_info && <span className="text-[10px] bg-purple-50 text-purple-600 px-1.5 py-0.5 rounded-full">📅 {t.date_info}</span>}
            {t.price && <span className="text-[10px] bg-green-50 text-green-600 px-1.5 py-0.5 rounded-full">💰 {t.price}</span>}
            {t.distance_from_home && <span className="text-[10px] bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded-full">🚗 {t.distance_from_home}</span>}
            {t.kid_friendly ? <span className="text-[10px] bg-pink-50 text-pink-600 px-1.5 py-0.5 rounded-full">👶</span> : null}
          </div>
        </div>
        <span className={`text-[#C7C7CC] text-sm transition-transform ${open ? 'rotate-90' : ''}`}>▸</span>
      </button>
      {open && (
        <div className="px-4 pb-4 space-y-2.5 border-t border-gray-100/50 pt-3">
          {t.details && <p className="text-xs text-[#636366] leading-relaxed whitespace-pre-wrap">{t.details}</p>}
          {t.address && <div className="text-xs"><b className="text-[#1C1C1E]">📮 Adresse:</b> <span className="text-[#636366]">{t.address}</span></div>}
          {t.opening_hours && <div className="text-xs"><b className="text-[#1C1C1E]">🕐</b> <span className="text-[#636366]">{t.opening_hours}</span></div>}
          {t.kid_notes && <div className="bg-pink-50 rounded-xl p-2.5 text-xs"><b className="text-pink-700">👶 Kinder:</b> <span className="text-pink-800"> {t.kid_notes}</span></div>}
          {t.tips && <div className="bg-blue-50 rounded-xl p-2.5 text-xs"><b className="text-blue-700">💡 Tipp:</b> <span className="text-blue-800"> {t.tips}</span></div>}
          {t.indoor_alternative && <div className="bg-purple-50 rounded-xl p-2.5 text-xs"><b className="text-purple-700">🌧️ Bei Regen:</b> <span className="text-purple-800"> {t.indoor_alternative}</span></div>}
          <div className="flex flex-wrap gap-2">
            {t.google_maps_url && <a href={t.google_maps_url} target="_blank" rel="noopener" className="text-xs font-semibold text-green-600 bg-green-50 px-2.5 py-1 rounded-lg">📍 Maps</a>}
            {(t.lat && t.lng) && <a href={`https://www.google.com/maps/dir/?api=1&destination=${t.lat},${t.lng}`} target="_blank" rel="noopener" className="text-xs font-semibold text-green-600 bg-green-50 px-2.5 py-1 rounded-lg">🧭 Route</a>}
            {t.website_url && <a href={t.website_url} target="_blank" rel="noopener" className="text-xs font-semibold text-blue-600 bg-blue-50 px-2.5 py-1 rounded-lg">🔗 Website</a>}
            {t.url && !t.website_url && <a href={t.url} target="_blank" rel="noopener" className="text-xs font-semibold text-blue-600 bg-blue-50 px-2.5 py-1 rounded-lg">🔗 Mehr Info</a>}
          </div>
        </div>
      )}
    </div>
  );
}

export default function WeekendDetailPage() {
  const router = useRouter();
  const { id } = useParams();
  const [tips, setTips] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  // id can be "2026-11" (year-week) or just a numeric tip id
  const isGrouped = typeof id === 'string' && id.includes('-');

  useEffect(() => {
    if (isGrouped) {
      const [year, week] = (id as string).split('-').map(Number);
      fetch(`/api/reisen?mode=weekend&year=${year}&week=${week}`)
        .then(r => r.json())
        .then(data => { setTips(Array.isArray(data) ? data.filter((t: any) => t.calendar_week === week) : []); })
        .catch(() => {})
        .finally(() => setLoading(false));
    } else {
      // Single tip by id
      fetch(`/api/reisen/wochenende/${id}`)
        .then(r => r.json())
        .then(data => { setTips([data]); })
        .catch(() => {})
        .finally(() => setLoading(false));
    }
  }, [id, isGrouped]);

  if (loading) return (
    <main className="min-h-screen bg-gradient-to-br from-[#F0F5FF] via-[#FFF5F0] to-[#F5F0FF] flex items-center justify-center">
      <div className="text-4xl animate-bounce">🎪</div>
    </main>
  );

  const events = tips.filter(t => t.is_event);
  const evergreen = tips.filter(t => !t.is_event);
  const week = tips[0]?.calendar_week || 0;
  const year = tips[0]?.year || 2026;

  // Calculate date range
  const jan4 = new Date(year, 0, 4);
  const dayOfWeek = jan4.getDay() || 7;
  const monday = new Date(jan4);
  monday.setDate(jan4.getDate() - dayOfWeek + 1 + (week - 1) * 7);
  const sat = new Date(monday); sat.setDate(monday.getDate() + 5);
  const sun = new Date(monday); sun.setDate(monday.getDate() + 6);
  const dateRange = `${sat.toLocaleDateString('de-DE', { day: '2-digit', month: 'long' })} – ${sun.toLocaleDateString('de-DE', { day: '2-digit', month: 'long', year: 'numeric' })}`;

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#F0F5FF] via-[#FFF5F0] to-[#F5F0FF]">
      {/* Hero */}
      <div className="relative h-40 overflow-hidden bg-gradient-to-br from-amber-400 via-orange-400 to-red-400">
        <div className="absolute inset-0 bg-gradient-to-t from-black/50 via-transparent to-transparent" />
        <button onClick={() => router.push('/reisen')} className="absolute top-12 left-5 z-10 w-10 h-10 bg-white/20 backdrop-blur-md rounded-2xl flex items-center justify-center">
          <svg className="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" /></svg>
        </button>
        <div className="absolute bottom-0 left-0 right-0 p-5">
          <div className="flex items-center gap-3">
            <div className="w-14 h-14 bg-white/20 backdrop-blur-md rounded-xl flex items-center justify-center">
              <span className="text-white text-xl font-black">KW{week}</span>
            </div>
            <div>
              <h1 className="text-xl font-extrabold text-white drop-shadow-md">Wochenende</h1>
              <p className="text-white/80 text-sm font-medium">{dateRange}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-2xl mx-auto px-5 pb-16 -mt-2 space-y-4">

        {/* Summary */}
        <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 p-4 shadow-sm">
          <div className="flex gap-3">
            {events.length > 0 && <span className="text-sm bg-purple-100 text-purple-700 px-3 py-1.5 rounded-xl font-semibold">🎪 {events.length} Event{events.length > 1 ? 's' : ''}</span>}
            <span className="text-sm bg-green-100 text-green-700 px-3 py-1.5 rounded-xl font-semibold">🌿 {evergreen.length} Tipp{evergreen.length > 1 ? 's' : ''}</span>
            <span className="text-sm bg-blue-100 text-blue-700 px-3 py-1.5 rounded-xl font-semibold">📍 {tips.length} gesamt</span>
          </div>
        </div>

        {/* Events — priority! */}
        {events.length > 0 && (
          <div>
            <h3 className="text-xs font-bold text-purple-600 uppercase tracking-wider mb-2 px-1">🎪 Events dieses Wochenende</h3>
            <div className="space-y-2.5">
              {events.map(t => <TipCard key={t.id} tip={t} />)}
            </div>
          </div>
        )}

        {/* Evergreen */}
        {evergreen.length > 0 && (
          <div>
            <h3 className="text-xs font-bold text-[#8E8E93] uppercase tracking-wider mb-2 px-1">🌿 Immer möglich</h3>
            <div className="space-y-2.5">
              {evergreen.map(t => <TipCard key={t.id} tip={t} />)}
            </div>
          </div>
        )}

        {tips.length === 0 && (
          <div className="text-center py-12">
            <div className="text-5xl mb-3">🎪</div>
            <p className="text-[#8E8E93]">Keine Tipps für dieses Wochenende</p>
          </div>
        )}
      </div>
    </main>
  );
}
