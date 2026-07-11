// API-Smoke-Test. Nutzung: node scripts/smoke.mjs <baseUrl> <agentKey>
// z.B. node scripts/smoke.mjs https://familienplaner.yagemi.app fp_agent_xxx
const base = (process.argv[2] || "http://localhost:3000").replace(/\/+$/, "");
const key = process.argv[3] || "";
const H = key ? { authorization: `Bearer ${key}` } : {};
let fail = 0;

async function check(name, path, { expect = 200, headers, ...opts } = {}) {
  try {
    const r = await fetch(base + path, { headers: { ...H, ...(headers ?? {}) }, ...opts });
    const okk = r.status === expect;
    console.log(`${okk ? "✓" : "✗"} ${name} [${r.status}${okk ? "" : ` erwartet ${expect}`}]`);
    if (!okk) fail++;
    return r;
  } catch (e) {
    console.log(`✗ ${name} (${e.message})`);
    fail++;
  }
}

console.log(`Smoke-Test gegen ${base}${key ? " (mit Agent-Key)" : " (ohne Key)"}\n`);
await check("healthz", "/healthz");
await check("version", "/version");
await check("api-index", "/api/v1");
await check("unauth→401", "/api/v1/termine", { headers: { authorization: "" }, expect: key ? 401 : 401 });
if (key) {
  await check("capabilities", "/api/v1/agent/capabilities");
  await check("termine-list", "/api/v1/termine?limit=1");
  await check("schema", "/api/v1/termine/schema");
  await check("dashboard-today", "/api/v1/dashboard/today");
  await check("search", "/api/v1/search?q=korfu");
  await check("reminders-due", "/api/v1/reminders/due");
  await check("jobs", "/api/v1/jobs");
  await check("dry-run-create", "/api/v1/termine?dry_run=1", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ title: "SMOKE", date: "2099-01-01" }), expect: 200 });
}
console.log(fail ? `\n❌ ${fail} Fehler` : "\n✅ Alle Checks grün");
process.exit(fail ? 1 : 0);
