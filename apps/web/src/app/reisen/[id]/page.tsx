'use client';

import { useState, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import { apiGet, apiSend } from '@/lib/api';
const TripMap = dynamic(() => import('./TripMap'), { ssr: false, loading: () => <div className="w-full h-[350px] rounded-2xl bg-gray-100 animate-pulse" /> });

interface Trip {
  id: number; title: string; type: string; status: string; start_date: string | null; end_date: string | null;
  destination: string | null; country: string | null; region: string | null; lat: number | null; lng: number | null;
  hotel: string | null; hotel_url: string | null; booking_ref: string | null; booking_platform: string | null;
  flight: string | null; flight_ref: string | null; transport: string | null; budget: string | null; cost_total: string | null;
  participants: string; activities: string | null; highlights: string | null; rating: number | null;
  cover_image: string | null; notes: string | null; tags: string | null;
  doc_count?: number; link_count?: number; docs?: any[]; links?: any[];
}

const TYPE_EMOJI: Record<string, string> = { urlaub: '🏖️', staedtereise: '🏙️', aktivitaet: '🎪', segeln: '⛵', tauchen: '🤿', wandern: '🥾', wellness: '🧖', kreuzfahrt: '🚢', tagesausflug: '🚗', wochenende: '💡' };
const DOC_EMOJI: Record<string, string> = { ticket: '🎫', buchung: '📄', rechnung: '💰', reisepass: '🛂', versicherung: '🛡️', karte: '🗺️', foto: '📸', sonstig: '📎' };
const ACT_CAT_EMOJI: Record<string, string> = { sehenswuerdigkeit: '🏛️', natur: '🌿', strand: '🏖️', kultur: '🎭', sport: '🏊', shopping: '🛍️', tour: '🚌' };
const EMAIL_CAT_EMOJI: Record<string, string> = { buchung: '📋', versicherung: '🛡️', allgemein: '📧', hotel: '🏨', flug: '✈️' };

function mapsUrl(lat: number, lng: number) { return `https://www.google.com/maps?q=${lat},${lng}`; }
function routeUrl(lat: number, lng: number) { return `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`; }
function formatDate(d: string | null) { return d ? new Date(d + 'T00:00:00').toLocaleDateString('de-DE', { day: '2-digit', month: 'long', year: 'numeric' }) : ''; }
function daysUntil(d: string) { const now = new Date(); now.setHours(0,0,0,0); return Math.ceil((new Date(d+'T00:00:00').getTime() - now.getTime()) / 86400000); }

/* ── Collapsible Section wrapper ── */
function Section({ title, emoji, count, children, defaultOpen = false, color = 'gray' }: { title: string; emoji: string; count?: number | string; children: React.ReactNode; defaultOpen?: boolean; color?: string }) {
  const [open, setOpen] = useState(defaultOpen);
  const borderColor: Record<string, string> = { gray: 'border-gray-200/50', sky: 'border-sky-200/50', cyan: 'border-cyan-200/50', blue: 'border-blue-200/50', orange: 'border-orange-200/50', pink: 'border-pink-200/50', green: 'border-green-200/50', red: 'border-red-200/50', purple: 'border-purple-200/50' };
  return (
    <div className={`bg-white/80 backdrop-blur-sm rounded-2xl border ${borderColor[color] || borderColor.gray} shadow-sm overflow-hidden`}>
      <button onClick={() => setOpen(!open)} className="w-full text-left px-4 py-3.5 flex items-center gap-2 active:bg-gray-50/50 transition">
        <span className="text-base">{emoji}</span>
        <span className="font-bold text-[#1C1C1E] text-sm flex-1">{title}</span>
        {count !== undefined && <span className="text-[10px] text-[#8E8E93] bg-gray-100 px-2 py-0.5 rounded-full">{count}</span>}
        <span className={`text-[#C7C7CC] text-sm transition-transform duration-200 ${open ? 'rotate-90' : ''}`}>▸</span>
      </button>
      {open && <div className="px-4 pb-4 border-t border-gray-100/50 pt-3">{children}</div>}
    </div>
  );
}

/* ── Flight Card ── */
const STATUS_MAP: Record<string, { label: string; color: string; bg: string }> = {
  scheduled: { label: 'Geplant', color: 'text-blue-700', bg: 'bg-blue-100' },
  checkin: { label: 'Check-in offen', color: 'text-green-700', bg: 'bg-green-100' },
  boarding: { label: 'Boarding', color: 'text-amber-700', bg: 'bg-amber-100' },
  departed: { label: 'Gestartet', color: 'text-sky-700', bg: 'bg-sky-100' },
  arrived: { label: 'Gelandet', color: 'text-green-700', bg: 'bg-green-100' },
  delayed: { label: 'Verspätet', color: 'text-red-700', bg: 'bg-red-100' },
  cancelled: { label: 'Storniert', color: 'text-red-700', bg: 'bg-red-200' },
};

function FlightCard({ flight: f }: { flight: any }) {
  const [open, setOpen] = useState(false);
  const st = STATUS_MAP[f.status] || STATUS_MAP.scheduled;
  const depDate = f.departure_time ? new Date(f.departure_time + (f.departure_time.includes('T') ? '' : 'T00:00:00')) : null;
  const arrDate = f.arrival_time ? new Date(f.arrival_time + (f.arrival_time.includes('T') ? '' : 'T00:00:00')) : null;
  const fmtDate = (d: Date) => d.toLocaleDateString('de-DE', { weekday: 'short', day: '2-digit', month: '2-digit' });
  const fmtTime = (d: Date) => d.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
  const hasTime = f.departure_time?.includes('T');
  const isOutbound = f.direction === 'outbound';
  const trackerUrl = f.flight_number ? `https://www.flightradar24.com/${f.flight_number.replace(/\s/g, '')}` : null;
  const flightAwareUrl = f.flight_number ? `https://flightaware.com/live/flight/${f.flight_number.replace(/\s/g, '')}` : null;

  return (
    <div className={`rounded-2xl overflow-hidden border shadow-sm ${isOutbound ? 'bg-sky-50/40 border-sky-200/40' : 'bg-indigo-50/40 border-indigo-200/40'}`}>
      <button onClick={() => setOpen(!open)} className="w-full text-left p-4 flex items-start gap-3 transition">
        <div className={`w-14 h-14 rounded-xl bg-gradient-to-br ${isOutbound ? 'from-sky-400 to-blue-500' : 'from-indigo-400 to-purple-500'} flex items-center justify-center flex-shrink-0`}>
          <span className="text-2xl">{isOutbound ? '🛫' : '🛬'}</span>
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-sm font-bold text-[#1C1C1E]">{isOutbound ? 'Hinflug' : 'Rückflug'}</span>
            <span className={`text-[10px] ${st.color} ${st.bg} px-1.5 py-0.5 rounded-full font-bold`}>{st.label}</span>
            {f.delay_minutes && f.delay_minutes > 0 && <span className="text-[10px] bg-red-100 text-red-700 px-1.5 py-0.5 rounded-full font-bold">+{f.delay_minutes} Min</span>}
          </div>
          {/* Route visualization */}
          <div className="flex items-center gap-2 mb-1">
            <div className="text-center">
              <span className="text-lg font-black text-[#1C1C1E]">{f.departure_code || '???'}</span>
              {hasTime && depDate && <span className="text-xs font-bold text-[#1C1C1E] block">{fmtTime(depDate)}</span>}
              {hasTime && <span className="text-[9px] text-[#8E8E93] block">Ortszeit</span>}
            </div>
            <div className="flex-1 flex flex-col items-center gap-0.5 px-1">
              <div className="flex items-center w-full gap-1">
                <div className="h-[2px] flex-1 bg-gradient-to-r from-sky-300 to-indigo-300 rounded" />
                <span className="text-xs text-[#8E8E93]">✈️</span>
                <div className="h-[2px] flex-1 bg-gradient-to-r from-indigo-300 to-sky-300 rounded" />
              </div>
              {f.duration && <span className="text-[9px] font-semibold text-[#8E8E93]">{f.duration}</span>}
            </div>
            <div className="text-center">
              <span className="text-lg font-black text-[#1C1C1E]">{f.arrival_code || '???'}</span>
              {hasTime && arrDate && <span className="text-xs font-bold text-[#1C1C1E] block">{fmtTime(arrDate)}</span>}
              {hasTime && <span className="text-[9px] text-[#8E8E93] block">Ortszeit</span>}
            </div>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {depDate && <span className="text-[10px] bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded-full">📅 {fmtDate(depDate)}</span>}
            {f.airline && <span className="text-[10px] bg-blue-50 text-blue-600 px-1.5 py-0.5 rounded-full">✈️ {f.airline}</span>}
            {f.flight_number && <span className="text-[10px] bg-sky-50 text-sky-700 px-1.5 py-0.5 rounded-full font-mono">{f.flight_number}</span>}
          </div>
        </div>
        <span className={`text-[#C7C7CC] text-sm transition-transform ${open ? 'rotate-90' : ''}`}>▸</span>
      </button>
      {open && (
        <div className="px-4 pb-4 space-y-2.5 border-t border-gray-100/50 pt-3">
          {/* Details Grid */}
          <div className="grid grid-cols-2 gap-2">
            {f.departure_airport && (
              <div className="bg-white/60 rounded-lg p-2">
                <span className="text-[9px] text-[#8E8E93] block">Abflug</span>
                <span className="text-xs font-semibold text-[#1C1C1E]">{f.departure_airport} ({f.departure_code})</span>
                {f.terminal && <span className="text-[10px] text-[#636366] block">Terminal {f.terminal}</span>}
                {f.gate && <span className="text-[10px] text-[#636366] block">Gate {f.gate}</span>}
              </div>
            )}
            {f.arrival_airport && (
              <div className="bg-white/60 rounded-lg p-2">
                <span className="text-[9px] text-[#8E8E93] block">Ankunft</span>
                <span className="text-xs font-semibold text-[#1C1C1E]">{f.arrival_airport} ({f.arrival_code})</span>
                {f.baggage_belt && <span className="text-[10px] text-[#636366] block">Gepäck: Band {f.baggage_belt}</span>}
              </div>
            )}
            {f.seat_info && (
              <div className="bg-white/60 rounded-lg p-2">
                <span className="text-[9px] text-[#8E8E93] block">Sitzplätze</span>
                <span className="text-xs font-semibold text-[#1C1C1E]">{f.seat_info}</span>
              </div>
            )}
            {f.aircraft_type && (
              <div className="bg-white/60 rounded-lg p-2">
                <span className="text-[9px] text-[#8E8E93] block">Flugzeug</span>
                <span className="text-xs font-semibold text-[#1C1C1E]">{f.aircraft_type}</span>
              </div>
            )}
            {f.booking_ref && (
              <div className="bg-white/60 rounded-lg p-2">
                <span className="text-[9px] text-[#8E8E93] block">Buchungsnr.</span>
                <span className="text-xs font-semibold text-[#1C1C1E] font-mono">{f.booking_ref}</span>
              </div>
            )}
          </div>
          {f.notes && <div className="bg-amber-50 rounded-lg p-2.5 text-xs"><b className="text-amber-700">ℹ️ Info:</b> <span className="text-amber-800"> {f.notes}</span></div>}
          {/* Action Buttons */}
          <div className="flex flex-wrap gap-2">
            {trackerUrl && <a href={trackerUrl} target="_blank" rel="noopener" className="text-xs font-semibold text-sky-600 bg-sky-50 px-3 py-1.5 rounded-lg hover:bg-sky-100 transition">📡 Flightradar24</a>}
            {flightAwareUrl && <a href={flightAwareUrl} target="_blank" rel="noopener" className="text-xs font-semibold text-blue-600 bg-blue-50 px-3 py-1.5 rounded-lg hover:bg-blue-100 transition">🔍 FlightAware</a>}
            {f.checkin_url && <a href={f.checkin_url} target="_blank" rel="noopener" className="text-xs font-semibold text-green-600 bg-green-50 px-3 py-1.5 rounded-lg hover:bg-green-100 transition">✅ Online Check-in</a>}
          </div>
        </div>
      )}
    </div>
  );
}

/* ── Sub-item cards ── */
function DivingCard({ dive: d }: { dive: any }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="bg-cyan-50/40 rounded-xl overflow-hidden">
      <button onClick={() => setOpen(!open)} className="w-full text-left p-3 flex items-start gap-3 active:bg-cyan-50/60 transition">
        <div className="w-12 h-12 rounded-lg bg-gradient-to-br from-cyan-100 to-blue-200 flex items-center justify-center flex-shrink-0 text-xl">🤿</div>
        <div className="flex-1 min-w-0">
          <h4 className="text-sm font-bold text-[#1C1C1E] leading-tight">{d.dive_center_name}</h4>
          <p className="text-[11px] text-[#636366] mt-0.5 line-clamp-2">{d.description}</p>
          <div className="flex flex-wrap gap-1 mt-1">
            {d.certifications && <span className="text-[10px] bg-cyan-50 text-cyan-700 px-1.5 py-0.5 rounded-full">🎓 {d.certifications}</span>}
            {d.price_range && <span className="text-[10px] bg-green-50 text-green-600 px-1.5 py-0.5 rounded-full">💰 {d.price_range}</span>}
          </div>
        </div>
        <span className={`text-[#8E8E93] text-xs transition-transform ${open ? 'rotate-90' : ''}`}>▸</span>
      </button>
      {open && (
        <div className="px-3 pb-3 space-y-2 border-t border-cyan-100 pt-2">
          {d.highlights && <div className="text-xs"><b className="text-cyan-700">🌊 Highlights:</b> <span className="text-[#636366]">{d.highlights}</span></div>}
          {d.conditions && <div className="bg-sky-50 rounded-lg p-2.5 text-xs"><b className="text-sky-700">🌡️ Bedingungen:</b> <span className="text-sky-800"> {d.conditions}</span></div>}
          {d.kid_notes && <div className="bg-pink-50 rounded-lg p-2.5 text-xs"><b className="text-pink-700">👶 Familie:</b> <span className="text-pink-800"> {d.kid_notes}</span></div>}
          {d.tips && <div className="bg-cyan-50 rounded-lg p-2.5 text-xs"><b className="text-cyan-700">💡 Tipp:</b> <span className="text-cyan-800"> {d.tips}</span></div>}
          <div className="flex flex-wrap gap-2">
            {d.google_maps_url && <a href={d.google_maps_url} target="_blank" rel="noopener" className="text-xs font-semibold text-green-600 bg-green-50 px-2.5 py-1 rounded-lg">📍 Maps</a>}
            {d.tripadvisor_url && <a href={d.tripadvisor_url} target="_blank" rel="noopener" className="text-xs font-semibold text-emerald-600 bg-emerald-50 px-2.5 py-1 rounded-lg">⭐ TripAdvisor</a>}
            {d.website_url && <a href={d.website_url} target="_blank" rel="noopener" className="text-xs font-semibold text-blue-600 bg-blue-50 px-2.5 py-1 rounded-lg">🔗 Website</a>}
          </div>
        </div>
      )}
    </div>
  );
}

function ActivityCard({ activity: a }: { activity: any }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="bg-blue-50/30 rounded-xl overflow-hidden">
      <button onClick={() => setOpen(!open)} className="w-full text-left p-3 flex items-start gap-3 active:bg-blue-50/50 transition">
        {a.image_url ? (
          <img src={a.image_url} alt={a.title} className="w-12 h-12 rounded-lg object-cover flex-shrink-0" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
        ) : (
          <div className="w-12 h-12 rounded-lg bg-gradient-to-br from-blue-100 to-indigo-100 flex items-center justify-center flex-shrink-0 text-xl">{ACT_CAT_EMOJI[a.category] || '🎯'}</div>
        )}
        <div className="flex-1 min-w-0">
          <h4 className="text-sm font-bold text-[#1C1C1E] leading-tight">{a.title}</h4>
          <p className="text-[11px] text-[#636366] mt-0.5 line-clamp-2">{a.description}</p>
          <div className="flex flex-wrap gap-1 mt-1">
            {a.duration && <span className="text-[10px] bg-blue-50 text-blue-600 px-1.5 py-0.5 rounded-full">⏱️ {a.duration}</span>}
            {a.price && <span className="text-[10px] bg-green-50 text-green-600 px-1.5 py-0.5 rounded-full">💰 {a.price}</span>}
            {a.kid_friendly ? <span className="text-[10px] bg-pink-50 text-pink-600 px-1.5 py-0.5 rounded-full">👶</span> : null}
          </div>
        </div>
        <span className={`text-[#8E8E93] text-xs transition-transform ${open ? 'rotate-90' : ''}`}>▸</span>
      </button>
      {open && (
        <div className="px-3 pb-3 space-y-2 border-t border-blue-100 pt-2">
          {a.details && <p className="text-xs text-[#636366] leading-relaxed whitespace-pre-wrap">{a.details}</p>}
          {a.kid_notes && <div className="bg-pink-50 rounded-lg p-2.5 text-xs"><b className="text-pink-700">👶 Kinder-Info:</b> <span className="text-pink-800"> {a.kid_notes}</span></div>}
          {a.best_time && <div className="bg-amber-50 rounded-lg p-2.5 text-xs"><b className="text-amber-700">⏰ Beste Zeit:</b> <span className="text-amber-800"> {a.best_time}</span></div>}
          {a.tips && <div className="bg-blue-50 rounded-lg p-2.5 text-xs"><b className="text-blue-700">💡 Tipp:</b> <span className="text-blue-800"> {a.tips}</span></div>}
          <div className="flex flex-wrap gap-2">
            {a.google_maps_url && <a href={a.google_maps_url} target="_blank" rel="noopener" className="text-xs font-semibold text-green-600 bg-green-50 px-2.5 py-1 rounded-lg">📍 Maps</a>}
            {a.tripadvisor_url && <a href={a.tripadvisor_url} target="_blank" rel="noopener" className="text-xs font-semibold text-emerald-600 bg-emerald-50 px-2.5 py-1 rounded-lg">⭐ TripAdvisor</a>}
            {a.website_url && <a href={a.website_url} target="_blank" rel="noopener" className="text-xs font-semibold text-blue-600 bg-blue-50 px-2.5 py-1 rounded-lg">🔗 Website</a>}
          </div>
        </div>
      )}
    </div>
  );
}

