import SwiftUI

// KI-Metadaten-Dialoge (spec §7.3 Cleaner + §7.4 Enhancer). Beide Sheets sind eigenständig
// und werden aus der Bibliothek präsentiert. Backend-Proxy → bei fehlendem OPENAI_API_KEY: 501.

// ── Geteilte Hilfen ──

private func aiString(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let arr = v as? [Any] { return arr.compactMap { $0 as? String }.joined(separator: ", ") }
    if let n = v as? NSNumber { return n.stringValue }
    if v == nil || v is NSNull { return "" }
    return String(describing: v!)
}

private func aiInt(_ v: Any?) -> Int {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    if let s = v as? String { return Int(s) ?? 0 }
    return 0
}

private func aiSplitList(_ s: String) -> [String] {
    s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// Deutsches Label je Metadatenfeld.
private func aiFieldLabel(_ field: String) -> String {
    switch field.lowercased() {
    case "authors": return "Autoren"
    case "publisher": return "Verlag"
    case "description": return "Beschreibung"
    case "thumbnail", "cover": return "Cover"
    case "categories": return "Kategorien"
    case "page_count", "pagecount": return "Seitenzahl"
    case "published_date", "publisheddate": return "Erscheinungsdatum"
    case "isbn": return "ISBN"
    case "title": return "Titel"
    default: return field
    }
}

/// KI-Feld → DB-Spalte + typgerechter Wert (authors/categories als JSON-String, page_count als Int).
private func aiColumnValue(for field: String, newValue: String) -> (String, Any)? {
    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    switch field.lowercased() {
    case "authors": return ("authors", encodeStringArray(aiSplitList(trimmed)))
    case "categories": return ("categories", encodeStringArray(aiSplitList(trimmed)))
    case "page_count", "pagecount":
        guard let n = Int(trimmed) else { return nil }
        return ("page_count", n)
    case "published_date", "publisheddate": return ("published_date", trimmed)
    case "publisher": return ("publisher", trimmed)
    case "description": return ("description", trimmed)
    case "isbn": return ("isbn", trimmed)
    case "thumbnail", "cover": return ("thumbnail", trimmed)
    case "title": return ("title", trimmed)
    default: return nil
    }
}

private struct ConfidenceBadge: View {
    let value: Int
    var body: some View {
        let color: Color = value >= 80 ? .green : (value >= 50 ? .orange : .red)
        return Label("\(value)%", systemImage: value >= 80 ? "checkmark.seal.fill" : "questionmark.circle")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct ValueBox: View {
    let label: String
    let text: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
            Text(text.isEmpty ? "—" : text).font(.caption).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// ── §7.3 AI Metadaten-Bereinigung ──

private struct CleanerChange: Identifiable {
    let id = UUID()
    let field: String
    let oldValue: String
    let newValue: String
    let confidence: Int
    let reasoning: String
    var approved: Bool = true
}

private struct CleanerBook: Identifiable {
    let id = UUID()
    let bookId: String
    let title: String
    var changes: [CleanerChange]
}

struct AiCleanerSheet: View {
    let books: [Book]

    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    @State private var applying = false
    @State private var errorText: String?
    @State private var items: [CleanerBook] = []

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    loadingView
                } else if let errorText {
                    ContentUnavailableView { Label("Hinweis", systemImage: "sparkles") } description: { Text(errorText) }
                } else if items.isEmpty {
                    ContentUnavailableView { Label("Nichts zu tun", systemImage: "sparkles") }
                        description: { Text("Keine Verbesserungen gefunden.") }
                } else {
                    content
                }
            }
            .navigationTitle("KI-Bereinigung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .task { await run() }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("KI analysiert die Metadaten …").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(get: { allSelected }, set: { setAll($0) })) {
                        Text("Alle auswählen (\(approvedCount) von \(totalCount))").font(.subheadline.weight(.semibold))
                    }
                    .tint(.purple)
                    ForEach($items) { $book in bookCard($book) }
                }
                .padding(16)
            }
            Button { apply() } label: {
                if applying { ProgressView().tint(.white) } else { Text("\(approvedCount) Änderungen anwenden") }
            }
            .buttonStyle(ElisButtonStyle(enabled: approvedCount > 0 && !applying))
            .disabled(approvedCount == 0 || applying)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func bookCard(_ book: Binding<CleanerBook>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(book.wrappedValue.title).font(.headline).lineLimit(2)
            ForEach(book.changes) { $change in changeRow($change) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Color.purple).frame(width: 4) }
    }

    private func changeRow(_ change: Binding<CleanerChange>) -> some View {
        let c = change.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(aiFieldLabel(c.field)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                ConfidenceBadge(value: c.confidence)
                Toggle("", isOn: change.approved).labelsHidden().tint(.purple)
            }
            ValueBox(label: "Aktuell", text: c.oldValue, color: .red)
            ValueBox(label: "Vorschlag", text: c.newValue, color: .green)
            if !c.reasoning.isEmpty {
                Text(c.reasoning).font(.caption).italic().foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ── Auswahl-Status ──
    private var totalCount: Int { items.flatMap { $0.changes }.count }
    private var approvedCount: Int { items.flatMap { $0.changes }.filter { $0.approved }.count }
    private var allSelected: Bool {
        let all = items.flatMap { $0.changes }
        return !all.isEmpty && all.allSatisfy { $0.approved }
    }
    private func setAll(_ v: Bool) {
        for i in items.indices { for j in items[i].changes.indices { items[i].changes[j].approved = v } }
    }

    // ── Aktionen ──
    private func run() async {
        loading = true
        errorText = nil
        guard !books.isEmpty else { loading = false; return }
        do {
            let raw = try await store.api.aiCleaner(books.map { store.api.aiBookPayload($0) })
            items = parse(raw)
        } catch let e as APIError where e.status == 501 {
            errorText = "KI-Bereinigung ist nicht aktiviert (OPENAI_API_KEY fehlt im Backend)."
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Fehler bei der KI-Bereinigung."
        }
        loading = false
    }

    private func parse(_ raw: [[String: Any]]) -> [CleanerBook] {
        raw.compactMap { dict -> CleanerBook? in
            guard let bookId = dict["bookId"] as? String else { return nil }
            let title = (dict["originalTitle"] as? String) ?? "Buch"
            let changes: [CleanerChange] = ((dict["changes"] as? [[String: Any]]) ?? []).compactMap { c in
                guard let field = c["field"] as? String else { return nil }
                let newV = aiString(c["newValue"])
                guard !newV.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return CleanerChange(field: field, oldValue: aiString(c["oldValue"]), newValue: newV,
                                     confidence: aiInt(c["confidence"]), reasoning: aiString(c["reasoning"]))
            }
            return changes.isEmpty ? nil : CleanerBook(bookId: bookId, title: title, changes: changes)
        }
    }

    private func apply() {
        applying = true
        Task {
            for book in items {
                var fields: [String: Any] = [:]
                for ch in book.changes where ch.approved {
                    if let (col, val) = aiColumnValue(for: ch.field, newValue: ch.newValue) { fields[col] = val }
                }
                if !fields.isEmpty { await store.updateBookFields(book.bookId, fields) }
            }
            applying = false
            dismiss()
        }
    }
}

// ── §7.4 AI Metadaten-Ergänzung ──

private struct EnhSuggestion: Identifiable {
    let id = UUID()
    let field: String            // "description" | "categories"
    let oldValue: String
    let newValue: String         // Anzeige (Kategorien: kommagetrennt)
    let categoriesArray: [String]?
    var approved: Bool = true
}

private struct EnhBook: Identifiable {
    let id = UUID()
    let bookId: String
    let title: String
    let confidence: Int
    var suggestions: [EnhSuggestion]
}

struct AiEnhancerSheet: View {
    let books: [Book]

    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    @State private var applying = false
    @State private var errorText: String?
    @State private var items: [EnhBook] = []

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    loadingView
                } else if let errorText {
                    ContentUnavailableView { Label("Hinweis", systemImage: "sparkles") } description: { Text(errorText) }
                } else if items.isEmpty {
                    ContentUnavailableView { Label("Nichts zu tun", systemImage: "sparkles") }
                        description: { Text("Keine Ergänzungen gefunden.") }
                } else {
                    content
                }
            }
            .navigationTitle("KI-Ergänzung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .task { await run() }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("KI ergänzt fehlende Metadaten …").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(get: { allSelected }, set: { setAll($0) })) {
                        Text("Alle auswählen (\(approvedCount) von \(totalCount))").font(.subheadline.weight(.semibold))
                    }
                    .tint(.purple)
                    ForEach($items) { $book in bookCard($book) }
                }
                .padding(16)
            }
            Button { apply() } label: {
                if applying { ProgressView().tint(.white) } else { Text("\(approvedCount) Ergänzungen anwenden") }
            }
            .buttonStyle(ElisButtonStyle(enabled: approvedCount > 0 && !applying))
            .disabled(approvedCount == 0 || applying)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func bookCard(_ book: Binding<EnhBook>) -> some View {
        let b = book.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(b.title).font(.headline).lineLimit(2)
                Spacer(minLength: 6)
                ConfidenceBadge(value: b.confidence)
            }
            ForEach(book.suggestions) { $s in suggestionRow($s) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Color.purple).frame(width: 4) }
    }

    private func suggestionRow(_ s: Binding<EnhSuggestion>) -> some View {
        let sv = s.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(aiFieldLabel(sv.field)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                Toggle("", isOn: s.approved).labelsHidden().tint(.purple)
            }
            if !sv.oldValue.isEmpty { ValueBox(label: "Aktuell", text: sv.oldValue, color: .red) }
            ValueBox(label: "Vorschlag", text: sv.newValue, color: .green)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ── Auswahl-Status ──
    private var totalCount: Int { items.flatMap { $0.suggestions }.count }
    private var approvedCount: Int { items.flatMap { $0.suggestions }.filter { $0.approved }.count }
    private var allSelected: Bool {
        let all = items.flatMap { $0.suggestions }
        return !all.isEmpty && all.allSatisfy { $0.approved }
    }
    private func setAll(_ v: Bool) {
        for i in items.indices { for j in items[i].suggestions.indices { items[i].suggestions[j].approved = v } }
    }

    // ── Aktionen ──
    private func run() async {
        loading = true
        errorText = nil
        guard !books.isEmpty else { loading = false; return }
        do {
            let raw = try await store.api.aiEnhancer(books.map { store.api.aiBookPayload($0) })
            items = parse(raw)
        } catch let e as APIError where e.status == 501 {
            errorText = "KI-Ergänzung ist nicht aktiviert (OPENAI_API_KEY fehlt im Backend)."
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Fehler bei der KI-Ergänzung."
        }
        loading = false
    }

    private func parse(_ raw: [[String: Any]]) -> [EnhBook] {
        raw.compactMap { dict -> EnhBook? in
            guard let bookId = dict["bookId"] as? String else { return nil }
            let title = (dict["originalTitle"] as? String) ?? "Buch"
            let book = books.first { $0.id == bookId }
            let sugg = (dict["suggestions"] as? [String: Any]) ?? [:]
            var out: [EnhSuggestion] = []

            // Nur fehlende Felder anbieten.
            if let desc = sugg["description"] as? String,
               !desc.trimmingCharacters(in: .whitespaces).isEmpty,
               (book?.description?.isEmpty ?? true) {
                out.append(EnhSuggestion(field: "description", oldValue: book?.description ?? "",
                                         newValue: desc, categoriesArray: nil))
            }
            let cats = decodeStringArray(sugg["categories"])
            if !cats.isEmpty, (book?.categories.isEmpty ?? true) {
                out.append(EnhSuggestion(field: "categories", oldValue: (book?.categories ?? []).joined(separator: ", "),
                                         newValue: cats.joined(separator: ", "), categoriesArray: cats))
            }
            return out.isEmpty ? nil : EnhBook(bookId: bookId, title: title, confidence: aiInt(dict["confidence"]), suggestions: out)
        }
    }

    private func apply() {
        applying = true
        Task {
            for book in items {
                var fields: [String: Any] = [:]
                for s in book.suggestions where s.approved {
                    if s.field == "description" {
                        fields["description"] = s.newValue
                    } else if s.field == "categories" {
                        fields["categories"] = encodeStringArray(s.categoriesArray ?? aiSplitList(s.newValue))
                    }
                }
                if !fields.isEmpty { await store.updateBookFields(book.bookId, fields) }
            }
            applying = false
            dismiss()
        }
    }
}
