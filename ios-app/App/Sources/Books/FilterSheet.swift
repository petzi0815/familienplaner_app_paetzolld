import SwiftUI

/// Erweiterte Filter (spec §5): deckt alle Filter-Dimensionen ab und ist an `store.filters` gebunden.
/// "Alle löschen" setzt auf frische `BookFilters()` zurück, behält aber die Sortierung.
struct FilterSheet: View {
    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Suche") {
                    TextField("Nach Titel, Autor, ISBN oder Beschreibung suchen …", text: $store.filters.searchTerm)
                }

                Section {
                    Picker("Regal", selection: $store.filters.bookshelf) {
                        Text("Alle Regale").tag("all")
                        ForEach(store.shelves) { s in Text(s.name).tag(s.id) }
                    }
                    Picker("Verlag", selection: $store.filters.publisher) {
                        Text("Alle").tag("all")
                        ForEach(store.availablePublishers, id: \.self) { p in Text(p).tag(p) }
                    }
                    Picker("Sprache", selection: $store.filters.language) {
                        Text("Alle").tag("all")
                        ForEach(store.availableLanguages, id: \.self) { l in Text(BookFilters.languageLabel(l)).tag(l) }
                    }
                    Picker("Kategorie", selection: $store.filters.category) {
                        Text("Alle").tag("all")
                        ForEach(store.availableCategories, id: \.self) { c in Text(c).tag(c) }
                    }
                }

                Section {
                    HStack {
                        TextField("Von", text: yearFrom).keyboardType(.numberPad)
                        Divider()
                        TextField("Bis", text: yearTo).keyboardType(.numberPad)
                    }
                } header: {
                    Text("Erscheinungsjahr")
                } footer: {
                    if let b = store.yearBounds { Text("Verfügbarer Bereich: \(b.0) - \(b.1)") }
                }

                Section("Lesestatus") {
                    Picker("Lesestatus", selection: $store.filters.readStatus) {
                        Text("Alle").tag(ReadStatus.all)
                        Text("Nur gelesene").tag(ReadStatus.read)
                        Text("Nur ungelesene").tag(ReadStatus.unread)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Beschreibung") {
                    Picker("Beschreibung", selection: descTri) {
                        Text("Alle").tag(0); Text("Ja").tag(1); Text("Nein").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Cover") {
                    Picker("Nur mit Cover", selection: thumbTri) {
                        Text("Alle").tag(0); Text("Ja").tag(1); Text("Nein").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Nur Bücher auf Pickliste", isOn: $store.filters.picklistOnly)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("Erweiterte Filter").font(.headline)
                        if store.filters.activeCount > 0 {
                            Text("\(store.filters.activeCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(BookTheme.amber700.opacity(0.15), in: Capsule())
                                .foregroundStyle(BookTheme.amber900)
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Alle löschen") { clearAll() }.disabled(store.filters.activeCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    // ── Tri-State-Bindings (Alle/Ja/Nein → nil/true/false) ──
    private var descTri: Binding<Int> {
        Binding(get: { triGet(store.filters.hasDescription) }, set: { store.filters.hasDescription = triSet($0) })
    }
    private var thumbTri: Binding<Int> {
        Binding(get: { triGet(store.filters.hasThumbnail) }, set: { store.filters.hasThumbnail = triSet($0) })
    }
    private func triGet(_ v: Bool?) -> Int { v == true ? 1 : (v == false ? 2 : 0) }
    private func triSet(_ i: Int) -> Bool? { i == 1 ? true : (i == 2 ? false : nil) }

    // ── Jahr-Bindings (Int? ↔ String) ──
    private var yearFrom: Binding<String> {
        Binding(get: { store.filters.yearFrom.map(String.init) ?? "" }, set: { store.filters.yearFrom = Int($0) })
    }
    private var yearTo: Binding<String> {
        Binding(get: { store.filters.yearTo.map(String.init) ?? "" }, set: { store.filters.yearTo = Int($0) })
    }

    private func clearAll() {
        let sort = store.filters.sort, asc = store.filters.sortAsc
        var f = BookFilters()
        f.sort = sort; f.sortAsc = asc
        store.filters = f
    }
}
