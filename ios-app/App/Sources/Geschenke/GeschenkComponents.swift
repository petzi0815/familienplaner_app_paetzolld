import SwiftUI

// Wiederverwendbare Bausteine des Geschenkplaner-Moduls (Chips, Badges, Budget-Balken).
// FlowLayout (umbrechende Chip-Reihe) wird aus Views/FieldViews.swift wiederverwendet.

// MARK: - Chips

/// Farbige Kapsel (heller Hintergrund + farbiger Text) — wie die Web-Chips.
struct GChip: View {
    let text: String
    var color: Color = .gray
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Chip als externer Link (nur sichtbar, wenn eine URL vorhanden ist).
struct GLinkChip: View {
    let text: String
    var color: Color = .gray
    let url: URL?
    var body: some View {
        if let url {
            Link(destination: url) { GChip(text: text, color: color) }
        }
    }
}

// MARK: - Countdown-Badge

struct GCountdownBadge: View {
    let datum: String
    var body: some View {
        let cd = GDate.countdown(datum)
        Text(cd.text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((cd.soon ? Color.red : Color.gray).opacity(0.15), in: Capsule())
            .foregroundStyle(cd.soon ? Color.red : Color.secondary)
    }
}

// MARK: - Ranking-Badge (+N gruen / -N rot; 0/nil = nichts)

struct GRankingBadge: View {
    let ranking: Int?
    var body: some View {
        if let r = ranking, r != 0 {
            let positive = r > 0
            Text("\(positive ? "+" : "")\(r)")
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background((positive ? Color.green : Color.red).opacity(0.15), in: Capsule())
                .foregroundStyle(positive ? Color.green : Color.red)
        }
    }
}

// MARK: - Status-Chip (tippbar → cycleStatus)

struct GStatusChip: View {
    let status: String
    var tappable: Bool = false
    var onTap: () -> Void = {}
    var body: some View {
        let color = GStyle.statusColor(status)
        Button(action: onTap) {
            Text(GStyle.statusLabel(status))
                .font(.caption2.weight(.bold))
                .strikethrough(status == "vergeben")
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(tappable)
    }
}

// MARK: - Budget-Balken

struct GBudgetBar: View {
    let ausgaben: Double
    let budgetMax: Double
    var body: some View {
        let pct = budgetMax > 0 ? min(1.0, ausgaben / budgetMax) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.15))
                Capsule().fill(GStyle.budgetColor(pct)).frame(width: geo.size.width * pct)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Anlass-Chips (auf der Kind-Karte)

struct GAnlassChips: View {
    let anlaesse: [GAnlassConfig]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(anlaesse) { a in
                let text = "\(GStyle.anlassEmoji(a.anlass)) \(a.budgetMin ?? 0)–\(a.budgetMax.map(String.init) ?? "?") €"
                GChip(text: text, color: a.aktiv ? GStyle.accent : .gray)
            }
        }
    }
}

// MARK: - Geschenk-Meta-Chips (Preis/Shop/Quelle/URL/idealo/Google)

struct GGiftMetaChips: View {
    let g: GGeschenk
    /// Einkauf-Kontext zeigt nur Preis/Shop/Kaufen (kein idealo/Google/Quelle).
    var compact: Bool = false
    var body: some View {
        FlowLayout(spacing: 6) {
            if let p = g.preis { GChip(text: "💰 \(GStyle.eur(p))", color: GStyle.cPrice) }
            if let s = g.shop, !s.isEmpty { GChip(text: "🏪 \(s)", color: GStyle.cShop) }
            if !compact, let q = g.quelle, !q.isEmpty { GChip(text: "📝 \(q)", color: GStyle.cQuelle) }
            if g.linkURL != nil { GLinkChip(text: compact ? "🔗 Kaufen" : "🔗 Shop", color: GStyle.cUrl, url: g.linkURL) }
            if !compact {
                GLinkChip(text: "📊 idealo", color: GStyle.cIdealo, url: gIdealoURL(g.titel))
                GLinkChip(text: "🛍️ Google", color: GStyle.cGoogle, url: gGoogleURL(g.titel))
            }
        }
    }
}

// MARK: - Externe Such-Links (clientseitig aus dem Titel generiert)

func gIdealoURL(_ titel: String) -> URL? {
    let q = titel.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? titel
    return URL(string: "https://www.idealo.de/preisvergleich/MainSearchProductCategory.html?q=\(q)")
}

func gGoogleURL(_ titel: String) -> URL? {
    let q = titel.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? titel
    return URL(string: "https://www.google.de/search?q=\(q)&tbm=shop")
}

// MARK: - Identifiable-Wrapper fuer .sheet(item:)

/// Geschenk-Formular-Kontext (nil = neu, sonst bearbeiten).
struct GiftEditRef: Identifiable {
    let id = UUID()
    let gift: GGeschenk?
}

/// Einkauf-Gruppe (Kind + Anlass + Jahr) fuer die gruppierte Liste. `id` = Gruppen-Ueberschrift.
struct GEinkaufGroup: Identifiable {
    let id: String
    let items: [GGeschenk]
}
