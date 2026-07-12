import SwiftUI

/// Scanner-Modus: Einzelscan (ein Buch) oder Bulk-Scan (mehrere Bücher am Stück).
enum BookScannerMode { case single, bulk }

/// ISBN-Scanner (§6.1 einzeln / §6.2 bulk). Manuelle ISBN-Eingabe + Kamera (VisionKit, wiederverwendet).
/// Neue Bücher landen im aktiven Regal (`store.activeShelf`); ohne Regal ist das Hinzufügen gesperrt.
struct BookScannerView: View {
    let mode: BookScannerMode
    @EnvironmentObject private var store: BooksStore

    @State private var isbn = ""
    @State private var showScanner = false

    // Einzelscan
    @State private var searching = false
    @State private var result: BookSearchResult?
    @State private var notFound = false

    // Bulk-Scan
    @State private var rows: [ScanRow] = []

    // 3s-Entprellung je Code
    @State private var lastScan: [String: Date] = [:]

    private var hasShelf: Bool { store.activeShelf != nil }

    struct ScanRow: Identifiable {
        let id = UUID()
        let isbn: String
        var status: Status = .pending
        var result: BookSearchResult?
        enum Status { case pending, found, notFound }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !hasShelf { shelfHint }
                isbnInput
                if mode == .single { singleContent } else { bulkContent }
            }
            .padding()
        }
        .sheet(isPresented: $showScanner) { scannerSheet }
    }

    // ── Eingabe (ISBN-Feld + Kamera) ──
    private var isbnInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .single ? "ISBN-Scanner" : "Bulk-Scanner").font(.title3.weight(.bold))
            HStack {
                TextField("ISBN eingeben oder scannen", text: $isbn)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.search)
                    .onSubmit(submit)
                Button(mode == .single ? "Suchen" : "Hinzufügen", action: submit)
                    .buttonStyle(.borderedProminent).tint(BookTheme.amber700)
                    .disabled(isbn.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if BarcodeScannerView.isSupported {
                Button { showScanner = true } label: {
                    Label("Kamera öffnen", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(BookTheme.amber700)
            }
        }
    }

    // ── Einzelscan ──
    @ViewBuilder private var singleContent: some View {
        if searching {
            HStack { ProgressView(); Text("Wird gesucht…").foregroundStyle(.secondary) }
        }
        if notFound {
            Label("Buch nicht gefunden", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(.red)
        }
        if let r = result { previewCard(r) }
    }

    private func previewCard(_ r: BookSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                BookCover(url: r.thumbnail).frame(width: 90)
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.title).font(.headline).lineLimit(3)
                    Text(r.authorText).font(.subheadline).foregroundStyle(.secondary)
                    if let p = r.publisher, !p.isEmpty { Text(p).font(.caption).foregroundStyle(.secondary) }
                    if let i = r.isbn, !i.isEmpty { Text("ISBN: \(i)").font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            Button { addSingle(r) } label: { Label("Buch hinzufügen", systemImage: "plus") }
                .buttonStyle(ElisButtonStyle(enabled: hasShelf))
                .disabled(!hasShelf)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BookTheme.amber700.opacity(0.2)))
    }

    // ── Bulk-Scan ──
    @ViewBuilder private var bulkContent: some View {
        if rows.isEmpty {
            Text("Scanne oder gib ISBNs ein, um mehrere Bücher zu erfassen.")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            HStack {
                Text("\(foundCount) Gefunden")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
                Spacer()
                Button(role: .destructive) { rows.removeAll() } label: { Label("Leeren", systemImage: "trash").font(.caption) }
            }
            VStack(spacing: 8) { ForEach(rows) { bulkRow($0) } }
            Button { addAllFound() } label: {
                Label("\(foundCount) Bücher hinzufügen", systemImage: "plus")
            }
            .buttonStyle(ElisButtonStyle(enabled: hasShelf && foundCount > 0))
            .disabled(!hasShelf || foundCount == 0)
        }
    }

    private func bulkRow(_ row: ScanRow) -> some View {
        HStack(spacing: 10) {
            statusIcon(row.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.result?.title ?? "ISBN \(row.isbn)").font(.subheadline.weight(.medium)).lineLimit(1)
                Text(statusText(row.status)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { rows.removeAll { $0.id == row.id } } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private func statusIcon(_ s: ScanRow.Status) -> some View {
        switch s {
        case .pending: ProgressView()
        case .found: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .notFound: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
    private func statusText(_ s: ScanRow.Status) -> String {
        switch s {
        case .pending: return "Wird gesucht…"
        case .found: return "Gefunden"
        case .notFound: return "Nicht gefunden"
        }
    }
    private var foundCount: Int { rows.filter { $0.status == .found }.count }

    // ── Kamera-Sheet ──
    private var scannerSheet: some View {
        NavigationStack {
            BarcodeScannerView { code in
                showScanner = false
                scanned(code)
            }
            .ignoresSafeArea()
            .navigationTitle("Barcode scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { showScanner = false } } }
        }
    }

    // ── Hinweis: kein Regal ──
    private var shelfHint: some View {
        Label("Kein Regal ausgewählt — bitte oben ein aktives Regal wählen.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // ── Logik ──
    private func submit() {
        let code = isbn.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        switch mode {
        case .single: runSingleSearch(code)
        case .bulk: processIsbn(code); isbn = ""
        }
    }

    private func scanned(_ code: String) {
        switch mode {
        case .single:
            guard shouldProcess(code) else { return }
            isbn = code
            runSingleSearch(code)
        case .bulk:
            processIsbn(code)
        }
    }

    private func runSingleSearch(_ code: String) {
        searching = true; notFound = false; result = nil
        Task {
            let r = await store.api.searchByISBN(code)
            searching = false
            if let r { result = r } else { notFound = true }
        }
    }

    private func addSingle(_ r: BookSearchResult) {
        guard let shelf = store.activeShelf else { store.notify("Kein Regal ausgewählt", error: true); return }
        Task {
            if await store.addBook(r.toBook(bookshelfId: shelf)) {
                result = nil; isbn = ""; notFound = false
            }
        }
    }

    private func processIsbn(_ raw: String) {
        let code = raw.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty, shouldProcess(code) else { return }
        guard !rows.contains(where: { $0.isbn == code }) else { return }
        let row = ScanRow(isbn: code)
        rows.insert(row, at: 0)
        let id = row.id
        Task {
            let r = await store.api.searchByISBN(code)
            guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
            if let r { rows[i].status = .found; rows[i].result = r }
            else { rows[i].status = .notFound }
        }
    }

    private func addAllFound() {
        guard let shelf = store.activeShelf else { store.notify("Kein Regal ausgewählt", error: true); return }
        let found = rows.compactMap { $0.result }
        Task {
            for r in found { _ = await store.addBook(r.toBook(bookshelfId: shelf)) }
            rows.removeAll()
        }
    }

    /// 3s-Entprellung: derselbe Code wird nicht mehrfach in kurzer Folge verarbeitet.
    private func shouldProcess(_ code: String) -> Bool {
        let now = Date()
        if let last = lastScan[code], now.timeIntervalSince(last) < 3 { return false }
        lastScan[code] = now
        return true
    }
}
