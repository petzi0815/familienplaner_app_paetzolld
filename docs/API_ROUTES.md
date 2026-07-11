# API Routes

| Route | Methods | File |
|---|---|---|
| `/api/bedarf` | GET, POST | `app/familienplaner-webapp/src/app/api/bedarf/route.ts` |
| `/api/bedarf/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/bedarf/[id]/route.ts` |
| `/api/buecher` | GET, POST | `app/familienplaner-webapp/src/app/api/buecher/route.ts` |
| `/api/buecher/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/buecher/[id]/route.ts` |
| `/api/buecher/download` | POST, GET | `app/familienplaner-webapp/src/app/api/buecher/download/route.ts` |
| `/api/buecher/enrich` | GET | `app/familienplaner-webapp/src/app/api/buecher/enrich/route.ts` |
| `/api/buecher/retry` | POST | `app/familienplaner-webapp/src/app/api/buecher/retry/route.ts` |
| `/api/buecher/search` | GET | `app/familienplaner-webapp/src/app/api/buecher/search/route.ts` |
| `/api/elisbooks/books` | GET, POST | `app/familienplaner-webapp/src/app/api/elisbooks/books/route.ts` |
| `/api/elisbooks/books/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/elisbooks/books/[id]/route.ts` |
| `/api/elisbooks/books/bulk` | POST | `app/familienplaner-webapp/src/app/api/elisbooks/books/bulk/route.ts` |
| `/api/elisbooks/bookshelves` | GET, POST | `app/familienplaner-webapp/src/app/api/elisbooks/bookshelves/route.ts` |
| `/api/elisbooks/bookshelves/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/elisbooks/bookshelves/[id]/route.ts` |
| `/api/elisbooks/bookshelves/bulk` | POST | `app/familienplaner-webapp/src/app/api/elisbooks/bookshelves/bulk/route.ts` |
| `/api/elisbooks/covers/[...path]` | GET | `app/familienplaner-webapp/src/app/api/elisbooks/covers/[...path]/route.ts` |
| `/api/elisbooks/functions/ai-metadata-cleaner` | POST | `app/familienplaner-webapp/src/app/api/elisbooks/functions/ai-metadata-cleaner/route.ts` |
| `/api/elisbooks/functions/ai-metadata-enhancer` | POST | `app/familienplaner-webapp/src/app/api/elisbooks/functions/ai-metadata-enhancer/route.ts` |
| `/api/elisbooks/functions/openai-book-recommendations` | POST | `app/familienplaner-webapp/src/app/api/elisbooks/functions/openai-book-recommendations/route.ts` |
| `/api/elisbooks/functions/shelf-scanner-ocr` | POST | `app/familienplaner-webapp/src/app/api/elisbooks/functions/shelf-scanner-ocr/route.ts` |
| `/api/elisbooks/settings` | GET, POST | `app/familienplaner-webapp/src/app/api/elisbooks/settings/route.ts` |
| `/api/elisbooks/stats` | GET | `app/familienplaner-webapp/src/app/api/elisbooks/stats/route.ts` |
| `/api/elisbooks/wishlist` | GET, POST | `app/familienplaner-webapp/src/app/api/elisbooks/wishlist/route.ts` |
| `/api/elisbooks/wishlist/[id]` | PATCH, DELETE | `app/familienplaner-webapp/src/app/api/elisbooks/wishlist/[id]/route.ts` |
| `/api/elisbooks/wishlist/bulk` | POST | `app/familienplaner-webapp/src/app/api/elisbooks/wishlist/bulk/route.ts` |
| `/api/garten/aufgaben` | GET, POST | `app/familienplaner-webapp/src/app/api/garten/aufgaben/route.ts` |
| `/api/garten/aufgaben/[id]` | GET, PUT, DELETE | `app/familienplaner-webapp/src/app/api/garten/aufgaben/[id]/route.ts` |
| `/api/garten/duenger` | GET, POST, PUT, DELETE | `app/familienplaner-webapp/src/app/api/garten/duenger/route.ts` |
| `/api/garten/duenger/[id]` | GET | `app/familienplaner-webapp/src/app/api/garten/duenger/[id]/route.ts` |
| `/api/garten/duenger/link` | POST, DELETE | `app/familienplaner-webapp/src/app/api/garten/duenger/link/route.ts` |
| `/api/garten/gts` | GET | `app/familienplaner-webapp/src/app/api/garten/gts/route.ts` |
| `/api/garten/images/[...path]` | GET | `app/familienplaner-webapp/src/app/api/garten/images/[...path]/route.ts` |
| `/api/garten/pflanzen` | GET, POST | `app/familienplaner-webapp/src/app/api/garten/pflanzen/route.ts` |
| `/api/garten/pflanzen/[id]` | GET, PUT, DELETE | `app/familienplaner-webapp/src/app/api/garten/pflanzen/[id]/route.ts` |
| `/api/garten/samen` | GET, POST | `app/familienplaner-webapp/src/app/api/garten/samen/route.ts` |
| `/api/garten/samen/[id]` | GET, PUT, DELETE | `app/familienplaner-webapp/src/app/api/garten/samen/[id]/route.ts` |
| `/api/garten/stats` | GET | `app/familienplaner-webapp/src/app/api/garten/stats/route.ts` |
| `/api/geschenkplaner/dashboard` | GET | `app/familienplaner-webapp/src/app/api/geschenkplaner/dashboard/route.ts` |
| `/api/geschenkplaner/ereignisse` | GET | `app/familienplaner-webapp/src/app/api/geschenkplaner/ereignisse/route.ts` |
| `/api/geschenkplaner/ereignisse/[id]` | GET, PATCH | `app/familienplaner-webapp/src/app/api/geschenkplaner/ereignisse/[id]/route.ts` |
| `/api/geschenkplaner/ereignisse/generieren` | POST | `app/familienplaner-webapp/src/app/api/geschenkplaner/ereignisse/generieren/route.ts` |
| `/api/geschenkplaner/geschenke` | GET, POST | `app/familienplaner-webapp/src/app/api/geschenkplaner/geschenke/route.ts` |
| `/api/geschenkplaner/geschenke/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/geschenkplaner/geschenke/[id]/route.ts` |
| `/api/geschenkplaner/geschenke/[id]/schon-geschenkt` | POST | `app/familienplaner-webapp/src/app/api/geschenkplaner/geschenke/[id]/schon-geschenkt/route.ts` |
| `/api/geschenkplaner/geschenke/[id]/vergeben` | POST | `app/familienplaner-webapp/src/app/api/geschenkplaner/geschenke/[id]/vergeben/route.ts` |
| `/api/geschenkplaner/kinder` | GET, POST | `app/familienplaner-webapp/src/app/api/geschenkplaner/kinder/route.ts` |
| `/api/geschenkplaner/kinder/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/geschenkplaner/kinder/[id]/route.ts` |
| `/api/geschenkplaner/kinder/[id]/anlaesse` | GET, PUT | `app/familienplaner-webapp/src/app/api/geschenkplaner/kinder/[id]/anlaesse/route.ts` |
| `/api/geschenkplaner/kinder/[id]/profil-bestaetigen` | POST | `app/familienplaner-webapp/src/app/api/geschenkplaner/kinder/[id]/profil-bestaetigen/route.ts` |
| `/api/geschenkplaner/vergangene-geschenke` | GET, POST | `app/familienplaner-webapp/src/app/api/geschenkplaner/vergangene-geschenke/route.ts` |
| `/api/geschenkplaner/vergangene-geschenke/[id]` | DELETE | `app/familienplaner-webapp/src/app/api/geschenkplaner/vergangene-geschenke/[id]/route.ts` |
| `/api/gypsi/futter` | GET, POST | `app/familienplaner-webapp/src/app/api/gypsi/futter/route.ts` |
| `/api/gypsi/futter/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/gypsi/futter/[id]/route.ts` |
| `/api/gypsi/images/[...path]` | GET | `app/familienplaner-webapp/src/app/api/gypsi/images/[...path]/route.ts` |
| `/api/images/[...path]` | GET | `app/familienplaner-webapp/src/app/api/images/[...path]/route.ts` |
| `/api/items` | GET | `app/familienplaner-webapp/src/app/api/items/route.ts` |
| `/api/items/[id]` | GET, PUT, DELETE | `app/familienplaner-webapp/src/app/api/items/[id]/route.ts` |
| `/api/marken` | GET | `app/familienplaner-webapp/src/app/api/marken/route.ts` |
| `/api/marken/[name]` | GET | `app/familienplaner-webapp/src/app/api/marken/[name]/route.ts` |
| `/api/reiniger` | GET, POST | `app/familienplaner-webapp/src/app/api/reiniger/route.ts` |
| `/api/reiniger/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/reiniger/[id]/route.ts` |
| `/api/reiniger/images/[...path]` | GET | `app/familienplaner-webapp/src/app/api/reiniger/images/[...path]/route.ts` |
| `/api/reisen` | GET, POST | `app/familienplaner-webapp/src/app/api/reisen/route.ts` |
| `/api/reisen/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/reisen/[id]/route.ts` |
| `/api/reisen/[id]/activities` | GET, POST, DELETE | `app/familienplaner-webapp/src/app/api/reisen/[id]/activities/route.ts` |
| `/api/reisen/[id]/dayplans` | POST | `app/familienplaner-webapp/src/app/api/reisen/[id]/dayplans/route.ts` |
| `/api/reisen/[id]/docs` | GET, POST | `app/familienplaner-webapp/src/app/api/reisen/[id]/docs/route.ts` |
| `/api/reisen/[id]/docs/[docId]` | GET, DELETE | `app/familienplaner-webapp/src/app/api/reisen/[id]/docs/[docId]/route.ts` |
| `/api/reisen/[id]/packing` | GET, POST | `app/familienplaner-webapp/src/app/api/reisen/[id]/packing/route.ts` |
| `/api/reisen/[id]/restaurants` | GET, POST, DELETE | `app/familienplaner-webapp/src/app/api/reisen/[id]/restaurants/route.ts` |
| `/api/reisen/[id]/weather-live` | GET | `app/familienplaner-webapp/src/app/api/reisen/[id]/weather-live/route.ts` |
| `/api/reisen/wochenende/[id]` | GET | `app/familienplaner-webapp/src/app/api/reisen/wochenende/[id]/route.ts` |
| `/api/smarthome/aliases` | GET, POST, DELETE | `app/familienplaner-webapp/src/app/api/smarthome/aliases/route.ts` |
| `/api/smarthome/ask` | POST, GET | `app/familienplaner-webapp/src/app/api/smarthome/ask/route.ts` |
| `/api/smarthome/entities` | GET | `app/familienplaner-webapp/src/app/api/smarthome/entities/route.ts` |
| `/api/smarthome/entities/toggle-disabled` | POST | `app/familienplaner-webapp/src/app/api/smarthome/entities/toggle-disabled/route.ts` |
| `/api/smarthome/exec` | GET | `app/familienplaner-webapp/src/app/api/smarthome/exec/route.ts` |
| `/api/smarthome/log` | GET | `app/familienplaner-webapp/src/app/api/smarthome/log/route.ts` |
| `/api/smarthome/prompt` | GET | `app/familienplaner-webapp/src/app/api/smarthome/prompt/route.ts` |
| `/api/smarthome/relationships` | GET, POST, DELETE, PATCH | `app/familienplaner-webapp/src/app/api/smarthome/relationships/route.ts` |
| `/api/smarthome/stats` | GET | `app/familienplaner-webapp/src/app/api/smarthome/stats/route.ts` |
| `/api/termine` | GET, POST | `app/familienplaner-webapp/src/app/api/termine/route.ts` |
| `/api/termine/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/termine/[id]/route.ts` |
| `/api/vorratskammer` | GET, POST | `app/familienplaner-webapp/src/app/api/vorratskammer/route.ts` |
| `/api/vorratskammer/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/vorratskammer/[id]/route.ts` |
| `/api/vorratskammer/images/[...path]` | GET | `app/familienplaner-webapp/src/app/api/vorratskammer/images/[...path]/route.ts` |
| `/api/vorratskammer/rezepte` | GET, POST, DELETE | `app/familienplaner-webapp/src/app/api/vorratskammer/rezepte/route.ts` |
| `/api/wunschliste/enrich` | POST | `app/familienplaner-webapp/src/app/api/wunschliste/enrich/route.ts` |
| `/api/wunschliste/events` | GET, POST | `app/familienplaner-webapp/src/app/api/wunschliste/events/route.ts` |
| `/api/wunschliste/events/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/wunschliste/events/[id]/route.ts` |
| `/api/wunschliste/items` | GET, POST | `app/familienplaner-webapp/src/app/api/wunschliste/items/route.ts` |
| `/api/wunschliste/items/[id]` | GET, PATCH, DELETE | `app/familienplaner-webapp/src/app/api/wunschliste/items/[id]/route.ts` |
| `/api/wunschliste/pricecheck` | POST | `app/familienplaner-webapp/src/app/api/wunschliste/pricecheck/route.ts` |
| `/api/wunschliste/scrape` | POST | `app/familienplaner-webapp/src/app/api/wunschliste/scrape/route.ts` |
