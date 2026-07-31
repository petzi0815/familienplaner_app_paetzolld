import SwiftUI

/// Weinliste des aktiven Segments. `List` statt `ScrollView`, damit es native Wisch-Aktionen gibt
/// (Loeschen + Flasche getrunken); der Karten-Look bleibt ueber transparente Zeilen erhalten
/// (Muster der acht umgebauten Listen dieses Repos).
struct WeinListView: View {
    /// Aktion des Leerzustands — oeffnet das Erfassen-Sheet der Bereichswurzel.
    var onErfassen: () -> Void = {}

    @EnvironmentObject private var store: WeinStore
    @State private var deleteTarget: Wein?

    var body: some View {
        Group {
            if store.gefiltert.isEmpty {
                ScrollView {
                    leerZustand.frame(maxWidth: .infinity).frame(minHeight: 300)
                }
                .refreshable { await store.reload() }
            } else {
                List {
                    ForEach(store.gefiltert) { w in zeile(w) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await store.reload() }
            }
        }
        .confirmationDialog(deleteTarget.map { $0.titel + " löschen?" } ?? "",
                            isPresented: Binding(get: { deleteTarget != nil },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let t = deleteTarget { Task { await store.delete(t) } }
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Der Wein wird mit allen Bewertungen und Preisen gelöscht.")
        }
    }

    // ── Leerzustand (unterscheidet leerer Bereich / kein Treffer) ──

    private var leerZustand: some View {
        // `filterAktiv` deckt Typ/Rebsorte/Land/Sterne ab; Suchtext und Segment kommen dazu.
        let gefiltertLeer = store.filterAktiv || !store.suche.isEmpty || store.tab != .alle
        let aktion: (() -> Void)? = gefiltertLeer ? nil : onErfassen
        let aktionLabel: String? = gefiltertLeer ? nil : "Wein erfassen"
        let hinweis: String = gefiltertLeer
            ? "Andere Filter oder Suchbegriffe probieren."
            : "Etikett fotografieren oder Barcode scannen — den Rest ergänzt die KI."
        return AreaEmptyState(
            emoji: gefiltertLeer ? "🔍" : "🍷",
            title: gefiltertLeer ? "Keine Treffer" : "Noch keine Weine erfasst",
            hint: hinweis,
            actionLabel: aktionLabel,
            action: aktion
        )
    }

    // ── Zeile: Karte im NavigationLink (antippbare Zelle MUSS ein Button sein) ──

    private func zeile(_ w: Wein) -> some View {
        // Closure-basierter NavigationLink: wertbasierte Links sind in bereits gepushten Views flaky.
        NavigationLink {
            WeinDetailView(wein: w).environmentObject(store)
        } label: {
            WeinKarte(wein: w, meine: store.meine(w), andere: store.andere(w))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wein-" + String(w.id))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleteTarget = w } label: {
                Label("Löschen", systemImage: "trash")
            }
            .accessibilityIdentifier("wein-swipe-loeschen-" + String(w.id))
            if w.bestand > 0 {
                Button { Task { await store.setBestand(w, w.bestand - 1) } } label: {
                    Label("Getrunken", systemImage: "wineglass")
                }
                .tint(Color(hex: "7C3AED"))
                .accessibilityIdentifier("wein-swipe-getrunken-" + String(w.id))
            }
        }
    }
}

// MARK: - Karte

/// Listenkarte: Etikettenfoto, Titel, Herkunft/Rebsorte, BEIDE Bewertungen nebeneinander,
/// Typ-Pille, Bestandsbadge und der beste Preis mit Rabatt-Hinweis.
struct WeinKarte: View {
    let wein: Wein
    var meine: WeinBewertung?
    var andere: WeinBewertung?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            etikett
            VStack(alignment: .leading, spacing: 5) {
                Text(wein.titel).font(.subheadline.weight(.semibold)).lineLimit(2)
                if !herkunft.isEmpty {
                    Text(herkunft).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                bewertungen
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Pill(text: wein.typ.emoji + " " + wein.typ.label, color: wein.typ.farbe)
                if wein.bestand > 0 {
                    Pill(text: String(wein.bestand) + " Fl.", systemImage: "archivebox",
                         color: Color(hex: "475569"), filled: false)
                }
                preis
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Herkunft + Rebsorten in einer Zeile — was da ist, in dieser Reihenfolge.
    private var herkunft: String {
        var teile: [String] = []
        let ort = WeinText.herkunft(land: wein.land, region: wein.region, lage: nil)
        if !ort.isEmpty { teile.append(ort) }
        if !wein.rebsorten.isEmpty { teile.append(wein.rebsorten.prefix(2).joined(separator: ", ")) }
        return teile.joined(separator: " · ")
    }

    private var etikett: some View {
        Group {
            if let path = wein.imagePath {
                AuthImage(path: path, contentMode: .fill)
            } else {
                Palette.gradient(for: "wein").opacity(0.20)
                    .overlay(Text(wein.typ.emoji).font(.title2))
            }
        }
        .frame(width: 54, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Beide Bewertungen nebeneinander (L 4 Sterne / E 5 Sterne) — Kernnutzen des Bereichs.
    @ViewBuilder private var bewertungen: some View {
        if meine == nil && andere == nil {
            Text("Noch nicht bewertet").font(.caption2).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                if let b = meine { WeinSterne(sterne: b.sterne, kuerzel: WeinText.kuerzel(b.owner)) }
                if let b = andere { WeinSterne(sterne: b.sterne, kuerzel: WeinText.kuerzel(b.owner)) }
            }
        }
    }

    /// Bester gefundener Preis; liegt er spuerbar unter dem Referenzpreis, kommt der Rabatt davor.
    @ViewBuilder private var preis: some View {
        if let best = wein.besterPreis {
            HStack(spacing: 5) {
                if let r = wein.rabattProzent, r >= 5 {
                    Pill(text: WeinText.rabatt(r), systemImage: "tag.fill", color: Color(hex: "16A34A"))
                }
                Text(WeinText.eur(best)).font(.caption.weight(.semibold))
            }
        } else if let ref = wein.referenzpreis {
            Text(WeinText.eur(ref)).font(.caption).foregroundStyle(.secondary)
        }
    }
}
