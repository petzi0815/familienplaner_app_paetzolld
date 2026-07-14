import { NextResponse } from 'next/server';
import { getAuth, hasRole } from '@/server/auth/auth';
import { getTermin, setTerminUserState } from '@/server/legacy/termine-db';

// Persönlicher Termin-Zustand des aufrufenden Users (owner aus dem API-Key):
// { read?: boolean, notify?: boolean }. Erfordert einen Per-User-Key (Lars/Elita).
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const auth = getAuth(request);
  if (!hasRole(auth, 'agent')) {
    return NextResponse.json({ error: { code: auth ? 'forbidden' : 'unauthorized', message: 'Nicht berechtigt.' } }, { status: auth ? 403 : 401 });
  }
  const owner = auth?.owner ?? null;
  if (!owner) {
    return NextResponse.json({ error: { code: 'no_owner', message: 'Per-User-Zustand erfordert einen persönlichen API-Key (Lars/Elita).' } }, { status: 400 });
  }
  const { id } = await params;
  const terminId = parseInt(id);
  if (!getTermin(terminId)) return NextResponse.json({ error: 'Termin nicht gefunden' }, { status: 404 });

  const body = await request.json().catch(() => ({} as Record<string, unknown>));
  const patch: { read?: boolean; notify?: boolean } = {};
  if ('read' in body) patch.read = !!body.read;
  if ('notify' in body) patch.notify = !!body.notify;
  if (patch.read === undefined && patch.notify === undefined) {
    return NextResponse.json({ error: { code: 'empty', message: 'read und/oder notify erforderlich.' } }, { status: 400 });
  }
  setTerminUserState(terminId, owner, patch);
  return NextResponse.json({ success: true, owner, ...patch });
}
