import SwiftUI
import UIKit

/// Schnell-Erfassung: Buch (ISBN) & Lebensmittel (EAN) scannen, oder Foto aufnehmen.
struct ScanHubView: View {
    @EnvironmentObject private var app: AppState
    @State private var sheet: ScanSheet?
    @State private var showCamera = false
    @State private var showFotobox = false

    enum ScanSheet: Identifiable { case book, food; var id: Int { hashValue } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Was möchtest du erfassen?")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button { showFotobox = true } label: {
                        tileLabel("Fotobox", "Foto + gültige Werte setzen → Ole", "camera.badge.ellipsis")
                    }
                    .buttonStyle(TileButtonStyle(gradientKey: "foto"))

                    Button { sheet = .book } label: {
                        tileLabel("Buch scannen", "ISBN-Barcode → automatisch anlegen", "barcode.viewfinder")
                    }
                    .buttonStyle(TileButtonStyle(gradientKey: "elisbooks"))
                    .accessibilityIdentifier("scan-buch")

                    Button { sheet = .food } label: {
                        tileLabel("Lebensmittel scannen", "EAN-Barcode → Vorratskammer", "carrot.fill")
                    }
                    .buttonStyle(TileButtonStyle(gradientKey: "vorratskammer"))
                    .accessibilityIdentifier("scan-lebensmittel")
                }
                .padding()
            }
            .background(Palette.gradient(for: "elisbooks").opacity(0.06).ignoresSafeArea())
            .navigationTitle("Erfassen")
            .navigationDestination(isPresented: $showCamera) {
                // Erst hier ist der Wunsch wirklich umgesetzt (siehe consumeCameraWish).
                CameraView().onAppear { app.pendingCamera = false }
            }
            .navigationDestination(isPresented: $showFotobox) { FotoboxView() }
            // Schnellaktion/Deep-Link „Foto aufnehmen", „Buch scannen" bzw. „Lebensmittel scannen":
            // der Tab wird erst beim Wechsel gebaut (dann greift .task), existiert er schon,
            // greift .onChange. Die Kamera braucht beide Wege genauso wie die Scan-Sheets — beim
            // Kaltstart über die Schnellaktion steht der Wunsch fest, bevor es diese View gibt.
            .task { consumeCameraWish(); consumeScanWish() }
            .onChange(of: app.pendingCamera) { _, _ in consumeCameraWish() }
            .onChange(of: app.pendingScanSheet) { _, _ in consumeScanWish() }
            .sheet(item: $sheet) { which in
                Group {
                    switch which {
                    case .book: BookScanSheet()
                    case .food: VorratScanSheet()
                    }
                }
                .environmentObject(app)
                // Erst wenn das GEWÜNSCHTE Sheet wirklich steht, ist der Wunsch eingelöst.
                .onAppear { if sheetZiel(app.pendingScanSheet) == which { app.pendingScanSheet = nil } }
            }
        }
    }

    /// Wunsch-Ziel → Sheet-Ziel (nil bleibt nil).
    private func sheetZiel(_ target: AppState.ScanTarget?) -> ScanSheet? {
        guard let t = target else { return nil }
        return t == .buch ? .book : .food
    }

    /// Offenen Wunsch „direkt scannen" einlösen (Schnellaktion vom App-Icon / Deep-Link).
    /// Verbraucht wird er erst, wenn das Sheet wirklich auf dem Schirm steht (`onAppear` oben) —
    /// bleibt die Präsentation aus, weil noch ein Sheet eines ANDEREN Tabs oben liegt, bleibt der
    /// Wunsch offen und der nächste `.task`/`.onChange`-Durchlauf versucht es erneut. Sonst wäre er
    /// spurlos weg (SwiftUI zeigt kein zweites Sheet) und nichts würde ihn wiederholen.
    private func consumeScanWish() {
        guard let ziel = sheetZiel(app.pendingScanSheet) else { return }
        // Gewünschtes Sheet steht schon → Wunsch erfüllt.
        if sheet == ziel { app.pendingScanSheet = nil; return }
        guard sheet != nil else { sheet = ziel; return }
        // Liegt ein ANDERES Sheet dieser View oben: erst schließen, Animation abwarten, dann neu
        // aufziehen — ein direkter Wechsel des `.sheet(item:)`-Ziels lässt sie hängen (gleiches
        // Muster und dieselbe Wartezeit wie `WeinRootView.wechsleZuErfassen`).
        sheet = nil
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            sheet = ziel
        }
    }

    /// Offenen Wunsch „Foto aufnehmen" einlösen (Schnellaktion vom App-Icon / Siri / Deep-Link).
    /// Verbraucht wird er erst, wenn die Kamera wirklich steht (`onAppear` oben).
    private func consumeCameraWish() {
        guard app.pendingCamera else { return }
        // Kamera steht schon → Wunsch erfüllt.
        if showCamera { app.pendingCamera = false; return }
        guard sheet != nil else { showCamera = true; return }
        // Ein offenes Sheet würde die gepushte Kamera verdecken: erst schließen, kurz warten.
        sheet = nil
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            showCamera = true
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
    @State private var publisher = ""
    @State private var publishedDate = ""
    @State private var bookDescription = ""
    @State private var pageCount = 0
    @State private var categoriesJSON = "[]"
    @State private var language = "de"
    @State private var coverURL: String?
    @State private var shelves: [Bookshelf] = []
    @State private var shelfId = ""
    @State private var isRead = false
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
                TextField("Verlag", text: $publisher)
                if pageCount > 0 {
                    LabeledContent("Seiten", value: "\(pageCount)")
                }
                if !categoriesLabel.isEmpty {
                    LabeledContent("Kategorien") { Text(categoriesLabel).multilineTextAlignment(.trailing) }
                }
            }
            Section("Ins Regal") {
                Picker("Regal", selection: $shelfId) {
                    Text("— kein Regal —").tag("")
                    ForEach(shelves) { s in Text(s.name).tag(s.id) }
                }
                Toggle("Schon gelesen", isOn: $isRead)
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
        .task { if shelves.isEmpty { shelves = (try? await app.api.bookshelves()) ?? [] } }
    }

    private var categoriesLabel: String {
        guard let data = categoriesJSON.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return "" }
        return arr.joined(separator: ", ")
    }

    private func lookup(_ code: String) async {
        let clean = String(code.filter { $0.isNumber || $0 == "X" })
        guard clean.count >= 10 else { return }
        isbn = clean
        busy = true; message = "Suche im Katalog …"; phase = .confirm
        let info = await ProductLookup.book(isbn: clean)
        title = info.title ?? ""
        author = info.authors.joined(separator: ", ")
        publisher = info.publisher ?? ""
        publishedDate = info.publishedDate ?? ""
        bookDescription = info.description ?? ""
        pageCount = info.pageCount ?? 0
        language = info.language ?? "de"
        categoriesJSON = jsonString(info.categories)
        coverURL = info.coverURL
        message = info.title == nil ? "Nicht im Katalog gefunden – bitte Titel ergänzen." : ""
        busy = false
    }

    // Legt das Buch mit dem VOLLEN Feldsatz an — wie die Bücher-App selbst (authors/categories als JSON,
    // publisher-Fallback "Unbekannter Verlag", Regal-Zuordnung, Lesestatus). Zielressource: elisbooks-books.
    private func save() async {
        busy = true; message = ""
        let authorsArray = author.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var fields: [String: Any] = [
            "id": UUID().uuidString.lowercased(),
            "isbn": isbn,
            "title": title,
            "authors": jsonString(authorsArray),
            "categories": categoriesJSON,
            "language": language.isEmpty ? "de" : language,
            "publisher": publisher.isEmpty ? "Unbekannter Verlag" : publisher,
            "is_read": isRead ? 1 : 0,
            "is_on_picklist": 0,
        ]
        if !publishedDate.isEmpty { fields["published_date"] = publishedDate }
        if !bookDescription.isEmpty { fields["description"] = bookDescription }
        if pageCount > 0 { fields["page_count"] = pageCount }
        if let coverURL, !coverURL.isEmpty { fields["thumbnail"] = coverURL }
        if !shelfId.isEmpty { fields["bookshelf_id"] = shelfId }
        do {
            try await app.api.createRecord("elisbooks-books", fields: fields)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            message = (error as? APIError)?.errorDescription ?? "Speichern fehlgeschlagen."
            busy = false
        }
    }

    private func jsonString(_ arr: [String]) -> String {
        (try? JSONSerialization.data(withJSONObject: arr)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

// MARK: - Lebensmittel scannen

struct VorratScanSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var marke = ""
    @State private var menge = ""
    @State private var kategorie = "kuehlschrank"
    @State private var mhd = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var photo: UIImage?
    @State private var autoFilled = false
    @State private var phase: Phase = .scan
    @State private var busy = false
    @State private var message = ""
    enum Phase { case scan, confirm }

    private static let mhdFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f }()

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
            Section {
                TextField("Name", text: $name)
                TextField("Marke (optional)", text: $marke)
                TextField("Menge (z.B. 400 g)", text: $menge)
            } header: {
                Text("Produkt")
            } footer: {
                if autoFilled { Text("Automatisch aus dem Barcode ausgefüllt – bitte prüfen.") }
            }
            Section("Lagerort") {
                Picker("Lagerort", selection: $kategorie) {
                    Text("Regal").tag("trocken")
                    Text("Kühlschrank").tag("kuehlschrank")
                    Text("Tiefkühl").tag("gefrierfach")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("vorrat-lagerort")
            }
            Section("Ablaufdatum / MHD") {
                DatePicker("Haltbar bis", selection: $mhd, displayedComponents: .date)
                    .accessibilityIdentifier("vorrat-mhd")
            }
            Section("Foto") {
                VorratPhotoField(image: $photo)
            }
            if !message.isEmpty { Section { Text(message).foregroundStyle(.secondary).font(.footnote) } }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack { if busy { ProgressView().padding(.trailing, 4) }; Text("In die Vorratskammer") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func lookup(_ code: String) async {
        busy = true; phase = .confirm; message = "Suche Produkt …"
        let info = await ProductLookup.food(ean: code)
        name = info.name ?? ""
        marke = info.brand ?? ""
        if let q = info.quantity { menge = q }
        if info.found { kategorie = ProductLookup.lagerort(categoryTags: info.categoryTags) }
        autoFilled = info.found
        message = info.name == nil ? "Nicht gefunden – bitte Namen eingeben." : ""
        // Produktbild als Foto-Vorschlag laden (überschreibbar). Nur wenn noch keins gewählt.
        if photo == nil, let img = await downloadImage(info.imageURL) { photo = img }
        busy = false
    }

    private func downloadImage(_ urlString: String?) async -> UIImage? {
        guard let s = urlString, let url = URL(string: s),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    private func save() async {
        busy = true; message = ""
        var fields: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "kategorie": kategorie,
            "mhd": Self.mhdFmt.string(from: mhd),
        ]
        if !marke.isEmpty { fields["marke"] = marke }
        if !menge.trimmingCharacters(in: .whitespaces).isEmpty { fields["menge"] = menge.trimmingCharacters(in: .whitespaces) }
        do {
            // Erst den Datensatz anlegen, dann das Foto anhängen (best effort) — so entstehen weder
            // verwaiste Medien-Dateien noch Duplikate, falls der Upload scheitert.
            let created = try await app.api.createRecord("vorrat-lebensmittel", fields: fields)
            if let jpeg = photo?.jpegForUpload(), let idVal = created["id"] {
                _ = try? await app.api.uploadMedia(jpeg: jpeg, area: "vorrat",
                                                   resource: "vorrat-lebensmittel", recordId: "\(idVal)")
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await app.loadDashboard()   // „Bald ablaufend" auf „Heute" sofort aktualisieren
            dismiss()
        } catch {
            message = (error as? APIError)?.errorDescription ?? "Speichern fehlgeschlagen."
            busy = false
        }
    }
}
