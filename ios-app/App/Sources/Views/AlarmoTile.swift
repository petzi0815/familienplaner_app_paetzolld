import SwiftUI

/// Alarmanlage-Kachel auf „Heute" (ersetzt die frühere globale Suche — die war doppelt zum Suchen-Tab).
/// Zeigt den Live-Status der „Alarmo"-Alarmanlage (Home Assistant) und schaltet scharf/unscharf.
/// Der PIN liegt SERVERSEITIG — hier wird nie ein Code eingegeben (Wunsch Lars).
struct AlarmoTile: View {
    @EnvironmentObject private var app: AppState

    private var status: AlarmoStatus? { app.alarmo }

    var body: some View {
        HStack(spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text("Alarmanlage").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                // Offene Tür/Fenster verhindern das Scharfschalten → proaktiv anzeigen (nur wenn unscharf).
                if let open = status?.openSensors, !open.isEmpty, status?.isDisarmed == true {
                    Label("Offen: \(open.joined(separator: ", "))", systemImage: "door.left.hand.open")
                        .font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
                if let err = app.alarmoError {
                    Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(16)
        .cardSurface()
        // KEIN Container-.accessibilityIdentifier hier: SwiftUI propagiert ihn auf ALLE Kind-Elemente
        // und ueberschreibt damit deren eigene IDs (alarmo-arm/alarmo-disarm/alarmo-retry) — die
        // Steuerung waere dann fuer XCUITest nur noch als „alarmo-tile" auffindbar. Die Kinder tragen
        // ihre eigenen, sprechenden IDs; die Kachel selbst braucht keine.
        // Fehlermeldung nach kurzer Zeit automatisch ausblenden. Cancellation-sicher:
        // bei Wechsel A→B wird die A-Task abgebrochen → NICHT die frische Meldung B löschen.
        .task(id: app.alarmoError) {
            guard app.alarmoError != nil else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            app.alarmoError = nil
        }
    }

    // ── Status-Icon (Farbe + Symbol je Zustand) ──
    private var icon: some View {
        Image(systemName: iconName)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(iconColor.onFill)   // luminanz-sicher (schwarz auf grün/orange, weiß auf rot/grau)
            .symbolEffect(.pulse, isActive: status?.isTriggered == true)
            .frame(width: 46, height: 46)
            .background(iconColor.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // ── Steuerung (rechts): Aktivieren-Menü / Deaktivieren / Aktualisieren / Spinner ──
    @ViewBuilder private var control: some View {
        if app.alarmoBusy || status == nil {
            // Läuft ein Schaltvorgang ODER Erstladen (status noch nil) → Spinner statt Retry-Knopf.
            ProgressView().frame(width: 64)
        } else if let s = status, s.reachable, s.isKnown {
            if s.isDisarmed {
                armMenu
            } else {
                disarmButton
            }
        } else {
            Button { Task { await app.loadAlarmo() } } label: {
                Image(systemName: "arrow.clockwise").font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("alarmo-retry")
        }
    }

    private var armMenu: some View {
        Menu {
            Button { act("arm_away") } label: { Label("Abwesend", systemImage: "figure.walk.departure") }
            Button { act("arm_home") } label: { Label("Zuhause", systemImage: "house.fill") }
            Button { act("arm_night") } label: { Label("Nacht", systemImage: "moon.stars.fill") }
        } label: {
            pillLabel("Aktivieren", systemImage: "lock.fill", color: .green)
        }
        .accessibilityIdentifier("alarmo-arm")
    }

    private var disarmButton: some View {
        Button { act("disarm") } label: {
            pillLabel("Deaktivieren", systemImage: "lock.open.fill", color: .red)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("alarmo-disarm")
    }

    private func pillLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(color, in: Capsule())
            .foregroundStyle(color.onFill)
    }

    private func act(_ action: String) { Task { await app.alarmoAction(action) } }

    // ── Ableitungen aus dem Zustand ──
    private var statusText: String {
        guard let s = status else { return "Wird geladen …" }
        if !s.reachable { return "Nicht erreichbar" }
        switch s.state {
        case "disarmed": return "Deaktiviert"
        case "arming": return "Wird aktiviert …"
        case "pending": return "Eingangsverzögerung läuft"
        case "triggered": return "Alarm ausgelöst!"
        case "armed_away": return "Scharf · Abwesend"
        case "armed_home": return "Scharf · Zuhause"
        case "armed_night": return "Scharf · Nacht"
        case "armed_vacation": return "Scharf · Urlaub"
        case "armed_custom_bypass": return "Scharf · Bypass"
        default: return s.state.map { "Status: \($0)" } ?? "Unbekannt"
        }
    }

    private var iconName: String {
        guard let s = status else { return "shield" }          // Erstladen: neutral
        if !s.reachable { return "shield.slash.fill" }
        if s.isTriggered { return "exclamationmark.shield.fill" }
        if s.isArming { return "shield.lefthalf.filled" }
        if s.isArmed { return "lock.shield.fill" }
        return "shield" // disarmed
    }

    private var iconColor: Color {
        guard let s = status, s.reachable else { return .gray }
        if s.isTriggered { return .red }
        if s.isArming { return .orange }
        if s.isArmed { return .red }
        return .green // disarmed
    }
}
