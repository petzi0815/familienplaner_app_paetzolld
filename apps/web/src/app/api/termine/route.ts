import { NextResponse } from 'next/server';
import { getAllTermine, addTermin, getUpcomingTermine, getDueReminders, getTermineForMonth, searchTermine, getConflicts, CATEGORIES } from '@/server/legacy/termine-db';
import { guard } from '@/server/legacy/compat';
import { getAuth } from '@/server/auth/auth';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const g = guard(request); if (g) return g;
  try {
    const { searchParams } = new URL(request.url);
    const mode = searchParams.get('mode');
    const owner = getAuth(request)?.owner ?? null; // Per-User read/notify (nur bei persönlichem Key)

    if (mode === 'upcoming') {
      const days = parseInt(searchParams.get('days') || '14');
      return NextResponse.json(getUpcomingTermine(days, owner));
    }

    if (mode === 'reminders') {
      return NextResponse.json(getDueReminders());
    }

    if (mode === 'month') {
      const year = parseInt(searchParams.get('year') || new Date().getFullYear().toString());
      const month = parseInt(searchParams.get('month') || (new Date().getMonth() + 1).toString());
      return NextResponse.json(getTermineForMonth(year, month, owner));
    }

    if (mode === 'categories') {
      return NextResponse.json(CATEGORIES);
    }

    if (mode === 'search') {
      const q = searchParams.get('q') || '';
      if (!q) return NextResponse.json([]);
      return NextResponse.json(searchTermine(q, owner));
    }

    if (mode === 'conflicts') {
      const date = searchParams.get('date');
      if (!date) return NextResponse.json({ error: 'date benötigt' }, { status: 400 });
      const excludeId = searchParams.get('exclude') ? parseInt(searchParams.get('exclude')!) : undefined;
      return NextResponse.json(getConflicts(date, excludeId));
    }

    const opts: { from?: string; to?: string; category?: string; status?: string; person?: string } = {};
    if (searchParams.get('from')) opts.from = searchParams.get('from')!;
    if (searchParams.get('to')) opts.to = searchParams.get('to')!;
    if (searchParams.get('category')) opts.category = searchParams.get('category')!;
    if (searchParams.get('status')) opts.status = searchParams.get('status')!;
    if (searchParams.get('person')) opts.person = searchParams.get('person')!;

    return NextResponse.json(getAllTermine(opts, owner));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const g = guard(request, 'agent'); if (g) return g;
  try {
    const data = await request.json();
    if (!data.title || !data.date) {
      return NextResponse.json({ error: 'title und date sind Pflichtfelder' }, { status: 400 });
    }
    const id = addTermin(data);
    return NextResponse.json({ id, success: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Fehler' }, { status: 500 });
  }
}
