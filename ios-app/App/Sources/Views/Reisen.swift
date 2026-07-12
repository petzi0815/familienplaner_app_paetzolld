import SwiftUI
import MapKit
import CoreLocation

// ── Helfer ──
private func reisenSubEmoji(_ key: String) -> String {
    switch key {
    case "reisen-activities": return "📍"
    case "reisen-dayplans": return "🗓️"
    case "reisen-diving": return "🤿"
    case "reisen-docs": return "📄"
    case "reisen-emails": return "📧"
    case "reisen-emergency": return "🆘"
    case "reisen-flights": return "✈️"
    case "reisen-hotel": return "🏨"
    case "reisen-links": return "🔗"
    case "reisen-packing": return "🎒"
    case "reisen-phrases": return "💬"
    case "reisen-restaurants": return "🍽️"
    case "reisen-samu-activities": return "👶"
    case "reisen-weather": return "🌤️"
    default: return "•"
    }
}
private func shortReisenLabel(_ label: String) -> String {
    label.replacingOccurrences(of: "Reise-", with: "")
}
private func doubleOf(_ v: Any?) -> Double? {
    if let n = v as? NSNumber { return n.doubleValue }
    return Double(fieldString(v))
}
private func tripFrom(_ f: [String: Any]) -> Trip {
    Trip(id: Int(fieldString(f["id"])) ?? 0,
         title: fieldString(f["title"]),
         destination: fieldString(f["destination"]).isEmpty ? nil : fieldString(f["destination"]),
         startDate: fieldString(f["start_date"]).isEmpty ? nil : fieldString(f["start_date"]),
         endDate: fieldString(f["end_date"]).isEmpty ? nil : fieldString(f["end_date"]),
         lat: doubleOf(f["lat"]), lng: doubleOf(f["lng"]),
         coverImage: fieldString(f["cover_image"]).isEmpty ? nil : fieldString(f["cover_image"]))
}

/// Reisen-Liste als Cover-Raster → Reise-Detail.
struct ReiseListView: View {
    @EnvironmentObject private var app: AppState
    @State private var trips: [GenericRecord] = []
    @State private var loaded = false
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private var res: ResourceInfo? { app.resources.first { $0.key == "reisen" } }

