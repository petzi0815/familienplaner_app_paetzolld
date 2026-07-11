# Secrets / Environment Variables

Echte Secrets wurden nicht ins Paket gelegt. Für die Ziel-Webapp/API bitte als Env Vars oder Secret Store pflegen:

- `OPENAI_API_KEY`: für Wunschliste-Enrichment, Smart-Home-Fragen und spätere KI-Funktionen.
- `TELEGRAM_BOT_TOKEN`: nur wenn der neue Dienst selbst Telegram-Nachrichten versenden soll.
- `TELEGRAM_FAMILY_CHAT_ID`: Familiengruppe, bisher `-1003415230540`.
- `TELEGRAM_LARS_CHAT_ID`: Lars DM, bisher `484600941`.
- `HOME_ASSISTANT_URL`, `HOME_ASSISTANT_TOKEN`: Smart-Home API.
- `UNIFI_URL`, `UNIFI_USERNAME`, `UNIFI_PASSWORD`: optional für Netzwerkdiagnose.
- `CALIBRE_URL` / Book Downloader API Secrets: für Elitas Bücher-Workflows.
- `DATABASE_URL` oder einzelne DB-Pfade, falls SQLite zunächst weitergenutzt wird.

Empfehlung: Für die Migration keine Tokens in Skripte schreiben. Der redigierte Watchdog zeigt nur die bisherige Betriebslogik.