function RestaurantCard({ restaurant: r }: { restaurant: any }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="bg-orange-50/30 rounded-xl overflow-hidden">
      <button onClick={() => setOpen(!open)} className="w-full text-left p-3 flex items-start gap-3 active:bg-orange-50/50 transition">
        {r.image_url ? (
          <img src={r.image_url} alt={r.name} className="w-12 h-12 rounded-lg object-cover flex-shrink-0" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
        ) : (
          <div className="w-12 h-12 rounded-lg bg-gradient-to-br from-orange-100 to-red-100 flex items-center justify-center flex-shrink-0 text-xl">🍽️</div>
        )}
        <div className="flex-1 min-w-0">
          <h4 className="text-sm font-bold text-[#1C1C1E] leading-tight">{r.name}</h4>
          {r.cuisine && <p className="text-[10px] text-[#8E8E93] font-medium">{r.cuisine}</p>}
          <p className="text-[11px] text-[#636366] mt-0.5 line-clamp-2">{r.description}</p>
          <div className="flex flex-wrap gap-1 mt-1">
            {r.price_range && <span className="text-[10px] bg-green-50 text-green-600 px-1.5 py-0.5 rounded-full">💰 {r.price_range}</span>}
            {r.kid_friendly ? <span className="text-[10px] bg-pink-50 text-pink-600 px-1.5 py-0.5 rounded-full">👶</span> : <span className="text-[10px] bg-gray-100 text-gray-500 px-1.5 py-0.5 rounded-full">🍷</span>}
            {r.reservation_needed ? <span className="text-[10px] bg-red-50 text-red-600 px-1.5 py-0.5 rounded-full">📞 Reservierung!</span> : null}
          </div>
        </div>
        <span className={`text-[#8E8E93] text-xs transition-transform ${open ? 'rotate-90' : ''}`}>▸</span>
      </button>
      {open && (
        <div className="px-3 pb-3 space-y-2 border-t border-orange-100 pt-2">
          {r.specialties && <div className="text-xs"><b className="text-[#1C1C1E]">🌟 Spezialitäten:</b> <span className="text-[#636366]">{r.specialties}</span></div>}
          {r.vegetarian_options && <div className="bg-green-50 rounded-lg p-2.5 text-xs"><b className="text-green-700">🥬 Vegetarisch:</b> <span className="text-green-800"> {r.vegetarian_options}</span></div>}
          {r.kid_notes && <div className="bg-pink-50 rounded-lg p-2.5 text-xs"><b className="text-pink-700">👶 Kinder-Info:</b> <span className="text-pink-800"> {r.kid_notes}</span></div>}
          {r.opening_hours && <div className="text-xs"><b className="text-[#1C1C1E]">🕐 Öffnungszeiten:</b> <span className="text-[#636366]"> {r.opening_hours}</span></div>}
          {r.tips && <div className="bg-orange-50 rounded-lg p-2.5 text-xs"><b className="text-orange-700">💡 Tipp:</b> <span className="text-orange-800"> {r.tips}</span></div>}
          <div className="flex flex-wrap gap-2">
            {r.menu_url && <a href={r.menu_url} target="_blank" rel="noopener" className="text-xs font-semibold text-orange-600 bg-orange-100 px-2.5 py-1 rounded-lg hover:bg-orange-200 transition">📋 Speisekarte</a>}
            {r.google_maps_url && <a href={r.google_maps_url} target="_blank" rel="noopener" className="text-xs font-semibold text-green-600 bg-green-50 px-2.5 py-1 rounded-lg">📍 Maps</a>}
            {r.tripadvisor_url && <a href={r.tripadvisor_url} target="_blank" rel="noopener" className="text-xs font-semibold text-emerald-600 bg-emerald-50 px-2.5 py-1 rounded-lg">⭐ TripAdvisor</a>}
            {r.website_url && <a href={r.website_url} target="_blank" rel="noopener" className="text-xs font-semibold text-blue-600 bg-blue-50 px-2.5 py-1 rounded-lg">🔗 Website</a>}
            {r.reservation_url && <a href={r.reservation_url} target="_blank" rel="noopener" className="text-xs font-semibold text-red-600 bg-red-50 px-2.5 py-1 rounded-lg">📞 Reservieren</a>}
          </div>
        </div>
      )}
    </div>
  );
}

