import SwiftUI
import UIKit

// MARK: - Kartenliste (Raster mit Summen-Kopf)

struct TrauerkartenListView: View {
    @EnvironmentObject private var store: TrauerkartenStore
    @State private var detail: Trauerkarte?
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            summary
            if store.visibleKarten.isEmpty {
                AreaEmptyState(emoji: "🕊️",
                               title: store.search.isEmpty ? "Noch keine Trauerkarten erfasst." : "Keine Treffer",
                               hint: store.search.isEmpty ? "Tippe oben rechts auf +, um eine Karte hinzuzufügen." : nil)
                    .frame(minHeight: 240)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(Array(store.visibleKarten.enumerated()), id: \.element.id) { idx, k in
                        Button { detail = k } label: { TrauerkarteCell(karte: k, index: idx + 1) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("karte-\(k.id)")
                    }
                }
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 28)
            }
        }
        .sheet(item: $detail) { k in TrauerkarteDetailSheet(karte: k).environmentObject(store) }
    }

    private var summary: some View {
        HStack {
            Text("\(String(store.kartenAnzahl)) \(store.kartenAnzahl == 1 ? "Karte" : "Karten")")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(TrauerStyle.primary, in: Capsule())
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("Gesamt-Trauergeld").font(.caption2).foregroundStyle(.secondary)
                Text(TrauerStyle.eur(store.trauerkartenSumme)).font(.title3.weight(.bold)).foregroundStyle(TrauerStyle.einnahme)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 14).padding(.top, 10)
    }
}

struct TrauerkarteCell: View {
    let karte: Trauerkarte
    let index: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color(.tertiarySystemBackground)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay { AuthImage(path: karte.fotoPath, contentMode: .fill) }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Text(TrauerStyle.eur(karte.geldbetrag))
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(TrauerStyle.einnahme, in: Capsule())
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    Text(String(index)).font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Color.black.opacity(0.6), in: Circle())
                        .padding(6)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(karte.name).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                if !karte.trauertext.isEmpty {
                    Text(karte.trauertext).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(TrauerStyle.prettyDate(karte.createdAt)).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    }
}

// MARK: - Detail

struct TrauerkarteDetailSheet: View {
    let karte: Trauerkarte
    @EnvironmentObject private var store: TrauerkartenStore
    @Environment(\.dismiss) private var dismiss
    @State private var edit = false
    @State private var confirmDelete = false

    private var current: Trauerkarte { store.karten.first { $0.id == karte.id } ?? karte }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AuthImage(path: current.fotoPath, contentMode: .fit)
                        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 380)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text(current.name).font(.title3.weight(.bold))
                    InfoRow(icon: "💶", label: "Geldbetrag", value: TrauerStyle.eur(current.geldbetrag), valueColor: TrauerStyle.einnahme)
                    InfoRow(icon: "👤", label: "Person", value: store.personName(current.personId))
                    if let d = current.createdAt, !d.isEmpty { InfoRow(icon: "📅", label: "Erfasst", value: TrauerStyle.prettyDate(d)) }
                    if !current.trauertext.isEmpty {
                        Text("Trauertext").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.top, 4)
                        Text(current.trauertext).font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(16)
            }
            .navigationTitle("Trauerkarte").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { edit = true } label: { Label("Bearbeiten", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Löschen", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $edit) { TrauerkarteFormSheet(karte: current).environmentObject(store) }
            .confirmationDialog("\(current.name) löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { Task { await store.deleteKarte(current); dismiss() } }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }
}

// MARK: - Anlegen / Bearbeiten (mit KI-Scan)

struct TrauerkarteFormSheet: View {
    let karte: Trauerkarte?
    @EnvironmentObject private var store: TrauerkartenStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var trauertext = ""
    @State private var betrag = ""
    @State private var personId: Int?
    @State private var pickedImage: UIImage?
    @State private var pickerSource: ImageSource?
    @State private var scanning = false
    @State private var saving = false

    private var isEdit: Bool { karte != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Foto") { photoSection }
                Section("Karte") {
                    TextField("Absender / Familie *", text: $name)
                    TextField("Trauertext", text: $trauertext, axis: .vertical).lineLimit(3...8)
                    HStack { TextField("Geldbetrag *", text: $betrag).keyboardType(.decimalPad); Text("€").foregroundStyle(.secondary) }
                    Picker("Person", selection: $personId) {
                        Text("Alle Personen").tag(Int?.none)
                        ForEach(store.personen) { p in Text(p.name).tag(Int?.some(p.id)) }
                    }
                }
            }
            .navigationTitle(isEdit ? "Karte bearbeiten" : "Neue Trauerkarte").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .sheet(item: $pickerSource) { src in
                ImagePicker(sourceType: src.type) { img in pickedImage = img }.ignoresSafeArea()
            }
            .onAppear(perform: prime)
        }
    }

    @ViewBuilder private var photoSection: some View {
        if let img = pickedImage {
            Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let path = karte?.fotoPath {
            AuthImage(path: path, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 200)
        }
        HStack(spacing: 16) {
            Button { pickerSource = ImageSource(.camera) } label: { Label("Kamera", systemImage: "camera") }
            Button { pickerSource = ImageSource(.photoLibrary) } label: { Label("Auswählen", systemImage: "photo") }
        }
        if pickedImage != nil {
            Button { Task { await runScan() } } label: {
                if scanning { HStack(spacing: 8) { ProgressView(); Text("KI liest die Karte …") } }
                else { Label("Mit KI auslesen", systemImage: "sparkles").foregroundStyle(TrauerStyle.accent) }
            }
            .disabled(scanning)
        }
    }

    private func prime() {
        guard let k = karte else { return }
        name = k.name; trauertext = k.trauertext
        betrag = k.geldbetrag == 0 ? "" : String(format: "%.2f", k.geldbetrag).replacingOccurrences(of: ".", with: ",")
        personId = k.personId
    }

    private func runScan() async {
        guard let jpeg = pickedImage?.jpegForUpload() else { return }
        scanning = true; defer { scanning = false }
        guard let r = await store.scan(jpeg: jpeg) else { return }
        if let n = r["name"] as? String, !n.isEmpty { name = n }
        if let t = r["trauertext"] as? String, !t.isEmpty { trauertext = t }
        if let b = Coerce.double(r["geldbetrag"]), b > 0 {
            betrag = String(format: "%.2f", b).replacingOccurrences(of: ".", with: ",")
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let b = Coerce.double(betrag) ?? 0
        let jpeg = pickedImage?.jpegForUpload()
        if await store.saveKarte(id: karte?.id, name: name.trimmingCharacters(in: .whitespaces),
                                 trauertext: trauertext, geldbetrag: b, personId: personId, jpeg: jpeg) {
            dismiss()
        }
    }
}
