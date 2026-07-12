import SwiftUI
import UIKit
import PhotosUI

/// Fotobox: Foto aufnehmen -> Domaene (auto-erkannt oder gewaehlt) -> kontextabhaengige Dropdowns
/// mit GUELTIGEN Werten setzen -> an Ole uebergeben. Die Feld-Optionen kommen datengetrieben aus
/// /fotobox-items/form-config, passen sich also an die gewaehlte Domaene an.
struct FotoboxView: View {
    @EnvironmentObject private var app: AppState

    @State private var cameraSource: ImageSource?
    @State private var pickerItem: PhotosPickerItem?
    @State private var picked: UIImage?

    @State private var forms: [FotoboxDomainForm] = []
    @State private var intents: [String] = []
    @State private var loadingForms = true

    @State private var domain = ""
    @State private var intent = "create"
    @State private var fieldValues: [String: String] = [:]
    @State private var customFields: Set<String> = []
    @State private var note = ""

    @State private var aiPicked = false
    @State private var aiHint = ""
    @State private var busy = false
    @State private var message = ""
    @State private var success = false
    @State private var tick = 0

    private var selectedForm: FotoboxDomainForm? { forms.first { $0.domain == domain } }
    private var gradientKey: String { Self.paletteKey(domain) }
    private var canSave: Bool { picked != nil && !domain.isEmpty && !busy }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                sourceButtons
                if picked != nil {
                    if loadingForms {
                        ProgressView("Werte laden …").padding(.top, 8)
                    } else {
                        domainSection
                        if let f = selectedForm, !f.fields.isEmpty { fieldsSection(f) }
                        intentSection
                        noteField
                        saveButton
                    }
                }
                if !message.isEmpty { statusLine }
            }
            .padding()
            .animation(.snappy, value: picked != nil)
            .animation(.snappy, value: domain)
        }
        .background(Palette.gradient(for: gradientKey).opacity(0.10).ignoresSafeArea())
        .navigationTitle("Fotobox")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $cameraSource) { src in ImagePicker(sourceType: src.type) { onPicked($0) } }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { onPicked(img) }
                pickerItem = nil
            }
        }
        .sensoryFeedback(.success, trigger: tick)
        .sensoryFeedback(.selection, trigger: domain)
        .task { await loadConfig() }
    }

    // MARK: - Kopf / Aufnahme

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemBackground))
            if let picked {
                Image(uiImage: picked).resizable().scaledToFill()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.aperture").font(.system(size: 54))
                        .foregroundStyle(Palette.gradient(for: "foto")).symbolEffect(.pulse, options: .repeating)
                    Text("Foto aufnehmen oder waehlen").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 260)
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
                .background(Palette.gradient(for: "foto"), in: Capsule()).foregroundStyle(.white)
            }
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Mediathek", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(Color(.secondarySystemBackground), in: Capsule()).foregroundStyle(.primary)
        }
        .font(.subheadline.weight(.semibold))
    }

    // MARK: - Domaene

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Bereich", aiPicked && !aiHint.isEmpty ? aiHint : "Wohin gehoert das Foto?")
            Menu {
                ForEach(forms) { f in
                    Button { selectDomain(f.domain, byAI: false) } label: {
                        if f.domain == domain { Label(f.label, systemImage: "checkmark") } else { Text(f.label) }
                    }
                }
            } label: {
                HStack {
                    Text(selectedForm?.label ?? "Bereich waehlen")
                        .font(.headline)
                        .foregroundStyle(domain.isEmpty ? Color.secondary : .primary)
                    Spacer()
                    if aiPicked { Image(systemName: "sparkles").foregroundStyle(Palette.gradient(for: gradientKey)) }
                    Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Kontextabhaengige Felder

    private func fieldsSection(_ form: FotoboxDomainForm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Details", "Gueltige Werte fuer " + form.label)
            VStack(spacing: 0) {
                ForEach(Array(form.fields.enumerated()), id: \.element.id) { idx, field in
                    if idx > 0 { Divider().padding(.leading, 14) }
                    fieldRow(field)
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder private func fieldRow(_ field: FotoboxFormField) -> some View {
        let current = fieldValues[field.key] ?? ""
        let showText = field.options.isEmpty || customFields.contains(field.key)
        VStack(spacing: 0) {
            HStack {
                Text(field.label).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                if field.options.isEmpty {
                    Text("frei").font(.caption).foregroundStyle(.tertiary)
                } else {
                    Menu {
                        ForEach(field.options, id: \.self) { opt in
                            Button { fieldValues[field.key] = opt; customFields.remove(field.key) } label: {
                                if current == opt { Label(opt, systemImage: "checkmark") } else { Text(opt) }
                            }
                        }
                        if !field.isStrict {
                            Divider()
                            Button { customFields.insert(field.key); if fieldValues[field.key] == nil { fieldValues[field.key] = "" } } label: {
                                Label("Anderer Wert …", systemImage: "pencil")
                            }
                        }
                        if !current.isEmpty {
                            Divider()
                            Button(role: .destructive) { fieldValues[field.key] = nil; customFields.remove(field.key) } label: {
                                Label("leeren", systemImage: "xmark")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(current.isEmpty ? "waehlen" : current)
                                .foregroundStyle(current.isEmpty ? Color.secondary : .primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if showText {
                TextField("Eigener Wert (optional)", text: Binding(
                    get: { fieldValues[field.key] ?? "" },
                    set: { fieldValues[field.key] = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }

    // MARK: - Intent / Notiz / Speichern

    private var intentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Aktion", "Was soll Ole tun?")
            Menu {
                ForEach(intentOptions, id: \.self) { i in
                    Button { intent = i } label: {
                        if intent == i { Label(i, systemImage: "checkmark") } else { Text(i) }
                    }
                }
            } label: {
                HStack {
                    Text(intent).font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var noteField: some View {
        TextField("Notiz fuer Ole (optional)", text: $note, axis: .vertical)
            .textFieldStyle(.plain).padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .lineLimit(1...3)
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) } else { Image(systemName: "paperplane.fill") }
                Text(busy ? "Speichert …" : "An Ole uebergeben")
            }
        }
        .buttonStyle(GradientButtonStyle(gradientKey: gradientKey, enabled: canSave))
        .disabled(!canSave)
    }

    private var statusLine: some View {
        Label(message, systemImage: success ? "checkmark.circle.fill" : "info.circle")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(success ? Color.green : .secondary)
            .symbolEffect(.bounce, value: tick)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            if !subtitle.isEmpty { Text(subtitle).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
    }

    private var intentOptions: [String] { intents.isEmpty ? ["create", "search", "update", "scan"] : intents }

    // MARK: - Logik

    private func loadConfig() async {
        loadingForms = true
        forms = (try? await app.api.fotoboxForms()) ?? []
        intents = (try? await app.api.fotoboxIntents()) ?? []
        loadingForms = false
    }

    private func onPicked(_ img: UIImage) {
        picked = img; message = ""; success = false
        if forms.isEmpty { Task { await loadConfig(); await suggestDomain(img) } }
        else { Task { await suggestDomain(img) } }
    }

    private func suggestDomain(_ img: UIImage) async {
        guard domain.isEmpty, PhotoBereichSuggester.isAvailable, !forms.isEmpty else { return }
        if let d = await PhotoBereichSuggester.suggestDomain(image: img, note: note, domains: forms) {
            withAnimation(.snappy) { selectDomain(d, byAI: true) }
        }
    }

    private func selectDomain(_ d: String, byAI: Bool) {
        domain = d
        aiPicked = byAI
        aiHint = byAI ? "Von der KI vorgeschlagen – bitte pruefen." : ""
        fieldValues = [:]
        customFields = []
    }

    private func save() async {
        guard let img = picked, let jpeg = img.jpegForUpload(), !domain.isEmpty else { return }
        busy = true; message = ""; success = false

        var hint: [String: Any] = [:]
        for (k, v) in fieldValues where !v.isEmpty { hint[k] = v }
        if !note.isEmpty { hint["notes"] = note }

        let device = UIDevice.current.identifierForVendor?.uuidString ?? "ios"
        let stamp = Int(Date().timeIntervalSince1970)
        var payload: [String: Any] = [
            "idempotency_key": "ios-\(device)-\(stamp)-\(UUID().uuidString.prefix(6))",
            "source": "app_fotobox",
            "status": "pending",
            "uploaded_by": ["device_id": device],
            "routing": [
                "domain": domain,
                "intent": intent,
                "preclassified_by": aiPicked ? "ios_local_ai" : "manual",
            ],
            "media": [[
                "data_base64": jpeg.base64EncodedString(),
                "mime": "image/jpeg",
                "filename": "fotobox.jpg",
            ]],
        ]
        if !hint.isEmpty { payload["analysis_hint"] = hint }

        do {
            _ = try await app.api.createFotoboxItem(payload)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            success = true; tick += 1
            message = "Uebergeben — Ole verarbeitet das Foto."
            picked = nil; domain = ""; fieldValues = [:]; customFields = []; note = ""; aiPicked = false; aiHint = ""
        } catch {
            message = (error as? APIError)?.errorDescription ?? "Speichern fehlgeschlagen."
        }
        busy = false
    }

    private static func paletteKey(_ domain: String) -> String {
        if domain.hasPrefix("garten") { return "garten" }
        switch domain {
        case "samu_items": return "samu"
        case "gypsi_futter": return "gypsi"
        case "vorrat_lebensmittel": return "vorratskammer"
        case "reiniger_produkt": return "reiniger"
        case "buecher_scan": return "buecher"
        case "geschenk_wunsch": return "geschenkplaner"
        case "reisen_doc": return "reisen"
        case "smarthome_device": return "smarthome"
        case "vertrag_doc": return "vertraege"
        default: return "foto"
        }
    }
}
