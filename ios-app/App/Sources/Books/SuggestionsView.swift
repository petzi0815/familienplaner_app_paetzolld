import SwiftUI

/// Vorschläge (§11): (1) Ähnliche Bücher lokal aus einem gewählten Buch, (2) KI-Empfehlungen (OpenAI).
struct SuggestionsView: View {
    enum Mode: String, CaseIterable, Identifiable { case similar, ai; var id: String { rawValue } }
    @State private var mode: Mode = .similar

    var body: some View {
        VStack(spacing: 0) {
            Picker("Modus", selection: $mode) {
                Text("Ähnliche Bücher").tag(Mode.similar)
                Text("KI-Empfehlungen").tag(Mode.ai)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            switch mode {
            case .similar: SimilarBooksSection()
            case .ai: AiRecommendationsSection()
            }
        }
    }
}

// MARK: - Ähnliche Bücher (lokal)

private struct SimilarBooksSection: View {
    @EnvironmentObject private var store: BooksStore
    @State private var query = ""
    @State private var selected: Book?
    @State private var results: [BookSearchResult] = []
    @State private var loading = false
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var matches: [Book] {
        let q = query.lowercased()
        let base = q.isEmpty ? store.books : store.books.filter {
            $0.title.lowercased().contains(q) || $0.authorText.lowercased().contains(q)
        }
        return Array(base.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Buch auswählen").font(.headline).padding(.horizontal, 14).padding(.top, 8)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Bibliothek durchsuchen …", text: $query)
                }
                .padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 14)

