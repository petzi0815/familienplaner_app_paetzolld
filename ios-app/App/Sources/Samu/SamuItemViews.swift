import SwiftUI

// MARK: - Item-Karte (Raster)

struct SamuItemCard: View {
    let item: SamuItem
    var onOpen: () -> Void
    var onMarke: (() -> Void)? = nil

    var body: some View {
        let info = SamuStyle.statusInfo(item.status)
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let path = item.imagePath {
                        AuthImage(path: path, contentMode: .fill)
                    } else {
                        Palette.gradient(for: "samu").opacity(0.18)
                            .overlay(Text(item.typEmoji).font(.system(size: 44)).opacity(0.5))
                    }
                }
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Pill(text: "\(info.emoji) \(info.label)", color: info.color)
                    .padding(6)
            }
            HStack(spacing: 4) {
                Text("#\(item.id)").font(.caption2).foregroundStyle(.secondary)
                Text(item.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if item.hasMarke, let onMarke {
                    Button { onMarke() } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            HStack(spacing: 4) {
                Text(item.kategorie ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let g = item.groesse, !g.isEmpty { Text("· Gr. \(g)").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if let w = item.verkaufswert, w > 0 {
                    Text("\(Int(w))€").font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule()).foregroundStyle(Color.green)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

// MARK: - Detail-Sheet (Ansehen + Bearbeiten)

struct SamuItemDetailSheet: View {
    let itemID: Int
    @EnvironmentObject private var store: SamuStore
    @Environment(\.dismiss) private var dismiss

    @State private var item: SamuItem?
    @State private var editMode = false
    @State private var fullscreen: ImageRef?

    // Bearbeiten-Formular
    @State private var fMarke = ""; @State private var fName = ""; @State private var fGroesse = ""
    @State private var fFarbe = ""; @State private var fWert = ""; @State private var fStatus = "aktiv"
    @State private var fZustand = ""; @State private var fNotizen = ""

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    if editMode { editForm(item) } else { detail(item) }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editMode ? "Abbrechen" : "Schließen") {
                        if editMode { editMode = false } else { dismiss() }
                    }
                }
                if let item, !editMode {
                    ToolbarItem(placement: .primaryAction) {
                        Button { startEdit(item) } label: { Label("Bearbeiten", systemImage: "pencil") }
                    }
                }
                if editMode {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") { Task { await save() } }
                    }
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $fullscreen) { ref in SamuFullscreenImage(path: ref.path) }
    }

    // ── Ansehen ──
    private func detail(_ item: SamuItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let path = item.imagePath {
                    AuthImage(path: path, contentMode: .fit)
                        .frame(maxHeight: 300)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .onTapGesture { fullscreen = ImageRef(path: path) }
                } else {
                    Palette.gradient(for: "samu").opacity(0.18)
                        .frame(height: 180)
                        .overlay(Text(item.typEmoji).font(.system(size: 64)).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Text(item.displayTitle).font(.title2.weight(.bold))
                if let name = item.name, name != item.displayTitle { Text(name).foregroundStyle(.secondary) }

                // Status-Schnellumschaltung (aktiv ↔ eingelagert)
                let info = SamuStyle.statusInfo(item.status)
                Button { Task { await store.toggleStatus(item); await load() } } label: {
                    HStack {
                        Text("\(info.emoji) \(info.label)").fontWeight(.semibold)
                        Text("· tippen zum Wechseln").font(.caption).opacity(0.9)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(info.color, in: Capsule())
                    .foregroundStyle(info.color.onFill)
                }
                .buttonStyle(.plain)

                VStack(spacing: 0) {
                    if let v = item.kategorie { InfoRow(icon: "🏷️", label: "Kategorie", value: v) }
                    if let v = item.groesse, !v.isEmpty { InfoRow(icon: "📏", label: "Größe", value: v) }
                    if let v = item.farbe { InfoRow(icon: "🎨", label: "Farbe", value: v) }
                    if let v = item.zustand { InfoRow(icon: "⭐", label: "Zustand", value: zustandLabel(v)) }
                    if let v = item.material { InfoRow(icon: "🧶", label: "Material", value: v) }
                    if let v = item.saison { InfoRow(icon: "🌤️", label: "Saison", value: v) }
                    if let w = item.verkaufswert, w > 0 { InfoRow(icon: "💰", label: "Wert", value: "\(Int(w))€", valueColor: .green) }
                    if let v = item.erfasstAm { InfoRow(icon: "📅", label: "Erfasst", value: DateText.pretty(v)) }
                }
                .padding(.horizontal, 4)

                if let b = item.beschreibung, !b.isEmpty { NoteBlock(icon: "📝", text: b, tint: Color(hex: "F59E0B")) }
                if let n = item.notizen, !n.isEmpty { NoteBlock(icon: "📝", text: n, tint: .yellow) }
            }
            .padding()
        }
    }

    // ── Bearbeiten ──
    private func editForm(_ item: SamuItem) -> some View {
        Form {
            Section("Details") {
                LabeledContent("Marke") { TextField("Marke", text: $fMarke) }
                LabeledContent("Name") { TextField("Name", text: $fName) }
                LabeledContent("Größe") { TextField("Größe", text: $fGroesse) }
                LabeledContent("Farbe") { TextField("Farbe", text: $fFarbe) }
                LabeledContent("Wert (€)") { TextField("0", text: $fWert).keyboardType(.decimalPad) }
            }
            Section("Status & Zustand") {
                Picker("Status", selection: $fStatus) {
                    ForEach(SamuStyle.statusOrder, id: \.self) { s in
                        let i = SamuStyle.statusInfo(s); Text("\(i.emoji) \(i.label)").tag(s)
                    }
                }
                Picker("Zustand", selection: $fZustand) {
                    Text("—").tag("")
                    ForEach(SamuStyle.zustandLabels, id: \.value) { z in Text(z.label).tag(z.value) }
                }
            }
            Section("Notizen") {
                TextField("Notizen", text: $fNotizen, axis: .vertical).lineLimit(3...6)
            }
        }
    }

    private func zustandLabel(_ v: String) -> String {
        SamuStyle.zustandLabels.first { $0.value == v }?.label ?? v
    }

    private func startEdit(_ item: SamuItem) {
        fMarke = item.marke ?? ""; fName = item.name ?? ""; fGroesse = item.groesse ?? ""
        fFarbe = item.farbe ?? ""; fWert = item.verkaufswert.map { String(Int($0)) } ?? ""
        fStatus = item.status; fZustand = item.zustand ?? ""; fNotizen = item.notizen ?? ""
        editMode = true
    }

    private func save() async {
        guard let item else { return }
        let fields: [String: Any] = [
            "name": fName, "marke": fMarke, "groesse": fGroesse, "farbe": fFarbe,
            "zustand": fZustand, "status": fStatus,
            "verkaufswert": Double(fWert.replacingOccurrences(of: ",", with: ".")) ?? 0,
            "notizen": fNotizen,
        ]
        if await store.saveItem(item.id, fields: fields) {
            editMode = false
            await load()
        }
    }

    private func load() async {
        if let fresh = try? await store.api.fetchItem(itemID) { item = fresh }
        else { item = store.items.first { $0.id == itemID } }
    }
}

// MARK: - Marken-Info

struct SamuMarkeSheet: View {
    let name: String
    @EnvironmentObject private var store: SamuStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                let m = store.marke(named: name)
                VStack(alignment: .leading, spacing: 12) {
                    Text("🏷️ \(name)").font(.title2.weight(.bold))
                    if let m {
                        VStack(spacing: 0) {
                            if let v = m.groessenInfo { InfoRow(icon: "📏", label: "Größen-Info", value: v) }
                            if let v = m.herkunft { InfoRow(icon: "🌍", label: "Herkunft", value: v) }
                            if let v = m.materialFokus { InfoRow(icon: "🧶", label: "Material-Fokus", value: v) }
                            if let v = m.preisSegment { InfoRow(icon: "💰", label: "Preissegment", value: v.capitalized) }
                        }
                        if let url = m.websiteURL { Link(destination: url) { Label("Website öffnen", systemImage: "link") } }
                        if let n = m.notizen, !n.isEmpty { NoteBlock(icon: "📝", text: n, tint: .yellow) }
                        if m.angereichertAm != nil { Text("Angereichert: \(DateText.pretty(m.angereichertAm!))").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text("Noch keine Infos vorhanden.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Vollbild

struct SamuFullscreenImage: View {
    let path: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AuthImage(path: path, contentMode: .fit).ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.9))
                    }.padding()
                }
                Spacer()
            }
        }
    }
}

/// Bild-Pfad als Identifiable-Wrapper (für `.fullScreenCover(item:)`).
struct ImageRef: Identifiable { let id = UUID(); let path: String }
/// Markenname als Identifiable-Wrapper (für `.sheet(item:)`).
struct MarkeRef: Identifiable { let id = UUID(); let name: String }
