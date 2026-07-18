import SwiftUI
import UIKit

/// Anlegen (`item == nil`) UND Bearbeiten (`item != nil`) eines Lebensmittels.
/// Native Steuerelemente: Lagerort-Picker (Regal/Kühlschrank/Tiefkühl), Menge als Freitext,
/// MHD als DatePicker (Pflicht), Foto (Kamera/Mediathek), Restock-Toggle.
struct VorratItemFormSheet: View {
    let item: VorratItem?
    @EnvironmentObject private var store: VorratStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var marke = ""
    @State private var kategorie = "kuehlschrank"
    @State private var menge = ""
    @State private var mhd = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var restock = true
    @State private var notizen = ""
    @State private var photo: UIImage?
    @State private var saving = false

    private var isEdit: Bool { item != nil }
    private var hasExistingPhoto: Bool { (item?.bildPfad?.isEmpty == false) }
    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Lebensmittel") {
                    TextField("Name *", text: $name)
                    TextField("Marke", text: $marke)
                    Picker("Lagerort", selection: $kategorie) {
                        ForEach(VorratKat.order, id: \.self) { k in
                            let i = VorratKat.info(k)
                            Text("\(i.emoji) \(i.label)").tag(k)
                        }
                    }
                }
                Section("Menge & Ablaufdatum") {
                    TextField("Menge (z.B. 500g, 2 Stk)", text: $menge)
                    DatePicker("Haltbar bis (MHD)", selection: $mhd, displayedComponents: .date)
                }
                Section("Foto") {
                    if hasExistingPhoto && photo == nil {
                        Text("Foto vorhanden – neues aufnehmen ersetzt es.").font(.caption).foregroundStyle(.secondary)
                    }
                    VorratPhotoField(image: $photo)
                }
                Section {
                    Toggle("Nachkaufen wenn leer", isOn: $restock)
                } footer: {
                    Text("Ist der Vorrat aufgebraucht, erscheint das Produkt auf der Einkaufsliste.")
                }
                Section("Notizen") {
                    TextField("Optionale Notizen …", text: $notizen, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(isEdit ? "Bearbeiten" : "Neues Lebensmittel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Speichern" : "Hinzufügen") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        guard let it = item else { return }
        name = it.name
        marke = it.marke ?? ""
        kategorie = VorratKat.order.contains(it.kategorie) ? it.kategorie : "kuehlschrank"
        menge = it.menge ?? ""
        if let m = it.mhd, let d = Self.isoFmt.date(from: String(m.prefix(10))) { mhd = d }
        restock = it.restock
        notizen = it.notizen ?? ""
    }

    private func save() async {
        saving = true
        var body: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "marke": marke,
            "kategorie": kategorie,
            "menge": menge,
            "mhd": Self.isoFmt.string(from: mhd),
            "restock": restock ? 1 : 0,
            "notizen": notizen,
        ]
        if let img = photo, let key = await store.uploadPhoto(img) { body["bild_pfad"] = key }
        let ok: Bool
        if let it = item { ok = await store.updateItem(it.id, body) }
        else { ok = await store.createItem(body) }
        saving = false
        if ok { dismiss() }
    }
}
