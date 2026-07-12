import SwiftUI

// Duplikat-Finder (Spec §9.3): scannt die ganze Bibliothek in Duplikat-Gruppen
// (jedes Buch wird genau einmal verbraucht) und erlaubt gezieltes Loeschen.

// ── Match-Typ einer Gruppe ──
private enum DupMatchKind: Int {
    case aehnlich = 0   // Titel-Aehnlichkeit > 0.7 + gleicher Erstautor
    case titel = 1      // Titel-Aehnlichkeit > 0.85
    case exact = 2      // identische ISBN

    var label: String {
        switch self {
        case .exact: return "Exakt"
        case .titel: return "Titel"
        case .aehnlich: return "Ähnlich"
        }
    }
    var color: Color {
        switch self {
        case .exact: return .red
        case .titel: return BookTheme.orange600
        case .aehnlich: return BookTheme.amber600
        }
    }
}

// ── Eine Duplikat-Gruppe ──
private struct DupGroup: Identifiable {
    let id: String          // Seed-Buch-ID
    let kind: DupMatchKind
    let similarity: Double
    let books: [Book]
}

struct DuplicateFinderSheet: View {
    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [DupGroup] = []
    @State private var toDelete: Book?

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(groups) { group in
                                groupCard(group)
                            }
                        }
                        .padding()
                    }
                    .background(BookTheme.bgWash.ignoresSafeArea())
                }
            }
            .navigationTitle("Duplikate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .onAppear { recompute() }
            .confirmationDialog(
                "Buch löschen?",
                isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                presenting: toDelete
            ) { book in
                Button("Löschen", role: .destructive) {
                    Task { await store.deleteBooks([book.id]); recompute() }
                }
                Button("Abbrechen", role: .cancel) { toDelete = nil }
            } message: { book in
                Text("\"\(book.title)\" wird dauerhaft entfernt.")
            }
        }
    }

    // ── Empty state ──
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Keine Duplikate gefunden! Ihre Bibliothek ist bereits bereinigt.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BookTheme.bgWash.ignoresSafeArea())
    }

    // ── Gruppen-Karte ──
    private func groupCard(_ group: DupGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                badge(group.kind.label, group.kind.color)
                if group.kind == .exact { badge("ISBN", .red) }
                Text("\(Int((group.similarity * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(group.books.count) Bücher")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(group.books.enumerated()), id: \.element.id) { idx, book in
                if idx > 0 { Divider() }
                bookRow(book)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func bookRow(_ book: Book) -> some View {
        HStack(alignment: .top, spacing: 10) {
            BookCover(url: book.thumbnail)
                .frame(width: 40, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(book.authorText) • \(book.publisher ?? "Unbekannter Verlag")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let isbn = book.isbn, !isbn.isEmpty {
                    Text(isbn)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button(role: .destructive) { toDelete = book } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    // ── Gruppierung ──
    private func recompute() {
        let all = store.books
        var consumed = Set<String>()
        var result: [DupGroup] = []

        for i in all.indices {
            let seed = all[i]
            if consumed.contains(seed.id) { continue }
            var members = [seed]
            var bestKind = DupMatchKind.aehnlich
            var bestSim = 0.0

            var j = i + 1
            while j < all.count {
                let cand = all[j]
                if !consumed.contains(cand.id), let m = match(seed, cand) {
                    members.append(cand)
                    consumed.insert(cand.id)
                    if m.kind.rawValue > bestKind.rawValue { bestKind = m.kind }
                    bestSim = max(bestSim, m.sim)
                }
                j += 1
            }

            if members.count >= 2 {
                consumed.insert(seed.id)
                result.append(DupGroup(id: seed.id, kind: bestKind, similarity: bestSim, books: members))
            }
        }

        groups = result.sorted { $0.similarity > $1.similarity }
    }

    // Zwei Buecher als Duplikat klassifizieren (nil = kein Duplikat).
    private func match(_ a: Book, _ b: Book) -> (kind: DupMatchKind, sim: Double)? {
        let ia = normISBN(a.isbn), ib = normISBN(b.isbn)
        if !ia.isEmpty, !ib.isEmpty, ia == ib { return (.exact, 1.0) }
        let ts = similarity(a.title, b.title)
        if ts > 0.85 { return (.titel, ts) }
        if ts > 0.7, sameFirstAuthor(a, b) { return (.aehnlich, ts) }
        return nil
    }

    private func normISBN(_ s: String?) -> String {
        guard let s else { return "" }
        return String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private func sameFirstAuthor(_ a: Book, _ b: Book) -> Bool {
        guard let fa = a.authors.first?.lowercased().trimmingCharacters(in: .whitespaces),
              let fb = b.authors.first?.lowercased().trimmingCharacters(in: .whitespaces),
              !fa.isEmpty, !fb.isEmpty else { return false }
        return fa == fb
    }

    // ── Levenshtein-basierte Aehnlichkeit (0...1) auf lowercased Titeln ──
    private func similarity(_ a: String, _ b: String) -> Double {
        let s1 = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let s2 = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s1.isEmpty && s2.isEmpty { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }
        if s1 == s2 { return 1.0 }
        let dist = levenshtein(Array(s1), Array(s2))
        let maxLen = max(s1.count, s2.count)
        return maxLen == 0 ? 1.0 : 1.0 - Double(dist) / Double(maxLen)
    }

    private func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        let n = a.count, m = b.count
        if n == 0 { return m }
        if m == 0 { return n }
        var prev = Array(0...m)
        var curr = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            curr[0] = i
            for j in 1...m {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[m]
    }
}
