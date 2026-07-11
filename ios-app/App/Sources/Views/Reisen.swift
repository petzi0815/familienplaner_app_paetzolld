import SwiftUI
import MapKit
import CoreLocation

/// Liste der Reisen (GET /api/v1/reisen) → Detail mit Karte.
struct ReiseListView: View {
    @EnvironmentObject private var app: AppState
    @State private var trips: [Trip] = []
    @State private var loaded = false

    var body: some View {
        List {
            if trips.isEmpty && loaded {
                ContentUnavailableView("Keine Reisen", systemImage: "airplane",
                                       description: Text("Reisen aus dem Familienplaner erscheinen hier."))
            }
            ForEach(trips) { trip in
                NavigationLink {
                    ReiseKarteView(trip: trip)
                } label: {
                    HStack(spacing: 12) {
                        GradientIcon(systemName: "airplane", gradientKey: "reisen", size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trip.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let dest = trip.destination, !dest.isEmpty {
                                Text(dest).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Reisen")
        .task { if !loaded { trips = (try? await app.api.trips()) ?? []; loaded = true } }
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
                    Marker(a.title, systemImage: icon(for: a.category),
                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
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

    private func icon(for category: String?) -> String {
        switch category ?? "" {
        case "restaurant": return "fork.knife"
        case "hotel": return "bed.double.fill"
        case "strand", "beach": return "beach.umbrella.fill"
        case "tauchen", "diving": return "figure.pool.swim"
        case "aktivitaet", "activity": return "figure.walk"
        default: return "mappin"
        }
    }
}
