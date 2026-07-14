import SwiftUI

/// Einkauf-Tab: Produkte, die leer/nachzukaufen UND restock-markiert sind. "Wieder da" -> aktiv.
struct ReinigerEinkaufView: View {
    @EnvironmentObject private var store: ReinigerStore

    var body: some View {
        ScrollView {
            let list = store.restockItems
            if list.isEmpty {
                AreaEmptyState(emoji: "🛒", title: "Keine Putzmittel auf der Einkaufsliste")
                    .frame(minHeight: 260)
            } else {
                VStack(spacing: 10) {
                    ForEach(list) { p in ReinigerEinkaufRow(produkt: p) }
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 24)
            }
        }
        .refreshable { await store.loadAll() }
    }
}

struct ReinigerEinkaufRow: View {
    @EnvironmentObject private var store: ReinigerStore
    let produkt: ReinigerProdukt

    private var subtitle: String {
        var parts: [String] = []
        if let m = produkt.marke, !m.isEmpty { parts.append(m) }
        if let mn = produkt.menge, !mn.isEmpty { parts.append(mn) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let path = produkt.imagePath {
                    AuthImage(path: path, contentMode: .fill)
                } else {
                    LinearGradient(colors: [Color(hex: "BAE6FD"), Color(hex: "D9F99D")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Text(ReinigerStyle.cat(produkt.kategorie).emoji).font(.system(size: 22)))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(produkt.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Button { Task { await store.setStatus(produkt.id, "aktiv") } } label: {
                Label("Wieder da", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.green, in: Capsule())
                    .foregroundStyle(Color.green.onFill)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
