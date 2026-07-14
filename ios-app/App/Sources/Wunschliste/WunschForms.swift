import SwiftUI

// Modale Formulare der Wunschliste (Geschenk hinzufügen, Anlass anlegen).

// MARK: - Geschenk hinzufügen

struct WunschItemFormSheet: View {
    let defaultEventID: Int?
    @EnvironmentObject private var store: WunschlisteStore
    @Environment(\.dismiss) private var dismiss

    @State private var eventID = 0
    @State private var url = ""
    @State private var title = ""
    @State private var description = ""
    @State private var price = ""
    @State private var category = ""
    @State private var ean = ""
    @State private var notes = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Anlass") {
                    Picker("Anlass *", selection: $eventID) {
                        Text("– bitte wählen –").tag(0)
                        ForEach(store.events) { ev in
                            Text("\(ev.emoji) \(ev.name)").tag(ev.id)
                        }
                    }
                }
                Section {
                    TextField("🔗 Link (optional)", text: $url)
                        .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Text("Automatisches Ausfüllen aus dem Link ist nicht verfügbar – bitte manuell eintragen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Geschenk") {
                    TextField("Titel / Artikelname *", text: $title)
                    TextField("Beschreibung", text: $description, axis: .vertical).lineLimit(2...5)
                }
                Section("Details") {
                    TextField("💰 Preis (z.B. ~9,99€)", text: $price)
                    Picker("Kategorie", selection: $category) {
                        ForEach(WunschStyle.categories, id: \.value) { c in
                            Text(c.label).tag(c.value)
                        }
                    }
                    TextField("📊 EAN / ISBN", text: $ean).font(.body.monospaced())
                    TextField("📝 Notizen", text: $notes, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle("🎁 Neues Geschenk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { Task { await save() } }
                        .disabled(!canSave || saving)
                }
            }
            .onAppear {
                if eventID == 0 {
                    eventID = defaultEventID ?? store.events.first?.id ?? 0
                }
            }
        }
    }

    private var canSave: Bool {
        eventID > 0 && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() async {
        saving = true
        let ok = await store.addItem(eventId: eventID, title: title, description: description,
                                     price: price, url: url, category: category, ean: ean, notes: notes)
        saving = false
        if ok { dismiss() }
    }
}

// MARK: - Anlass anlegen

struct WunschEventFormSheet: View {
    @EnvironmentObject private var store: WunschlisteStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "🎁"
    @State private var hasDate = false
    @State private var date = Date()
    @State private var saving = false

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Emoji") {
                    HStack(spacing: 10) {
                        ForEach(WunschStyle.eventPresets, id: \.emoji) { preset in
                            Button {
                                emoji = preset.emoji
                                if name.trimmingCharacters(in: .whitespaces).isEmpty, let n = preset.name { name = n }
                            } label: {
                                Text(preset.emoji)
                                    .font(.title2)
                                    .frame(width: 46, height: 46)
                                    .background(emoji == preset.emoji ? AnyShapeStyle(WunschStyle.accent.opacity(0.2))
                                                                       : AnyShapeStyle(Color(.secondarySystemBackground)),
                                                in: Circle())
                                    .overlay(Circle().strokeBorder(emoji == preset.emoji ? WunschStyle.accent : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
                Section("Anlass") {
                    TextField("Event-Name *", text: $name)
                    Toggle("Datum angeben", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Datum", selection: $date, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("🎉 Neuer Anlass")
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
        let d = hasDate ? Self.isoFmt.string(from: date) : nil
        let ok = await store.addEvent(name: name, emoji: emoji, date: d)
        saving = false
        if ok { dismiss() }
    }
}
