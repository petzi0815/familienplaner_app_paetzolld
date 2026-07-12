import { NextResponse } from 'next/server';
import { guard, getDb } from '@/server/legacy/compat';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const LATITUDE = 52.4833;  // Burgwedel
const LONGITUDE = 9.8667;

interface GTSDay {
  date: string;
  temp: number;
  factor: number;
  contribution: number;
  cumulative: number;
}

interface GTSResult {
  date: string;
  gts_current: number;
  gts_projected_14d: number;
  threshold_150_reached: boolean;
  threshold_200_reached: boolean;
  forecast_reach_150: string | null;
  forecast_reach_200: string | null;
  remaining_150: number;
  remaining_200: number;
  history: GTSDay[];
  forecast: GTSDay[];
  plant_tips: PlantTip[];
  frost_plants: FrostPlant[];
}

interface PlantTip {
  gts: number;
  label: string;
  emoji: string;
  description: string;
  reached: boolean;
  forecast_date: string | null;
  plants?: string[];
}

interface FrostPlant {
  id: number;
  name: string;
  min_temp: number;
  frostempfindlich: boolean;
  gts_raus: number | null;
  status: 'draussen_ok' | 'reinholen' | 'drinnen_lassen';
  hinweis: string;
}

function getGTSFactor(month: number): number {
  if (month === 0) return 0.5;   // January
  if (month === 1) return 0.75;  // February
  return 1.0;                     // March+
}

// Build dynamic plant tips from DB + static garden milestones
function getPlantTips(gtsCurrent: number, allDays: GTSDay[]): PlantTip[] {
  // Static gardening milestones
  const staticTips: Omit<PlantTip, 'reached' | 'forecast_date'>[] = [
    { gts: 80, label: 'Vorfrühling', emoji: '🌸', description: 'Forsythienblüte, Rasen vertikutieren möglich' },
    { gts: 100, label: 'Rasen: Erste Pflege', emoji: '🌾', description: 'Rasen walzen, erstes vorsichtiges Mähen bei trockenem Boden' },
    { gts: 150, label: 'Erste Düngung', emoji: '🧪', description: 'Rasendüngung starten (Langzeitdünger). Hecken schneiden.' },
    { gts: 200, label: 'Nachhaltiges Wachstum', emoji: '🌿', description: 'Volles Graswachstum, regelmäßig mähen. Stauden düngen.' },
    { gts: 250, label: 'Zweite Düngung', emoji: '💚', description: 'Nachdüngung Rasen bei Bedarf. Sommerblumen pflanzen.' },
    { gts: 500, label: 'Hochsommer-Pflege', emoji: '☀️', description: 'Rasen-Sommerdüngung, Bewässerung intensivieren.' },
  ];

  // Dynamic plant tips from DB
  try {
    const db = getDb();
    const plants = db.prepare(
      "SELECT id, name, gts_raus, gts_rein, frostempfindlich, min_temp FROM garten_pflanzen WHERE status='aktiv' AND gts_raus IS NOT NULL"
    ).all() as any[];

    // Group plants by their gts_raus threshold
    const gtsGroups = new Map<number, string[]>();
    for (const p of plants) {
      if (p.gts_raus) {
        const existing = gtsGroups.get(p.gts_raus) || [];
        existing.push(p.name);
        gtsGroups.set(p.gts_raus, existing);
      }
    }

    // Add dynamic tips for each GTS group
    for (const [gts, plantNames] of gtsGroups) {
      // Don't duplicate if a static tip already has this exact GTS
      const existingStatic = staticTips.find(t => t.gts === gts);
      if (existingStatic) {
        existingStatic.description += ` 🌳 ${plantNames.join(', ')} können raus!`;
        (existingStatic as any).plants = plantNames;
      } else {
        staticTips.push({
          gts,
          label: `${plantNames.join(', ')} raus!`,
          emoji: '🌳',
          description: `${plantNames.join(', ')} können nach draußen (nach Eisheiligen prüfen!).`,
          plants: plantNames,
        } as any);
      }
    }
  } catch (e) {
    // DB not available - use only static tips
  }

  // Sort by GTS value
  staticTips.sort((a, b) => a.gts - b.gts);

  return staticTips.map(t => {
    const reached = gtsCurrent >= t.gts;
    let forecast_date: string | null = null;
    if (!reached) {
      const day = allDays.find(d => d.cumulative >= t.gts);
      if (day) forecast_date = day.date;
    }
    return { ...t, reached, forecast_date };
  });
}

