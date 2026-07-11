import SwiftUI
import UIKit

/// Schnell-Erfassung: Buch (ISBN) & Lebensmittel (EAN) scannen, oder Foto aufnehmen.
struct ScanHubView: View {
    @EnvironmentObject private var app: AppState
    @State private var sheet: ScanSheet?
    @State private var showCamera = false

    enum ScanSheet: Identifiable { case book, food; var id: Int { hashValue } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Was möchtest du erfassen?")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button { sheet = .book } label: {
                        tileLabel("Buch scannen", "ISBN-Barcode → automatisch anlegen", "barcode.viewfinder")
                    }
                    .buttonStyle(TileButtonStyle(gradientKey: "elisbooks"))

                    Button { sheet = .food } label: {
                        tileLabel("Lebensmittel scannen", "EAN-Barcode → Vorratskammer", "carrot.fill")
                    }
                    .buttonStyle(TileButtonStyle(gradientKey: "vorratskammer"))

                    Button { showCamera = true } label: {
                        tileLabel("Foto aufnehmen", "In den Foto-Eingang", "camera.fill")
                    }
                    .buttonStyle(TileButtonStyle(gradientKey: "foto"))
                }
                .padding()
            }
            .background(Palette.gradient(for: "elisbooks").opacity(0.06).ignoresSafeArea())
            .navigationTitle("Erfassen")
            .navigationDestination(isPresented: $showCamera) { CameraView() }
            .onChange(of: app.openCameraTick) { _, _ in showCamera = true }
            .sheet(item: $sheet) { which in
                switch which {
                case .book: BookScanSheet().environmentObject(app)
                case .food: VorratScanSheet().environmentObject(app)
                }
            }
        }
    }

    private func tileLabel(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34, weight: .semibold))
            Text(title).font(.headline)
            Text(subtitle).font(.caption).opacity(0.9)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Buch scannen

struct BookScanSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isbn = ""
    @State private var title = ""
    @State private var author = ""
    @State private var coverURL: String?
    @State private var phase: Phase = .scan
    @State private var busy = false
    @State private var message = ""
    enum Phase { case scan, confirm }

    var body: some View {
        NavigationStack {
            Group {
                if phase == .scan { scanPhase } else { confirmPhase }
            }
            .navigationTitle("Buch scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }

    private var scanPhase: some View {
        VStack(spacing: 16) {
            if BarcodeScannerView.isSupported {
                BarcodeScannerView { code in Task { await lookup(code) } }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        Text("ISBN-Barcode anvisieren").font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule()).padding()
                    }
            } else {
                ContentUnavailableView("Scanner nicht verfügbar", systemImage: "barcode.viewfinder",
                                       description: Text("ISBN unten manuell eingeben."))
            }
            HStack {
                TextField("ISBN manuell", text: $isbn).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                Button("Suchen") { Task { await lookup(isbn) } }
                    .buttonStyle(.glassProminent).disabled(isbn.count < 10)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private var confirmPhase: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AsyncImage(url: coverURL.flatMap(URL.init)) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        GradientIcon(systemName: "book.closed.fill", gradientKey: "elisbooks", size: 56)
                    }
                    .frame(width: 60, height: 88).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.isEmpty ? "Unbekannter Titel" : title).font(.headline).lineLimit(3)
                        if !author.isEmpty { Text(author).font(.subheadline).foregroundStyle(.secondary) }
                        Text("ISBN \(isbn)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Section("Details") {
                TextField("Titel", text: $title)
                TextField("Autor(en)", text: $author)
            }
            if !message.isEmpty {
                Section { Text(message).foregroundStyle(.secondary).font(.footnote) }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack { if busy { ProgressView().padding(.trailing, 4) }; Text("Zur Bibliothek hinzufügen") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).disabled(busy || title.isEmpty)
            }
        }
    }

    private func lookup(_ code: String) async {
        let clean = String(code.filter { $0.isNumber || $0 == "X" })
        guard clean.count >= 10 else { return }
        isbn = clean
        busy = true; message = "Suche im Katalog …"; phase = .confirm
        let info = await ProductLookup.book(isbn: clean)
        title = info.title ?? ""
        author = info.authors.joined(separator: ", ")
        coverURL = info.coverURL
        message = info.title == nil ? "Nicht im Katalog gefunden – bitte Titel ergänzen." : ""
        busy = false
    }

    private func save() async {
        busy = true; message = ""
        let authorsArray = author.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let authorsJSON = (try? JSONSerialization.data(withJSONObject: authorsArray)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        var fields: [String: Any] = [
            "id": UUID().uuidString,
            "isbn": isbn,
            "title": title,
            "authors": authorsJSON,
        ]
        if let coverURL { fields["thumbnail"] = coverURL }
        do {
            try await app.api.createRecord("elisbooks-books", fields: fields)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            message = (error as? APIError)?.errorDescription ?? "Speichern fehlgeschlagen."
            busy = false
        }
    }
}