                if store.books.isEmpty {
                    Text("Noch keine Bücher in der Bibliothek.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 14)
                } else if selected == nil {
                    VStack(spacing: 0) {
                        ForEach(matches) { b in
                            Button { pick(b) } label: {
                                HStack(spacing: 12) {
                                    BookCover(url: b.thumbnail).frame(width: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(b.authorText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 8)
                            Divider()
                        }
                    }
                }

                if let sel = selected {
                    HStack {
                        Text("Ähnlich zu: \(sel.title)").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Button { selected = nil; results = [] } label: { Label("Anderes Buch", systemImage: "arrow.uturn.backward") }
                            .font(.caption)
                    }
                    .padding(.horizontal, 14)

                    if loading {
                        ProgressView("Suche ähnliche Bücher …").frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else if results.isEmpty {
                        ContentUnavailableView("Keine ähnlichen Bücher gefunden", systemImage: "sparkles")
                            .padding(.top, 12)
                    } else {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(results) { r in similarCard(r, for: sel) }
                        }
                        .padding(.horizontal, 14)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func similarCard(_ r: BookSearchResult, for book: Book) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BookCover(url: r.thumbnail)
            Text(r.title).font(.caption.weight(.semibold)).lineLimit(2)
            Text(r.authorText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if let p = r.publisher, !p.isEmpty { Text(p).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            Text(reason(r, for: book)).font(.caption2.weight(.medium))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(BookTheme.amber700.opacity(0.14), in: Capsule()).foregroundStyle(BookTheme.amber900)
            Button {
                Task { await store.addToWishlist(r, source: r.source) }
            } label: { Label("Zur Wunschliste", systemImage: "heart") }
                .font(.caption2.weight(.semibold)).tint(BookTheme.orange600)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BookTheme.amber700.opacity(0.15)))
    }

    private func reason(_ r: BookSearchResult, for book: Book) -> String {
        if let a = r.authors.first(where: { book.authors.contains($0) }) { return "Gleicher Autor: \(a)" }
        if let c = r.categories.first(where: { book.categories.contains($0) }) { return "Ähnliche Kategorie: \(c)" }
        if let p = r.publisher, book.publisher == p, !p.isEmpty { return "Gleicher Verlag: \(p)" }
        return "Ähnlicher Inhalt"
    }

    private func pick(_ b: Book) {
        selected = b; results = []; loading = true
        Task {
            let q = b.categories.first ?? b.authors.first ?? b.title
            let found = (try? await store.api.searchMetadata(query: q)) ?? []
            results = Array(found.filter { $0.title.lowercased() != b.title.lowercased() }.prefix(6))
            loading = false
        }
    }
}

// MARK: - KI-Empfehlungen (OpenAI)

private struct AiRecommendationsSection: View {
    @EnvironmentObject private var store: BooksStore
    @State private var count = 5.0
    @State private var timeframe = "12-months"
    @State private var prompt = ""
    @State private var recs: [[String: Any]] = []
    @State private var loading = false
    @State private var errorText: String?
    private let cols = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    private let timeframes: [(String, String)] = [
        ("6-months", "Letzten 6 Monate"), ("12-months", "Letztes Jahr"),
        ("24-months", "Letzten 2 Jahre"), ("all-time", "Alle Zeiten"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Anzahl Empfehlungen").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(count))").font(.subheadline.weight(.bold)).foregroundStyle(BookTheme.amber900)
                    }
                    Slider(value: $count, in: 1...10, step: 1)

                    Picker("Zeitraum für Neuerscheinungen", selection: $timeframe) {
                        ForEach(timeframes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.menu)

                    Text("Zusätzliche Anforderungen (optional)").font(.subheadline.weight(.medium))
                    TextField("z.B. Nur Science Fiction Romane", text: $prompt, axis: .vertical).lineLimit(1...4)
                        .padding(8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button {
                        generate()
                    } label: {
                        HStack {
                            if loading { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                            Text(loading ? "Empfehlungen werden generiert …" : "Empfehlungen generieren")
                        }
                    }
                    .buttonStyle(ElisButtonStyle(enabled: !store.books.isEmpty && !loading))
                    .disabled(store.books.isEmpty || loading)

                    if store.books.isEmpty {
                        Text("Mindestens 1 Buch in der Bibliothek erforderlich.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(LinearGradient(colors: [Color(hex: "#F5F3FF"), Color(hex: "#EFF6FF")], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 14).padding(.top, 8)

                if let e = errorText {
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 14)
                }

                if !recs.isEmpty {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(Array(recs.enumerated()), id: \.offset) { _, d in recCard(d) }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func recCard(_ d: [String: Any]) -> some View {
        let title = d["title"] as? String ?? "Unbekannter Titel"
        let authors = decodeStringArray(d["authors"])
        let publisher = d["publisher"] as? String
        let desc = d["description"] as? String
        let categories = decodeStringArray(d["categories"])
        let reason = d["reason"] as? String ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(3)
            Text(authors.isEmpty ? "Unbekannter Autor" : authors.joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let p = publisher, !p.isEmpty { Text(p).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            if let ds = desc, !ds.isEmpty { Text(ds).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
            if !categories.isEmpty { CategoryPills(categories: categories) }
            if !reason.isEmpty {
                Text("Warum empfohlen: \(reason)").font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(hex: "#EDE9FE").opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .leading) { Rectangle().fill(Color(hex: "#8B5CF6")).frame(width: 3) }
            }
            Button {
                let r = resultFromDict(d)
                Task { await store.addToWishlist(r, source: "openai-recommendations") }
            } label: { Label("Zur Wunschliste", systemImage: "heart") }
                .font(.caption.weight(.semibold)).tint(BookTheme.orange600)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(hex: "#FAF5FF"), Color(hex: "#EFF6FF")], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: "#8B5CF6").opacity(0.2)))
    }

    private func resultFromDict(_ d: [String: Any]) -> BookSearchResult {
        BookSearchResult(title: d["title"] as? String ?? "Unbekannter Titel",
                         authors: decodeStringArray(d["authors"]),
                         publisher: d["publisher"] as? String,
                         publishedDate: d["publishedDate"] as? String,
                         description: d["description"] as? String,
                         pageCount: nil,
                         categories: decodeStringArray(d["categories"]),
                         thumbnail: d["thumbnail"] as? String,
                         isbn: d["isbn"] as? String,
                         source: "openai-recommendations")
    }

    private func generate() {
        guard !store.books.isEmpty else { return }
        loading = true; errorText = nil; recs = []
        let library = store.books.prefix(60).map { b in
            ["title": b.title, "authors": b.authors, "categories": b.categories] as [String: Any]
        }
        Task {
            do {
                recs = try await store.api.aiRecommendations(count: Int(count), timeframe: timeframe, prompt: prompt, library: library)
                if recs.isEmpty { errorText = "Keine Empfehlungen erhalten." }
            } catch let e as APIError where e.status == 501 {
                errorText = "KI-Empfehlungen sind noch nicht aktiviert (OPENAI_API_KEY fehlt im Backend)."
            } catch {
                errorText = (error as? APIError)?.errorDescription ?? "Fehler bei der Generierung."
            }
            loading = false
        }
    }
}
