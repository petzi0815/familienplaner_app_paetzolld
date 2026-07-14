import SwiftUI

/// Entity-Detail als Sheet: Stammdaten, Zustand, Aliase (hinzufuegen/loeschen), Aktivieren/Deaktivieren
/// und die `attributes`-JSON-Objektspalte als Key/Value-Zeilen. Liest die Entity immer frisch aus
/// dem Store (per entity_id), damit Aenderungen (Toggle/Alias) sofort sichtbar sind.
struct SmartHomeEntityDetail: View {
    let entityId: String
    @EnvironmentObject private var store: SmartHomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var newAlias = ""

    private var entity: HAEntity? { store.entities.first { $0.entityId == entityId } }

    var body: some View {
        NavigationStack {
            Group {
                if let e = entity { content(e) }
                else { AreaEmptyState(emoji: "🏠", title: "Nicht gefunden", hint: "Diese Entity ist nicht mehr geladen.") }
            }
            .navigationTitle(entity?.displayName ?? "Entity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func content(_ e: HAEntity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(e)
                stammdaten(e)
                aliasSection(e)
                attributesSection(e)
            }
            .padding()
        }
    }

    // MARK: - Kopf + Zustand + Toggle

    private func header(_ e: HAEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(SmartHomeStyle.domainEmoji(e.domain)).font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.displayName).font(.title3.weight(.bold))
                    Text(e.entityId).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(SmartHomeStyle.stateColor(e.state)).frame(width: 10, height: 10)
                    Text((e.state ?? "unbekannt").uppercased()).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(SmartHomeStyle.stateColor(e.state).opacity(0.15), in: Capsule())

                if e.disabled { Pill(text: "deaktiviert", color: .red) }
                Spacer()
            }

            Button { Task { await store.toggleDisabled(e) } } label: {
                Label(e.disabled ? "Aktivieren" : "Deaktivieren",
                      systemImage: e.disabled ? "checkmark.circle" : "minus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle((e.disabled ? SmartHomeStyle.green : Color.red).onFill)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(e.disabled ? SmartHomeStyle.green : Color.red, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stammdaten

    private func stammdaten(_ e: HAEntity) -> some View {
        VStack(spacing: 0) {
            InfoRow(icon: "🧩", label: "Domain", value: e.domain)
            InfoRow(icon: "🚪", label: "Raum", value: (e.areaName?.isEmpty == false) ? e.areaName! : "Ohne Raum")
            if let d = e.deviceName, !d.isEmpty { InfoRow(icon: "📟", label: "Gerät", value: d) }
            if let s = e.lastSynced, !s.isEmpty { InfoRow(icon: "🔄", label: "Zuletzt sync.", value: DateText.pretty(s)) }
            if let s = e.discoveredAt, !s.isEmpty { InfoRow(icon: "✨", label: "Entdeckt", value: DateText.pretty(s)) }
            if let u = e.usageCount, u > 0 { InfoRow(icon: "⚡", label: "Geschaltet", value: "\(u)x") }
        }
    }

    // MARK: - Aliase

    private func aliasSection(_ e: HAEntity) -> some View {
        let al = store.aliasList(for: e.entityId)
        return VStack(alignment: .leading, spacing: 8) {
            Text("🏷️ Aliase").font(.headline)
            if al.isEmpty {
                Text("Noch keine Aliase.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(al) { a in
                    HStack {
                        Text(a.alias).font(.subheadline)
                        Spacer()
                        Button(role: .destructive) { Task { await store.deleteAlias(a) } } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(SmartHomeStyle.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            HStack(spacing: 8) {
                TextField("Neuer Alias …", text: $newAlias)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { submitAlias(e) }
                Button { submitAlias(e) } label: { Label("Hinzufügen", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .disabled(newAlias.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func submitAlias(_ e: HAEntity) {
        let value = newAlias
        Task { if await store.addAlias(entityId: e.entityId, alias: value) { newAlias = "" } }
    }

    // MARK: - Attribute (JSON-Objekt als Key/Value)

    @ViewBuilder private func attributesSection(_ e: HAEntity) -> some View {
        if !e.attributes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("⚙️ Attribute").font(.headline)
                VStack(spacing: 0) {
                    ForEach(e.attributes.keys.sorted(), id: \.self) { key in
                        InfoRow(icon: "•", label: key, value: Self.valueString(e.attributes[key]))
                    }
                }
            }
        }
    }

    /// HA-Attributwert lesbar darstellen (String/Zahl/Bool/Array/Objekt tolerant).
    /// Booleans werden ueber CFBoolean von 0/1-Zahlen unterschieden.
    static func valueString(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "—" }
        if let s = v as? String { return s.isEmpty ? "—" : s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "ja" : "nein" }
            return n.stringValue
        }
        if let arr = v as? [Any] { return arr.map { valueString($0) }.joined(separator: ", ") }
        if let d = try? JSONSerialization.data(withJSONObject: v), let s = String(data: d, encoding: .utf8) { return s }
        return String(describing: v)
    }
}
