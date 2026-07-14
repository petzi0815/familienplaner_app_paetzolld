import SwiftUI

/// „Buch suchen"-Tab: externe Shelfmark-Suche (Anna's Archive) → Treffer herunterladen oder auf die
/// Wunschliste setzen. Darunter das manuelle Anlegen als Fallback (kein externer Dienst nötig).
struct EbooksSearchView: View {
    @EnvironmentObject private var store: EbooksStore

    private var canSearch: Bool { store.searchQuery.trimmingCharacters(in: .whitespaces).count >= 2 && !store.searching }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                searchCard
                if store.searching || store.searchError != nil || !store.searchResults.isEmpty {
                    resultsCard
                }
                EbookManualAddForm().environmentObject(store)
            }
            .padding(14)
            .padding(.bottom, 24)
        }
    }

    // ── Externe Suche ──
    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Externe Buchsuche", systemImage: "magnifyingglass").font(.headline)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Titel, Autor oder ISBN …", text: $store.searchQuery)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { Task { await store.performSearch() } }
                    .accessibilityIdentifier("ebook-search-field")
                if !store.searchQuery.isEmpty {
                    Button { store.searchQuery = ""; store.searchResults = []; store.searchError = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button { Task { await store.performSearch() } } label: {
                Label(store.searching ? "Sucht …" : "Buch suchen", systemImage: "magnifyingglass")
            }
            .buttonStyle(GradientButtonStyle(gradientKey: "ebooks", enabled: canSearch))
            .disabled(!canSearch)
            .accessibilityIdentifier("ebook-search-button")

            Text("Sucht über die familieneigene Shelfmark-Instanz und lädt direkt nach Calibre. Kein Treffer? Unten manuell auf die Wunschliste setzen — Ole sucht regelmäßig danach.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // ── Ergebnisse ──
    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.searching {
                HStack(spacing: 8) { ProgressView(); Text("Sucht bei Shelfmark …").foregroundStyle(.secondary) }
                    .font(.caption)
            } else if let e = store.searchError {
                Label(e, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(store.searchResults.count) Treffer").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            ForEach(store.searchResults) { r in
                ShelfmarkResultRow(result: r).environmentObject(store)
                if r.id != store.searchResults.last?.id { Divider() }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Eine Zeile eines externen Suchtreffers mit Download-/Wunschliste-Aktion.
struct ShelfmarkResultRow: View {
    let result: ShelfmarkResult
    @EnvironmentObject private var store: EbooksStore
    private var busy: Bool { store.downloadingID == result.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            if let a = result.author, !a.isEmpty {
                Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let f = result.format, !f.isEmpty { Pill(text: f.uppercased(), color: EbookStyle.indigo, filled: false) }
                    if let s = result.size, !s.isEmpty { Pill(text: s, color: .gray, filled: false) }
                    if let l = EbookStyle.langLabel(result.language) { Pill(text: l, color: EbookStyle.green, filled: false) }
                    if let y = result.year, !y.isEmpty { Pill(text: y, color: .gray, filled: false) }
                    if let p = result.publisher, !p.isEmpty { Pill(text: p, color: .gray, filled: false) }
                }
            }
            HStack(spacing: 10) {
                Button { Task { await store.downloadResult(result, addOnly: false) } } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill").font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent).tint(EbookStyle.rose).disabled(busy)
                Button { Task { await store.downloadResult(result, addOnly: true) } } label: {
                    Label("Wunschliste", systemImage: "star").font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered).disabled(busy)
                if busy { ProgressView() }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Manuelles Anlegen

struct EbookManualAddForm: View {
    @EnvironmentObject private var store: EbooksStore

    @State private var title = ""; @State private var author = ""; @State private var publisher = ""
    @State private var year = ""; @State private var category = ""; @State private var language = "de"
    @State private var isbn = ""; @State private var descriptionText = ""; @State private var notes = ""
    @State private var saving = false

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !saving }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Manuell zur Wunschliste", systemImage: "square.and.pencil").font(.headline)

            field("Titel", text: $title, placeholder: "Buchtitel …")
            HStack(spacing: 10) {
                field("Autor", text: $author, placeholder: "optional")
                field("Verlag", text: $publisher, placeholder: "optional")
            }
            HStack(spacing: 10) {
                field("Jahr", text: $year, placeholder: "z.B. 2024", keyboard: .numberPad)
                field("Sprache", text: $language, placeholder: "de", autocap: false)
            }
            field("Kategorie", text: $category, placeholder: "optional")
            field("ISBN", text: $isbn, placeholder: "optional", keyboard: .numbersAndPunctuation, autocap: false)

            VStack(alignment: .leading, spacing: 4) {
                Text("Beschreibung").font(.caption).foregroundStyle(.secondary)
                TextField("optional", text: $descriptionText, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Notizen").font(.caption).foregroundStyle(.secondary)
                TextField("optional", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4)
            }

            Button {
                Task { await submit() }
            } label: {
                Label(saving ? "Speichert …" : "Auf Wunschliste setzen", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(GradientButtonStyle(gradientKey: "ebooks", enabled: canSave))
            .disabled(!canSave)
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType = .default, autocap: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .autocorrectionDisabled(!autocap)
        }
    }

    private func submit() async {
        saving = true
        let ok = await store.createManual(
            title: title, author: author, publisher: publisher, year: year,
            category: category, language: language, isbn: isbn,
            descriptionText: descriptionText, notes: notes)
        saving = false
        if ok {
            title = ""; author = ""; publisher = ""; year = ""; category = ""
            language = "de"; isbn = ""; descriptionText = ""; notes = ""
            store.tab = .wunschliste
        }
    }
}
