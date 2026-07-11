import SwiftUI
import UIKit
import PhotosUI

/// Kernfeature: Foto aufnehmen/wählen → Bereich zuordnen → in den Foto-Eingang hochladen.
struct CameraView: View {
    @EnvironmentObject private var app: AppState

    @State private var cameraSource: ImageSource?
    @State private var pickerItem: PhotosPickerItem?
    @State private var picked: UIImage?
    @State private var bereich = ""
    @State private var notiz = ""
    @State private var busy = false
    @State private var message = ""
    @State private var success = false
    @State private var successTick = 0
    @State private var aiHint = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                    hero
                    sourceButtons
                    if !app.lebensbereiche.isEmpty { bereichPicker }
                    if !aiHint.isEmpty {
                        Label(aiHint, systemImage: "sparkles")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.colors(for: bereich.isEmpty ? "foto" : bereich).first!)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                    TextField("Notiz für Ole (optional)", text: $notiz, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .lineLimit(1...3)

                    Button {
                        Task { await upload() }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            else { Image(systemName: "arrow.up.circle.fill") }
                            Text(busy ? "Lädt hoch …" : "Hochladen")
                        }
                    }
                    .buttonStyle(GradientButtonStyle(gradientKey: bereich.isEmpty ? "foto" : bereich, enabled: picked != nil && !busy))
                    .disabled(picked == nil || busy)

                    if !message.isEmpty {
                        Label(message, systemImage: success ? "checkmark.circle.fill" : "info.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(success ? Color.green : .secondary)
                            .symbolEffect(.bounce, value: successTick)
                    }
                }
                .padding()
                .animation(.snappy, value: picked != nil)
            }
            .background(bgWash.ignoresSafeArea())
            .navigationTitle("Foto-Eingang")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $cameraSource) { src in
                ImagePicker(sourceType: src.type) { img in onPicked(img) }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        onPicked(img)
                    }
                    pickerItem = nil
                }
            }
            .sensoryFeedback(.success, trigger: successTick)
            .sensoryFeedback(.selection, trigger: bereich)
            .task { if app.lebensbereiche.isEmpty { await app.loadLebensbereiche() } }
    }

    // Verlaufs-Schimmer im Hintergrund (dezent).
    private var bgWash: some View {
        Palette.gradient(for: bereich.isEmpty ? "foto" : bereich).opacity(0.10)
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            if let picked {
                Image(uiImage: picked).resizable().scaledToFill()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 56))
                        .foregroundStyle(Palette.gradient(for: "foto"))
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Foto aufnehmen oder wählen")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private var sourceButtons: some View {
        HStack(spacing: 12) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { cameraSource = ImageSource(.camera) } label: {
                    Label("Kamera", systemImage: "camera.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(Palette.gradient(for: "foto"), in: Capsule())
                .foregroundStyle(.white)
            }
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Mediathek", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(.primary)
        }
        .font(.subheadline.weight(.semibold))
    }

    private var bereichPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bereich").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(app.lebensbereiche) { b in
                        Button {
                            bereich = (bereich == b.key) ? "" : b.key
                        } label: {
                            BereichChip(bereich: b, selected: bereich == b.key)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
            }
        }
    }

    /// Gemeinsamer Einstieg für Kamera & Mediathek: setzt das Bild und startet den KI-Vorschlag.
    private func onPicked(_ img: UIImage) {
        picked = img; message = ""; aiHint = ""
        Task { await suggestBereich(img) }
    }

    /// On-Device-Vorschlag des Bereichs (nur wenn verfügbar und noch keiner gewählt).
    private func suggestBereich(_ img: UIImage) async {
        guard bereich.isEmpty, PhotoBereichSuggester.isAvailable else { return }
        if let key = await PhotoBereichSuggester.suggest(image: img, note: notiz, bereiche: app.lebensbereiche) {
            withAnimation(.snappy) {
                bereich = key
                aiHint = "Bereich von der KI vorgeschlagen – kurz prüfen."
            }
        }
    }

    private func upload() async {
        guard let img = picked, let data = img.jpegForUpload() else { return }
        busy = true; message = ""; success = false
        do {
            _ = try await app.api.uploadFoto(jpeg: data, bereich: bereich, notiz: notiz)
            success = true; successTick += 1
            message = "Hochgeladen — Ole ordnet es zu."
            picked = nil; notiz = ""
            await app.loadInbox()
        } catch {
            message = (error as? APIError)?.errorDescription ?? "Upload fehlgeschlagen."
        }
        busy = false
    }
}
