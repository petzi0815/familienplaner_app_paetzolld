import { NextResponse } from 'next/server';
import { getAuth, hasRole } from '@/server/auth/auth';
import { getTermin, updateTermin, setTerminUserState, getTerminUserState } from '@/server/legacy/termine-db';

// Quittierung eines Termins — direkt vom Sperrbildschirm (Notification-Action) oder aus der
// Live Activity heraus, ohne die App zu öffnen. `owner` kommt aus dem Per-User-API-Key.
//   gelesen  → persönlich „gelesen" + Quittier-Zeitpunkt
//   erledigt → zusätzlich der GETEILTE Termin-Status (termine.status='erledigt')
//   stumm    → keine Erinnerung mehr für DIESEN Termin (muted=1, notify=0)
//   laut     → Stummschaltung UND Quittierung zurücknehmen (ack_at=NULL) — sonst bliebe der Termin
//              in Live Activity/Status dauerhaft „quittiert", obwohl der Nutzer ihn wieder hören will
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const ACTIONS = ['gelesen', 'erledigt', 'stumm', 'laut'] as const;
type AckAction = (typeof ACTIONS)[number];

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const auth = getAuth(request);
  if (!hasRole(auth, 'agent')) {
    return NextResponse.json({ error: { code: auth ? 'forbidden' : 'unauthorized', message: 'Nicht berechtigt.' } }, { status: auth ? 403 : 401 });
  }
  const owner = auth?.owner ?? null;
  if (!owner) {
    return NextResponse.json({ error: { code: 'no_owner', message: 'Quittieren erfordert einen persönlichen API-Key (Lars/Elita).' } }, { status: 400 });
  }
  const { id } = await params;
  const terminId = parseInt(id);
  if (!getTermin(terminId)) return NextResponse.json({ error: 'Termin nicht gefunden' }, { status: 404 });

  const body = await request.json().catch(() => ({} as Record<string, unknown>));
  const action = String((body as { action?: unknown }).action ?? '').trim() as AckAction;
  if (!ACTIONS.includes(action)) {
    return NextResponse.json(
      { error: { code: 'invalid_value', message: "Feld 'action' erforderlich.", details: { column: 'action', allowed: ACTIONS } } },
      { status: 400 },
    );
  }

  switch (action) {
    case 'gelesen':
      setTerminUserState(terminId, owner, { read: true, ack_at: 'now' });
      break;
    case 'erledigt':
      setTerminUserState(terminId, owner, { read: true, ack_at: 'now' });
      updateTermin(terminId, { status: 'erledigt' }); // geteilt (nicht per-User)
      break;
    case 'stumm':
      setTerminUserState(terminId, owner, { muted: true, notify: false });
      break;
    case 'laut':
      setTerminUserState(terminId, owner, { muted: false, ack_at: '' }); // '' = Quittierung löschen
      break;
  }

  const s = getTerminUserState(terminId, owner);
  return NextResponse.json({ success: true, owner, action, state: { read: s.read, notify: s.notify, muted: s.muted, acked: !!s.ack_at } });
}
