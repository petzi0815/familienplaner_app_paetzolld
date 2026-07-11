import SwiftUI
import UIKit

/// Kernfeature: Foto aufnehmen/wählen → Bereich zuordnen → in den Foto-Eingang hochladen.
struct CameraView: View {
    @EnvironmentObject private var app: AppState

    @State private var source: ImageSource?
    @State private var picked: UIImage?
    @State private var bereich = ""
    @State private var notiz = ""
    @State private var busy = false
    @State private var message = ""
    @State private var success = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                        if let picked {
                            Image(uiImage: picked).resizable().scaledToFill()
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
                                Text("Foto aufnehmen oder wählen").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    HStack(spacing: 10) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { source = ImageSource(.camera) } label: {
                                Label("Kamera", systemImage: "camera").frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent)
                        }
                        Button { source = ImageSource(.photoLibrary) } label: {
                            Label("Mediathek", systemImage: "photo").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }

                    if !app.lebensbereiche.isEmpty {
                        Picker("Bereich", selection: $bereich) {
                            Text("— nicht zugeordnet —").tag("")
                            ForEach(app.lebensbereiche) { b in
                                Text("\(b.emoji ?? "") \(b.titel)").tag(b.key)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }

                    TextField("Notiz (optional)", text: $notiz, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)

                    Button {
                        Task { await upload() }
                    } label: {
                        HStack {
                            if busy { ProgressView().padding(.trailing, 4) }
                            Text(busy ? "Lädt hoch …" : "Hochladen")
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(busy || picked == nil)

                    if !message.isEmpty {
                        Text(message).font(.footnote).foregroundStyle(success ? Color.green : .secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Foto-Eingang")
            .sheet(item: $source) { src in
                ImagePicker(sourceType: src.type) { img in picked = img; message = "" }
            }
            .task { if app.lebensbereiche.isEmpty { await app.loadLebensbereiche() } }
        }
    }

    private func upload() async {
        guard let img = picked, let data = img.jpegForUpload() else { return }
        busy = true; message = ""; success = false
        do {
            _ = try await app.api.uploadFoto(jpeg: data, bereich: bereich, notiz: notiz)
            success = true
            message = "Hochgeladen — Ole ordnet es zu."
            picked = nil
            notiz = ""
            await app.loadInbox()
        } catch {
            message = (error as? APIError)?.errorDescription ?? "Upload fehlgeschlagen."
        }
        busy = false
    }
}