// Check frost-sensitive plants against current/forecast temps
function getFrostPlants(forecastTemps: { date: string; temp: number }[], gtsCurrent: number): FrostPlant[] {
  try {
    const db = getDb();
    const plants = db.prepare(
      "SELECT id, name, gts_raus, frostempfindlich, min_temp FROM garten_pflanzen WHERE status='aktiv' AND frostempfindlich=1"
    ).all() as any[];

    if (plants.length === 0) return [];

    // Find min forecast temp in next 7 days
    const next7 = forecastTemps.slice(0, 7);
    const minForecast = next7.length > 0 ? Math.min(...next7.map(d => d.temp)) : 10;
    const month = new Date().getMonth() + 1; // 1-12

    return plants.map(p => {
      const minTemp = p.min_temp ?? 0;
      const gtsRaus = p.gts_raus ?? 300;

      let status: FrostPlant['status'];
      let hinweis: string;

      if (month >= 5 && month <= 9 && gtsCurrent >= gtsRaus) {
        // Summer, GTS reached - safe outside
        if (minForecast <= minTemp + 2) {
          status = 'reinholen';
          hinweis = `⚠️ Kälteeinbruch! Min. ${minForecast}°C erwartet — sicherheitshalber reinholen!`;
        } else {
          status = 'draussen_ok';
          hinweis = `Draußen OK. Min. ${minForecast}°C erwartet (Grenze: ${minTemp}°C).`;
        }
      } else if (gtsCurrent < gtsRaus || month <= 4 || month >= 10) {
        // Not yet safe or autumn/winter
        if (minForecast <= minTemp) {
          status = 'drinnen_lassen';
          hinweis = `Drinnen lassen! Min. ${minForecast}°C erwartet (Grenze: ${minTemp}°C).`;
        } else if (month >= 3 && month <= 5 && minForecast > minTemp + 5) {
          status = 'drinnen_lassen';
          hinweis = `Noch drinnen. Tagsüber zum Akklimatisieren rausstellen möglich (${minForecast}°C min).`;
        } else {
          status = 'drinnen_lassen';
          hinweis = `Drinnen lassen. GTS ${Math.round(gtsCurrent)} von ${gtsRaus} — noch nicht soweit.`;
        }
      } else {
        status = 'draussen_ok';
        hinweis = 'Draußen OK.';
      }

      return {
        id: p.id,
        name: p.name,
        min_temp: minTemp,
        frostempfindlich: true,
        gts_raus: gtsRaus,
        status,
        hinweis,
      };
    });
  } catch (e) {
    return [];
  }
}

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const now = new Date();
    const year = now.getFullYear();
    const today = now.toISOString().split('T')[0];
    const jan1 = `${year}-01-01`;

    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split('T')[0];

    // Fetch historical data
    const archiveUrl = `https://archive-api.open-meteo.com/v1/archive?latitude=${LATITUDE}&longitude=${LONGITUDE}&daily=temperature_2m_mean&start_date=${jan1}&end_date=${yesterdayStr}&timezone=Europe/Berlin`;

    let histRes = await fetch(archiveUrl, { next: { revalidate: 3600 } });
    if (!histRes.ok) {
      // Fallback to forecast API
      const histUrl = `https://api.open-meteo.com/v1/forecast?latitude=${LATITUDE}&longitude=${LONGITUDE}&daily=temperature_2m_mean&start_date=${jan1}&end_date=${yesterdayStr}&timezone=Europe/Berlin`;
      histRes = await fetch(histUrl, { next: { revalidate: 3600 } });
    }
    const histData = await histRes.json();

    // Fetch 14-day forecast
    const fcUrl = `https://api.open-meteo.com/v1/forecast?latitude=${LATITUDE}&longitude=${LONGITUDE}&daily=temperature_2m_mean&timezone=Europe/Berlin&forecast_days=14`;
    const fcRes = await fetch(fcUrl, { next: { revalidate: 3600 } });
    const fcData = await fcRes.json();

    // Calculate historical GTS
    const history: GTSDay[] = [];
    let cumulative = 0;

    if (histData.daily?.time) {
      for (let i = 0; i < histData.daily.time.length; i++) {
        const dateStr = histData.daily.time[i];
        const temp = histData.daily.temperature_2m_mean[i];
        if (temp === null || temp === undefined) continue;

        const date = new Date(dateStr);
        const factor = getGTSFactor(date.getMonth());
        const contribution = Math.max(0, temp) * factor;
        cumulative += contribution;

        history.push({
          date: dateStr,
          temp: Math.round(temp * 10) / 10,
          factor,
          contribution: Math.round(contribution * 10) / 10,
          cumulative: Math.round(cumulative * 10) / 10,
        });
      }
    }

    const gtsCurrent = Math.round(cumulative * 10) / 10;
    const lastHistDate = history.length > 0 ? history[history.length - 1].date : today;

    // Calculate forecast GTS
    const forecast: GTSDay[] = [];
    let fcCumulative = cumulative;

    if (fcData.daily?.time) {
      for (let i = 0; i < fcData.daily.time.length; i++) {
        const dateStr = fcData.daily.time[i];
        const temp = fcData.daily.temperature_2m_mean[i];
        if (temp === null || temp === undefined) continue;
        if (dateStr <= lastHistDate) continue;

        const date = new Date(dateStr);
        const factor = getGTSFactor(date.getMonth());
        const contribution = Math.max(0, temp) * factor;
        fcCumulative += contribution;

        forecast.push({
          date: dateStr,
          temp: Math.round(temp * 10) / 10,
          factor,
          contribution: Math.round(contribution * 10) / 10,
          cumulative: Math.round(fcCumulative * 10) / 10,
        });
      }
    }

    const gtsProjected = Math.round(fcCumulative * 10) / 10;

    // Find threshold dates
    const allDaysForThresholds = [...history, ...forecast];
    const reach150 = allDaysForThresholds.find(d => d.cumulative >= 150);
    const reach200 = allDaysForThresholds.find(d => d.cumulative >= 200);

    const allDays = [...history, ...forecast];
    const plantTips = getPlantTips(gtsCurrent, allDays);

    // Forecast temps for frost check
    const forecastTemps = forecast.map(d => ({ date: d.date, temp: d.temp }));
    const frostPlants = getFrostPlants(forecastTemps, gtsCurrent);

    const result: GTSResult = {
      date: today,
      gts_current: gtsCurrent,
      gts_projected_14d: gtsProjected,
      threshold_150_reached: gtsCurrent >= 150,
      threshold_200_reached: gtsCurrent >= 200,
      forecast_reach_150: gtsCurrent < 150 ? (reach150?.date ?? null) : null,
      forecast_reach_200: gtsCurrent < 200 ? (reach200?.date ?? null) : null,
      remaining_150: Math.max(0, Math.round((150 - gtsCurrent) * 10) / 10),
      remaining_200: Math.max(0, Math.round((200 - gtsCurrent) * 10) / 10),
      history,
      forecast,
      plant_tips: plantTips,
      frost_plants: frostPlants,
    };

    return NextResponse.json(result);
  } catch (error: any) {
    console.error('GTS fetch error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
