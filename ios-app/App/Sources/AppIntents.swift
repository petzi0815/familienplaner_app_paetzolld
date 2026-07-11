import AppIntents

// Siri / Spotlight / Kurzbefehle. Intents laufen im App-Prozess und lesen dieselbe
// Settings (Base-URL + API-Key aus dem Schlüsselbund) wie die App.

/// „Foto zum Familienplaner hinzufügen" → öffnet die App auf dem Foto-Tab.
struct FotoHinzufuegenIntent: AppIntent {
    static var title: LocalizedStringResource = "Foto zum Familienplaner hinzufügen"
    static var description = IntentDescription("Öffnet den Familienplaner, um ein Foto aufzunehmen und zuzuordnen.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.appState?.requestCamera()
        return .result()
    }
}

/// „Buch scannen" → öffnet den Scan-Hub.
struct BuchScannenIntent: AppIntent {
    static var title: LocalizedStringResource = "Buch scannen"
    static var description = IntentDescription("Öffnet den Scanner, um ein Buch per ISBN zu erfassen.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.appState?.selectedTab = .scan
        return .result()
    }
}

/// „Was steht heute an?" → liest das Dashboard und antwortet per Sprache (ohne App-Öffnen).
struct HeuteIntent: AppIntent {
    static var title: LocalizedStringResource = "Was steht heute an"
    static var description = IntentDescription("Nennt anstehende Termine und fällige Erinnerungen.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = Settings()
        guard settings.isConfigured else { return .result(dialog: "Bitte melde dich zuerst im Familienplaner an.") }
        let api = APIClient(settings: settings)
        do {
            let d = try await api.dashboard()
            var msg = d.termineUpcoming.isEmpty ? "Heute stehen keine Termine an." : "Du hast \(d.termineUpcoming.count) anstehende Termine."
            if let next = d.termineUpcoming.first { msg += " Als Nächstes: \(next.title)." }
            if d.remindersDue > 0 { msg += " \(d.remindersDue) Erinnerungen sind fällig." }
            if d.counts.fotoInboxNeu > 0 { msg += " \(d.counts.fotoInboxNeu) neue Fotos warten auf Zuordnung." }
            return .result(dialog: IntentDialog(stringLiteral: msg))
        } catch {
            return .result(dialog: "Ich konnte die Übersicht gerade nicht laden.")
        }
    }
}

/// „Zum Vorrat hinzufügen" → legt ein Lebensmittel an (fragt nach dem Produktnamen).
struct ZumVorratIntent: AppIntent {
    static var title: LocalizedStringResource = "Zum Vorrat hinzufügen"
    static var description = IntentDescription("Legt ein Lebensmittel in der Vorratskammer an.")

    @Parameter(title: "Produkt")
    var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$name) zur Vorratskammer hinzufügen")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = Settings()
        guard settings.isConfigured else { return .result(dialog: "Bitte melde dich zuerst im Familienplaner an.") }
        let api = APIClient(settings: settings)
        do {
            try await api.createRecord("vorrat-lebensmittel", fields: ["name": name, "kategorie": "trocken"])
            return .result(dialog: "\"\(name)\" wurde zur Vorratskammer hinzugefügt.")
        } catch {
            return .result(dialog: "Ich konnte \"\(name)\" nicht hinzufügen.")
        }
    }
}

struct FamilienplanerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: HeuteIntent(),
                    phrases: ["Was steht heute an in \(.applicationName)", "\(.applicationName) Tagesüberblick"],
                    shortTitle: "Heute", systemImageName: "square.grid.2x2.fill")
        AppShortcut(intent: FotoHinzufuegenIntent(),
                    phrases: ["Foto in \(.applicationName) aufnehmen", "\(.applicationName) Foto hinzufügen"],
                    shortTitle: "Foto aufnehmen", systemImageName: "camera.fill")
        AppShortcut(intent: BuchScannenIntent(),
                    phrases: ["Buch in \(.applicationName) scannen", "\(.applicationName) Buch scannen"],
                    shortTitle: "Buch scannen", systemImageName: "barcode.viewfinder")
        AppShortcut(intent: ZumVorratIntent(),
                    phrases: ["Zum Vorrat in \(.applicationName) hinzufügen", "\(.applicationName) Vorrat ergänzen"],
                    shortTitle: "Zum Vorrat", systemImageName: "carrot.fill")
    }
}