    var body: some View {
        ScrollView {
            if trips.isEmpty && loaded {
                ContentUnavailableView("Keine Reisen", systemImage: "airplane")
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(trips) { t in
                        NavigationLink { ReiseDetailView(record: t) } label: { card(t) }.buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Reisen")
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }

    private func card(_ t: GenericRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthImage(path: recordImageURL(t.fields, res?.image))
                .frame(maxWidth: .infinity).frame(height: 110).clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(fieldString(t.fields["title"])).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(fieldString(t.fields["destination"])).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private func load() async {
        await app.loadCapabilities()
        if let r = res {
            trips = (try? await app.api.listRecords("reisen", primaryKey: r.primaryKey, limit: 100)) ?? []
        }
        loaded = true
    }
}

/// Reise-Detail: Hero (Cover/Countdown/Status), Eckdaten, Karte + alle Unterbereiche (Flüge, Hotel,
/// Aktivitäten, Restaurants, Packliste [abhakbar], Tagesplan, Doku, Wetter …) — datengetrieben.
struct ReiseDetailView: View {
    let record: GenericRecord
    @EnvironmentObject private var app: AppState
    @State private var subs: [String: [GenericRecord]] = [:]
    @State private var loaded = false

    private var f: [String: Any] { record.fields }
    private var tripId: String { fieldString(f["id"]) }
    private var reisenRes: ResourceInfo? { app.resources.first { $0.key == "reisen" } }
    private var subResources: [ResourceInfo] {
        (app.domains.first { $0.key == "reisen" }?.resources ?? [])
            .filter { $0.key != "reisen" && $0.columns.contains("trip_id") }
    }
    private var countdown: Int? {
        guard fieldString(f["status"]) == "geplant", let d = DateText.parse(date: fieldString(f["start_date"])) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day ?? 0
        return days >= 0 ? days : nil
    }

    var body: some View {
        List {
            headerSection
            metaSection
            Section("Reise-Inhalte") {
                ForEach(subResources) { res in
                    if let items = subs[res.key], !items.isEmpty {
                        DisclosureGroup {
                            ForEach(items) { it in subItemRow(res, it) }
                        } label: {
                            Text("\(reisenSubEmoji(res.key))  \(shortReisenLabel(res.label))  ·  \(items.count)")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                if loaded && subResources.allSatisfy({ (subs[$0.key]?.isEmpty ?? true) }) {
                    Text("Noch keine Inhalte hinterlegt.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(fieldString(f["title"]))
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await loadSubs() } }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                if let cover = recordImageURL(f, reisenRes?.image) {
                    AuthImage(path: cover)
                        .frame(maxWidth: .infinity).frame(height: 190).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(fieldString(f["title"])).font(.title3.weight(.bold))
                let dest = fieldString(f["destination"])
                if !dest.isEmpty {
                    let land = fieldString(f["country"])
                    Text("📍 " + dest + (land.isEmpty ? "" : ", \(land)")).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if !fieldString(f["status"]).isEmpty { BadgeView(text: fieldString(f["status"])) }
                    if let c = countdown {
                        Text("✈️ noch \(c) \(c == 1 ? "Tag" : "Tage")").font(.caption.weight(.bold))
                            .foregroundStyle(Palette.colors(for: "reisen").first!)
                    }
                    Spacer()
                    NavigationLink { ReiseKarteView(trip: tripFrom(f)) } label: {
                        Label("Karte", systemImage: "map").font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var metaSection: some View {
        Group {
            if let r = reisenRes {
                let spec = specFor(r)
                let cols = detailColumns(f, r, spec)
                if !cols.isEmpty {
                    Section("Eckdaten") {
                        ForEach(cols, id: \.self) { col in
                            let fmt = formatFor(f, col, spec)
                            if fmt != .hidden {
                                LabeledContent { FieldValueView(value: f[col], format: fmt, accent: Palette.colors(for: "reisen").first!) } label: {
                                    Text(prettyColumn(col)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func subItemRow(_ res: ResourceInfo, _ item: GenericRecord) -> some View {
        let spec = specFor(res)
        let title = titleText(item.fields, spec)
        if res.key == "reisen-packing" {
            let packed = ["1", "true"].contains(fieldString(item.fields["packed"]).lowercased())
            Button { Task { await togglePacked(res, item, packed) } } label: {
                HStack {
                    Image(systemName: packed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(packed ? .green : .secondary)
                    Text(title).strikethrough(packed).foregroundStyle(packed ? .secondary : .primary)
                    Spacer()
                    if let cat = item.fields["category"].map({ fieldString($0) }), !cat.isEmpty {
                        Text(cat).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { ResourceDetailView(resource: res, record: item) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).lineLimit(1)
                    if let sub = formattedFieldText(item.fields, spec.listSubtitle, spec) {
                        Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private func loadSubs() async {
        loaded = true
        await app.loadCapabilities()
        let tid = tripId
        for res in subResources {
            if let items = try? await app.api.listRecords(res.key, primaryKey: res.primaryKey, filter: ["trip_id": tid]) {
                subs[res.key] = items
            }
        }
    }

    private func togglePacked(_ res: ResourceInfo, _ item: GenericRecord, _ packed: Bool) async {
        let newVal = packed ? 0 : 1
        try? await app.api.patchRecord(res.key, id: item.id, fields: ["packed": newVal])
        if var arr = subs[res.key], let idx = arr.firstIndex(where: { $0.id == item.id }) {
            var flds = arr[idx].fields; flds["packed"] = newVal
            arr[idx] = GenericRecord(id: item.id, fields: flds)
            subs[res.key] = arr
        }
    }
}

/// Reiseziel + Aktivitäten auf einer Karte (MapKit).
struct ReiseKarteView: View {
    @EnvironmentObject private var app: AppState
    let trip: Trip

    @State private var activities: [TripActivity] = []
    @State private var center: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var loaded = false

    var body: some View {
        Map(position: $camera) {
            if let c = center {
                Marker(trip.destination ?? trip.title, systemImage: "airplane", coordinate: c)
                    .tint(Palette.colors(for: "reisen").first!)
            }
            ForEach(activities) { a in
                if let lat = a.lat, let lng = a.lng {
                    Marker(a.title, systemImage: "mappin", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                        .tint(.orange)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .overlay(alignment: .bottom) {
            if loaded && center == nil && !activities.contains(where: { $0.lat != nil }) {
                Text("Keine Koordinaten hinterlegt")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule()).padding()
            }
        }
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load() } }
    }

    private func load() async {
        activities = (try? await app.api.tripActivities(tripId: trip.id)) ?? []
        if let lat = trip.lat, let lng = trip.lng {
            center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else if let a = activities.first(where: { $0.lat != nil && $0.lng != nil }), let lat = a.lat, let lng = a.lng {
            center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else if let dest = trip.destination, !dest.isEmpty {
            center = await geocode(dest)
        }
        loaded = true
    }

    private func geocode(_ query: String) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { cont in
            CLGeocoder().geocodeAddressString(query) { placemarks, _ in
                cont.resume(returning: placemarks?.first?.location?.coordinate)
            }
        }
    }
}
