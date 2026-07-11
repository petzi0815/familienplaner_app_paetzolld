import SwiftUI
import UIKit

struct InboxView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            List {
                if app.inbox.isEmpty {
                    ContentUnavailableView("Noch keine Fotos", systemImage: "tray",
                        description: Text("Fotos, die du hochlädst, erscheinen hier."))
                }
                ForEach(app.inbox) { item in
                    HStack(spacing: 12) {
                        AuthImage(path: item.storageKeyUrl)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.bereich?.isEmpty == false ? item.bereich! : "nicht zugeordnet")
                                .font(.subheadline.weight(.semibold))
                            if let notiz = item.notiz, !notiz.isEmpty {
                                Text(notiz).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            StatusBadge(status: item.status)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Inbox")
            .refreshable { await app.loadInbox() }
            .task { await app.loadInbox() }
        }
    }
}

struct StatusBadge: View {
    let status: String
    private var color: Color {
        switch status {
        case "neu": return .blue
        case "in_bearbeitung": return .orange
        case "zugeordnet": return .green
        default: return .gray
        }
    }
    private var label: String {
        switch status {
        case "neu": return "neu"
        case "in_bearbeitung": return "in Arbeit"
        case "zugeordnet": return "zugeordnet"
        case "verworfen": return "verworfen"
        default: return status
        }
    }
    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Lädt Media auth-bewusst (Bearer-Header) und zeigt es an.
struct AuthImage: View {
    let path: String?
    @EnvironmentObject private var app: AppState
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(.secondarySystemBackground))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
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
