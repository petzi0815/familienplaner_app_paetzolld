import SwiftUI

// MARK: - Detail-Sheet (Ansehen + Menü Bearbeiten/Löschen)

struct VertragDetailSheet: View {
    let vertragID: Int
    @EnvironmentObject private var store: VertraegeStore
    @Environment(\.dismiss) private var dismiss

    @State private var vertrag: Vertrag?
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let v = vertrag {
                    detail(v)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                if vertrag != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { editing = true } label: { Label("Bearbeiten", systemImage: "pencil") }
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Löschen", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Vertrag wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let v = vertrag { Task { await store.delete(v); dismiss() } }
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .sheet(isPresented: $editing) {
                VertragEditSheet(existing: vertrag).environmentObject(store)
            }
            .onChange(of: editing) { _, isEditing in
                if !isEditing { Task { await load() } }   // nach dem Bearbeiten neu laden
            }
        }
        .task { await load() }
    }

    private func detail(_ v: Vertrag) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text(v.catIcon).font(.system(size: 26))
                        .frame(width: 52, height: 52)
                        .background(v.catColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.anbieter ?? "—").font(.title3.weight(.bold))
                        if let t = v.bezeichnung, !t.isEmpty { Text(t).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }

                // Kosten prominent
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let k = v.kosten {
                        Text(VertragFmt.eur(k)).font(.system(size: 30, weight: .heavy))
                    } else {
                        Text("—").font(.system(size: 30, weight: .heavy)).foregroundStyle(.secondary)
                    }
                    if let i = v.kostenIntervall, !i.isEmpty { Text(i.capitalized).foregroundStyle(.secondary) }
                }
                if v.kosten != nil, (v.kostenIntervall ?? "monatlich").lowercased() != "monatlich" {
                    Text("≈ \(VertragFmt.eurMo(v.monatlich))").font(.subheadline).foregroundStyle(.secondary)
                }

                if let nr = v.vertragsnummer, !nr.isEmpty {
                    Button { store.copy(nr) } label: {
                        Label("Nr. \(nr)", systemImage: "doc.on.doc")
                            .font(.subheadline.monospaced())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 0) {
                    InfoRow(icon: "🏷️", label: "Kategorie", value: v.kategorieName)
                    if let x = v.kundennummer, !x.isEmpty { InfoRow(icon: "🆔", label: "Kundennummer", value: x) }
                    if let x = v.beginn, !x.isEmpty { InfoRow(icon: "📅", label: "Beginn", value: DateText.pretty(x)) }
                    if let x = v.laufzeitBis, !x.isEmpty { InfoRow(icon: "⏳", label: "Laufzeit bis", value: DateText.pretty(x)) }
                    if let x = v.kuendigungsfrist, !x.isEmpty { InfoRow(icon: "✂️", label: "Kündigungsfrist", value: x) }
                    if let x = v.verlaengerung, !x.isEmpty { InfoRow(icon: "🔁", label: "Verlängerung", value: x) }
                    if let x = v.status, !x.isEmpty { InfoRow(icon: "📍", label: "Status", value: x.capitalized) }
                }
                .padding(.horizontal, 4)

                if let n = v.notizen, !n.isEmpty { NoteBlock(icon: "📝", text: n, tint: .yellow) }
            }
            .padding()
        }
    }

    private func load() async {
        if let fresh = try? await store.api.fetchOne(vertragID) { vertrag = fresh }
        else { vertrag = store.vertraege.first { $0.id == vertragID } }
    }
}

// MARK: - Bearbeiten / Neu

struct VertragEditSheet: View {
    let existing: Vertrag?
    @EnvironmentObject private var store: VertraegeStore
    @Environment(\.dismiss) private var dismiss

    @State private var kategorie: String
    @State private var anbieter: String
    @State private var bezeichnung: String
    @State private var kundennummer: String
    @State private var vertragsnummer: String
    @State private var kosten: String
    @State private var intervall: String
    @State private var beginn: String
    @State private var laufzeitBis: String
    @State private var kuendigungsfrist: String
    @State private var verlaengerung: String
    @State private var status: String
    @State private var notizen: String
    @State private var saving = false

