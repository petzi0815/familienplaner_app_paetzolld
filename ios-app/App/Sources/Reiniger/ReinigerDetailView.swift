import SwiftUI

/// Produkt-Detail (Sheet): Bild, Einsatz-/Anwendungs-Infos, verknuepfte Faelle, Schnellaktionen.
struct ReinigerDetailSheet: View {
    let productID: Int
    @EnvironmentObject private var store: ReinigerStore
    @Environment(\.dismiss) private var dismiss

    @State private var product: ReinigerProdukt?
    @State private var editRef: ReinigerEditRef?
    @State private var confirmDelete = false
    @State private var fullscreen: ImageRef?

    var body: some View {
        NavigationStack {
            Group {
                if let product { detail(product) }
                else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                if let product {
                    ToolbarItem(placement: .primaryAction) {
                        Button { editRef = ReinigerEditRef(product: product) } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: $editRef, onDismiss: { Task { await load() } }) { ref in
            ReinigerEditView(product: ref.product).environmentObject(store)
        }
        .fullScreenCover(item: $fullscreen) { ref in ReinigerFullscreenImage(path: ref.path) }
        .confirmationDialog("Diesen Reiniger wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task { if await store.deleteProduct(productID) { dismiss() } }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: - Ansicht

    private func detail(_ p: ReinigerProdukt) -> some View {
        let cat = ReinigerStyle.cat(p.kategorie)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let path = p.imagePath {
                    AuthImage(path: path, contentMode: .fit)
                        .frame(maxHeight: 240).frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .onTapGesture { fullscreen = ImageRef(path: path) }
                } else {
                    LinearGradient(colors: [Color(hex: "BAE6FD"), Color(hex: "D9F99D")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(height: 160)
                        .overlay(Text(cat.emoji).font(.system(size: 60)))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Pill(text: "\(cat.emoji) \(cat.label)", color: cat.color)
                    Text(p.name).font(.title2.weight(.bold))
                    Text(p.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }

                einsatz(p)
                anwendung(p)
                verknuepfteFaelle(p)
                actions(p)
            }
            .padding()
        }
    }

    @ViewBuilder private func einsatz(_ p: ReinigerProdukt) -> some View {
        if p.einsatzorte != nil || p.geeignetFuer != nil || p.nichtGeeignetFuer != nil || p.flecken != nil {
            ReinigerSectionCard(title: "Einsatz") {
                ReinigerField(icon: "📍", label: "Orte", value: p.einsatzorte)
                ReinigerField(icon: "✅", label: "Geeignet", value: p.geeignetFuer)
                ReinigerField(icon: "⛔", label: "Nicht geeignet", value: p.nichtGeeignetFuer, valueColor: .red)
                ReinigerField(icon: "🎯", label: "Hilft bei", value: p.flecken)
            }
        }
    }

    @ViewBuilder private func anwendung(_ p: ReinigerProdukt) -> some View {
        if p.pflegehinweise != nil || p.dosierung != nil || p.sicherheit != nil || p.notizen != nil {
            ReinigerSectionCard(title: "Anwendung") {
                ReinigerField(icon: "🧼", label: "Hinweise", value: p.pflegehinweise)
                ReinigerField(icon: "💧", label: "Dosierung", value: p.dosierung)
                ReinigerField(icon: "⚠️", label: "Sicherheit", value: p.sicherheit, valueColor: .red)
                ReinigerField(icon: "📝", label: "Notizen", value: p.notizen)
            }
        }
    }

    @ViewBuilder private func verknuepfteFaelle(_ p: ReinigerProdukt) -> some View {
        let cases = store.linkedAnwendungen(p.id)
        if !cases.isEmpty {
            ReinigerSectionCard(title: "Verknüpfte Fälle") {
                ForEach(cases) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title).font(.subheadline.weight(.semibold))
                        if let s = a.surface, !s.isEmpty { Text("Auf: \(s)").font(.caption).foregroundStyle(.secondary) }
                        if let b = a.begruendung, !b.isEmpty { Text("Warum: \(b)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Aktionen

    private func actions(_ p: ReinigerProdukt) -> some View {
        VStack(spacing: 10) {
            if let url = p.externalURL {
                Link(destination: url) {
                    Label("Produktlink öffnen", systemImage: "link")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Theme.accent)
                }
            }
            HStack(spacing: 10) {
                statusButton("Nachkaufen", "cart.badge.plus", .green, target: "nachkaufen", current: p.status)
                statusButton("Leer", "drop", Color(hex: "F59E0B"), target: "leer", current: p.status)
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Löschen", systemImage: "trash")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private func statusButton(_ title: String, _ icon: String, _ color: Color, target: String, current: String) -> some View {
        Button { Task { await store.setStatus(productID, target); await load() } } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(current == target ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.15)),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(current == target ? color.onFill : color)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        if let fresh = try? await store.api.fetchItem(productID) { product = fresh }
        else { product = store.items.first { $0.id == productID } }
    }
}

// MARK: - Wiederverwendbare Detail-Bausteine (prefixed)

struct ReinigerSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ReinigerField: View {
    let icon: String
    let label: String
    let value: String?
    var valueColor: Color = .primary
    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Text(icon).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.subheadline).foregroundStyle(valueColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }
}

struct ReinigerFullscreenImage: View {
    let path: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AuthImage(path: path, contentMode: .fit).ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.9))
                    }.padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Anlegen / Bearbeiten

/// Formular zum Anlegen (product == nil) oder Bearbeiten eines Reinigers. Volles Feldset wie die PWA.
struct ReinigerEditView: View {
    let product: ReinigerProdukt?
    @EnvironmentObject private var store: ReinigerStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var marke = ""
    @State private var kategorie = "allzweck"
    @State private var menge = ""
    @State private var einsatzorte = ""
    @State private var geeignetFuer = ""
    @State private var nichtGeeignetFuer = ""
    @State private var flecken = ""
    @State private var pflegehinweise = ""
    @State private var sicherheit = ""
    @State private var dosierung = ""
    @State private var quelleUrl = ""
    @State private var notizen = ""
    @State private var restock = true
    @State private var saving = false

    private var isEdit: Bool { product != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !saving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basis") {
                    LabeledContent("Name *") { TextField("z.B. Frosch Badreiniger", text: $name) }
                    LabeledContent("Marke") { TextField("z.B. Frosch, Dr. Beckmann", text: $marke) }
                    Picker("Kategorie", selection: $kategorie) {
                        ForEach(ReinigerStyle.categoryOrder, id: \.self) { key in
                            let c = ReinigerStyle.cat(key)
                            Text("\(c.emoji) \(c.label)").tag(key)
                        }
                    }
                    LabeledContent("Menge") { TextField("750 ml", text: $menge) }
                }
                Section("Einsatz") {
                    LabeledContent("Einsatzorte") { TextField("Bad, Dusche, Armaturen …", text: $einsatzorte) }
                    LabeledContent("Geeignet für") { TextField("Keramik, Edelstahl, Glas …", text: $geeignetFuer) }
                    LabeledContent("Nicht geeignet für") { TextField("Naturstein, Marmor …", text: $nichtGeeignetFuer) }
                }
                Section("Hinweise") {
                    field("Flecken und Probleme", "Kalk, Fett, Wasserflecken …", $flecken)
                    field("Pflege und Anwendung", "Kurz einwirken lassen …", $pflegehinweise)
                    field("Sicherheit", "Nicht mit Chlor mischen, Handschuhe …", $sicherheit)
                    LabeledContent("Dosierung") { TextField("pur, 1 Kappe auf 5 l …", text: $dosierung) }
                }
                Section("Weiteres") {
                    LabeledContent("Quelle / Produktseite") {
                        TextField("https://…", text: $quelleUrl)
                            .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    field("Notizen", "Interne Hinweise …", $notizen)
                    Toggle("Nachkaufen wenn leer", isOn: $restock)
                }
            }
            .navigationTitle(isEdit ? "Reiniger bearbeiten" : "Neuer Reiniger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { Task { await save() } }.disabled(!canSave)
                }
            }
            .onAppear { populate() }
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text, axis: .vertical).lineLimit(2...5)
        }
    }

    private func populate() {
        guard let p = product else { return }
        name = p.name
        marke = p.marke ?? ""
        kategorie = p.kategorie ?? "allzweck"
        menge = p.menge ?? ""
        einsatzorte = p.einsatzorte ?? ""
        geeignetFuer = p.geeignetFuer ?? ""
        nichtGeeignetFuer = p.nichtGeeignetFuer ?? ""
        flecken = p.flecken ?? ""
        pflegehinweise = p.pflegehinweise ?? ""
        sicherheit = p.sicherheit ?? ""
        dosierung = p.dosierung ?? ""
        quelleUrl = p.quelleUrl ?? ""
        notizen = p.notizen ?? ""
        restock = p.restock
    }

    private func save() async {
        saving = true
        let fields: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "marke": marke, "kategorie": kategorie, "menge": menge,
            "einsatzorte": einsatzorte, "geeignet_fuer": geeignetFuer,
            "nicht_geeignet_fuer": nichtGeeignetFuer, "flecken": flecken,
            "pflegehinweise": pflegehinweise, "sicherheit": sicherheit,
            "dosierung": dosierung, "quelle_url": quelleUrl, "notizen": notizen,
            "restock": restock ? 1 : 0,
            "status": product?.status ?? "aktiv",
        ]
        let ok = await store.saveProduct(id: product?.id, fields: fields)
        saving = false
        if ok { dismiss() }
    }
}
