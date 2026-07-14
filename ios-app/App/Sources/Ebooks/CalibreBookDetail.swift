import SwiftUI
import UIKit

/// Detailseite eines Calibre-Buchs: Cover + Metadaten + Beschreibung, Datei-Download (→ Apple Books),
/// und Regale zuordnen/entfernen (Häkchen = liegt auf dem Regal → tippen entfernt; leer → tippen legt darauf).
struct CalibreBookDetail: View {
    let book: CalibreBook
    @EnvironmentObject private var store: EbooksStore
    @Environment(\.dismiss) private var dismiss
    @State private var full: CalibreBook
    @State private var shelfIds: Set<Int> = []
    @State private var loading = true
    @State private var busyShelf: Int?
    @State private var formats: [String] = []
    @State private var downloading: String?
    @State private var shareFile: DownloadFile?

    init(book: CalibreBook) { self.book = book; _full = State(initialValue: book) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    meta
                    downloadSection
                    if let d = full.description, !d.isEmpty { NoteBlock(icon: "📖", text: d, tint: EbookStyle.rose) }
                    shelvesSection
                }
                .padding()
            }
            .navigationTitle("Buch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .sheet(item: $shareFile) { ShareSheet(items: [$0.url]) }
        }
        .task { await load() }
    }

    // ── Datei-Download (epub/…) → Teilen-Dialog → „In Bücher kopieren" ──
    @ViewBuilder private var downloadSection: some View {
        let fmts = formats.isEmpty ? ["epub"] : formats   // Fallback: die meisten Bücher sind epub
        VStack(alignment: .leading, spacing: 8) {
            Label("Auf dieses Gerät laden", systemImage: "arrow.down.circle.fill")
                .font(.headline).foregroundStyle(EbookStyle.rose)
            HStack(spacing: 10) {
                ForEach(fmts, id: \.self) { f in downloadButton(f) }
                Spacer(minLength: 0)
            }
            Text("Öffnet den Teilen-Dialog – dort „In Bücher kopieren“ wählen.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func downloadButton(_ format: String) -> some View {
        Button { Task { await download(format) } } label: {
            HStack(spacing: 6) {
                if downloading == format { ProgressView().tint(.white) }
                else { Image(systemName: "arrow.down.doc.fill") }
                Text(format.uppercased())
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Palette.gradient(for: "ebooks"), in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(downloading != nil)
        .accessibilityIdentifier("calibre-download-\(format)")
    }

    private func download(_ format: String) async {
        downloading = format
        defer { downloading = nil }
        do {
            let data = try await store.api.calibreDownload(id: book.id, format: format)
            let name = downloadFileName(full.title, format: format)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: .atomic)
            shareFile = DownloadFile(url: url)
        } catch {
            store.notify((error as? APIError)?.errorDescription ?? "Download fehlgeschlagen", error: true)
        }
    }

    /// Sicherer Dateiname `<Titel>.<format>` (illegale Zeichen ersetzt, gekürzt).
    private func downloadFileName(_ title: String, format: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let safe = (title.isEmpty ? "buch" : title).components(separatedBy: illegal).joined(separator: "-")
        let trimmed = String(safe.prefix(80)).trimmingCharacters(in: .whitespaces)
        return "\(trimmed.isEmpty ? "buch" : trimmed).\(format.lowercased())"
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let p = full.coverPath { AuthImage(path: p, contentMode: .fit) }
                else { Palette.gradient(for: "ebooks").opacity(0.85).overlay(Text("📚").font(.largeTitle)) }
            }
            .frame(width: 96, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(full.title).font(.title3.weight(.bold))
                if !full.authors.isEmpty { Text(full.authors).foregroundStyle(EbookStyle.rose) }
                if let s = full.series, !s.isEmpty { Pill(text: "📚 \(s)", color: EbookStyle.purple, filled: false) }
            }
            Spacer(minLength: 0)
        }
    }

    private var meta: some View {
        VStack(spacing: 0) {
            if let v = full.publisher, !v.isEmpty { InfoRow(icon: "🏢", label: "Verlag", value: v) }
            if let v = full.published, !v.isEmpty { InfoRow(icon: "📅", label: "Jahr", value: v) }
            if let v = full.languages, !v.isEmpty { InfoRow(icon: "🌐", label: "Sprache", value: v) }
            if let v = full.rating, !v.isEmpty { InfoRow(icon: "⭐️", label: "Bewertung", value: v) }
            if let v = full.isbn, !v.isEmpty { InfoRow(icon: "🔖", label: "ISBN", value: v) }
            if !full.tags.isEmpty { InfoRow(icon: "🏷️", label: "Tags", value: full.tags.joined(separator: ", ")) }
        }
    }

    private var shelvesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Regale", systemImage: "books.vertical").font(.headline)
                if loading { ProgressView().padding(.leading, 4) }
            }
            if store.calibreShelves.isEmpty {
                Text("Keine Regale geladen.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.calibreShelves) { s in shelfRow(s) }
            }
        }
    }

    private func shelfRow(_ s: CalibreShelf) -> some View {
        let on = shelfIds.contains(s.id)
        return Button { Task { await toggle(s) } } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? EbookStyle.green : .secondary)
                Text(s.name)
                Spacer()
                if busyShelf == s.id { ProgressView() }
                else { Image(systemName: on ? "minus.circle" : "plus.circle").foregroundStyle(on ? .red : Theme.accent) }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(busyShelf != nil)
        .accessibilityIdentifier("calibre-detail-shelf-\(s.id)")
    }

    private func load() async {
        loading = true
        if let d = try? await store.api.calibreBookDetail(id: book.id, title: book.title) {
            shelfIds = Set(d.shelfIds)
            formats = d.formats
            if let f = d.book { full = f }
        }
        loading = false
    }

    private func toggle(_ s: CalibreShelf) async {
        let isOn = shelfIds.contains(s.id)
        busyShelf = s.id
        defer { busyShelf = nil }
        do {
            _ = try await store.api.calibreShelfAction(bookId: book.id, shelfId: s.id, action: isOn ? "remove" : "add")
            if isOn { shelfIds.remove(s.id) } else { shelfIds.insert(s.id) }
            store.notify(isOn ? "Von „\(s.name)“ entfernt" : "Auf „\(s.name)“ gelegt")
        } catch {
            store.notify((error as? APIError)?.errorDescription ?? "Fehler", error: true)
        }
    }
}

/// Heruntergeladene Datei (für den Teilen-Dialog).
struct DownloadFile: Identifiable { let id = UUID(); let url: URL }

/// System-Teilen-Dialog (UIActivityViewController) — bietet u.a. „In Bücher kopieren".
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
