import SwiftUI

/// „Buch suchen"-Tab. Die externe Shelfmark-Suche + Google-Books-Anreicherung sind serverseitig
/// 501 → hier deaktiviert dargestellt. Das manuelle Anlegen (`POST /api/buecher`) funktioniert und
/// ist der native Ersatz: Titel (+ optionale Felder) direkt auf die Wunschliste setzen.
struct EbooksSearchView: View {
    @EnvironmentObject private var store: EbooksStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                disabledSearchCard
                EbookManualAddForm().environmentObject(store)
            }
            .padding(14)
            .padding(.bottom, 24)
        }
    }

    // ── Deaktivierte externe Suche ──
    private var disabledSearchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Externe Buchsuche", systemImage: "magnifyingglass")
                .font(.headline)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                Text("Titel, Autor oder ISBN …").foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))

            Label("Die Shelfmark-Suche und der Calibre-Download sind in dieser Version nicht verfügbar. Bücher lassen sich unten manuell auf die Wunschliste setzen — Ole sucht regelmäßig danach.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(0.9)
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
