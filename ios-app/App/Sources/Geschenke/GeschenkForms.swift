import SwiftUI

// Modale Formulare des Geschenkplaners (Kind anlegen, Geschenk anlegen/bearbeiten, vergangenes Geschenk).

// MARK: - Kind anlegen

struct GChildCreateSheet: View {
    @EnvironmentObject private var store: GeschenkStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hatGeburtsdatum = false
    @State private var geburtsdatum = Date()
    @State private var profil = ""
    @State private var negativliste = ""
    @State private var saving = false

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Kind") {
                    TextField("Name *", text: $name)
                    Toggle("Geburtsdatum angeben", isOn: $hatGeburtsdatum)
                    if hatGeburtsdatum {
                        DatePicker("Geburtsdatum", selection: $geburtsdatum, displayedComponents: .date)
                    } else {
                        Text("Ohne Geburtsdatum werden keine Geburtstags-Ereignisse generiert.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Profil (Interessen, Hobbys)") {
                    TextField("Interessen, Hobbys …", text: $profil, axis: .vertical).lineLimit(3...6)
                }
                Section("🚫 Negativliste") {
                    TextField("z.B. Kleidung, Süßigkeiten, Videospiele …", text: $negativliste, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("👶 Kind hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        let geb = hatGeburtsdatum ? Self.isoFmt.string(from: geburtsdatum) : ""
        let ok = await store.createKind(name: name, geburtsdatum: geb, profil: profil, negativliste: negativliste)
        saving = false
        if ok { dismiss() }
    }
}

// MARK: - Geschenk anlegen/bearbeiten

struct GGiftFormSheet: View {
    let ereignisID: Int
    let kindId: Int
    let gift: GGeschenk?
    @EnvironmentObject private var store: GeschenkStore
    @Environment(\.dismiss) private var dismiss

    @State private var titel = ""
    @State private var beschreibung = ""
    @State private var preis = ""
    @State private var status = "vorschlag"
    @State private var ranking = "0"
    @State private var shop = ""
    @State private var quelle = ""
    @State private var url = ""
    @State private var notizen = ""
    @State private var saving = false

    private var isEdit: Bool { gift != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Geschenk") {
                    TextField("Titel *", text: $titel)
                    TextField("Beschreibung", text: $beschreibung, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    TextField("Preis (€)", text: $preis).keyboardType(.decimalPad)
                    Picker("Status", selection: $status) {
                        ForEach(GStyle.statuses, id: \.self) { s in Text(GStyle.statusLabel(s)).tag(s) }
                    }
                    HStack {
                        Text("Ranking")
                        Spacer()
                        Button { adjustRanking(-1) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                            .buttonStyle(.plain)
                        TextField("0", text: $ranking).keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.center).frame(width: 60)
                        Button { adjustRanking(1) } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.green) }
                            .buttonStyle(.plain)
                    }
                }
                Section("Details") {
                    TextField("Shop", text: $shop)
                    TextField("Quelle (z.B. Lars, AI)", text: $quelle)
                    TextField("URL (https://…)", text: $url).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Notizen", text: $notizen, axis: .vertical).lineLimit(2...4)
                }
                if isEdit {
                    Section {
                        Button { Task { await schonGeschenkt() } } label: {
                            Label("Hatten wir schon (archivieren)", systemImage: "arrow.uturn.left")
                                .foregroundStyle(Color(hex: "F97316"))
                        }
                    }
                }
            }
            .navigationTitle(isEdit ? "✏️ Geschenk bearbeiten" : "🎁 Geschenk hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { Task { await save() } }
                        .disabled(titel.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        guard let g = gift else { return }
        titel = g.titel
        beschreibung = g.beschreibung ?? ""
        preis = g.preis.map { String(format: "%g", $0) } ?? ""
        status = g.status
        ranking = String(g.ranking ?? 0)
        shop = g.shop ?? ""
        quelle = g.quelle ?? ""
        url = g.url ?? ""
        notizen = g.notizen ?? ""
    }

    private func adjustRanking(_ delta: Int) {
        ranking = String((Int(ranking) ?? 0) + delta)
    }

    private func opt(_ s: String) -> Any { s.trimmingCharacters(in: .whitespaces).isEmpty ? NSNull() : s }

    private func preisValue() -> Any {
        let t = preis.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { return NSNull() }
        return Double(t).map { $0 as Any } ?? NSNull()
    }

    private func save() async {
        saving = true
        var body: [String: Any] = [
            "titel": titel,
            "beschreibung": opt(beschreibung),
            "preis": preisValue(),
            "url": opt(url),
            "shop": opt(shop),
            "quelle": opt(quelle),
            "notizen": opt(notizen),
            "status": status,
            "ranking": Int(ranking) ?? 0,
        ]
        do {
            if let g = gift {
                try await store.api.updateGeschenk(g.id, body)
                store.notify("Geschenk aktualisiert ✅")
            } else {
                body["ereignis_id"] = ereignisID
                body["kind_id"] = kindId
                body["ist_manuell"] = 1
                _ = try await store.api.createGeschenk(body)
                store.notify("Geschenk hinzugefügt ✅")
            }
            await store.loadDashboard(); await store.loadEinkauf()
            saving = false
            dismiss()
        } catch {
            store.notify(store.errText(error), error: true)
            saving = false
        }
    }

    private func schonGeschenkt() async {
        guard let g = gift else { return }
        do {
            try await store.api.schonGeschenkt(g.id)
            store.notify("Als schon geschenkt markiert & entfernt 🔄")
            await store.loadDashboard(); await store.loadEinkauf()
            dismiss()
        } catch { store.notify(store.errText(error), error: true) }
    }
}

// MARK: - Vergangenes Geschenk eintragen

struct GPastGiftSheet: View {
    let kinder: [GKind]
    @EnvironmentObject private var store: GeschenkStore
    @Environment(\.dismiss) private var dismiss

    @State private var kindId = 0
    @State private var titel = ""
    @State private var anlass = ""
    @State private var jahr = String(GDate.currentYear())
    @State private var notizen = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Vergangenes Geschenk") {
                    Picker("Kind *", selection: $kindId) {
                        ForEach(kinder) { k in Text(k.name).tag(k.id) }
                    }
                    TextField("Titel *", text: $titel)
                }
                Section {
                    Picker("Anlass", selection: $anlass) {
                        Text("–").tag("")
                        ForEach(GStyle.anlassOrder, id: \.self) { a in Text(GStyle.anlassLabel(a)).tag(a) }
                    }
                    TextField("Jahr", text: $jahr).keyboardType(.numberPad)
                    TextField("Notizen", text: $notizen, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("📦 Vergangenes Geschenk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { Task { await save() } }
                        .disabled(kindId == 0 || titel.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear { if kindId == 0, let first = kinder.first { kindId = first.id } }
        }
    }

    private func save() async {
        saving = true
        let ok = await store.createVergangenes(kindId: kindId, titel: titel, anlass: anlass, jahr: Int(jahr), notizen: notizen)
        saving = false
        if ok { dismiss() }
    }
}