function EmailCard({ email: e }: { email: any }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="bg-gray-50/80 rounded-xl overflow-hidden">
      <button onClick={() => setOpen(!open)} className="w-full text-left px-3 py-2.5 flex items-start gap-2.5 active:bg-gray-100/50 transition">
        <span className="text-base mt-0.5">{EMAIL_CAT_EMOJI[e.category] || '📧'}</span>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-[10px] text-[#8E8E93]">{e.email_date}</span>
            <span className="text-[10px] bg-gray-200 text-gray-600 px-1.5 py-0.5 rounded">{e.category}</span>
          </div>
          <p className="text-xs font-semibold text-[#1C1C1E] leading-tight mt-0.5 line-clamp-2">{e.email_subject}</p>
          <p className="text-[10px] text-[#8E8E93] truncate">{e.email_from}</p>
        </div>
        <span className={`text-[#8E8E93] text-xs transition-transform ${open ? 'rotate-90' : ''}`}>▸</span>
      </button>
      {open && e.email_snippet && (
        <div className="px-3 pb-3 pt-1 border-t border-gray-100">
          <p className="text-[11px] text-[#636366] leading-relaxed">{e.email_snippet}</p>
        </div>
      )}
    </div>
  );
}

/* ── Samu Activities Card ── */
function SamuActivityCard({ act: a }: { act: any }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="bg-pink-50/40 rounded-xl overflow-hidden">
      <button onClick={() => setOpen(!open)} className="w-full text-left p-3 flex items-start gap-3 active:bg-pink-50/60 transition">
        <div className="w-12 h-12 rounded-lg bg-gradient-to-br from-pink-100 to-purple-100 flex items-center justify-center flex-shrink-0 text-xl">{a.emoji || '👶'}</div>
        <div className="flex-1 min-w-0">
          <h4 className="text-sm font-bold text-[#1C1C1E] leading-tight">{a.title}</h4>
          <p className="text-[11px] text-[#636366] mt-0.5 line-clamp-2">{a.description}</p>
          <div className="flex flex-wrap gap-1 mt-1">
            {a.age_range && <span className="text-[10px] bg-purple-50 text-purple-600 px-1.5 py-0.5 rounded-full">👶 {a.age_range}</span>}
            {a.location && <span className="text-[10px] bg-blue-50 text-blue-600 px-1.5 py-0.5 rounded-full">📍 {a.location}</span>}
          </div>
        </div>
        <span className={`text-[#8E8E93] text-xs transition-transform ${open ? 'rotate-90' : ''}`}>▸</span>
      </button>
      {open && (
        <div className="px-3 pb-3 space-y-2 border-t border-pink-100 pt-2">
          {a.details && <p className="text-xs text-[#636366] leading-relaxed whitespace-pre-wrap">{a.details}</p>}
          {a.equipment_needed && <div className="bg-amber-50 rounded-lg p-2.5 text-xs"><b className="text-amber-700">🎒 Mitbringen:</b> <span className="text-amber-800"> {a.equipment_needed}</span></div>}
          {a.safety_notes && <div className="bg-red-50 rounded-lg p-2.5 text-xs"><b className="text-red-700">⚠️ Sicherheit:</b> <span className="text-red-800"> {a.safety_notes}</span></div>}
          {a.tips && <div className="bg-pink-50 rounded-lg p-2.5 text-xs"><b className="text-pink-700">💡 Tipp:</b> <span className="text-pink-800"> {a.tips}</span></div>}
        </div>
      )}
    </div>
  );
}

/* ── Clean notes: filter out redundant E-Mail/PDF sections ── */
function cleanNotes(notes: string): string {
  const lines = notes.split('\n');
  const filtered: string[] = [];
  let skip = false;
  for (const line of lines) {
    if (line.startsWith('E-Mail-Nachweise:') || line.startsWith('PDF-Dokumente in E-Mails:') || line.startsWith('--- Auto-Sync')) {
      skip = true;
      continue;
    }
    if (skip && (line.startsWith('- ') || line.trim() === '')) {
      if (line.trim() === '' && filtered.length > 0 && filtered[filtered.length-1].trim() === '') continue;
      if (line.startsWith('- ')) continue;
      skip = false;
    } else {
      skip = false;
    }
    filtered.push(line);
  }
  return filtered.join('\n').trim();
}

