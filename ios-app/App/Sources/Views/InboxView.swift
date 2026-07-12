import SwiftUI
import UIKit

private func statusColor(_ s: String) -> Color {
    switch s {
    case "neu": return .blue
    case "in_bearbeitung": return .orange
    case "zugeordnet": return .green
    default: return .gray
    }
}
private func statusLabel(_ s: String) -> String {
    switch s {
    case "neu": return "neu"
    case "in_bearbeitung": return "in Arbeit"
    case "zugeordnet": return "zugeordnet"
    case "verworfen": return "verworfen"
    default: return s
    }
}

struct InboxView: View {
    @EnvironmentObject private var app: AppState
    @State private var detail: FotoInboxItem?

    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if app.inbox.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Fotos", systemImage: "tray.full")
                    } description: {
                        Text("Fotos, die du hochlädst, erscheinen hier — mit Status, sobald Ole sie zuordnet.")
                    }
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(app.inbox) { item in
                            Button { detail = item } label: { cell(item) }.buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
            .background(Palette.gradient(for: "foto").opacity(0.07).ignoresSafeArea())
            .navigationTitle("Inbox")
            .refreshable { await app.loadInbox() }
            .task { await app.loadInbox() }
            .sheet(item: $detail) { FotoDetailSheet(item: $0) }
        }
    }

    private func cell(_ item: FotoInboxItem) -> some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay { AuthImage(path: item.storageKeyUrl) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Circle().fill(statusColor(item.status))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .padding(7)
            }
            .overlay(alignment: .bottomLeading) {
                if let b = item.bereich, !b.isEmpty {
                    Text(b).font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(7)
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
    }
}

struct FotoDetailSheet: View {
    let item: FotoInboxItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AuthImage(path: item.storageKeyUrl, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 14, y: 8)

                    HStack {
                        Label(statusLabel(item.status), systemImage: "circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(statusColor(item.status))
                        Spacer()
                        if let b = item.bereich, !b.isEmpty {
                            Text(b).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                    }

                    if let n = item.notiz, !n.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notiz").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            Text(n)
                        }
                    }
                    if let r = item.zugeordnetResource, !r.isEmpty {
                        Label("Zugeordnet: \(r)", systemImage: "checkmark.seal.fill")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                }
                .padding()
            }
            .navigationTitle("Foto #\(item.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

/// Lädt Media auth-bewusst (Bearer-Header) und zeigt es an.
/// `.fill` (Default) füllt die vom Aufrufer gesetzte Fläche und **clippt sich selbst** (kein Überlauf).
/// `.fit` zeigt das ganze Bild (für Detail-Ansichten).
struct AuthImage: View {
    let path: String?
    var contentMode: ContentMode = .fill
    @EnvironmentObject private var app: AppState
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                if contentMode == .fill {
                    Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                Palette.gradient(for: "foto").opacity(0.25)
                    .overlay(Image(systemName: "photo").font(.title3).foregroundStyle(.white.opacity(0.8)))
            }
        }
        .task(id: path) {
            guard let path, image == nil else { return }
            if let data = try? await app.api.loadMedia(pathOrUrl: path), let img = UIImage(data: data) {
                image = img
            }
        }
    }
}
