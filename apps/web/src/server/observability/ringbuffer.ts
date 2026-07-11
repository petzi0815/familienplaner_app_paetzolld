/**
 * In-Memory-Log-Ringpuffer — die letzten N Zeilen ohne Coolify-Terminal abrufbar
 * über GET /api/v1/debug/logs (admin). Überlebt KEINEN Container-Neustart.
 * Muster übernommen aus dem Referenzprojekt (RingBufferHandler).
 */
const MAX = 1500;
const buffer: string[] = [];

export function push(line: string): void {
  buffer.push(line);
  if (buffer.length > MAX) buffer.splice(0, buffer.length - MAX);
}

export function tail(lines = 300, grep?: string): string[] {
  let rows = buffer;
  if (grep) {
    const needle = grep.toLowerCase();
    rows = rows.filter((r) => r.toLowerCase().includes(needle));
  }
  const n = Math.max(1, Math.min(lines, MAX));
  return rows.slice(-n);
}

export function size(): number {
  return buffer.length;
}
