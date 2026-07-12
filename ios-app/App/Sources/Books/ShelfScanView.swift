import SwiftUI
import UIKit
import PhotosUI

/// Regal-Scanner mit KI-Erkennung (§6.3): Foto eines Bücherregals → Server-OCR (OpenAI Vision)
/// erkennt Buchrücken-Titel → pro Titel Metadaten-Suche (Google Books/Open Library) → als
/// Bücher ins aktive Regal übernehmen. Titel sind inline editierbar, Zeilen entfernbar.
struct ShelfScanView: View {
    @EnvironmentObject private var store: BooksStore

    @State private var cameraSource: ImageSource?
    @State private var pickerItem: PhotosPickerItem?
    @State private var rows: [DetectedRow] = []
    @State private var scanning = false
    @State private var errorMessage: String?
    @State private var notActivated = false

    // ── Zeilen-Status ──
    private enum RowStatus { case searching, found, notFound }

    private struct DetectedRow: Identifiable {
        let id: String
        let detectedTitle: String
        var editedTitle: String
        var confidence: Double
        var match: BookSearchResult?
        var status: RowStatus
    }

    private var addableCount: Int { rows.filter { $0.match != nil }.count }
    private var canAdd: Bool { store.activeShelf != nil && addableCount > 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                infoCard
                if store.activeShelf == nil { shelfHint }
                photoButtons
                if scanning { scanningIndicator }
                if let errorMessage { errorCard(errorMessage) }
                if !rows.isEmpty { detectedList }
                if !rows.isEmpty { addButton }
            }
            .padding(14)
        }
        .background(BookTheme.bgWash.ignoresSafeArea())
        .sheet(item: $cameraSource) { src in
            ImagePicker(sourceType: src.type) { img in Task { await scan(img) } }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await scan(img)
                }
                pickerItem = nil
            }
        }
    }

    // ── Kopf ──
    private var headerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.viewfinder").font(.title2).foregroundStyle(BookTheme.amber700)
            VStack(alignment: .leading, spacing: 2) {
                Text("Regal-Scanner mit KI-Erkennung").font(.headline).foregroundStyle(BookTheme.amber900)
                Text("Fotografiere ein Regal — die KI erkennt die Titel.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // ── Hinweis-/Info-Karte ──
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Für beste Ergebnisse", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(BookTheme.amber900)
            tip("Fotografiere die Buchrücken möglichst frontal.")
            tip("Sorge für gute, gleichmäßige Beleuchtung.")
            tip("Erkannte Titel sind editierbar — korrigiere sie bei Bedarf.")
            tip("Falsche Treffer kannst du pro Zeile entfernen.")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BookTheme.amber700.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(BookTheme.amber600)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var shelfHint: some View {
        Label("Bitte oben zuerst ein aktives Regal auswählen — sonst können keine Bücher hinzugefügt werden.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.medium)).foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // ── Foto-Aufnahme ──
    private var photoButtons: some View {
        HStack(spacing: 12) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { cameraSource = ImageSource(.camera) } label: {
                    Label("Regal fotografieren", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(BookTheme.brandGradient, in: Capsule())
                .foregroundStyle(.white)
                .disabled(scanning)
            }
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Bild wählen", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(.primary)
            .disabled(scanning)
        }
    }

    private var scanningIndicator: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Regal wird analysiert …").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium)).foregroundStyle(.red)
            if notActivated {
                Button { store.currentView = .manual } label: {
                    Label("Stattdessen manuell suchen", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(BookTheme.amber700)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // ── Erkannte Titel ──
    private var detectedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Erkannte Titel (\(rows.count))").font(.subheadline.weight(.semibold)).foregroundStyle(BookTheme.amber900)
            ForEach($rows) { $row in rowView($row) }
        }
    }

    private func rowView(_ row: Binding<DetectedRow>) -> some View {
        let r = row.wrappedValue
        return HStack(alignment: .top, spacing: 10) {
            statusIcon(r.status).font(.title3).padding(.top, 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Titel", text: row.editedTitle)
                        .textFieldStyle(.roundedBorder)
                    Text("\(confidencePct(r.confidence)) %")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(BookTheme.amber700.opacity(0.15), in: Capsule())
                        .foregroundStyle(BookTheme.amber900)
                }
                HStack(spacing: 8) {
                    Button { Task { await search(rowID: r.id) } } label: {
                        Label("Suchen", systemImage: "magnifyingglass").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(r.status == .searching)
                    if r.status == .searching { ProgressView().controlSize(.small) }
                }
                if let match = r.match {
                    HStack(spacing: 8) {
                        BookCover(url: match.thumbnail).frame(width: 34, height: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.title).font(.caption.weight(.semibold)).lineLimit(2)
                            Text(match.authorText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if r.status == .notFound {
                    Text("Kein Treffer gefunden — Titel anpassen und erneut suchen.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { remove(r.id) } label: {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private func statusIcon(_ s: RowStatus) -> some View {
        switch s {
        case .searching: Image(systemName: "hourglass").foregroundStyle(.orange)
        case .found: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .notFound: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    // ── Hinzufügen ──
    private var addButton: some View {
        VStack(spacing: 6) {
            Button { Task { await addAll() } } label: {
                Text("\(addableCount) \(addableCount == 1 ? "Buch" : "Bücher") zum Regal hinzufügen")
            }
            .buttonStyle(ElisButtonStyle(enabled: canAdd))
            .disabled(!canAdd)
            if let name = store.shelf(store.activeShelf)?.name {
                Text("Neue Bücher landen im Regal \"\(name)\".")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // ── Aktionen ──
    private func scan(_ img: UIImage) async {
        scanning = true; errorMessage = nil; notActivated = false; rows = []
        let dataURL = "data:image/jpeg;base64," + (img.jpegForUpload()?.base64EncodedString() ?? "")
        do {
            let detected = try await store.api.aiShelfOcr(imageBase64: dataURL)
            rows = detected.map { d in
                let title = (d["title"] as? String) ?? ""
                let rid = (d["id"] as? String) ?? UUID().uuidString
                return DetectedRow(id: rid, detectedTitle: title, editedTitle: title,
                                   confidence: asDouble(d["confidence"]), match: nil, status: .searching)
            }
            scanning = false
            for row in rows { await search(rowID: row.id) }
            if rows.isEmpty { errorMessage = "Keine Buchtitel im Foto erkannt. Versuche es näher/heller." }
        } catch let e as APIError where e.status == 501 {
            scanning = false
            notActivated = true
            errorMessage = "Regal-Scan ist noch nicht aktiviert (OPENAI_API_KEY fehlt im Backend). Bitte im Coolify setzen."
        } catch {
            scanning = false
            errorMessage = (error as? APIError)?.errorDescription ?? "Analyse fehlgeschlagen."
        }
    }

    private func search(rowID: String) async {
        guard let i = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[i].status = .searching
        let query = rows[i].editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = (try? await store.api.searchMetadata(query: query)) ?? []
        guard let j = rows.firstIndex(where: { $0.id == rowID }) else { return }
        if let first = results.first {
            rows[j].match = first
            rows[j].status = .found
        } else {
            rows[j].match = nil
            rows[j].status = .notFound
        }
    }

    private func remove(_ id: String) { rows.removeAll { $0.id == id } }

    private func addAll() async {
        guard store.activeShelf != nil else { return }
        let matches = rows.compactMap { $0.match }
        guard !matches.isEmpty else { return }
        for m in matches { _ = await store.addBook(m.toBook(bookshelfId: store.activeShelf)) }
        rows = []
        store.notify("\(matches.count) \(matches.count == 1 ? "Buch" : "Bücher") zum Regal hinzugefügt")
    }

    // ── Helfer ──
    private func confidencePct(_ c: Double) -> Int { Int((c <= 1 ? c * 100 : c).rounded()) }
    private func asDouble(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }
}
