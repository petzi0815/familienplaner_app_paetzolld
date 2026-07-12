'use client';

interface MapPin { lat: number; lng: number; title: string; emoji: string; type: string; }

/** Leichte Karte ohne Extra-Dependency: OpenStreetMap-Embed, zentriert auf Hotel/erste Aktivität. */
export default function TripMap({ pins, hotelLat, hotelLng }: { pins: MapPin[]; hotelLat?: number; hotelLng?: number }) {
  const valid = pins.filter((p) => p.lat && p.lng);
  const lat = hotelLat ?? valid[0]?.lat;
  const lng = hotelLng ?? valid[0]?.lng;

  if (!lat || !lng) {
    return (
      <div className="w-full h-[350px] rounded-2xl bg-gray-100 flex items-center justify-center text-gray-400 text-sm">
        Keine Koordinaten hinterlegt
      </div>
    );
  }

  const d = 0.12;
  const bbox = `${lng - d}%2C${lat - d}%2C${lng + d}%2C${lat + d}`;
  const src = `https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik&marker=${lat}%2C${lng}`;

  return (
    <div className="w-full rounded-2xl overflow-hidden shadow-sm border border-gray-200/50">
      <iframe src={src} className="w-full h-[320px] border-0" loading="lazy" title="Karte" />
      <div className="text-center py-1.5 bg-gray-50">
        <a href={`https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=12/${lat}/${lng}`}
           target="_blank" rel="noopener" className="text-xs font-semibold text-[#007AFF]">
          Größere Karte öffnen ↗
        </a>
      </div>
    </div>
  );
}
