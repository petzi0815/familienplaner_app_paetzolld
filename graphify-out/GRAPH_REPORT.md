# Graph Report - apps/web/src  (2026-07-11)

## Corpus Check
- Corpus is ~13,155 words - fits in a single context window. You may not need a graph.

## Summary
- 221 nodes · 805 edges · 15 communities (14 shown, 1 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 5 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Datenbank & FTS-Suche|Datenbank & FTS-Suche]]
- [[_COMMUNITY_Domaenen-API-Routen & Layout|Domaenen-API-Routen & Layout]]
- [[_COMMUNITY_Migration, Seed & Jobs|Migration, Seed & Jobs]]
- [[_COMMUNITY_Auth & DebugBackup|Auth & Debug/Backup]]
- [[_COMMUNITY_Ressourcen-Browser (UI)|Ressourcen-Browser (UI)]]
- [[_COMMUNITY_Agent-Endpunkte|Agent-Endpunkte]]
- [[_COMMUNITY_Auth-Rollen & ConfigJobs|Auth-Rollen & Config/Jobs]]
- [[_COMMUNITY_Generisches CRUD|Generisches CRUD]]
- [[_COMMUNITY_Portal & Navigation|Portal & Navigation]]
- [[_COMMUNITY_HTTP-Antworten & Media|HTTP-Antworten & Media]]
- [[_COMMUNITY_Log-Ringpuffer|Log-Ringpuffer]]
- [[_COMMUNITY_Middleware (Login-Gate)|Middleware (Login-Gate)]]

## God Nodes (most connected - your core abstractions)
1. `getDb()` - 55 edges
2. `getAuth()` - 52 edges
3. `unauthorized()` - 47 edges
4. `hasRole()` - 46 edges
5. `ok()` - 35 edges
6. `notFound()` - 29 edges
7. `fail()` - 27 edges
8. `forbidden()` - 21 edges
9. `config` - 19 edges
10. `createRow()` - 18 edges

## Surprising Connections (you probably didn't know these)
- `register()` --calls--> `getDb()`  [INFERRED]
  instrumentation.ts → server/db/connection.ts
- `register()` --calls--> `startScheduler()`  [INFERRED]
  instrumentation.ts → server/jobs/scheduler.ts
- `Portal()` --calls--> `getDb()`  [EXTRACTED]
  app/page.tsx → server/db/connection.ts
- `GET()` --calls--> `getDb()`  [EXTRACTED]
  app/api/v1/route.ts → server/db/connection.ts
- `GET()` --calls--> `getDb()`  [INFERRED]
  app/api/v1/[domain]/[id]/route.ts → server/db/connection.ts

## Communities (15 total, 1 thin omitted)

### Community 0 - "Datenbank & FTS-Suche"
Cohesion: 0.13
Nodes (38): getDb(), contentOf(), ensureFtsPopulated(), ftsAvailable(), ftsSearch(), rebuildAll(), reindexRow(), removeFromIndex() (+30 more)

### Community 1 - "Domaenen-API-Routen & Layout"
Cohesion: 0.09
Nodes (19): metadata, viewport, Auth, RANK, readCookie(), Role, getSessionUser(), SECRET() (+11 more)

### Community 2 - "Migration, Seed & Jobs"
Cohesion: 0.1
Nodes (21): runMigrations(), findUp(), resolveMigrationsDir(), resolveSeedDir(), ensureSeeded(), notify(), jobByName(), JobCtx (+13 more)

### Community 3 - "Auth & Debug/Backup"
Cohesion: 0.27
Nodes (15): getAuth(), backupDir(), GET(), POST(), GET(), GET(), GET(), Termin (+7 more)

### Community 4 - "Ressourcen-Browser (UI)"
Cohesion: 0.12
Nodes (16): AUTO, Column, ImageSpec, imgOf(), LONG, QuickAction, ResourceBrowser(), Row (+8 more)

### Community 5 - "Agent-Endpunkte"
Cohesion: 0.42
Nodes (9): ActionBody, POST(), GET(), POST(), resourceByKey(), fail(), notFound(), POST() (+1 more)

### Community 6 - "Auth-Rollen & Config/Jobs"
Cohesion: 0.44
Nodes (7): hasRole(), GET(), PUT(), forbidden(), POST(), POST(), POST()

### Community 7 - "Generisches CRUD"
Cohesion: 0.44
Nodes (9): Ctx, DELETE(), GET(), isDry(), PATCH(), POST(), PUT(), readBody() (+1 more)

### Community 8 - "Portal & Navigation"
Cohesion: 0.33
Nodes (5): Bereich, DOMAIN_OF, GRADIENTS, Portal(), LogoutButton()

### Community 9 - "HTTP-Antworten & Media"
Cohesion: 0.33
Nodes (3): NOSTORE, GET(), MIME

### Community 10 - "Log-Ringpuffer"
Cohesion: 0.6
Nodes (4): GET(), buffer, size(), tail()

## Knowledge Gaps
- **39 isolated node(s):** `config`, `metadata`, `viewport`, `DOMAIN_OF`, `GRADIENTS` (+34 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `getDb()` connect `Datenbank & FTS-Suche` to `Domaenen-API-Routen & Layout`, `Migration, Seed & Jobs`, `Auth & Debug/Backup`, `Ressourcen-Browser (UI)`, `Auth-Rollen & Config/Jobs`, `Generisches CRUD`, `Portal & Navigation`, `HTTP-Antworten & Media`?**
  _High betweenness centrality (0.198) - this node is a cross-community bridge._
- **Why does `getAuth()` connect `Auth & Debug/Backup` to `Datenbank & FTS-Suche`, `Domaenen-API-Routen & Layout`, `Migration, Seed & Jobs`, `Agent-Endpunkte`, `Auth-Rollen & Config/Jobs`, `Generisches CRUD`, `HTTP-Antworten & Media`, `Log-Ringpuffer`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._
- **Why does `config` connect `Domaenen-API-Routen & Layout` to `HTTP-Antworten & Media`, `Migration, Seed & Jobs`, `Auth & Debug/Backup`, `Agent-Endpunkte`?**
  _High betweenness centrality (0.047) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `getDb()` (e.g. with `register()` and `GET()`) actually correct?**
  _`getDb()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `config`, `metadata`, `viewport` to the rest of the system?**
  _39 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Datenbank & FTS-Suche` be split into smaller, more focused modules?**
  _Cohesion score 0.13 - nodes in this community are weakly interconnected._
- **Should `Domaenen-API-Routen & Layout` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._