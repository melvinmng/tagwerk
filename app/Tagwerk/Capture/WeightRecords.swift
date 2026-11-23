import Foundation
import SwiftData
import TagwerkCore

// Own body weights of the "Erfassen" tab (decision KG2a). Tagwerk is the source of truth; Health holds a mirrored copy.
// Schema rule: later attributes must be optional or have a default value.

@Model
final class WeightRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kilograms: Double
    /// Body fat in percent; `nil` when not measured (never 0 for "unknown").
    var bodyFatPercent: Double?
    /// Sync version in Health; increases with every edit.
    var healthVersion: Int = 1
    var healthSynced: Bool = false

    init(_ value: WeightValue, healthVersion: Int = 1) {
        self.id = value.id
        self.date = value.date
        self.kilograms = value.kilograms
        self.bodyFatPercent = value.bodyFatPercent
        self.healthVersion = healthVersion
    }

    var value: WeightValue { WeightValue(id: id, date: date, kilograms: kilograms, bodyFatPercent: bodyFatPercent) }
}
