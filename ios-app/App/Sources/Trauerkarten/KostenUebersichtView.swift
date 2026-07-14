import SwiftUI
import UIKit

// MARK: - Kostenübersicht (Summen + Liste + Verteilung + Ausgleich)

struct KostenUebersichtView: View {
    @EnvironmentObject private var store: TrauerkartenStore
    @State private var editEntry: KostenEintrag?
    @State private var confirmDelete: KostenEintrag?
    @State private var belegPreview: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCards
                spendenSection
                if !store.kosten.isEmpty { manualSection }
                totalCard
                if !store.personen.isEmpty {
                    VerteilungSection(items: store.verteilung)
                    AusgleichSection(zahlungen: store.ausgleichszahlungen, gesamt: store.gesamtImbalance)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
        }
        .sheet(item: $editEntry) { e in KostenFormSheet(eintrag: e).environmentObject(store) }
        .sheet(item: Binding(get: { belegPreview.map { PreviewPath(path: $0) } }, set: { belegPreview = $0?.path })) { p in
            BelegPreviewSheet(path: p.path)
        }
        .confirmationDialog(confirmDelete.map { "\($0.beschreibung) löschen?" } ?? "",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let e = confirmDelete { Task { await store.deleteKosten(e) } }; confirmDelete = nil }
            Button("Abbrechen", role: .cancel) { confirmDelete = nil }
        }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            KostenSummaryCard(title: "Einnahmen", value: TrauerStyle.eur(store.summeEinnahmen), color: TrauerStyle.einnahme, tint: TrauerStyle.einnahme)
            KostenSummaryCard(title: "Ausgaben", value: TrauerStyle.eur(store.summeAusgaben), color: TrauerStyle.ausgabe, tint: TrauerStyle.ausgabe)
            KostenSummaryCard(title: "Saldo", value: TrauerStyle.eur(store.saldo), color: TrauerStyle.saldoColor(store.saldo), tint: TrauerStyle.saldoColor(store.saldo))
            KostenSummaryCard(title: "Einträge", value: "\(store.eintraegeAnzahl)", color: .primary, tint: .gray)
        }
    }

    // Trauerkarten-Spenden nach Person (automatische Einnahmen).
    @ViewBuilder private var spendenSection: some View {
        let groups = store.spendenNachPerson
        if !groups.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Pill(text: "Einnahme", color: TrauerStyle.einnahme)
                            Text("Trauerkarten-Spenden (\(String(g.karten.count)) Karten)").font(.subheadline.weight(.semibold))
                            Text("\(g.person?.name ?? "Alle Personen") · Automatisch").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(TrauerStyle.eur(g.summe))").font(.subheadline.weight(.bold)).foregroundStyle(TrauerStyle.einnahme)
                    }
                    .padding(12)
                    .background(TrauerStyle.einnahme.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if groups.count > 1 {   // gemischte Zuordnung → zusätzliche Gesamt-Summenkarte (wie im Original)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Pill(text: "Einnahme", color: TrauerStyle.einnahme)
                            Text("Trauerkarten-Spenden Gesamt (\(String(store.kartenAnzahl)) Karten)").font(.subheadline.weight(.bold))
                        }
                        Spacer()
                        Text("+\(TrauerStyle.eur(store.trauerkartenSumme))").font(.subheadline.weight(.bold)).foregroundStyle(TrauerStyle.einnahme)
                    }
                    .padding(12)
                    .background(TrauerStyle.einnahme.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var manualSection: some View {
        VStack(spacing: 8) {
            ForEach(store.kosten) { e in
                KostenEntryRow(eintrag: e,
                               personName: store.personName(e.personId),
                               onEdit: { editEntry = e },
                               onDelete: { confirmDelete = e },
                               onBeleg: { if let p = e.belegPath { belegPreview = p } })
            }
        }
    }

    private var totalCard: some View {
        HStack {
            Text("Summe aller Einnahmen und Ausgaben").font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(store.saldo >= 0 ? "+" : "")\(TrauerStyle.eur(store.saldo))")
                .font(.headline.weight(.bold)).foregroundStyle(TrauerStyle.saldoColor(store.saldo))
        }
        .padding(14)
        .background(TrauerStyle.saldoColor(store.saldo).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PreviewPath: Identifiable { let id = UUID(); let path: String }

struct KostenSummaryCard: View {
    let title: String; let value: String; let color: Color; let tint: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct KostenEntryRow: View {
    let eintrag: KostenEintrag
    let personName: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onBeleg: () -> Void

    private var color: Color { eintrag.istEinnahme ? TrauerStyle.einnahme : TrauerStyle.ausgabe }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let path = eintrag.belegPath {
                Button(action: onBeleg) {
                    AuthImage(path: path, contentMode: .fill).frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 3) {
                Pill(text: eintrag.istEinnahme ? "Einnahme" : "Ausgabe", color: color)
                Text(eintrag.beschreibung).font(.subheadline.weight(.semibold))
                Text("\(TrauerStyle.prettyDate(eintrag.datum)) · \(personName)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 8) {
                Text("\(eintrag.istEinnahme ? "+" : "-")\(TrauerStyle.eur(eintrag.betrag))")
                    .font(.subheadline.weight(.bold)).foregroundStyle(color)
                HStack(spacing: 12) {
                    Button(action: onEdit) { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(TrauerStyle.ausgabe)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Kostenverteilung + Ausgleich

struct VerteilungSection: View {
    let items: [PersonSaldo]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Kostenverteilung pro Person", systemImage: "person.2").font(.subheadline.weight(.bold))
            ForEach(items) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.subheadline.weight(.semibold))
                        Text("Einnahmen: \(TrauerStyle.eur(p.einnahmen)) · Ausgaben: \(TrauerStyle.eur(p.ausgaben))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(p.saldo >= 0 ? "+" : "")\(TrauerStyle.eur(p.saldo))")
                        .font(.subheadline.weight(.bold)).foregroundStyle(p.saldo >= 0 ? TrauerStyle.einnahme : TrauerStyle.ausgabe)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AusgleichSection: View {
    let zahlungen: [Ausgleichszahlung]
    let gesamt: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ausgleichszahlungen", systemImage: "arrow.left.arrow.right").font(.subheadline.weight(.bold))
            if zahlungen.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(TrauerStyle.einnahme)
                        Text("Alle Kosten sind ausgeglichen").font(.subheadline)
                    }
                    Text("Keine Ausgleichszahlungen erforderlich").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(TrauerStyle.einnahme.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("Gesamtbetrag auszugleichen: \(TrauerStyle.eur(gesamt))").font(.caption).foregroundStyle(.secondary)
                ForEach(zahlungen) { z in
                    HStack {
                        Text(z.from).font(.subheadline.weight(.medium))
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Text(z.to).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(TrauerStyle.eur(z.betrag)).font(.subheadline.weight(.bold)).foregroundStyle(TrauerStyle.saldoPos)
                    }
                    .padding(10)
                    .background(TrauerStyle.saldoPos.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text("Hinweis: Diese Berechnung optimiert die Anzahl der Transaktionen. Nach Durchführung aller Zahlungen haben alle Personen den gleichen Anteil an den Gesamtkosten getragen.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Beleg-Vollbild

struct BelegPreviewSheet: View {
    let path: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            AuthImage(path: path, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.9)).ignoresSafeArea(edges: .bottom)
                .navigationTitle("Beleg").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
    }
}

// MARK: - Eintrag anlegen/bearbeiten

struct KostenFormSheet: View {
    let eintrag: KostenEintrag?
    @EnvironmentObject private var store: TrauerkartenStore
    @Environment(\.dismiss) private var dismiss

    @State private var istEinnahme = false
    @State private var beschreibung = ""
    @State private var betrag = ""
    @State private var datum = Date()
    @State private var personId: Int?
    @State private var pickedImage: UIImage?
    @State private var pickerSource: ImageSource?
    @State private var saving = false

    private var isEdit: Bool { eintrag != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Typ", selection: $istEinnahme) {
                        Text("Ausgabe").tag(false)
                        Text("Einnahme").tag(true)
                    }.pickerStyle(.segmented)
                }
                Section("Eintrag") {
                    TextField("Beschreibung *", text: $beschreibung, axis: .vertical).lineLimit(1...4)
                    HStack { TextField("Betrag *", text: $betrag).keyboardType(.decimalPad); Text("€").foregroundStyle(.secondary) }
                    DatePicker("Datum", selection: $datum, displayedComponents: .date).environment(\.locale, Locale(identifier: "de_DE"))
                    Picker("Person", selection: $personId) {
                        Text("Alle (keine spezielle Person)").tag(Int?.none)
                        ForEach(store.personen) { p in Text(p.name).tag(Int?.some(p.id)) }
                    }
                }
                Section("Beleg (optional)") { belegSection }
            }
            .navigationTitle(isEdit ? "Eintrag bearbeiten" : "Neuer Eintrag").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Speichern" : "Hinzufügen") { Task { await save() } }
                        .disabled(beschreibung.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .sheet(item: $pickerSource) { src in ImagePicker(sourceType: src.type) { img in pickedImage = img }.ignoresSafeArea() }
            .onAppear(perform: prime)
        }
    }

    @ViewBuilder private var belegSection: some View {
        if let img = pickedImage {
            Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let path = eintrag?.belegPath {
            AuthImage(path: path, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 160)
        }
        HStack(spacing: 16) {
            Button { pickerSource = ImageSource(.camera) } label: { Label("Kamera", systemImage: "camera") }
            Button { pickerSource = ImageSource(.photoLibrary) } label: { Label("Auswählen", systemImage: "photo") }
        }
    }

    private func prime() {
        guard let e = eintrag else { return }
        istEinnahme = e.istEinnahme
        beschreibung = e.beschreibung
        betrag = e.betrag == 0 ? "" : String(format: "%.2f", e.betrag).replacingOccurrences(of: ".", with: ",")
        personId = e.personId
        if let d = e.datum, let parsed = Self.ymd.date(from: String(d.prefix(10))) { datum = parsed }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let b = Coerce.double(betrag) ?? 0
        let jpeg = pickedImage?.jpegForUpload()
        if await store.saveKosten(id: eintrag?.id, beschreibung: beschreibung.trimmingCharacters(in: .whitespaces),
                                  betrag: b, istEinnahme: istEinnahme, datum: Self.ymd.string(from: datum),
                                  personId: personId, jpeg: jpeg) {
            dismiss()
        }
    }

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}

// MARK: - Personen-Verwaltung

struct PersonenVerwaltungSheet: View {
    @EnvironmentObject private var store: TrauerkartenStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var confirmDelete: TrauerPerson?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Person hinzufügen", text: $newName)
                        Button { Task { if await store.addPerson(newName.trimmingCharacters(in: .whitespaces)) { newName = "" } } } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    if store.personen.isEmpty {
                        Text("Noch keine Personen angelegt").foregroundStyle(.secondary)
                    }
                    ForEach(store.personen) { p in
                        PersonRow(person: p, onRename: { name in Task { await store.renamePerson(p.id, name) } },
                                  onDelete: { confirmDelete = p })
                    }
                }
            }
            .navigationTitle("Personen").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
            .confirmationDialog(confirmDelete.map { "\($0.name) löschen? Bestehende Einträge werden auf Alle gesetzt." } ?? "",
                                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { if let p = confirmDelete { Task { await store.deletePerson(p) } }; confirmDelete = nil }
                Button("Abbrechen", role: .cancel) { confirmDelete = nil }
            }
        }
    }
}

struct PersonRow: View {
    let person: TrauerPerson
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @State private var name = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack {
            TextField("Name", text: $name).focused($focused)
                .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty, name != person.name { onRename(name) } }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(TrauerStyle.ausgabe)
        }
        .onAppear { name = person.name }
    }
}
