import ActivityKit
import Foundation

/// Live Activities für Termine (Sperrbildschirm + Dynamic Island).
///
/// Aufgabenteilung mit dem Backend:
/// - **Push-to-start**: das Gerät liefert ein `pushToStartTokenUpdates`-Token → wir melden es als
///   `kind:"start"`; der Job `termine-live-activity` startet damit die Activity per APNs.
/// - **Update/Ende**: jede laufende Activity liefert ein eigenes `pushTokenUpdates`-Token →
///   `kind:"update"` inkl. `activity_id`/`termin_id`.
/// - **Lokaler Fallback**: beim App-Start bzw. Foreground starten wir für den nächsten Termin
///   HEUTE selbst eine Activity, falls noch keine läuft (push-to-start greift erst, wenn das
///   Token registriert ist).
///
/// Alles best-effort: wirft nie, ist No-Op wenn Live Activities deaktiviert sind.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    /// Der API-Client der App (schwach — AppState hält ihn).
    private weak var api: APIClient?
    private var started = false
    /// Laufende Beobachter (Token-Streams) — beim Abmelden abbrechen.
    private var tasks: [Task<Void, Never>] = []
    /// Bereits beobachtete Activity-IDs (doppelte Beobachter vermeiden).
    private var observedIds: Set<String> = []

    /// Schlüssel der zuletzt ans Backend gemeldeten Live-Activity-Tokens. Persistiert, weil ein
    /// Logout auch direkt nach dem App-Start (bevor die Token-Streams etwas geliefert haben)
    /// aufräumen können muss — sonst startet der Server weiter Activities auf diesem Gerät.
    private static let reportedTokensKey = "liveActivityReportedTokens"

    private var reportedTokens: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.reportedTokensKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.reportedTokensKey) }
    }

    /// Beobachtung starten (idempotent). Wird beim Login/App-Start aufgerufen.
    func start(api: APIClient) {
        self.api = api
        guard !started, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        started = true
        observePushToStart()
        observeActivities()
        Task { await ensureLocalActivity() }
    }

    /// Alles beenden: Beobachter abbrechen und laufende Activities schließen.
    ///
    /// - Parameter unregisterRemote: beim Abmelden `true` — dann werden die gemeldeten Tokens
    ///   zusätzlich serverseitig entfernt (`DELETE /api/v1/push/live-activity`). **Muss aufgerufen
    ///   werden, SOLANGE der API-Key noch gesetzt ist** (die Requests werden hier synchron gebaut).
    func stopAll(unregisterRemote: Bool = false) {
        if unregisterRemote { unregisterTokens() }
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        observedIds.removeAll()
        started = false
        let running = Activity<TerminActivityAttributes>.activities
        Task {
            for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Gemeldete Live-Activity-Tokens serverseitig löschen. Best-effort: Requests werden JETZT
    /// gebaut (Key noch gültig) und im Hintergrund abgeschickt — der Logout blockiert nie und
    /// scheitert nie an einem Netzfehler.
    private func unregisterTokens() {
        let tokens = reportedTokens
        reportedTokens = []
        guard !tokens.isEmpty else { return }
        let requests: [URLRequest] = tokens.compactMap { token in
            guard var req = SharedStore.request("/api/v1/push/live-activity", method: "DELETE") else { return nil }
            req.timeoutInterval = 5
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
            return req
        }
        guard !requests.isEmpty else { return }
        Task.detached(priority: .utility) {
            for req in requests { _ = try? await URLSession.shared.data(for: req) }
        }
    }

    // MARK: - Token-Beobachtung

    /// Push-to-start-Token des Geräts (pro Attributes-Typ) ans Backend melden.
    private func observePushToStart() {
        tasks.append(Task { [weak self] in
            for await tokenData in Activity<TerminActivityAttributes>.pushToStartTokenUpdates {
                await self?.report(token: Self.hex(tokenData), kind: "start")
            }
        })
    }

    /// Bereits laufende Activities beobachten + neu (auch per Push) gestartete aufgreifen.
    private func observeActivities() {
        for activity in Activity<TerminActivityAttributes>.activities { observe(activity) }
        tasks.append(Task { [weak self] in
            for await activity in Activity<TerminActivityAttributes>.activityUpdates {
                self?.observe(activity)
            }
        })
    }

    /// Update-Token einer konkreten Activity melden (einmal je Activity).
    private func observe(_ activity: Activity<TerminActivityAttributes>) {
        guard !observedIds.contains(activity.id) else { return }
        observedIds.insert(activity.id)
        let activityId = activity.id
        let terminId = activity.attributes.terminId
        tasks.append(Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                await self?.report(token: Self.hex(tokenData), kind: "update",
                                   activityId: activityId, terminId: terminId)
            }
        })
    }

    private func report(token: String, kind: String, activityId: String? = nil, terminId: Int? = nil) async {
        guard let api else { return }
        // Erst merken, dann melden: beim Abmelden müssen wir GENAU diese Tokens wieder löschen.
        reportedTokens.insert(token)
        try? await api.registerLiveActivityToken(token: token, kind: kind,
                                                 activityId: activityId, terminId: terminId)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Lokaler Start-Fallback

    /// Für den nächsten (noch nicht vorbeigegangenen) Termin HEUTE eine Activity starten,
    /// falls für diesen Termin noch keine läuft. Ohne Login/ohne Feed = No-Op.
    func ensureLocalActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let api else { return }
        guard let feed = try? await api.widgetTermine(days: 1) else { return }
        let now = Date()
        let cal = Calendar.current
        let candidate = feed.items.first { item in
            item.source == "termin" && !item.muted && item.refId > 0
                && cal.isDate(item.startDate, inSameDayAs: now) && !item.isPast(at: now)
        }
        guard let t = candidate else { return }
        let running = Activity<TerminActivityAttributes>.activities
        guard !running.contains(where: { $0.attributes.terminId == t.refId }) else { return }

        let state = TerminActivityAttributes.ContentState(
            title: t.title,
            subtitle: t.subtitle,
            location: t.location,
            startAtEpoch: t.startAt,
            endAtEpoch: t.endAt,
            allDay: t.allDay,
            status: t.isRunning(at: now) ? "laeuft" : "bevorstehend",
            emoji: t.emoji,
            ackedBy: t.read ? [SharedStore.owner ?? "ich"] : []
        )
        // Der Widget-Feed liefert keine Kategorie-ID → `source` als grober Typ; der Server
        // überschreibt die Attribute ohnehin, sobald er die Activity selbst startet.
        let attributes = TerminActivityAttributes(terminId: t.refId, category: t.source)
        // Nach Terminende (bzw. +2 h ohne Ende) ist die Anzeige veraltet.
        let stale = (t.endDate ?? t.startDate.addingTimeInterval(7200)).addingTimeInterval(1800)
        let content = ActivityContent(state: state, staleDate: stale, relevanceScore: 1.0)
        do {
            let activity = try Activity<TerminActivityAttributes>.request(
                attributes: attributes, content: content, pushType: .token)
            observe(activity)
        } catch {
            // Best-effort — z.B. Limit erreicht oder vom Nutzer verboten.
        }
    }

    // MARK: - Sofort-Rückmeldung nach dem Quittieren

    /// Laufende Activity eines Termins lokal auf „quittiert" setzen (der Server schickt
    /// zusätzlich ein Push-Update — das hier ist die sofortige Rückmeldung).
    ///
    /// Die eigentliche Logik liegt in `Shared/WidgetIntents.swift` (`TerminLiveActivity`), damit
    /// der Quittieren-Button aus Widget/Live Activity (`TerminAckIntent`, kompiliert auch in der
    /// Extension) exakt dasselbe tut wie die App.
    func markAcked(terminId: Int) async {
        await TerminLiveActivity.markAcked(terminId: terminId)
    }

    /// Activity eines Termins beenden (z.B. nach „erledigt"/„stumm").
    func end(terminId: Int) async {
        await TerminLiveActivity.end(terminId: terminId)
    }
}
