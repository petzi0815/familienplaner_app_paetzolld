import SwiftUI

/// Modales Anlegen/Bearbeiten eines Termins (native Form + DatePicker + Picker) mit Konflikt-Vorprüfung.
struct TermineFormSheet: View {
    let termin: Termin?
    let initialDate: String?
    @EnvironmentObject private var store: TermineStore
    @Environment(\.dismiss) private var dismiss

    @State private var titel = ""
    @State private var beschreibung = ""
    @State private var kategorie = "allgemein"
    @State private var datum = Date()
    @State private var hatUhrzeit = false
    @State private var uhrzeit = Date()
    @State private var hatEnde = false
    @State private var endeDatum = Date()
    @State private var erinnerung = 2
    @State private var ort = ""
    @State private var person = ""
    @State private var notizen = ""
    @State private var saving = false
    @State private var conflicts: [Termin] = []
    @State private var didPrefill = false

    private var isEdit: Bool { termin != nil }

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Was steht an? *", text: $titel)
                    TextField("Beschreibung / Details", text: $beschreibung, axis: .vertical).lineLimit(2...5)
                    Picker("Kategorie", selection: $kategorie) {
                        ForEach(store.categories) { c in Text("\(c.emoji) \(c.label)").tag(c.id) }
                    }
                }

                Section("Zeit") {
                    DatePicker("Datum *", selection: $datum, displayedComponents: .date)
                    Toggle("Mit Uhrzeit", isOn: $hatUhrzeit)
                    if hatUhrzeit {
                        DatePicker("Uhrzeit", selection: $uhrzeit, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Mehrtägig", isOn: $hatEnde)
                    if hatEnde {
                        DatePicker("Ende", selection: $endeDatum, in: datum..., displayedComponents: .date)
                    }
                }

                if !conflicts.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("⚠️ An diesem Tag gibt es bereits \(conflicts.count) Termin(e):")
                                .font(.caption.weight(.semibold)).foregroundStyle(Color.orange)
                            ForEach(conflicts) { c in
                                Text("\(store.category(c.category).emoji) \(c.title)" + (c.time.map { " · \($0)" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.orange.opacity(0.12))
                }

                Section("Details") {
                    Picker("Erinnerung", selection: $erinnerung) {
                        ForEach(TermineStyle.reminderOptions) { o in Text(o.label).tag(o.id) }
                    }
                    TextField("📍 Ort", text: $ort)
                    Picker("Für …", selection: $person) {
                        Text("–").tag("")
                        ForEach(TermineStyle.persons) { p in Text("\(p.emoji) \(p.label)").tag(p.id) }
                    }
                    TextField("📝 Notizen", text: $notizen, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle(isEdit ? "✏️ Termin bearbeiten" : "📅 Neuer Termin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Speichern" : "Anlegen") { Task { await save() } }
                        .disabled(titel.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: datum) { _, _ in Task { await checkConflicts() } }
        }
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        if let t = termin {
            titel = t.title
            beschreibung = t.beschreibung ?? ""
            kategorie = t.category
            if let d = Self.isoFmt.date(from: t.date) { datum = d }
            if let tm = t.time, !tm.isEmpty, let td = Self.timeFmt.date(from: tm) { hatUhrzeit = true; uhrzeit = td }
            if let e = t.endDate, !e.isEmpty, let ed = Self.isoFmt.date(from: e) { hatEnde = true; endeDatum = ed }
            erinnerung = t.reminderDays
            ort = t.location ?? ""
            person = t.person ?? ""
            notizen = t.notes ?? ""
        } else if let initISO = initialDate, let d = Self.isoFmt.date(from: initISO) {
            datum = d
        }
        Task { await checkConflicts() }
    }

    private func checkConflicts() async {
        let iso = Self.isoFmt.string(from: datum)
        conflicts = (try? await store.api.conflicts(date: iso, exclude: termin?.id)) ?? []
    }

    private func opt(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? NSNull() : t
    }

    private func save() async {
        saving = true
        let timeValue: Any = hatUhrzeit ? Self.timeFmt.string(from: uhrzeit) : NSNull()
        let endValue: Any = hatEnde ? Self.isoFmt.string(from: max(endeDatum, datum)) : NSNull()
        let personValue: Any = person.isEmpty ? NSNull() : person
        let body: [String: Any] = [
            "title": titel.trimmingCharacters(in: .whitespaces),
            "description": opt(beschreibung),
            "category": kategorie,
            "date": Self.isoFmt.string(from: datum),
            "time": timeValue,
            "end_date": endValue,
            "location": opt(ort),
            "person": personValue,
            "reminder_days": erinnerung,
            "notes": opt(notizen),
        ]
        let ok = await store.saveTermin(id: termin?.id, body: body)
        saving = false
        if ok { dismiss() }
    }
}
