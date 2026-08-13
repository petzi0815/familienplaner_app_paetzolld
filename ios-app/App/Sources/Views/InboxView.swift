import CryptoKit
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
            // Raster mit ~104-pt-Kacheln — die Vorschau reicht dicke; das Original bleibt dem Detail.
            .overlay { AuthImage(path: item.storageKeyUrl, thumb: 320) }
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

/// Zweistufiger Zwischenspeicher für Medien (Arbeitsspeicher + Platte).
///
/// WARUM: `AuthImage` lud bisher bei JEDEM Erscheinen neu — und `List`/`LazyVGrid` recyceln ihre
/// Zellen, dasselbe Etikett ging beim Scrollen also immer wieder über eine authentifizierte
/// Anfrage. Das ist die eigentliche Ursache der Verzögerung, wichtiger noch als die kleinere Datei.
///
/// Die Plattenkopie liegt bewusst in `.cachesDirectory`: iOS darf sie bei Platzmangel selbst
/// räumen, damit braucht es hier keine eigene Verfallslogik.
final class MediaCache {
    static let shared = MediaCache()

    private let speicher = NSCache<NSString, UIImage>()
    private let ordner: URL?
    /// Alle Plattenzugriffe laufen auf einer eigenen Schlange — Lesen und Schreiben dürfen die
    /// Hauptschlange nicht blockieren, auf der die Ansichten gezeichnet werden.
    private let schlange = DispatchQueue(label: "app.yagemi.familienplaner.media-cache", qos: .utility)

    private init() {
        // Kosten = tatsächlicher Bildspeicher (bytesPerRow * height), nicht die JPEG-Grösse:
        // ein 300-KB-JPEG belegt entpackt schnell 10 MB, danach richtet sich das Limit.
        speicher.totalCostLimit = 48 * 1024 * 1024
        let basis = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let ziel = basis?.appendingPathComponent("media-cache", isDirectory: true)
        if let ziel { try? FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true) }
        ordner = ziel
    }

    /// Synchroner Blick in den Arbeitsspeicher. Er ist der Grund, warum beim Wechsel der Adresse
    /// nichts flackert: erst fragen, dann erst das alte Bild verwerfen.
    func imSpeicher(_ schluessel: String) -> UIImage? {
        speicher.object(forKey: schluessel as NSString)
    }

    /// Plattenkopie lesen (abseits der Hauptschlange) und in den Arbeitsspeicher nachziehen.
    func vonPlatte(_ schluessel: String) async -> UIImage? {
        guard let datei = datei(fuer: schluessel) else { return nil }
        let bild: UIImage? = await withCheckedContinuation { fortsetzung in
            schlange.async {
                guard let data = try? Data(contentsOf: datei) else {
                    fortsetzung.resume(returning: nil)
                    return
                }
                fortsetzung.resume(returning: UIImage(data: data))
            }
        }
        if let bild { merken(bild, fuer: schluessel) }
        return bild
    }

    /// Frisch geladene Daten in beide Stufen legen. Das Schreiben ist atomar, damit ein zweiter
    /// Leser nie eine halbe Datei sieht.
    func ablegen(_ bild: UIImage, daten: Data, fuer schluessel: String) {
        merken(bild, fuer: schluessel)
        guard let datei = datei(fuer: schluessel) else { return }
        schlange.async { try? daten.write(to: datei, options: .atomic) }
    }

    private func merken(_ bild: UIImage, fuer schluessel: String) {
        speicher.setObject(bild, forKey: schluessel as NSString, cost: kosten(bild))
    }

    private func kosten(_ bild: UIImage) -> Int {
        guard let cg = bild.cgImage else { return 1 }
        return max(1, cg.bytesPerRow * cg.height)
    }

    /// Dateiname = SHA-256 des Schlüssels: der Schlüssel enthält Pfad UND `?w=`, ist also kein
    /// gültiger Dateiname, und der Hash hält ihn zugleich kurz.
    private func datei(fuer schluessel: String) -> URL? {
        guard let ordner else { return nil }
        let hash = SHA256.hash(data: Data(schluessel.utf8))
        return ordner.appendingPathComponent(hash.map { String(format: "%02x", $0) }.joined())
    }
}

/// Lädt Media auth-bewusst (Bearer-Header) und zeigt es an.
/// `.fill` (Default) füllt die vom Aufrufer gesetzte Fläche und **clippt sich selbst** (kein Überlauf).
/// `.fit` zeigt das ganze Bild (für Detail-Ansichten).
/// `thumb` fordert eine serverseitig verkleinerte Vorschau an (`?w=`) — nur dort setzen, wo klein
/// gerendert wird; Detail- und Vollbildansichten bleiben beim Original.
struct AuthImage: View {
    let path: String?
    var contentMode: ContentMode = .fill
    var thumb: Int? = nil
    @EnvironmentObject private var app: AppState
    @State private var image: UIImage?
    /// Zu welcher Adresse das angezeigte Bild gehört — sonst bliebe beim Wechsel das alte stehen.
    @State private var geladeneQuelle: String?

    /// Adresse inklusive Vorschaubreite. Die Breite MUSS Teil davon sein, sonst überschreiben sich
    /// Vorschau und Original gegenseitig im Zwischenspeicher.
    private var quelle: String? {
        guard let path else { return nil }
        guard let thumb else { return path }
        return path + (path.contains("?") ? "&" : "?") + "w=" + String(thumb)
    }

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
        .task(id: quelle) {
            // Ohne Pfad bleibt der Platzhalter stehen (unverändertes Verhalten).
            guard let quelle else { return }
            if geladeneQuelle == quelle, image != nil { return }
            // Erst den Arbeitsspeicher fragen, dann erst umschalten: so gibt es beim Wechsel der
            // Adresse kein Aufblitzen des Platzhalters, wenn das neue Bild schon vorliegt.
            if let gemerkt = MediaCache.shared.imSpeicher(quelle) {
                image = gemerkt
                geladeneQuelle = quelle
                return
            }
            // Ab hier gehört das angezeigte Bild zu einer anderen Adresse — weg damit.
            image = nil
            geladeneQuelle = nil
            if let vonPlatte = await MediaCache.shared.vonPlatte(quelle) {
                guard !Task.isCancelled else { return }
                image = vonPlatte
                geladeneQuelle = quelle
                return
            }
            guard !Task.isCancelled,
                  let data = try? await app.api.loadMedia(pathOrUrl: quelle),
                  let img = UIImage(data: data) else { return }
            MediaCache.shared.ablegen(img, daten: data, fuer: quelle)
            guard !Task.isCancelled else { return }
            image = img
            geladeneQuelle = quelle
        }
    }
}
