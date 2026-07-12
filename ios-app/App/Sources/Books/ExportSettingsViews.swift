import SwiftUI

/// Export-Sheet (spec §12): Vollständiges Backup (JSON), CSV-Export, Pickliste (Text),
/// Einkaufsliste/Wunschliste (Text) — je Option ein `ShareLink`. Robust ohne PDF-Bibliothek:
/// JSON/CSV werden in temporäre Dateien geschrieben und als Datei geteilt (mit String-Fallback),
/// Text-Listen werden direkt als Text geteilt.
struct BooksExportSheet: View {
    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss

    @State private var backupURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let url = backupURL {
                        ShareLink(item: url) { optionLabel("Vollständiges Backup (JSON)", "arrow.down.doc") }
                    } else {
                        ShareLink(item: backupJSONString()) { optionLabel("Vollständiges Backup (JSON)", "arrow.down.doc") }
                    }
                } footer: {
                    Text("Regale (\(store.shelves.count)), Bücher (\(store.books.count)) und Wunschliste (\(store.wishlist.count)) als JSON-Datei.")
                }

                Section {
                    if let url = csvURL {
                        ShareLink(item: url) { optionLabel("CSV-Export", "tablecells") }
                    } else {
                        ShareLink(item: csvString()) { optionLabel("CSV-Export", "tablecells") }
                    }
                } footer: {
                    Text("\(store.filteredBooks.count) gefilterte Bücher als CSV (Excel-kompatibel).")
                }

                Section {
                    ShareLink(item: picklistString()) { optionLabel("Pickliste (Text)", "checklist") }
                } footer: {
                    Text("\(store.picklistCount) Bücher auf der Pickliste — zum Verschieben.")
                }

                Section {
                    ShareLink(item: wishlistString()) { optionLabel("Einkaufsliste / Wunschliste (Text)", "cart") }
                } footer: {
                    Text("\(store.wishlist.count) Einträge der Wunschliste als Einkaufsliste.")
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                backupURL = writeTemp("elisbooks-backup.json", backupJSONString())
                csvURL = writeTemp("elisbooks.csv", csvString())
            }
        }
    }

    private func optionLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
    }

    // ── Vollständiges Backup als JSON-String ──
    private func backupJSONString() -> String {
        func s(_ v: String?) -> Any { v ?? NSNull() }
        func i(_ v: Int?) -> Any { v ?? NSNull() }

        let books: [[String: Any]] = store.books.map { b in
            [
                "id": b.id,
                "isbn": s(b.isbn),
                "title": b.title,
                "authors": b.authors,
                "publisher": s(b.publisher),
                "published_date": s(b.publishedDate),
                "description": s(b.description),
                "page_count": i(b.pageCount),
                "categories": b.categories,
                "thumbnail": s(b.thumbnail),
                "language": s(b.language),
                "bookshelf_id": s(b.bookshelfId),
                "is_read": b.isRead,
                "is_on_picklist": b.isOnPicklist,
            ]
        }
        let shelves: [[String: Any]] = store.shelves.map { sh in
            ["id": sh.id, "name": sh.name, "description": s(sh.description), "color": sh.color]
        }
        let wishlist: [[String: Any]] = store.wishlist.map { w in
            [
                "id": w.id,
                "title": w.title,
                "authors": w.authors,
                "publisher": s(w.publisher),
                "published_date": s(w.publishedDate),
                "description": s(w.description),
                "categories": w.categories,
                "thumbnail": s(w.thumbnail),
                "isbn": s(w.isbn),
                "source": w.source,
            ]
        }
        let root: [String: Any] = ["books": books, "bookshelves": shelves, "wishlist": wishlist]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    // ── CSV aus den aktuell gefilterten Büchern ──
    private func csvString() -> String {
        func esc(_ v: String) -> String {
            if v.contains(",") || v.contains("\"") || v.contains("\n") {
                return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return v
        }
        let header = "Titel,Autoren,Verlag,Erscheinungsjahr,ISBN,Kategorien,Regal,Gelesen,Seiten,Sprache"
        let rows: [String] = store.filteredBooks.map { b in
            let year: String = b.yearInt.map(String.init) ?? ""
            let pages: String = b.pageCount.map(String.init) ?? ""
            let shelf: String = store.shelf(b.bookshelfId)?.name ?? ""
            let cols: [String] = [
                b.title,
                b.authors.joined(separator: ", "),
                b.publisher ?? "",
                year,
                b.isbn ?? "",
                b.categories.joined(separator: ", "),
                shelf,
                b.isRead ? "Ja" : "Nein",
                pages,
                b.language ?? "",
            ]
            return cols.map(esc).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // ── Pickliste als Text: Titel — Autor — Aktuelles Regal ──
    private func picklistString() -> String {
        let lines = store.books.filter { $0.isOnPicklist }.map { b in
            "\(b.title) — \(b.authorText) — \(store.shelf(b.bookshelfId)?.name ?? "Kein Regal")"
        }
        return (["Pickliste - Bücher verschieben", ""] + lines).joined(separator: "\n")
    }

    // ── Wunschliste als Einkaufsliste: Titel — Autor — Kategorie ──
    private func wishlistString() -> String {
        let lines = store.wishlist.map { w in
            "\(w.title) — \(w.authorText) — \(w.categories.first ?? "")"
        }
        return (["Wunschliste - Einkaufsliste", ""] + lines).joined(separator: "\n")
    }

    private func writeTemp(_ name: String, _ contents: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// Einstellungen-Sheet (spec §13): Suchlimit + Menü-Sichtbarkeit (informativ) + Info.
/// Persistenz via `@AppStorage`. Kein Store nötig.
struct BooksSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("elisbooks.maxResults") private var maxResults = 10

    @AppStorage("elisbooks.menu.scanner") private var menuScanner = true
    @AppStorage("elisbooks.menu.bulk-scanner") private var menuBulk = true
    @AppStorage("elisbooks.menu.shelf-scanner") private var menuRegalscan = true
    @AppStorage("elisbooks.menu.ocr-scanner") private var menuOcr = true
    @AppStorage("elisbooks.menu.manual") private var menuManual = true
    @AppStorage("elisbooks.menu.similar") private var menuVorschlaege = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $maxResults, in: 1...50) {
                        HStack {
                            Text("Maximale Ergebnisse pro Service")
                            Spacer()
                            Text("\(maxResults)").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Suche")
                } footer: {
                    Text("Wie viele Treffer jeder Metadaten-Dienst höchstens liefert.")
                }

                Section {
                    Toggle("Scanner", isOn: $menuScanner)
                    Toggle("Bulk Scanner", isOn: $menuBulk)
                    Toggle("Regalscan", isOn: $menuRegalscan)
                    Toggle("OCR Scanner", isOn: $menuOcr)
                    Toggle("Manuell", isOn: $menuManual)
                    Toggle("Vorschläge", isOn: $menuVorschlaege)
                } header: {
                    Text("Menü")
                } footer: {
                    Text("Optionale Bereiche ein-/ausblenden. Regale, Bücher und Wunschliste sind immer sichtbar.")
                }

                Section {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("ElisBooks").foregroundStyle(.secondary)
                    }
                    Text("Die Daten liegen in der Familienplaner-API. KI-Funktionen (Regalscan, OCR, Vorschläge, Metadaten-Bereinigung) benötigen einen OPENAI_API_KEY im Backend.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Info")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
