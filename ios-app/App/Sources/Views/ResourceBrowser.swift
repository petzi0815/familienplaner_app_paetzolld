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

/// Generische Liste einer Ressource — Bildraster für bildlastige Bereiche, sonst Liste. Mit Suche.
struct ResourceListView: View {
    let resource: ResourceInfo
    @EnvironmentObject private var app: AppState
    @State private var records: [GenericRecord] = []
    @State private var query = ""
    @State private var loading = true

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
        let title = recordTitle(rec.fields)
        return HStack(spacing: 12) {
            if let url = recordImageURL(rec.fields, resource.image) {
                AuthImage(path: url).frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let sub = recordSubtitle(rec.fields, titleShown: title) {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
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
        AuthImage(path: recordImageURL(rec.fields, resource.image))
            .aspectRatio(1, contentMode: .fill)
            .frame(minHeight: 110)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(recordTitle(rec.fields)).font(.caption2.weight(.bold)).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule()).padding(6)
            }
    }

    private func load() async {
        loading = true
        records = (try? await app.api.listRecords(resource.key, primaryKey: resource.primaryKey,
                                                   search: query.isEmpty ? nil : query)) ?? []
        loading = false
    }
}

/// Detail eines Datensatzes — Bild, Schnellaktionen, alle Felder.
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

    private var actions: [QuickAction] { QUICK_ACTIONS[resource.key] ?? [] }
    private var recordId: String { fieldString(fields[resource.primaryKey]) }
    private var displayColumns: [String] { resource.columns.filter { $0 != resource.image?.col } }

    var body: some View {
        List {
            if let url = recordImageURL(fields, resource.image) {
                Section {
                    AuthImage(path: url)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
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
            Section("Details") {
                ForEach(displayColumns, id: \.self) { col in
                    let v = fieldString(fields[col])
                    if !v.isEmpty {
                        LabeledContent(prettyColumn(col)) {
                            Text(v).multilineTextAlignment(.trailing).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(recordTitle(fields))
        .navigationBarTitleDisplayMode(.inline)
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
