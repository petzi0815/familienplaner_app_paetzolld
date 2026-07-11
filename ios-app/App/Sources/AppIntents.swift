import AppIntents

/// Siri/Kurzbefehl: „Foto zum Familienplaner hinzufügen" → öffnet die App auf dem Foto-Tab.
struct FotoHinzufuegenIntent: AppIntent {
    static var title: LocalizedStringResource = "Foto zum Familienplaner hinzufügen"
    static var description = IntentDescription("Öffnet den Familienplaner, um ein Foto aufzunehmen und zuzuordnen.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.appState?.selectedTab = .foto
        return .result()
    }
}

struct FamilienplanerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FotoHinzufuegenIntent(),
            phrases: [
                "Foto in \(.applicationName) aufnehmen",
                "\(.applicationName) Foto hinzufügen",
            ],
            shortTitle: "Foto aufnehmen",
            systemImageName: "camera.fill"
        )
    }
}