/* ── Packliste (interactive) ── */
const PACK_CATS: Record<string, { emoji: string; label: string }> = {
  dokumente: { emoji: '📄', label: 'Dokumente' }, samu: { emoji: '👶', label: 'Samu' },
  medizin: { emoji: '💊', label: 'Reiseapotheke' }, kleidung: { emoji: '👕', label: 'Kleidung' },
  strand: { emoji: '🏖️', label: 'Strand' }, technik: { emoji: '📱', label: 'Technik' },
  hygiene: { emoji: '🧴', label: 'Hygiene' }, sonstiges: { emoji: '📦', label: 'Sonstiges' }
};
function PackingSection({ tripId, initialItems }: { tripId: number; initialItems: any[] }) {
  const [items, setItems] = useState(initialItems);
  const [adding, setAdding] = useState(false);
  const [newItem, setNewItem] = useState('');
  const [newCat, setNewCat] = useState('sonstiges');
  const packed = items.filter((i: any) => i.packed).length;
  const total = items.length;
  const pct = total ? Math.round((packed / total) * 100) : 0;

  const toggle = async (id: number) => {
    const cur = items.find((i: any) => i.id === id);
    const nv = cur?.packed ? 0 : 1;
    setItems(prev => prev.map((i: any) => i.id === id ? { ...i, packed: nv } : i));
    await apiSend(`/reisen-packing/${id}`, 'PATCH', { packed: nv });
  };
  const resetAll = async () => {
    if (!confirm('Alle Häkchen zurücksetzen?')) return;
    const ids = items.map((i: any) => i.id);
    setItems(prev => prev.map((i: any) => ({ ...i, packed: 0 })));
    await Promise.all(ids.map((id: number) => apiSend(`/reisen-packing/${id}`, 'PATCH', { packed: 0 }).catch(() => {})));
  };
  const addItem = async () => {
    if (!newItem.trim()) return;
    const data = await apiSend<any>(`/reisen-packing`, 'POST', { trip_id: Number(tripId), category: newCat, item: newItem.trim(), quantity: 1, packed: 0 });
    setItems(prev => [...prev, { id: data.id, trip_id: tripId, category: newCat, item: newItem.trim(), quantity: 1, packed: 0, notes: null }]);
    setNewItem(''); setAdding(false);
  };
  const deleteItem = async (id: number) => {
    setItems(prev => prev.filter((i: any) => i.id !== id));
    await apiSend(`/reisen-packing/${id}`, 'DELETE');
  };

  const grouped = items.reduce((acc: any, i: any) => { (acc[i.category] = acc[i.category] || []).push(i); return acc; }, {});

  return (
    <Section title="Packliste" emoji="📋" count={`${packed}/${total}`} color="green">
      {/* Progress */}
      <div className="mb-3">
        <div className="flex items-center justify-between mb-1">
          <span className="text-xs text-[#636366]">{packed} von {total} gepackt</span>
          <span className={`text-xs font-bold ${pct === 100 ? 'text-green-600' : pct > 50 ? 'text-amber-600' : 'text-red-500'}`}>{pct}%</span>
        </div>
        <div className="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
          <div className={`h-full rounded-full transition-all duration-500 ${pct === 100 ? 'bg-green-500' : pct > 50 ? 'bg-amber-400' : 'bg-red-400'}`} style={{ width: `${pct}%` }} />
        </div>
      </div>

      {/* Categories */}
      <div className="space-y-3">
        {Object.entries(grouped).map(([cat, catItems]) => (
          <div key={cat}>
            <h4 className="text-xs font-bold text-[#636366] mb-1">{PACK_CATS[cat]?.emoji || '📦'} {PACK_CATS[cat]?.label || cat} <span className="text-[#8E8E93] font-normal">({(catItems as any[]).filter((i:any)=>i.packed).length}/{(catItems as any[]).length})</span></h4>
            <div className="space-y-0.5">
              {(catItems as any[]).map((item: any) => (
                <div key={item.id} className="flex items-center gap-2 py-1 group">
                  <button onClick={() => toggle(item.id)} className={`w-5 h-5 rounded-md border-2 flex items-center justify-center transition ${item.packed ? 'bg-green-500 border-green-500 text-white' : 'border-gray-300'}`}>
                    {item.packed ? '✓' : ''}
                  </button>
                  <span className={`text-sm flex-1 ${item.packed ? 'line-through text-[#8E8E93]' : 'text-[#1C1C1E]'}`}>
                    {item.item}{item.quantity > 1 ? ` (×${item.quantity})` : ''}
                  </span>
                  {item.notes && <span className="text-[9px] text-[#8E8E93] max-w-[120px] truncate">{item.notes}</span>}
                  <button onClick={() => deleteItem(item.id)} className="text-red-400 text-xs active:text-red-600 px-1">✕</button>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* Add + Reset */}
      <div className="flex gap-2 mt-3">
        {adding ? (
          <div className="flex-1 flex gap-1.5">
            <select value={newCat} onChange={e => setNewCat(e.target.value)} className="text-xs border rounded-lg px-2 py-1.5 bg-white">
              {Object.entries(PACK_CATS).map(([k, v]) => <option key={k} value={k}>{v.emoji} {v.label}</option>)}
            </select>
            <input value={newItem} onChange={e => setNewItem(e.target.value)} onKeyDown={e => e.key === 'Enter' && addItem()} placeholder="Item..." className="flex-1 text-sm border rounded-lg px-2 py-1.5" autoFocus />
            <button onClick={addItem} className="bg-green-500 text-white text-xs font-bold px-2.5 rounded-lg">+</button>
            <button onClick={() => setAdding(false)} className="text-[#8E8E93] text-xs px-1.5">✕</button>
          </div>
        ) : (
          <>
            <button onClick={() => setAdding(true)} className="text-xs font-semibold text-green-600 bg-green-50 px-3 py-1.5 rounded-lg">+ Hinzufügen</button>
            <button onClick={resetAll} className="text-xs font-semibold text-red-500 bg-red-50 px-3 py-1.5 rounded-lg">↺ Reset</button>
          </>
        )}
      </div>
    </Section>
  );
}

/* ── Tagesplaner (interactive) ── */
function DayPlanSection({ tripId, initialPlans, activities, restaurants, startDate }: { tripId: number; initialPlans: any[]; activities: any[]; restaurants: any[]; startDate: string }) {
  const [plans, setPlans] = useState<any[]>(initialPlans);
  const [adding, setAdding] = useState<number | null>(null); // day_number being added to
  const [showPicker, setShowPicker] = useState<number | null>(null); // day for activity picker
  const [activeItem, setActiveItem] = useState<number | null>(null); // item id with controls shown
  const [newText, setNewText] = useState('');
  const [newTime, setNewTime] = useState('');
  const [newEmoji, setNewEmoji] = useState('📍');

  const byDay: Record<number, any[]> = {};
  plans.forEach((d: any) => { (byDay[d.day_number] = byDay[d.day_number] || []).push(d); });
  const dayNums = Object.keys(byDay).map(Number).sort((a, b) => a - b);
  const maxDay = dayNums.length > 0 ? Math.max(...dayNums) : 0;

  const getDayDate = (dayNum: number) => {
    if (!startDate) return null;
    const d = new Date(startDate + 'T12:00:00');
    d.setDate(d.getDate() + dayNum - 1);
    return d.toISOString().slice(0, 10);
  };

  const api = async (body: any): Promise<any> => {
    try {
      if (body.action === 'delete') { await apiSend(`/reisen-dayplans/${body.itemId}`, 'DELETE'); return {}; }
      if (body.action === 'reorder') { await Promise.all((body.items || []).map((it: any) => apiSend(`/reisen-dayplans/${it.id}`, 'PATCH', { sort_order: it.sort_order }).catch(() => {}))); return {}; }
      if (body.action === 'move') { await apiSend(`/reisen-dayplans/${body.itemId}`, 'PATCH', { day_number: body.day_number, sort_order: body.sort_order }); return {}; }
      const { action, activityId, itemId, items, ...fields } = body;
      const payload: Record<string, unknown> = { trip_id: Number(tripId), sort_order: 99, ...fields };
      if (activityId) payload.activity_id = activityId;
      return await apiSend(`/reisen-dayplans`, 'POST', payload);
    } catch { return { id: Date.now() }; }
  };

  const deleteItem = async (id: number) => {
    setPlans(prev => prev.filter(p => p.id !== id));
    await api({ action: 'delete', itemId: id });
  };

  const moveUp = async (item: any, dayItems: any[]) => {
    const idx = dayItems.findIndex((d: any) => d.id === item.id);
    if (idx <= 0) return;
    const prev = dayItems[idx - 1];
    const newItems = [...dayItems];
    newItems[idx - 1] = { ...item, sort_order: prev.sort_order };
    newItems[idx] = { ...prev, sort_order: item.sort_order };
    setPlans(p => p.map(x => x.id === item.id ? { ...x, sort_order: prev.sort_order } : x.id === prev.id ? { ...x, sort_order: item.sort_order } : x));
    await api({ action: 'reorder', items: [{ id: item.id, sort_order: prev.sort_order }, { id: prev.id, sort_order: item.sort_order }] });
  };

  const moveDown = async (item: any, dayItems: any[]) => {
    const idx = dayItems.findIndex((d: any) => d.id === item.id);
    if (idx >= dayItems.length - 1) return;
    const next = dayItems[idx + 1];
    setPlans(p => p.map(x => x.id === item.id ? { ...x, sort_order: next.sort_order } : x.id === next.id ? { ...x, sort_order: item.sort_order } : x));
    await api({ action: 'reorder', items: [{ id: item.id, sort_order: next.sort_order }, { id: next.id, sort_order: item.sort_order }] });
  };

  const moveToDay = async (item: any, newDay: number) => {
    setPlans(p => p.map(x => x.id === item.id ? { ...x, day_number: newDay, sort_order: 99 } : x));
    await api({ action: 'move', itemId: item.id, day_number: newDay, sort_order: 99 });
  };

  const addFreeText = async (dayNum: number) => {
    if (!newText.trim()) return;
    const data = await api({ day_number: dayNum, day_date: getDayDate(dayNum), time_slot: newTime || null, activity: newText.trim(), emoji: newEmoji });
    setPlans(prev => [...prev, { id: data.id, trip_id: tripId, day_number: dayNum, day_date: getDayDate(dayNum), time_slot: newTime, activity: newText.trim(), emoji: newEmoji, sort_order: 99 }]);
    setNewText(''); setNewTime(''); setNewEmoji('📍'); setAdding(null);
  };

  const addActivity = async (dayNum: number, act: any) => {
    const data = await api({ action: 'add_activity', activityId: act.id, day_number: dayNum, day_date: getDayDate(dayNum) });
    setPlans(prev => [...prev, { id: data.id, trip_id: tripId, day_number: dayNum, day_date: getDayDate(dayNum), activity: act.title, emoji: act.emoji || '🎯', location: act.location, notes: act.description, sort_order: 99 }]);
    setShowPicker(null);
  };

  // Sorted plans for display
  const sortedByDay: Record<number, any[]> = {};
  plans.forEach((d: any) => { (sortedByDay[d.day_number] = sortedByDay[d.day_number] || []).push(d); });
  Object.values(sortedByDay).forEach(arr => arr.sort((a: any, b: any) => (a.sort_order || 0) - (b.sort_order || 0)));

  return (
    <Section title="Tagesplaner" emoji="🗓️" count={Object.keys(sortedByDay).length + ' Tage'} color="purple">
      <div className="space-y-4">
        {Object.entries(sortedByDay).sort(([a],[b]) => Number(a)-Number(b)).map(([dayNum, dayItems]) => {
          const items = dayItems as any[];
          const dn = Number(dayNum);
          return (
            <div key={dayNum}>
              <div className="flex items-center gap-2 mb-2">
                <span className="bg-purple-500 text-white text-xs font-black px-2.5 py-1 rounded-lg">Tag {dayNum}</span>
                <span className="text-sm font-bold text-[#1C1C1E]">{items[0]?.title || ''}</span>
                {getDayDate(dn) && <span className="text-[10px] text-[#8E8E93]">{new Date(getDayDate(dn)! + 'T12:00:00').toLocaleDateString('de-DE', { weekday: 'short', day: '2-digit', month: '2-digit' })}</span>}
              </div>
              <div className="relative pl-6 space-y-0">
                <div className="absolute left-[11px] top-2 bottom-2 w-0.5 bg-purple-200 rounded" />
                {items.map((item: any, idx: number) => (
                  <div key={item.id} className="relative py-1.5">
                    <div className="flex items-start gap-2 cursor-pointer" onClick={() => setActiveItem(activeItem === item.id ? null : item.id)}>
                      <div className="absolute left-[-15px] top-2.5 w-3 h-3 rounded-full bg-purple-400 border-2 border-white shadow-sm z-10" />
                      <span className="text-[10px] text-[#8E8E93] font-mono min-w-[40px] pt-0.5">{item.time_slot || ''}</span>
                      <span className="text-base">{item.emoji || '📍'}</span>
                      <div className="flex-1 min-w-0">
                        <span className="text-sm font-semibold text-[#1C1C1E]">{item.activity}</span>
                        {item.location && <span className="text-[10px] text-[#8E8E93] block">📍 {item.location}</span>}
                        {item.notes && <span className="text-[10px] text-[#636366] block">{item.notes}</span>}
                      </div>
                      <span className="text-[10px] text-purple-400 flex-shrink-0 pt-1">{activeItem === item.id ? '▾' : '⋯'}</span>
                    </div>
                    {/* Controls — shown on tap */}
                    {activeItem === item.id && (
                      <div className="flex gap-2 items-center mt-1.5 ml-[52px] flex-wrap">
                        {idx > 0 && <button onClick={() => moveUp(item, items)} className="text-[11px] text-purple-600 bg-purple-100 active:bg-purple-200 rounded-lg px-2.5 py-1 font-bold">▲ Hoch</button>}
                        {idx < items.length - 1 && <button onClick={() => moveDown(item, items)} className="text-[11px] text-purple-600 bg-purple-100 active:bg-purple-200 rounded-lg px-2.5 py-1 font-bold">▼ Runter</button>}
                        <select onChange={e => { if (e.target.value) { moveToDay(item, Number(e.target.value)); setActiveItem(null); } e.target.value = ''; }} className="text-[11px] text-gray-600 bg-gray-100 rounded-lg px-2 py-1 font-semibold" defaultValue="">
                          <option value="" disabled>→ Tag</option>
                          {Array.from({ length: maxDay + 1 }, (_, i) => i + 1).filter(d => d !== dn).map(d => <option key={d} value={d}>Tag {d}</option>)}
                        </select>
                        <button onClick={() => { deleteItem(item.id); setActiveItem(null); }} className="text-[11px] text-red-500 bg-red-100 active:bg-red-200 rounded-lg px-2.5 py-1 font-bold">🗑 Löschen</button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
              {/* Add buttons per day */}
              <div className="flex gap-1.5 mt-1.5 ml-6">
                {adding === dn ? (
                  <div className="flex-1 flex gap-1 items-center">
                    <input value={newTime} onChange={e => setNewTime(e.target.value)} placeholder="09:00" className="w-14 text-[10px] border rounded px-1.5 py-1" />
                    <select value={newEmoji} onChange={e => setNewEmoji(e.target.value)} className="text-sm border rounded px-1 py-0.5">
                      {['📍','🏖️','🍽️','🏊','🚗','⛪','🛍️','🧖','🎭','🏨','✈️','🚕'].map(e => <option key={e} value={e}>{e}</option>)}
                    </select>
                    <input value={newText} onChange={e => setNewText(e.target.value)} onKeyDown={e => e.key === 'Enter' && addFreeText(dn)} placeholder="Aktivität..." className="flex-1 text-xs border rounded px-2 py-1" autoFocus />
                    <button onClick={() => addFreeText(dn)} className="text-xs bg-purple-500 text-white font-bold px-2 py-1 rounded">+</button>
                    <button onClick={() => setAdding(null)} className="text-xs text-gray-400 px-1">✕</button>
                  </div>
                ) : showPicker === dn ? (
                  <div className="flex-1 space-y-1">
                    <div className="text-[10px] text-[#8E8E93] font-semibold">Aktivität zuweisen:</div>
                    <div className="flex flex-wrap gap-1">
                      {[...activities, ...restaurants.map((r: any) => ({ ...r, title: r.name, emoji: '🍽️' }))].map((a: any) => (
                        <button key={a.id + '-' + (a.name || a.title)} onClick={() => addActivity(dn, a)} className="text-[10px] bg-purple-50 text-purple-700 px-2 py-1 rounded-lg font-semibold hover:bg-purple-100 transition">
                          {a.emoji || '🎯'} {a.title || a.name}
                        </button>
                      ))}
                    </div>
                    <button onClick={() => setShowPicker(null)} className="text-[10px] text-gray-400">Abbrechen</button>
                  </div>
                ) : (
                  <>
                    <button onClick={() => setAdding(dn)} className="text-[10px] font-semibold text-purple-600 bg-purple-50 px-2 py-1 rounded-lg">+ Freitext</button>
                    <button onClick={() => setShowPicker(dn)} className="text-[10px] font-semibold text-blue-600 bg-blue-50 px-2 py-1 rounded-lg">🎯 Aktivität</button>
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </Section>
  );
}

export default function TripDetailPage() {
  const params = useParams();
  const router = useRouter();
  const tripId = params.id as string;

  const [trip, setTrip] = useState<Trip & { docs: any[]; links: any[] } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(0);
  const [editing, setEditing] = useState(false);
  const [editData, setEditData] = useState<Partial<Trip>>({});
  const [liveWeather, setLiveWeather] = useState<any>(null);

  const loadTrip = async () => {
    try {
      const list = async (r: string): Promise<any[]> => {
        try { return (await apiGet<{ data: any[] }>(`/${r}?trip_id=${tripId}&limit=300`)).data ?? []; }
        catch { return []; }
      };
      const [tripData, docs, links, activityList, restaurantList, emailList, weatherList, divingList, samuList, flightList, hotelList, packingList, dayPlans, emergencyList, phraseList] = await Promise.all([
        apiGet<any>(`/reisen/${tripId}`),
        list('reisen-docs'), list('reisen-links'), list('reisen-activities'), list('reisen-restaurants'),
        list('reisen-emails'), list('reisen-weather'), list('reisen-diving'), list('reisen-samu-activities'),
        list('reisen-flights'), list('reisen-hotel'), list('reisen-packing'), list('reisen-dayplans'),
        list('reisen-emergency'), list('reisen-phrases'),
      ]);
      const data = { ...tripData, docs, links, activityList, restaurantList, emailList, weatherList, divingList, samuList, flightList, hotelInfo: hotelList[0] ?? null, packingList, dayPlans, emergencyList, phraseList };
      setTrip(data);
      setEditData(data);
    } catch (err: any) { setError(err?.message === 'HTTP 404' ? 'Trip nicht gefunden' : (err.message || 'Fehler beim Laden')); }
    finally { setLoading(false); }
  };

  useEffect(() => { loadTrip(); }, [tripId]);
  // Live-Wetter (externer Dienst) ist in v1 nicht angebunden → liveWeather bleibt leer.

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !trip) return;
    setUploading(true);
    const fd = new FormData();
    fd.append('file', file);
    fd.append('name', file.name);
    fd.append('trip_id', String(trip.id));
    await fetch('/api/v1/files/reisen-docs', { method: 'POST', credentials: 'include', body: fd });
    await loadTrip();
    setUploading(false);
  };

  const handleDeleteDoc = async (docId: number) => {
    if (!trip) return;
    await apiSend(`/reisen-docs/${docId}`, 'DELETE');
    await loadTrip();
  };

  const handleDeleteTrip = async () => {
    if (!trip) return;
    if (confirmDelete < 2) { setConfirmDelete(c => c + 1); return; }
    await apiSend(`/reisen/${trip.id}`, 'DELETE');
    router.push('/reisen');
  };

  const handleSaveEdit = async () => {
    if (!trip) return;
    const strip = new Set(['docs', 'links', 'activityList', 'restaurantList', 'emailList', 'weatherList', 'divingList', 'samuList', 'flightList', 'hotelInfo', 'packingList', 'dayPlans', 'emergencyList', 'phraseList', 'doc_count', 'link_count', 'id', 'created_at', 'updated_at']);
    const payload: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(editData)) if (!strip.has(k)) payload[k] = v;
    await apiSend(`/reisen/${trip.id}`, 'PATCH', payload);
    setEditing(false);
    await loadTrip();
  };

  if (error) return (
    <main className="min-h-screen bg-gradient-to-br from-[#F0F5FF] via-[#FFF5F0] to-[#F5F0FF] flex flex-col items-center justify-center gap-4 px-5">
      <div className="text-4xl">⚠️</div>
      <p className="text-[#636366] font-medium text-center">{error}</p>
      <button onClick={() => router.push('/reisen')} className="px-4 py-2 bg-blue-500 text-white rounded-xl text-sm font-semibold">← Zurück</button>
    </main>
  );

  if (loading) return (
    <main className="min-h-screen bg-gradient-to-br from-[#F0F5FF] via-[#FFF5F0] to-[#F5F0FF] flex items-center justify-center">
      <div className="text-4xl animate-bounce">✈️</div>
    </main>
  );

  if (!trip) return null;

  const emoji = TYPE_EMOJI[trip.type] || '🌍';
  const isPast = trip.status === 'vergangen';
  const countdown = trip.start_date && trip.status === 'geplant' ? daysUntil(trip.start_date) : null;
  const cleanedNotes = trip.notes ? cleanNotes(trip.notes) : null;

  return (
    <main className="min-h-screen bg-gradient-to-br from-[#F0F5FF] via-[#FFF5F0] to-[#F5F0FF]">
      {/* Hero Image */}
      <div className="relative h-56 md:h-72 overflow-hidden">
        {trip.cover_image ? (
          <img src={trip.cover_image} alt={trip.title} className={`w-full h-full object-cover ${isPast ? 'brightness-80 saturate-75' : ''}`} />
        ) : (
          <div className={`w-full h-full bg-gradient-to-br ${isPast ? 'from-gray-400 to-gray-600' : 'from-blue-500 via-indigo-500 to-purple-600'}`} />
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent" />
        <Link href="/reisen" className="absolute top-4 left-4 w-10 h-10 bg-black/30 backdrop-blur-md rounded-full flex items-center justify-center text-white active:scale-95 transition safe-area-inset">
          <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" /></svg>
        </Link>
        {countdown !== null && countdown > 0 && (
          <div className="absolute top-4 right-4 bg-white/20 backdrop-blur-md rounded-full px-3.5 py-1.5 text-white text-sm font-bold">✈️ noch {countdown} Tage</div>
        )}
        <div className="absolute bottom-0 left-0 right-0 p-5">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-3xl drop-shadow-lg">{emoji}</span>
            {trip.rating && <span className="text-sm bg-amber-500/80 backdrop-blur-md text-white px-2 py-0.5 rounded-full font-bold">{Array.from({length:trip.rating}).map(()=>'⭐').join('')}</span>}
          </div>
          <h1 className="text-2xl font-extrabold text-white leading-tight drop-shadow-md">{trip.title}</h1>
          <p className="text-white/80 text-sm font-medium mt-0.5 drop-shadow">📍 {trip.destination}{trip.country ? `, ${trip.country}` : ''}</p>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-2xl mx-auto px-5 pb-16 -mt-2 space-y-3">

        {/* Status & Dates — always visible */}
        <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 p-4 shadow-sm">
          <div className="flex flex-wrap gap-2 mb-3">
            {trip.start_date && (
              <span className="text-sm bg-blue-100 text-blue-700 px-3 py-1.5 rounded-xl font-semibold">
                📅 {formatDate(trip.start_date)}{trip.end_date && trip.end_date !== trip.start_date ? ` – ${formatDate(trip.end_date)}` : ''}
              </span>
            )}
            <span className={`text-sm px-3 py-1.5 rounded-xl font-semibold ${trip.status === 'geplant' ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'}`}>
              {trip.status === 'geplant' ? '🟢 Geplant' : '✅ Vergangen'}
            </span>
            {trip.participants && <span className="text-sm bg-purple-100 text-purple-700 px-3 py-1.5 rounded-xl font-semibold">👥 {trip.participants}</span>}
          </div>
          {trip.lat && trip.lng && (
            <div className="flex gap-2">
              <a href={mapsUrl(trip.lat, trip.lng)} target="_blank" rel="noopener" className="flex-1 text-center py-3 bg-blue-50 text-blue-600 text-sm font-semibold rounded-xl">📍 Karte</a>
              <a href={routeUrl(trip.lat, trip.lng)} target="_blank" rel="noopener" className="flex-1 text-center py-3 bg-green-50 text-green-600 text-sm font-semibold rounded-xl">🧭 Route</a>
            </div>
          )}
        </div>

        {/* ⏱️ Countdown + Timezone + Live Weather — always visible for planned trips */}
        {trip.status === 'geplant' && trip.start_date && (() => {
          const start = new Date(trip.start_date + 'T00:00:00');
          const now = new Date();
          const diffMs = start.getTime() - now.getTime();
          const days = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
          const tzOffset = (trip as any).timezone_offset || 0;
          const tzName = (trip as any).timezone_name || '';
          const localNow = new Date(now.getTime() + tzOffset * 60 * 60 * 1000);
          const localTimeStr = localNow.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit', timeZone: 'UTC' });
          return days > 0 ? (
            <div className="bg-gradient-to-r from-blue-500 to-purple-500 rounded-2xl p-4 shadow-sm text-white">
              <div className="flex items-center justify-between">
                <div>
                  <span className="text-3xl font-black">{days}</span>
                  <span className="text-sm font-semibold ml-1.5">Tage</span>
                  <span className="text-xs opacity-80 block">bis {trip.destination || 'zum Urlaub'} ✈️</span>
                </div>
                {tzOffset !== 0 && (
                  <div className="text-right">
                    <span className="text-lg font-bold">{localTimeStr}</span>
                    <span className="text-[10px] opacity-80 block">Ortszeit {trip.destination}</span>
                    <span className="text-[9px] opacity-60">{tzName}</span>
                  </div>
                )}
              </div>
              {days <= 14 && <div className="mt-2 bg-white/20 rounded-lg px-3 py-1.5 text-xs font-semibold">🎒 Koffer packen! Check-in bald möglich</div>}
              {liveWeather && (
                <div className="mt-2 bg-white/15 rounded-lg px-3 py-2 flex items-center gap-3">
                  <div>
                    <span className="text-2xl font-black">{liveWeather.temp}°</span>
                    <span className="text-[10px] opacity-80 block">Aktuell in {trip.destination}</span>
                  </div>
                  <div className="flex-1 text-right text-xs">
                    <span className="block">{liveWeather.desc}</span>
                    <span className="opacity-70">🌡️ {liveWeather.min_temp}°–{liveWeather.max_temp}° | 💨 {liveWeather.wind_kmph} km/h | ☀️ UV {liveWeather.uv}</span>
                  </div>
                </div>
              )}
            </div>
          ) : null;
        })()}

        {/* Details Cards — always visible */}
        <div className="grid grid-cols-2 gap-2.5">
          {trip.hotel && (
            <div onClick={() => { const el = document.getElementById('hotel-section'); if(el) { el.scrollIntoView({behavior:'smooth'}); (el.querySelector('button') as HTMLButtonElement)?.click(); }}} className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 p-3.5 shadow-sm cursor-pointer hover:bg-blue-50/30 transition">
              <span className="text-[#8E8E93] text-xs block mb-0.5">🏨 Hotel</span>
              <span className="font-semibold text-sm text-[#1C1C1E]">{trip.hotel}</span>
              {(trip as any).hotelInfo && <span className="text-[10px] text-blue-500 block mt-0.5">Details ▸</span>}
            </div>
          )}
          {trip.booking_ref && (
            <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 p-3.5 shadow-sm">
              <span className="text-[#8E8E93] text-xs block mb-0.5">📋 Buchung</span>
              <span className="font-semibold text-sm text-[#1C1C1E] font-mono">{trip.booking_ref}</span>
              {trip.booking_platform && <span className="text-[#8E8E93] text-xs block">({trip.booking_platform})</span>}
            </div>
          )}
          {trip.flight && (
            <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 p-3.5 shadow-sm">
              <span className="text-[#8E8E93] text-xs block mb-0.5">✈️ Flug</span>
              <span className="font-semibold text-sm text-[#1C1C1E]">{trip.flight}</span>
              {trip.flight_ref && <span className="text-[#8E8E93] text-xs block font-mono">{trip.flight_ref}</span>}
            </div>
          )}
          {trip.transport && (
            <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 p-3.5 shadow-sm">
              <span className="text-[#8E8E93] text-xs block mb-0.5">🚆 Anreise</span>
              <span className="font-semibold text-sm text-[#1C1C1E]">{trip.transport}</span>
            </div>
          )}
          {trip.cost_total && (
            <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 p-3.5 shadow-sm">
              <span className="text-[#8E8E93] text-xs block mb-0.5">💰 Kosten</span>
              <span className="font-semibold text-sm text-[#1C1C1E]">{trip.cost_total}</span>
            </div>
          )}
        </div>

        {/* Highlights — always visible */}
        {trip.highlights && (
          <div className="bg-amber-50/80 backdrop-blur-sm rounded-2xl border border-amber-200/50 p-4 shadow-sm">
            <span className="font-bold text-amber-700 text-sm">✨ Highlights</span>
            <p className="text-amber-800 text-sm mt-1">{trip.highlights}</p>
          </div>
        )}

        {/* ── All sections below are COLLAPSIBLE, closed by default ── */}

        {/* 🏨 Hotel-Info */}
        {(trip as any).hotelInfo && (
          <div id="hotel-section"><Section title={(trip as any).hotelInfo.name || 'Hotel'} emoji="🏨" color="blue">
            <div className="space-y-3">
              {/* Category + Board */}
              <div className="flex flex-wrap gap-2">
                {(trip as any).hotelInfo.category && <span className="text-xs bg-amber-100 text-amber-700 px-2.5 py-1 rounded-lg font-semibold">⭐ {(trip as any).hotelInfo.category}</span>}
              </div>

              {/* Description */}
              {(trip as any).hotelInfo.description && <p className="text-sm text-[#636366] leading-relaxed">{(trip as any).hotelInfo.description}</p>}

              {/* Details Grid */}
              <div className="space-y-2">
                {(trip as any).hotelInfo.board_type && <div className="bg-green-50 rounded-xl p-3 text-xs"><b className="text-green-700">🍽️ Verpflegung:</b> <span className="text-green-800"> {(trip as any).hotelInfo.board_type}</span></div>}
                {(trip as any).hotelInfo.room_type && <div className="bg-blue-50 rounded-xl p-3 text-xs"><b className="text-blue-700">🛏️ Zimmer:</b> <span className="text-blue-800"> {(trip as any).hotelInfo.room_type}</span></div>}
                {(trip as any).hotelInfo.pools && <div className="bg-sky-50 rounded-xl p-3 text-xs"><b className="text-sky-700">🏊 Pools:</b> <span className="text-sky-800"> {(trip as any).hotelInfo.pools}</span></div>}
                {(trip as any).hotelInfo.beach && <div className="bg-amber-50 rounded-xl p-3 text-xs"><b className="text-amber-700">🏖️ Strand:</b> <span className="text-amber-800"> {(trip as any).hotelInfo.beach}</span></div>}
                {(trip as any).hotelInfo.spa && <div className="bg-purple-50 rounded-xl p-3 text-xs"><b className="text-purple-700">🧖 Spa:</b> <span className="text-purple-800"> {(trip as any).hotelInfo.spa}</span></div>}
                {(trip as any).hotelInfo.kids_club && <div className="bg-pink-50 rounded-xl p-3 text-xs"><b className="text-pink-700">👶 Kinderbetreuung:</b> <span className="text-pink-800"> {(trip as any).hotelInfo.kids_club}</span></div>}
                {(trip as any).hotelInfo.restaurants_info && <div className="bg-orange-50 rounded-xl p-3 text-xs"><b className="text-orange-700">🍽️ Restaurants:</b> <span className="text-orange-800"> {(trip as any).hotelInfo.restaurants_info}</span></div>}
                {(trip as any).hotelInfo.amenities && <div className="bg-gray-50 rounded-xl p-3 text-xs"><b className="text-gray-700">✨ Ausstattung:</b> <span className="text-gray-600"> {(trip as any).hotelInfo.amenities}</span></div>}
              </div>

              {/* Check-in/out */}
              <div className="grid grid-cols-2 gap-2">
                {(trip as any).hotelInfo.check_in && <div className="bg-white/60 rounded-lg p-2.5"><span className="text-[9px] text-[#8E8E93] block">Check-in</span><span className="text-xs font-semibold">{(trip as any).hotelInfo.check_in}</span></div>}
                {(trip as any).hotelInfo.check_out && <div className="bg-white/60 rounded-lg p-2.5"><span className="text-[9px] text-[#8E8E93] block">Check-out</span><span className="text-xs font-semibold">{(trip as any).hotelInfo.check_out}</span></div>}
              </div>

              {/* Booking notes */}
              {(trip as any).hotelInfo.notes && <div className="bg-amber-50 rounded-xl p-3 text-xs"><b className="text-amber-700">📋 Buchung:</b> <span className="text-amber-800"> {(trip as any).hotelInfo.notes}</span></div>}

              {/* Links */}
              <div className="flex flex-wrap gap-2">
                {(trip as any).hotelInfo.website_url && <a href={(trip as any).hotelInfo.website_url} target="_blank" rel="noopener" className="text-xs font-semibold text-blue-600 bg-blue-50 px-3 py-1.5 rounded-lg">🔗 Hotel-Website</a>}
                {(trip as any).hotelInfo.tripadvisor_url && <a href={(trip as any).hotelInfo.tripadvisor_url} target="_blank" rel="noopener" className="text-xs font-semibold text-emerald-600 bg-emerald-50 px-3 py-1.5 rounded-lg">⭐ TripAdvisor</a>}
                {(trip as any).hotelInfo.holidaycheck_url && <a href={(trip as any).hotelInfo.holidaycheck_url} target="_blank" rel="noopener" className="text-xs font-semibold text-orange-600 bg-orange-50 px-3 py-1.5 rounded-lg">🏆 HolidayCheck</a>}
                {(trip as any).hotelInfo.booking_url && <a href={(trip as any).hotelInfo.booking_url} target="_blank" rel="noopener" className="text-xs font-semibold text-green-600 bg-green-50 px-3 py-1.5 rounded-lg">📋 Mein TUI</a>}
              </div>
            </div>
          </Section></div>
        )}

        {/* 🏝️ Reiseziel-Info */}
        {(trip as any).destination_info && (
          <Section title={`Über ${trip.destination || 'das Reiseziel'}`} emoji="🏝️" color="green">
            <div className="text-sm text-[#636366] leading-relaxed whitespace-pre-wrap">{(trip as any).destination_info}</div>
          </Section>
        )}

        {/* ✈️ Flüge */}
        {(trip as any).flightList && (trip as any).flightList.length > 0 && (
          <Section title="Flüge" emoji="✈️" count={(trip as any).flightList.length} color="sky">
            <div className="space-y-3">
              {(trip as any).flightList.map((f: any) => <FlightCard key={f.id} flight={f} />)}
            </div>
          </Section>
        )}

        {/* 👶 Samu-Aktivitäten */}
        {(trip as any).samuList && (trip as any).samuList.length > 0 && (
          <Section title="Samu-Aktivitäten" emoji="👶" count={(trip as any).samuList.length} color="pink">
            <div className="space-y-2">
              {(trip as any).samuList.map((a: any) => <SamuActivityCard key={a.id} act={a} />)}
            </div>
          </Section>
        )}

        {/* 🌤️ Wetter */}
        {(trip as any).weatherList && (trip as any).weatherList.length > 0 && (
          <Section title="Wetter & Wassertemperatur" emoji="🌤️" count={(trip as any).weatherList.length} color="sky">
            <div className="space-y-2.5">
              {(trip as any).weatherList.map((w: any) => (
                <div key={w.id} className={`rounded-xl p-3 ${w.type === 'forecast' ? 'bg-sky-50 border border-sky-200/50' : 'bg-gray-50'}`}>
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-xs font-bold text-sky-700">{w.type === 'historical' ? '📊 Historisch' : '🔮 Vorhersage'}</span>
                    <span className="text-[10px] text-[#8E8E93]">{w.date}</span>
                  </div>
                  {w.temp_max && (
                    <div className="flex gap-3 flex-wrap mb-1">
                      <span className="text-xs">🌡️ <b>{w.temp_min}–{w.temp_max}°C</b></span>
                      {w.temp_water && <span className="text-xs">🌊 <b>{w.temp_water}°C</b> Wasser</span>}
                      {w.sun_hours && <span className="text-xs">☀️ <b>{w.sun_hours}h</b> Sonne</span>}
                      {w.rain_days !== null && <span className="text-xs">🌧️ <b>{w.rain_days}</b> Regentage</span>}
                    </div>
                  )}
                  {w.description && <p className="text-[11px] text-[#636366] leading-relaxed">{w.description}</p>}
                  {w.source && <p className="text-[9px] text-[#C7C7CC] mt-1">Quelle: {w.source}</p>}
                </div>
              ))}
            </div>
          </Section>
        )}

        {/* 🤿 Tauchen */}
        {(trip as any).divingList && (trip as any).divingList.length > 0 && (
          <Section title="Tauchen" emoji="🤿" count={(trip as any).divingList.length} color="cyan">
            <div className="space-y-2">
              {(trip as any).divingList.map((d: any) => <DivingCard key={d.id} dive={d} />)}
            </div>
          </Section>
        )}

        {/* 🎯 Aktivitäten */}
        {(trip as any).activityList && (trip as any).activityList.length > 0 && (
          <Section title="Aktivitäten & Ausflüge" emoji="🎯" count={(trip as any).activityList.length} color="blue">
            <div className="space-y-2">
              {(trip as any).activityList.map((act: any) => <ActivityCard key={act.id} activity={act} />)}
            </div>
          </Section>
        )}

        {/* 🍽️ Restaurants */}
        {(trip as any).restaurantList && (trip as any).restaurantList.length > 0 && (
          <Section title="Restaurant-Tipps" emoji="🍽️" count={(trip as any).restaurantList.length} color="orange">
            <div className="space-y-2">
              {(trip as any).restaurantList.map((r: any) => <RestaurantCard key={r.id} restaurant={r} />)}
            </div>
          </Section>
        )}

        {/* 🇬🇷 Sprachführer */}
        {(trip as any).phraseList && (trip as any).phraseList.length > 0 && (
          <Section title="Sprachführer" emoji="🗣️" count={(trip as any).phraseList.length} color="blue">
            <div className="space-y-3">
              {(() => {
                const cats: Record<string, { emoji: string; label: string }> = {
                  grundlagen: { emoji: '👋', label: 'Grundlagen' }, restaurant: { emoji: '🍽️', label: 'Im Restaurant' },
                  unterwegs: { emoji: '🧭', label: 'Unterwegs' }, baby: { emoji: '👶', label: 'Mit Baby' }
                };
                const grouped = (trip as any).phraseList.reduce((acc: any, p: any) => { (acc[p.category] = acc[p.category] || []).push(p); return acc; }, {});
                return Object.entries(grouped).map(([cat, phrases]: [string, any]) => (
                  <div key={cat}>
                    <h4 className="text-xs font-bold text-[#636366] mb-1.5">{cats[cat]?.emoji || '📝'} {cats[cat]?.label || cat}</h4>
                    <div className="grid gap-1">
                      {(phrases as any[]).map((p: any) => (
                        <div key={p.id} className="bg-white/70 rounded-xl p-2.5 flex items-center gap-3">
                          <div className="flex-1 min-w-0">
                            <span className="text-sm font-bold text-[#1C1C1E]">{p.local_text}</span>
                            <span className="text-xs text-blue-600 block italic">{p.pronunciation}</span>
                          </div>
                          <span className="text-xs text-[#636366] text-right flex-shrink-0 max-w-[120px]">{p.german}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                ));
              })()}
            </div>
          </Section>
        )}

        {/* 🆘 Notfall-Karte — PINNED at top priority */}
        {(trip as any).emergencyList && (trip as any).emergencyList.length > 0 && (
          <Section title="Notfall & Wichtige Nummern" emoji="🆘" count={(trip as any).emergencyList.length} color="red">
            <div className="space-y-2">
              {(() => {
                const cats: Record<string, { emoji: string; label: string; color: string }> = {
                  notruf: { emoji: '🚨', label: 'Notrufe', color: 'red' }, krankenhaus: { emoji: '🏥', label: 'Krankenhaus', color: 'red' },
                  botschaft: { emoji: '🇩🇪', label: 'Botschaft/Konsulat', color: 'blue' }, versicherung: { emoji: '🛡️', label: 'Versicherung', color: 'purple' },
                  reisebuero: { emoji: '✈️', label: 'Reisebüro', color: 'sky' }, hotel: { emoji: '🏨', label: 'Hotel', color: 'blue' },
                  kinderarzt: { emoji: '👶', label: 'Kinderarzt', color: 'pink' }, sonstiges: { emoji: '📋', label: 'Sonstiges', color: 'gray' }
                };
                const grouped = (trip as any).emergencyList.reduce((acc: any, e: any) => { (acc[e.category] = acc[e.category] || []).push(e); return acc; }, {});
                return Object.entries(grouped).map(([cat, items]: [string, any]) => (
                  <div key={cat} className="space-y-1">
                    <h4 className="text-xs font-bold text-[#636366] flex items-center gap-1">{cats[cat]?.emoji} {cats[cat]?.label || cat}</h4>
                    {items.map((e: any) => (
                      <div key={e.id} className="bg-white/70 rounded-xl p-2.5 flex items-center gap-3">
                        <div className="flex-1 min-w-0">
                          <span className="text-sm font-semibold text-[#1C1C1E]">{e.title}</span>
                          {e.notes && <span className="text-[11px] text-[#636366] block">{e.notes}</span>}
                          {e.address && <span className="text-[10px] text-[#8E8E93] block">📍 {e.address}</span>}
                        </div>
                        <div className="flex gap-1.5 flex-shrink-0">
                          {e.phone && <a href={`tel:${e.phone}`} className="bg-green-500 text-white text-xs font-bold px-2.5 py-1.5 rounded-lg">📞 {e.phone}</a>}
                          {e.url && <a href={e.url} target="_blank" rel="noopener" className="bg-blue-50 text-blue-600 text-[10px] font-semibold px-2 py-1.5 rounded-lg">🔗</a>}
                        </div>
                      </div>
                    ))}
                  </div>
                ));
              })()}
            </div>
          </Section>
        )}

        {/* 📋 Packliste */}
        {(trip as any).packingList && (trip as any).packingList.length > 0 && (
          <PackingSection tripId={trip.id} initialItems={(trip as any).packingList} />
        )}

        {/* 🗓️ Tagesplaner */}
        {(trip as any).dayPlans && (
          <DayPlanSection tripId={trip.id} initialPlans={(trip as any).dayPlans || []} activities={(trip as any).activityList || []} restaurants={(trip as any).restaurantList || []} startDate={trip.start_date || ''} />
        )}

        {/* 🗺️ Karte */}
        {(() => {
          const pins: any[] = [];
          ((trip as any).activityList || []).forEach((a: any) => { if (a.lat && a.lng) pins.push({ lat: a.lat, lng: a.lng, title: a.title, emoji: a.emoji || '🎯', type: 'activity' }); });
          ((trip as any).restaurantList || []).forEach((r: any) => { if (r.lat && r.lng) pins.push({ lat: r.lat, lng: r.lng, title: r.name, emoji: '🍽️', type: 'restaurant' }); });
          ((trip as any).emergencyList || []).filter((e: any) => e.lat && e.lng).forEach((e: any) => { pins.push({ lat: e.lat, lng: e.lng, title: e.title, emoji: '🆘', type: 'emergency' }); });
          if (pins.length === 0) return null;
          return (
            <Section title="Karte" emoji="🗺️" count={pins.length + ' Orte'} color="green">
              <TripMap pins={pins} hotelLat={trip.lat || undefined} hotelLng={trip.lng || undefined} />
              <p className="text-[10px] text-[#8E8E93] mt-1.5 text-center">📍 Aktivitäten (blau) • 🍽️ Restaurants (rot) • 🆘 Notfall (gelb) • 🏨 Hotel</p>
            </Section>
          );
        })()}

        {/* 📝 Notizen — cleaned (without E-Mail/PDF duplicates) */}
        {cleanedNotes && (
          <Section title="Notizen & Buchungsdetails" emoji="📝">
            <div className="text-sm text-[#636366] whitespace-pre-wrap leading-relaxed">{cleanedNotes}</div>
          </Section>
        )}

        {/* 📧 E-Mails */}
        {(trip as any).emailList && (trip as any).emailList.length > 0 && (
          <Section title="Verknüpfte E-Mails" emoji="📧" count={(trip as any).emailList.length}>
            <div className="space-y-2">
              {(trip as any).emailList.map((email: any) => <EmailCard key={email.id} email={email} />)}
            </div>
          </Section>
        )}

        {/* 📎 Dokumente */}
        <Section title="Dokumente" emoji="📎" count={trip.docs?.length || 0}>
          {trip.docs && trip.docs.length > 0 ? (
            <div className="space-y-3">
              {trip.docs.filter((d: any) => d.file_size).length > 0 && (
                <div>
                  <span className="text-[10px] font-bold text-[#8E8E93] uppercase tracking-wider block mb-1.5">PDF-Dokumente</span>
                  <div className="space-y-1.5">
                    {trip.docs.filter((d: any) => d.file_size).map((doc: any) => (
                      <div key={doc.id} className="flex items-center gap-3 py-2 px-3 bg-red-50/60 rounded-xl group">
                        <span className="text-lg">📄</span>
                        <div className="flex-1 min-w-0">
                          <a href={`/api/v1/files/reisen-docs/${doc.id}`} target="_blank" className="text-sm font-semibold text-red-700 hover:underline truncate block">{doc.name.replace(/\.pdf$/, '')}</a>
                          <span className="text-[10px] text-red-400">{(doc.file_size / 1024).toFixed(0)} KB · {DOC_EMOJI[doc.doc_type]||''} {doc.doc_type}</span>
                        </div>
                        <button onClick={() => handleDeleteDoc(doc.id)} className="text-xs text-gray-300 hover:text-red-400 p-1">🗑️</button>
                      </div>
                    ))}
                  </div>
                </div>
              )}
              {trip.docs.filter((d: any) => !d.file_size && d.url).length > 0 && (
                <div>
                  <span className="text-[10px] font-bold text-[#8E8E93] uppercase tracking-wider block mb-1.5">Links & Referenzen</span>
                  <div className="space-y-1.5">
                    {trip.docs.filter((d: any) => !d.file_size && d.url).map((doc: any) => (
                      <a key={doc.id} href={doc.url} target="_blank" rel="noopener" className="flex items-center gap-3 py-2 px-3 bg-blue-50/60 rounded-xl hover:bg-blue-50 transition">
                        <span className="text-lg">🔗</span>
                        <span className="text-sm font-semibold text-blue-600 truncate">{doc.name}</span>
                      </a>
                    ))}
                  </div>
                </div>
              )}
            </div>
          ) : (
            <p className="text-sm text-[#8E8E93]">Noch keine Dokumente</p>
          )}
          <label className="mt-3 block">
            <span className="inline-block text-sm text-blue-500 font-semibold cursor-pointer bg-blue-50 px-4 py-2 rounded-xl active:scale-95">＋ Hochladen{uploading && ' ⏳'}</span>
            <input type="file" className="hidden" onChange={handleUpload} accept=".pdf,.jpg,.jpeg,.png,.doc,.docx" />
          </label>
        </Section>

        {/* Tags */}
        {trip.tags && (
          <div className="flex flex-wrap gap-1.5">
            {trip.tags.split(',').map((tag: string, i: number) => (
              <span key={i} className="text-xs bg-gray-100 text-gray-500 px-2.5 py-1 rounded-full">#{tag.trim()}</span>
            ))}
          </div>
        )}

        {/* Action Buttons */}
        <div className="flex gap-2 pt-2">
          <button onClick={() => setEditing(!editing)} className="flex-1 py-3 bg-blue-50 text-blue-600 text-sm font-semibold rounded-2xl active:scale-95">✏️ Bearbeiten</button>
          <button onClick={handleDeleteTrip} className={`py-3 px-5 text-sm font-semibold rounded-2xl active:scale-95 ${confirmDelete === 0 ? 'bg-gray-100 text-gray-400' : confirmDelete === 1 ? 'bg-red-100 text-red-500' : 'bg-red-500 text-white'}`}>
            {confirmDelete === 0 ? '🗑️' : confirmDelete === 1 ? '⚠️ Sicher?' : '🗑️ Endgültig'}
          </button>
        </div>

        {/* Edit Form */}
        {editing && (
          <div className="bg-white/90 backdrop-blur-sm rounded-2xl border border-blue-200/50 p-5 shadow-sm space-y-3">
            <h4 className="text-sm font-bold text-[#1C1C1E]">✏️ Reise bearbeiten</h4>
            <input type="text" value={editData.title || ''} onChange={e => setEditData(d => ({...d, title: e.target.value}))} placeholder="Titel" className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
            <div className="flex gap-2">
              <input type="text" value={editData.destination || ''} onChange={e => setEditData(d => ({...d, destination: e.target.value}))} placeholder="Zielort" className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
              <input type="text" value={editData.country || ''} onChange={e => setEditData(d => ({...d, country: e.target.value}))} placeholder="Land" className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
            </div>
            <div className="flex gap-2">
              <input type="date" value={editData.start_date || ''} onChange={e => setEditData(d => ({...d, start_date: e.target.value}))} className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
              <input type="date" value={editData.end_date || ''} onChange={e => setEditData(d => ({...d, end_date: e.target.value}))} className="flex-1 bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
            </div>
            <input type="text" value={editData.hotel || ''} onChange={e => setEditData(d => ({...d, hotel: e.target.value}))} placeholder="🏨 Hotel" className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
            <input type="text" value={editData.cover_image || ''} onChange={e => setEditData(d => ({...d, cover_image: e.target.value}))} placeholder="🖼️ Cover-Bild URL" className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400" />
            <textarea value={editData.highlights || ''} onChange={e => setEditData(d => ({...d, highlights: e.target.value}))} placeholder="✨ Highlights" rows={2} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400 resize-none" />
            <textarea value={editData.notes || ''} onChange={e => setEditData(d => ({...d, notes: e.target.value}))} placeholder="📝 Notizen" rows={4} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400 resize-none" />
            <select value={editData.status || 'geplant'} onChange={e => setEditData(d => ({...d, status: e.target.value}))} className="w-full bg-[#F2F2F7] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-400">
              <option value="geplant">🟢 Geplant</option>
              <option value="vergangen">✅ Vergangen</option>
            </select>
            <div className="flex gap-2 pt-1">
              <button onClick={handleSaveEdit} className="flex-1 py-3 bg-gradient-to-r from-blue-500 to-indigo-500 text-white text-sm font-semibold rounded-xl active:scale-95">💾 Speichern</button>
              <button onClick={() => { setEditing(false); setEditData(trip); }} className="px-5 py-3 bg-gray-100 text-gray-500 text-sm font-semibold rounded-xl active:scale-95">✕</button>
            </div>
          </div>
        )}
      </div>
    </main>
  );
}
