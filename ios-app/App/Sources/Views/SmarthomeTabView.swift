import SwiftUI

/// „Smarthome"-Tab (Schnellzugriff): Alarmanlage + Raffstore-Steuerung (Höhe & Lamellen-Neigung) + Szenen.
struct SmarthomeTabView: View {
    @EnvironmentObject private var app: AppState

    private let scriptCols = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if app.alarmo?.configured != false { AlarmoTile() }
                    raffstoreSection
                    szenenSection
                }
                .padding()
            }
            .background(Palette.gradient(for: "smarthome").opacity(0.06).ignoresSafeArea())
            .navigationTitle("Smarthome")
            .refreshable { await app.loadAlarmo(); await app.loadHouse() }
            .task { if !app.houseLoaded { await app.loadHouse() } }
            .task { if app.alarmo == nil { await app.loadAlarmo() } }
            .areaToast($app.houseMessage, isError: app.houseMessageIsError)
        }
    }

    // ── Raffstores ──
    @ViewBuilder private var raffstoreSection: some View {
        SectionCard(title: "Raffstores", systemImage: "blinds.horizontal.closed", key: "smarthome") {
            if !app.houseLoaded && app.houseCovers.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 12)
            } else if app.houseCovers.isEmpty {
                Text(app.houseConfigured ? "Keine Raffstores gefunden." : "Home Assistant ist nicht konfiguriert.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                ForEach(app.houseCovers) { cover in
                    BlindCard(cover: cover) { action, value in
                        Task { await app.coverAction(entity: cover.entity, action: action, value: value) }
                    }
                    if cover.id != app.houseCovers.last?.id { Divider().padding(.vertical, 4) }
                }
            }
        }
    }

    // ── Szenen (Scripts) ──
    @ViewBuilder private var szenenSection: some View {
        if !app.houseScripts.isEmpty {
            SectionCard(title: "Szenen", systemImage: "wand.and.stars", key: "smarthome") {
                LazyVGrid(columns: scriptCols, spacing: 12) {
                    ForEach(app.houseScripts) { s in
                        Button { Task { await app.runScript(s) } } label: {
                            VStack(spacing: 8) {
                                Image(systemName: s.icon).font(.title3)
                                Text(s.name).font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Palette.gradient(for: "smarthome"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("script-\(s.entity)")
                    }
                }
            }
        }
    }
}

/// Eine Raffstore-Karte: Visual + Höhen-/Neigungs-Slider + Auf/Stop/Zu-Knöpfe.
/// Die Slider committen erst beim Loslassen (kein HA-Spam während des Ziehens).
struct BlindCard: View {
    let cover: RaffstoreCover
    let onAction: (String, Int?) -> Void

    @State private var pos: Double
    @State private var tilt: Double
    @State private var editingPos = false
    @State private var editingTilt = false
    // „pending" = der Nutzer hat einen Zielwert gesetzt und der Raffstore fährt noch dorthin →
    // Server-Zwischenstände NICHT auf den Slider zurückschreiben (sonst springt er während der Fahrt).
    @State private var pendingPos = false
    @State private var pendingTilt = false

    init(cover: RaffstoreCover, onAction: @escaping (String, Int?) -> Void) {
        self.cover = cover
        self.onAction = onAction
        _pos = State(initialValue: Double(cover.position ?? 0))
        _tilt = State(initialValue: Double(cover.tilt ?? 0))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                BlindGlyph(position: Int(pos), tilt: Int(tilt))
                VStack(alignment: .leading, spacing: 3) {
                    Text(cover.name).font(.headline)
                    Text(stateText).font(.caption).foregroundStyle(cover.reachable ? Color.secondary : Color.red)
                }
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    iconButton("chevron.up") { onAction("open", nil) }
                    iconButton("stop.fill") { onAction("stop", nil) }
                    iconButton("chevron.down") { onAction("close", nil) }
                }
            }
            slider(icon: "arrow.up.and.down", value: $pos, editing: $editingPos, pending: $pendingPos, action: "set_position")
            slider(icon: "line.3.horizontal.decrease", value: $tilt, editing: $editingTilt, pending: $pendingTilt, action: "set_tilt")
        }
        .padding(.vertical, 4)
        .opacity(cover.reachable ? 1 : 0.55)
        .accessibilityIdentifier("blind-\(cover.entity)")
        // Externen Zustand übernehmen — außer der Nutzer zieht gerade (editing) ODER der Raffstore fährt
        // noch auf einen gesetzten Zielwert zu (pending) → dann lokalen Wert halten (kein Springen).
        .onChange(of: cover.position) { _, n in sync(n, to: $pos, editing: editingPos, pending: $pendingPos) }
        .onChange(of: cover.tilt) { _, n in sync(n, to: $tilt, editing: editingTilt, pending: $pendingTilt) }
    }

    /// Server-Wert übernehmen, sofern nicht gerade editiert wird; bei „pending" erst wenn das Ziel
    /// (±2 %) erreicht ist (dann pending lösen und wieder live folgen).
    private func sync(_ newValue: Int?, to local: Binding<Double>, editing: Bool, pending: Binding<Bool>) {
        guard let newValue else { return }
        if editing { return }
        if pending.wrappedValue {
            if abs(Double(newValue) - local.wrappedValue) <= 2 { pending.wrappedValue = false }
            return
        }
        local.wrappedValue = Double(newValue)
    }

    private var stateText: String {
        if !cover.reachable { return "Nicht erreichbar" }
        var parts: [String] = []
        if let p = cover.position { parts.append("\(p)% offen") }
        switch cover.state {
        case "opening": parts.append("öffnet …")
        case "closing": parts.append("schließt …")
        default: break
        }
        return parts.isEmpty ? (cover.state ?? "—") : parts.joined(separator: " · ")
    }

    private func slider(icon: String, value: Binding<Double>, editing: Binding<Bool>, pending: Binding<Bool>, action: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 20)
            Slider(value: value, in: 0...100, step: 1, onEditingChanged: { ed in
                editing.wrappedValue = ed
                if !ed {
                    pending.wrappedValue = true
                    onAction(action, Int(value.wrappedValue.rounded()))
                }
            })
            .tint(Palette.colors(for: "smarthome").first!)
            .disabled(!cover.reachable)
            Text("\(Int(value.wrappedValue))%")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!cover.reachable)
    }
}

/// Kleines Raffstore-Symbol: Fenster mit Lamellen. Füllhöhe = geschlossener Anteil (100−Höhe),
/// Lamellen-Abstand steigt mit der Neigung (offener = mehr Licht/Sicht).
struct BlindGlyph: View {
    let position: Int   // 0..100 (100 = offen)
    let tilt: Int       // 0..100

    private let boxW: CGFloat = 40
    private let boxH: CGFloat = 52

    var body: some View {
        let coverFrac = CGFloat(max(0, min(100, 100 - position))) / 100
        let gap = 1.5 + CGFloat(max(0, min(100, tilt))) / 100 * 3.5
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            VStack(spacing: gap) {
                ForEach(0..<12, id: \.self) { _ in
                    Capsule().fill(Color.secondary.opacity(0.65)).frame(height: 2.5)
                }
            }
            .padding(.horizontal, 5)
            .padding(.top, 4)
            .frame(height: boxH * coverFrac, alignment: .top)
            .clipped()
        }
        .frame(width: boxW, height: boxH)
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.secondary.opacity(0.25)))
        .animation(.easeInOut(duration: 0.25), value: position)
        .accessibilityHidden(true)
    }
}
