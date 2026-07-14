import SwiftUI
import AVKit

/// „Smarthome"-Tab (Schnellzugriff): Alarmanlage + Kameras + Raffstore-Steuerung (Höhe & Lamellen) + Szenen.
struct SmarthomeTabView: View {
    @EnvironmentObject private var app: AppState
    @State private var liveCamera: Camera?

    private let scriptCols = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]
    private let cameraCols = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if app.alarmo?.configured != false { AlarmoTile() }
                    kamerasSection
                    raffstoreSection
                    szenenSection
                }
                .padding()
            }
            .background(Palette.gradient(for: "smarthome").opacity(0.06).ignoresSafeArea())
            .navigationTitle("Smarthome")
            .refreshable { await app.loadAlarmo(); await app.loadHouse(); await app.loadCameras() }
            .task { if !app.houseLoaded { await app.loadHouse() } }
            .task { if !app.camerasLoaded { await app.loadCameras() } }
            .task { if app.alarmo == nil { await app.loadAlarmo() } }
            .areaToast($app.houseMessage, isError: app.houseMessageIsError)
            .fullScreenCover(item: $liveCamera) { cam in CameraLiveView(camera: cam) }
        }
    }

    // ── Kameras (Schnappschuss-Raster, Tap → Live-Stream) ──
    @ViewBuilder private var kamerasSection: some View {
        if !app.cameras.isEmpty {
            SectionCard(title: "Kameras", systemImage: "video.fill", key: "smarthome") {
                LazyVGrid(columns: cameraCols, spacing: 10) {
                    ForEach(app.cameras) { cam in
                        CameraThumb(camera: cam) { liveCamera = cam }
                    }
                }
            }
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

/// Kamera-Kachel mit automatisch aktualisierendem Schnappschuss (Tap → Live-Stream).
/// Polling nur, solange die App aktiv ist (scenePhase-gekoppelter Task).
struct CameraThumb: View {
    let camera: Camera
    let onTap: () -> Void
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var failed = false

    private var taskKey: String { "\(camera.entity)-\(scenePhase == .active)" }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color(.secondarySystemBackground))
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else if failed {
                    Image(systemName: "video.slash.fill").font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .center)
                    .allowsHitTesting(false)
                HStack(spacing: 5) {
                    Image(systemName: "play.circle.fill")
                    Text(camera.name).font(.caption.weight(.semibold)).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(8)
            }
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("camera-\(camera.entity)")
        .task(id: taskKey) {
            guard scenePhase == .active else { return }
            await refreshLoop()
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            if let data = try? await app.api.cameraSnapshot(entity: camera.entity), let img = UIImage(data: data) {
                image = img; failed = false
            } else if image == nil {
                failed = true
            }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
        }
    }
}

/// Vollbild-Live-Ansicht einer Kamera (HLS über AVPlayer; Stream-URL kommt frisch vom Backend/HA).
struct CameraLiveView: View {
    let camera: Camera
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player).ignoresSafeArea(edges: .bottom)
                } else if let errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                        Text(errorText).font(.callout).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                        Button("Erneut") { Task { await start() } }.buttonStyle(.borderedProminent)
                    }.padding()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle(camera.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
            .task { await start() }
            .onDisappear { player?.pause(); player = nil }
        }
    }

    private func start() async {
        errorText = nil
        player = nil
        do {
            let url = try await app.api.cameraStreamURL(entity: camera.entity)
            let item = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: item)
            p.play()
            player = p
            // Auf readyToPlay/failed warten → bei Fehler die ECHTE Ursache zeigen (statt AVKit-Standardsymbol).
            for _ in 0..<24 {
                if item.status == .failed {
                    errorText = item.error?.localizedDescription ?? "Stream konnte nicht geladen werden."
                    player = nil
                    return
                }
                if item.status == .readyToPlay { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Live-Stream nicht verfügbar."
        }
    }
}
