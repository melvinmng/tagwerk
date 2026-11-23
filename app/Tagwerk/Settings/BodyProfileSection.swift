import SwiftUI
import TagwerkCore

/// The section "Körper" of Einstellungen › Erfassen (decision PV4b): height, birth year and the sex of the formula, each from
/// Health where Health delivers it, else typed. The three values feed the cross-check of the goal planning; nothing is sent
/// anywhere from here.
struct BodyProfileSection: View {
    let store: BodyProfileStore

    var body: some View {
        let profile = store.profile
        Section {
            Button("Aus Health lesen") { Task { await store.readFromHealth() } }
                .accessibilityIdentifier(AccessibilityID.BodyProfile.readButton)
            heightRow(profile.height)
            birthYearRow(profile.birthYear)
            sexRow(profile.sex)
        } header: {
            Text("Körper")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if store.lastRead == .nothingDelivered {
                    Text("Health hat nichts geliefert. Entweder fehlt die Angabe in Health oder das Lesen ist nicht erlaubt; iOS teilt Tagwerk das nicht mit. Trage die Werte hier ein oder erlaube das Lesen in Health › Teilen › Apps › Tagwerk.")
                        .accessibilityIdentifier(AccessibilityID.BodyProfile.nothingDelivered)
                }
                Text("Größe, Alter und Geschlecht rechnen nur auf diesem iPhone: Tagwerk prüft damit Zielvorschläge. Gespeichert werden die Größe in ganzen Zentimetern, das Geburtsjahr und das Geschlecht der Formel, nie das Geburtsdatum. Was Health liefert, gilt; die Felder sind der Ersatz.")
            }
        }
        .task { await store.refresh() }
    }

    // MARK: Rows

    @ViewBuilder
    private func heightRow(_ field: BodyValue<Int>) -> some View {
        if field.source == .health, let value = field.value {
            LabeledContent("Größe") { Text(Self.heightText(value, source: .health)).monospacedDigit() }
        } else {
            LabeledContent("Größe") {
                HStack(spacing: 4) {
                    TextField("fehlt", value: Binding(get: { store.profile.height.value }, set: { store.setTypedHeight($0) }),
                              format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 80)
                        .accessibilityIdentifier(AccessibilityID.BodyProfile.heightField)
                    Text("cm").foregroundStyle(.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func birthYearRow(_ field: BodyValue<Int>) -> some View {
        if field.source == .health, let value = field.value {
            LabeledContent("Geburtsjahr") { Text(Self.birthYearText(value, source: .health)).monospacedDigit() }
        } else {
            LabeledContent("Geburtsjahr") {
                TextField("fehlt", value: Binding(get: { store.profile.birthYear.value }, set: { store.setTypedBirthYear($0) }),
                          format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 100)
                    .accessibilityIdentifier(AccessibilityID.BodyProfile.birthYearField)
            }
        }
    }

    @ViewBuilder
    private func sexRow(_ field: BodyValue<FormulaSex>) -> some View {
        if field.source == .health, let value = field.value {
            LabeledContent("Geschlecht für die Formel") { Text(Self.sexText(value, source: .health)) }
        } else {
            Picker("Geschlecht für die Formel", selection: Binding(get: { store.profile.sex.value }, set: { store.setTypedSex($0) })) {
                Text("nicht gewählt").tag(FormulaSex?.none)
                ForEach(FormulaSex.allCases, id: \.self) { sex in Text(Self.sexName(sex)).tag(FormulaSex?.some(sex)) }
            }
            .accessibilityIdentifier(AccessibilityID.BodyProfile.sexPicker)
        }
    }

    // MARK: Texts

    /// "180 cm · aus Health".
    static func heightText(_ centimetres: Int, source: BodyValueSource) -> String {
        withSource(String(localized: "\(centimetres) cm"), source: source)
    }

    static func birthYearText(_ year: Int, source: BodyValueSource) -> String {
        withSource(String(year), source: source)
    }

    static func sexText(_ sex: FormulaSex, source: BodyValueSource) -> String {
        withSource(sexName(sex), source: source)
    }

    static func sexName(_ sex: FormulaSex) -> String {
        switch sex {
        case .female: String(localized: "weiblich")
        case .male: String(localized: "männlich")
        }
    }

    private static func withSource(_ value: String, source: BodyValueSource) -> String {
        switch source {
        case .health: String(localized: "\(value) · aus Health")
        case .typed: String(localized: "\(value) · eingetragen")
        case .missing: String(localized: "fehlt")
        }
    }
}