    init(existing: Vertrag?) {
        self.existing = existing
        _kategorie = State(initialValue: existing?.kategorie ?? "")
        _anbieter = State(initialValue: existing?.anbieter ?? "")
        _bezeichnung = State(initialValue: existing?.bezeichnung ?? "")
        _kundennummer = State(initialValue: existing?.kundennummer ?? "")
        _vertragsnummer = State(initialValue: existing?.vertragsnummer ?? "")
        _kosten = State(initialValue: existing?.kosten.map { VertragFmt.plain($0) } ?? "")
        _intervall = State(initialValue: existing?.kostenIntervall ?? "monatlich")
        _beginn = State(initialValue: existing?.beginn ?? "")
        _laufzeitBis = State(initialValue: existing?.laufzeitBis ?? "")
        _kuendigungsfrist = State(initialValue: existing?.kuendigungsfrist ?? "")
        _verlaengerung = State(initialValue: existing?.verlaengerung ?? "")
        _status = State(initialValue: existing?.status ?? "aktiv")
        _notizen = State(initialValue: existing?.notizen ?? "")
    }

    private var isNew: Bool { existing == nil }
    private var canSave: Bool { !anbieter.trimmingCharacters(in: .whitespaces).isEmpty && !saving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vertrag") {
                    TextField("Anbieter", text: $anbieter)
                    TextField("Bezeichnung", text: $bezeichnung)
                    HStack {
                        TextField("Kategorie", text: $kategorie)
                        Menu {
                            ForEach(VertragStyle.catOrder, id: \.self) { name in
                                Button(name) { kategorie = name }
                            }
                        } label: {
                            Image(systemName: "list.bullet.circle")
                        }
                    }
                }
                Section("Kosten") {
                    LabeledContent("Betrag (€)") {
                        TextField("0,00", text: $kosten).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Intervall", selection: $intervall) {
                        ForEach(VertragStyle.intervalle, id: \.self) { i in Text(i.capitalized).tag(i) }
                    }
                }
                Section("Vertragsdaten") {
                    TextField("Kundennummer", text: $kundennummer)
                    TextField("Vertragsnummer", text: $vertragsnummer)
                    TextField("Beginn (z.B. 2024-01-01)", text: $beginn)
                    TextField("Laufzeit bis", text: $laufzeitBis)
                    TextField("Kündigungsfrist", text: $kuendigungsfrist)
                    TextField("Verlängerung", text: $verlaengerung)
                    Picker("Status", selection: $status) {
                        ForEach(VertragStyle.statusWerte, id: \.self) { s in Text(s.capitalized).tag(s) }
                    }
                }
                Section("Notizen") {
                    TextField("Notizen", text: $notizen, axis: .vertical).lineLimit(3...6)
                }
            }
            .navigationTitle(isNew ? "Neuer Vertrag" : "Vertrag bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { Task { await save() } }.disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        var body: [String: Any] = [:]
        func put(_ key: String, _ val: String) {
            let t = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { body[key] = t }
        }
        put("kategorie", kategorie)
        put("anbieter", anbieter)
        put("bezeichnung", bezeichnung)
        put("kundennummer", kundennummer)
        put("vertragsnummer", vertragsnummer)
        put("beginn", beginn)
        put("laufzeit_bis", laufzeitBis)
        put("kuendigungsfrist", kuendigungsfrist)
        put("verlaengerung", verlaengerung)
        put("notizen", notizen)
        put("status", status)
        put("kosten_intervall", intervall)
        if let k = Double(kosten.replacingOccurrences(of: ",", with: ".")) { body["kosten"] = k }

        saving = true
        let ok = await store.save(id: existing?.id, fields: body)
        saving = false
        if ok { dismiss() }
    }
}
