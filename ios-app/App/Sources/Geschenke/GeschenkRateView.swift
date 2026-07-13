import SwiftUI

/// Tinder-artiger Bewerten-Modus: wischbare Karte ueber noch nicht bewertete Geschenke.
/// Wischen (>80px) oder Buttons vergeben Ranking-Deltas; ⏩ ueberspringt ohne Server-Call.
struct GeschenkRateView: View {
    let geschenke: [GGeschenk]
    var onVote: (GGeschenk, Int) -> Void
    var onSchonGeschenkt: (GGeschenk) -> Void
    var onExit: () -> Void

    @State private var voted: Set<Int> = []

    private var unvoted: [GGeschenk] { geschenke.filter { !voted.contains($0.id) } }

    var body: some View {
        if geschenke.isEmpty {
            AreaEmptyState(emoji: "🎁", title: "Noch keine Geschenkideen.", hint: "Füge eine hinzu!")
                .frame(minHeight: 180)
        } else if let current = unvoted.first {
            VStack(spacing: 14) {
                Text("\(voted.count + 1) / \(geschenke.count) · noch \(unvoted.count)")
                    .font(.caption2).foregroundStyle(.secondary)

                GRateCard(g: current) { dir in
                    vote(current, dir > 0 ? 1 : -1)
                }
                .id(current.id)

                buttons(current)

                HStack(spacing: 18) {
                    ForEach(["−1", "Hatten wir", "Skip", "+3", "+1"], id: \.self) { t in
                        Text(t).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            doneScreen
        }
    }

    private func buttons(_ current: GGeschenk) -> some View {
        HStack(spacing: 14) {
            circleButton("👎", size: 56, tint: .red) { vote(current, -1) }
            circleButton("🔄", size: 46, tint: Color(hex: "F97316")) { voted.insert(current.id); onSchonGeschenkt(current) }
            circleButton("⏩", size: 42, tint: .gray) { voted.insert(current.id) }
            circleButton("⭐", size: 56, tint: .blue) { vote(current, 3) }
            circleButton("👍", size: 56, tint: .green) { vote(current, 1) }
        }
    }

    private var doneScreen: some View {
        VStack(spacing: 12) {
            Text("🎉").font(.system(size: 60))
            Text("Alle bewertet!").font(.title3.weight(.heavy))
            Text("\(voted.count) Geschenkideen durchgesehen").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { voted.removeAll() } label: {
                    Text("🔄 Neuer Durchlauf").font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(hex: "EC4899"), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button { onExit() } label: {
                    Text("📋 Zur Liste").font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func vote(_ g: GGeschenk, _ delta: Int) {
        voted.insert(g.id)
        onVote(g, delta)
    }

    private func circleButton(_ label: String, size: CGFloat, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: size * 0.42))
                .frame(width: size, height: size)
                .background(tint.opacity(0.15), in: Circle())
                .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Wischbare Karte

struct GRateCard: View {
    let g: GGeschenk
    /// Aufruf bei Loslassen ueber Schwelle: dir = +1 (rechts) / -1 (links).
    var onRelease: (Int) -> Void

    @State private var offset: CGSize = .zero

    private var borderColor: Color {
        if offset.width > 40 { return .green }
        if offset.width < -40 { return .red }
        return GStyle.accent.opacity(0.4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            image
            content
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(borderColor, lineWidth: 2))
        .overlay(alignment: .topLeading) {
            if offset.width > 40 {
                overlayBadge("👍", .green).padding(18)
            }
        }
        .overlay(alignment: .topTrailing) {
            if offset.width < -40 {
                overlayBadge("👎", .red).padding(18)
            }
        }
        .offset(x: offset.width, y: offset.height)
        .rotationEffect(.degrees(Double(offset.width) * 0.05))
        .gesture(
            DragGesture()
                .onChanged { offset = $0.translation }
                .onEnded { v in
                    if abs(v.translation.width) > 80 {
                        let dir = v.translation.width > 0 ? 1.0 : -1.0
                        withAnimation(.easeOut(duration: 0.25)) {
                            offset = CGSize(width: dir * 700, height: v.translation.height)
                        }
                        onRelease(dir > 0 ? 1 : -1)
                    } else {
                        withAnimation(.spring(response: 0.3)) { offset = .zero }
                    }
                }
        )
    }

    @ViewBuilder private var image: some View {
        Group {
            if let path = g.imagePath {
                AuthImage(path: path, contentMode: .fit)
            } else {
                Palette.gradient(for: "geschenkplaner").opacity(0.15)
                    .overlay(Text("🎁").font(.system(size: 64)))
            }
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemBackground))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                GStatusChip(status: g.status)
                GRankingBadge(ranking: g.ranking)
            }
            Text(g.titel).font(.title3.weight(.heavy))
            if let d = g.beschreibung, !d.isEmpty {
                Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            if let b = g.begruendung, !b.isEmpty {
                NoteBlock(icon: "💡", text: b, tint: Color(hex: "F59E0B"))
            }
            GGiftMetaChips(g: g)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overlayBadge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 40))
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(text == "👍" ? -12 : 12))
    }
}