// MARK: - Lebensmittel scannen

struct VorratScanSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var marke = ""
    @State private var kategorie = "trocken"
    @State private var hasMHD = false
    @State private var mhd = Date()
    @State private var phase: Phase = .scan
    @State private var busy = false
    @State private var message = ""
    enum Phase { case scan, confirm }

    private static let mhdFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()

    var body: some View {
        NavigationStack {
            Group {
                if phase == .scan { scanPhase } else { confirmPhase }
            }
            .navigationTitle("Lebensmittel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                if phase == .scan {
                    ToolbarItem(placement: .confirmationAction) { Button("Manuell") { phase = .confirm } }
                }
            }
        }
    }

    private var scanPhase: some View {
        VStack {
            if BarcodeScannerView.isSupported {
                BarcodeScannerView { code in Task { await lookup(code) } }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .bottom) {
                        Text("EAN-Barcode anvisieren").font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule()).padding()
                    }
            } else {
                ContentUnavailableView("Scanner nicht verfügbar", systemImage: "barcode.viewfinder",
                                       description: Text("Tippe oben auf \"Manuell\"."))
            }
        }
        .padding()
    }

    private var confirmPhase: some View {
        Form {
            Section("Produkt") {
                TextField("Name", text: $name)
                TextField("Marke (optional)", text: $marke)
            }
            Section("Lagerung") {
                Picker("Kategorie", selection: $kategorie) {
                    Text("Trocken").tag("trocken")
                    Text("Kühlschrank").tag("kuehlschrank")
                    Text("Gefrierfach").tag("gefrierfach")
                }
                .pickerStyle(.segmented)
                Toggle("Mindesthaltbarkeit", isOn: $hasMHD.animation())
                if hasMHD { DatePicker("MHD", selection: $mhd, displayedComponents: .date) }
            }
            if !message.isEmpty { Section { Text(message).foregroundStyle(.secondary).font(.footnote) } }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack { if busy { ProgressView().padding(.trailing, 4) }; Text("In die Vorratskammer") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).disabled(busy || name.isEmpty)
            }
        }
    }

    private func lookup(_ code: String) async {
        busy = true; phase = .confirm; message = "Suche Produkt …"
        let info = await ProductLookup.food(ean: code)
        name = info.name ?? ""
        marke = info.brand ?? ""
        message = info.name == nil ? "Nicht gefunden – bitte Namen eingeben." : ""
        busy = false
    }

    private func save() async {
        busy = true; message = ""
        var fields: [String: Any] = ["name": name, "kategorie": kategorie]
        if !marke.isEmpty { fields["marke"] = marke }
        if hasMHD { fields["mhd"] = Self.mhdFmt.string(from: mhd) }
        do {
            try await app.api.createRecord("vorrat-lebensmittel", fields: fields)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            message = (error as? APIError)?.errorDescription ?? "Speichern fehlgeschlagen."
            busy = false
        }
    }
}
