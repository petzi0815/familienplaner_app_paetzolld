import { NextResponse } from 'next/server';
import { getAllSamen, addSamen } from '@/server/legacy/garten-db';
import { guard } from '@/server/legacy/compat';
import fs from 'fs';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Notify Ole about new seeds that need enrichment
async function notifyOleNewSeed(id: number, name: string) {
  try {
    // Read gateway config for auth
    const config = JSON.parse(fs.readFileSync('/home/node/.openclaw/openclaw.json', 'utf8'));
    const botToken = config.channels?.telegram?.botToken;
    const groupId = '-1003415230540'; // Familiengruppe

    if (!botToken) return;

    // Send a silent message to the group — Ole picks it up instantly
    await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: groupId,
        text: `🌱 Neuer Samen im Portal angelegt: "${name}" (ID: ${id}) — bitte anreichern!`,
        disable_notification: true,
      }),
    });
  } catch (err) {
    console.error('[Garten Webhook] Notify failed:', err);
  }
}

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);

    const filters = {
      aktiv: searchParams.get('aktiv') !== null ? parseInt(searchParams.get('aktiv')!) : undefined,
      art: searchParams.get('art') || undefined,
      hersteller: searchParams.get('hersteller') || undefined,
      bio: searchParams.get('bio') || undefined,
      typ: searchParams.get('typ') || undefined,
      samenfest: searchParams.get('samenfest') !== null ? parseInt(searchParams.get('samenfest')!) : undefined,
      keimfaehig: searchParams.get('keimfaehig') as 'ok' | 'abgelaufen' | 'unbekannt' | undefined,
      search: searchParams.get('search') || undefined,
    };

    const samen = getAllSamen(filters);
    return NextResponse.json(samen);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    const id = addSamen(data);

    // Fire-and-forget: notify Ole to enrich the new seed
    notifyOleNewSeed(id, data.name || data.nummer || `#${id}`);

    return NextResponse.json({ id, success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
