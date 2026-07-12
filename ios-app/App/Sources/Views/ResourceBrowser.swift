import SwiftUI
import UIKit

/// Schnellaktionen je Ressource (spiegelt die Registry-Actions im Backend).
struct QuickAction: Identifiable {
    let label: String
    let systemImage: String
    let patch: [String: Any]
    var id: String { label }
}
let QUICK_ACTIONS: [String: [QuickAction]] = [
    "samu-items": [
        QuickAction(label: "Aussortieren", systemImage: "archivebox", patch: ["status": "aussortiert"]),
        QuickAction(label: "Aktiv", systemImage: "checkmark.circle", patch: ["status": "aktiv"]),
    ],
    "geschenk-geschenke": [
        QuickAction(label: "Vergeben", systemImage: "gift", patch: ["status": "vergeben"]),
        QuickAction(label: "Schon geschenkt", systemImage: "checkmark.seal", patch: ["status": "geschenkt"]),
    ],
    "vorrat-lebensmittel": [
        QuickAction(label: "Als verbraucht markieren", systemImage: "trash", patch: ["status": "verbraucht"]),
    ],
]

/// Generische Liste einer Ressource — Bildraster für bildlastige Bereiche, sonst Liste. Spec-getrieben.
struct ResourceListView: View {
    let resource: ResourceInfo
    @EnvironmentObject private var app: AppState
    @State private var records: [GenericRecord] = []
    @State private var query = ""
    @State private var loading = true

    private var spec: DisplaySpec { specFor(resource) }
    private var isGrid: Bool { resource.image != nil }
    private let gcols = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        Group {
            if loading && records.isEmpty {
                ProgressView().padding(.top, 60)
            } else if records.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Noch nichts hier" : "Keine Treffer",
                                       systemImage: isGrid ? "photo.on.rectangle" : "tray")
            } else if isGrid {
                gridBody
            } else {
                listBody
            }
        }
        .navigationTitle(resource.label)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "In \(resource.label) suchen")
        .onSubmit(of: .search) { Task { await load() } }
        .onChange(of: query) { _, v in if v.isEmpty { Task { await load() } } }
        .task { if records.isEmpty { await load() } }
        .refreshable { await load() }
    }

    private var listBody: some View {
        List(records) { rec in
            NavigationLink { ResourceDetailView(resource: resource, record: rec) } label: { row(rec) }
        }
        .listStyle(.plain)
    }

    private func row(_ rec: GenericRecord) -> some View {
        let title = titleText(rec.fields, spec)
        let sub = formattedFieldText(rec.fields, spec.listSubtitle, spec)
        let badge = badgeValue(rec.fields)
        return HStack(spacing: 12) {
            if let url = recordImageURL(rec.fields, resource.image) {
                AuthImage(path: url).frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let sub { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if let badge { BadgeView(text: badge) }
        }
    }

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(columns: gcols, spacing: 10) {
                ForEach(records) { rec in
                    NavigationLink { ResourceDetailView(resource: resource, record: rec) } label: { cell(rec) }
                        .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private func cell(_ rec: GenericRecord) -> some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay { AuthImage(path: recordImageURL(rec.fields, resource.image)) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(titleText(rec.fields, spec)).font(.caption2.weight(.bold)).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule()).padding(6)
            }
            .overlay(alignment: .topTrailing) {
                if let b = badgeValue(rec.fields) {
                    Circle().fill(badgeColor(b)).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5)).padding(6)
                }
            }
    }

    private func badgeValue(_ fields: [String: Any]) -> String? {
        guard let key = spec.badgeField else { return nil }
        let v = fieldString(fields[key]); return v.isEmpty ? nil : v
    }

    private func load() async {
        loading = true
        records = (try? await app.api.listRecords(resource.key, primaryKey: resource.primaryKey,
                                                   search: query.isEmpty ? nil : query)) ?? []
        loading = false
    }
}

/// Detail eines Datensatzes — Kopf-Karte (Bild/Titel/Untertitel/Badge), Schnellaktionen, formatierte Felder.
struct ResourceDetailView: View {
    let resource: ResourceInfo
    @EnvironmentObject private var app: AppState
    @State private var fields: [String: Any]
    @State private var busy = false
    @State private var message = ""

    init(resource: ResourceInfo, record: GenericRecord) {
        self.resource = resource
        _fields = State(initialValue: record.fields)
    }

    private var spec: DisplaySpec { specFor(resource) }
    private var accent: Color { Palette.colors(for: resource.domain).first ?? .accentColor }
    private var actions: [QuickAction] { QUICK_ACTIONS[resource.key] ?? [] }
    private var recordId: String { fieldString(fields[resource.primaryKey]) }
    private var heroURLs: [String] { recordImageURLs(fields, resource.image) }

    var body: some View {
        List {
            // ── Kopf-Karte ──
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if !heroURLs.isEmpty { hero }
                    Text(titleText(fields, spec)).font(.title3.weight(.bold))
                    if let sub = formattedFieldText(fields, spec.subtitleField, spec) {
                        Text(sub).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let b = badgeValue { BadgeView(text: b) }
                }
                .padding(.vertical, 4)
            }

            if !actions.isEmpty {
                Section("Aktionen") {
                    ForEach(actions) { a in
                        Button { Task { await apply(a) } } label: { Label(a.label, systemImage: a.systemImage) }
                            .disabled(busy)
                    }
                    if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }

            // ── Felder ──
            Section("Details") {
                ForEach(detailColumns(fields, resource, spec), id: \.self) { col in
                    fieldRow(col)
                }
            }
        }
        .navigationTitle(resource.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var badgeValue: String? {
        guard let key = spec.badgeField else { return nil }
        let v = fieldString(fields[key]); return v.isEmpty ? nil : v
    }

    @ViewBuilder private var hero: some View {
        if heroURLs.count == 1 {
            AuthImage(path: heroURLs[0], contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(heroURLs.enumerated()), id: \.offset) { _, u in
                        AuthImage(path: u)
                            .frame(width: 190, height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder private func fieldRow(_ col: String) -> some View {
        let f = formatFor(fields, col, spec)
        if f != .hidden {
            if f.isBlock {
                VStack(alignment: .leading, spacing: 4) {
                    Text(prettyColumn(col)).font(.caption).foregroundStyle(.secondary)
                    FieldValueView(value: fields[col], format: f, accent: accent)
                }
                .padding(.vertical, 2)
            } else {
                LabeledContent { FieldValueView(value: fields[col], format: f, accent: accent) } label: {
                    Text(prettyColumn(col)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func apply(_ a: QuickAction) async {
        busy = true; message = ""
        do {
            try await app.api.patchRecord(resource.key, id: recordId, fields: a.patch)
            for (k, v) in a.patch { fields[k] = v }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            message = "\"\(a.label)\" übernommen."
        } catch {
            message = (error as? APIError)?.errorDescription ?? "Aktion fehlgeschlagen."
        }
        busy = false
    }
}

/// Lädt einen Datensatz per ID (z.B. aus einem Suchtreffer) und zeigt sein Detail.
struct RecordLoaderView: View {
    let resource: ResourceInfo
    let id: String
    @EnvironmentObject private var app: AppState
    @State private var record: GenericRecord?
    @State private var failed = false

    var body: some View {
        Group {
            if let record {
                ResourceDetailView(resource: resource, record: record)
            } else if failed {
                ContentUnavailableView("Nicht gefunden", systemImage: "questionmark.circle")
            } else {
                ProgressView().task {
                    do { record = try await app.api.getRecord(resource.key, id: id) }
                    catch { failed = true }
                }
            }
        }
    }
}
