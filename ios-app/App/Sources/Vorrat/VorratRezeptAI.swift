import SwiftUI

// KI-Rezeptvorschlag (OpenAI) aus bald ablaufenden Lebensmitteln. One-Click: Sheet öffnen → Backend
// generiert ein vollständiges Rezept, das die ablaufenden Zutaten verbraucht (Standardzutaten vorausgesetzt).

// MARK: - Modelle (tolerant via Coerce — Zahlen mal Int/String)

struct RezeptZutat: Identifiable {
    let id = UUID()
    let menge: String?
    let zutat: String
    init(fields f: [String: Any]) { menge = Coerce.str(f["menge"]); zutat = Coerce.str(f["zutat"]) ?? "" }
    var line: String { [menge, zutat].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") }
}

struct Rezept {
    let titel: String
    let beschreibung: String?
    let portionen: Int?
    let dauerMinuten: Int?
    let verwendeteZutaten: [String]
    let zutaten: [RezeptZutat]
    let schritte: [String]
    let tipp: String?

    init(fields f: [String: Any]) {
        titel = Coerce.str(f["titel"]) ?? "Rezept"
        beschreibung = Coerce.str(f["beschreibung"])
        portionen = Coerce.int(f["portionen"])
        dauerMinuten = Coerce.int(f["dauer_minuten"])
        verwendeteZutaten = Coerce.stringArray(f["verwendete_zutaten"])
        zutaten = (f["zutaten"] as? [Any])?.compactMap { ($0 as? [String: Any]).map(RezeptZutat.init(fields:)) } ?? []
        schritte = Coerce.stringArray(f["schritte"])
        tipp = Coerce.str(f["tipp"])
    }

    /// Klartext (für die Ablage in vorrat_rezepte.notizen — die Rezepte-Karte zeigt nur Titel/Beschreibung/Chips).
    var plainText: String {
        var out: [String] = []
        if let b = beschreibung { out.append(b) }
        if !zutaten.isEmpty { out.append("Zutaten:\n" + zutaten.map { "- \($0.line)" }.joined(separator: "\n")) }
        if !schritte.isEmpty { out.append("Zubereitung:\n" + schritte.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")) }
        if let t = tipp, !t.isEmpty { out.append("Tipp: \(t)") }
        return out.joined(separator: "\n\n")
    }
}

// MARK: - Sheet

/// Generiert per One-Click ein KI-Rezept aus den ablaufenden Zutaten und zeigt es vollständig an.
struct RezeptVorschlagSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading
    @State private var rezept: Rezept?
    @State private var errText = ""
    @State private var saving = false
    @State private var saved = false
    @State private var saveError = ""
    enum Phase { case loading, loaded, error }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading: loadingView
                case .error: errorView
                case .loaded: if let r = rezept { rezeptView(r) } else { errorView }
                }
            }
            .navigationTitle("KI-Rezept")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                if phase == .loaded {
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await generate() } } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityIdentifier("rezept-regenerate")
                            .accessibilityLabel("Neues Rezept generieren")
                    }
                }
            }
            .task { if rezept == nil { await generate() } }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Koche mir was aus …").font(.headline)
            Text("Die KI erstellt ein Rezept aus deinen bald ablaufenden Zutaten.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Kein Rezept", systemImage: "fork.knife")
        } description: {
            Text(errText)
        } actions: {
            Button("Erneut versuchen") { Task { await generate() } }.buttonStyle(.glassProminent)
        }
    }

    private func rezeptView(_ r: Rezept) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.titel).font(.title2.weight(.bold)).accessibilityIdentifier("rezept-titel")
                    if let b = r.beschreibung, !b.isEmpty { Text(b).font(.subheadline).foregroundStyle(.secondary) }
                    HStack(spacing: 14) {
                        if let p = r.portionen { Label("\(p) Portionen", systemImage: "person.2.fill") }
                        if let d = r.dauerMinuten { Label("\(d) Min", systemImage: "clock") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }

                if !r.verwendeteZutaten.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Verbraucht diese ablaufenden Zutaten").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(r.verwendeteZutaten.joined(separator: " · "))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.colors(for: "vorratskammer").first!)
                    }
                }

                if !r.zutaten.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zutaten").font(.headline)
                        ForEach(r.zutaten) { z in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundStyle(.secondary)
                                Text(z.line); Spacer(minLength: 0)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if !r.schritte.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Zubereitung").font(.headline)
                        ForEach(Array(r.schritte.enumerated()), id: \.offset) { i, s in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Palette.colors(for: "vorratskammer").first!, in: Circle())
                                Text(s).font(.subheadline); Spacer(minLength: 0)
                            }
                        }
                    }
                }

                if let t = r.tipp, !t.isEmpty { NoteBlock(icon: "💡", text: t, tint: .yellow) }

                Button { Task { await save(r) } } label: {
                    HStack {
                        if saving { ProgressView().padding(.trailing, 4) }
                        Label(saved ? "Gespeichert" : "Zu Rezepten speichern",
                              systemImage: saved ? "checkmark" : "square.and.arrow.down")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).disabled(saving || saved).padding(.top, 4)
                if !saveError.isEmpty { Text(saveError).font(.caption).foregroundStyle(.red) }
            }
            .padding()
        }
    }

    private func generate() async {
        phase = .loading; errText = ""; saved = false; saveError = ""
        do {
            rezept = try await app.api.generateRezept()
            phase = .loaded
        } catch {
            errText = (error as? APIError)?.errorDescription ?? "Rezept konnte nicht erstellt werden."
            phase = .error
        }
    }

    private func save(_ r: Rezept) async {
        saving = true; saveError = ""
        let fields: [String: Any] = [
            "titel": r.titel,
            "beschreibung": r.beschreibung ?? "",
            "zutaten_match": r.verwendeteZutaten.joined(separator: ", "),
            "quelle": "KI (OpenAI)",
            "notizen": r.plainText,
        ]
        do {
            _ = try await app.api.createRecord("vorrat-rezepte", fields: fields)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            saved = true
        } catch {
            saveError = (error as? APIError)?.errorDescription ?? "Speichern fehlgeschlagen."
        }
        saving = false
    }
}
