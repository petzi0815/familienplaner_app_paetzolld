import SwiftUI

/// Anlegen (`item == nil`) UND Bearbeiten (`item != nil`) eines Lebensmittels.
/// Native Steuerelemente: Kategorie-Picker (auf die 3 CHECK-Werte begrenzt),
/// Menge als Freitext, MHD als DatePicker (optional), Restock-Toggle.
struct VorratItemFormSheet: View {
    let item: VorratItem?
    @EnvironmentObject private var store: VorratStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var marke = ""
    @State private var kategorie = "trocken"
    @State private var menge = ""
    @State private var hatMhd = false
    @State private var mhd = Date()
    @State private var restock = true
    @State private var notizen = ""
    @State private var saving = false

    private var isEdit: Bool { item != nil }
    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Lebensmittel") {
                    TextField("Name *", text: $name)
                    TextField("Marke", text: $marke)
                    Picker("Kategorie", selection: $kategorie) {
                        ForEach(VorratKat.order, id: \.self) { k in
                            let i = VorratKat.info(k)
                            Text("\(i.emoji) \(i.label)").tag(k)
                        }
                    }
                }
                Section("Menge & Haltbarkeit") {
                    TextField("Menge (z.B. 500g, 2 Stk)", text: $menge)
                    Toggle("MHD angeben", isOn: $hatMhd)
                    if hatMhd {
                        DatePicker("Mindestens haltbar bis", selection: $mhd, displayedComponents: .date)
                    }
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
        kategorie = VorratKat.order.contains(it.kategorie) ? it.kategorie : "trocken"
        menge = it.menge ?? ""
        if let m = it.mhd, let d = Self.isoFmt.date(from: String(m.prefix(10))) { mhd = d; hatMhd = true }
        restock = it.restock
        notizen = it.notizen ?? ""
    }

    private func save() async {
        saving = true
        let body: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "marke": marke,
            "kategorie": kategorie,
            "menge": menge,
            "mhd": hatMhd ? Self.isoFmt.string(from: mhd) : "",
            "restock": restock ? 1 : 0,
            "notizen": notizen,
        ]
        let ok: Bool
        if let it = item { ok = await store.updateItem(it.id, body) }
        else { ok = await store.createItem(body) }
        saving = false
        if ok { dismiss() }
    }
}
