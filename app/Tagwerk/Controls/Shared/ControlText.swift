import Foundation

/// The texts of the controls. Control Center and the lock screen are visible while the device is locked, so every text
/// here is generic: no habit name, no streak or rate, no water or calorie figure, no task title (privacy rule of #167).
/// The one figure is the amount a tap adds, which the user chose in the control's configuration.
enum ControlText {
    static let waterName: LocalizedStringResource = "Wasser"
    static let habitName: LocalizedStringResource = "Gewohnheit"
    static let dictateName: LocalizedStringResource = "Notiz diktieren"
    static let focusName: LocalizedStringResource = "Fokus"
    static let captureName: LocalizedStringResource = "Erfassen"
    static let routineName: LocalizedStringResource = "Tagesroutine"
    static let shoppingName: LocalizedStringResource = "Einkaufsliste"

    static let focusOn: LocalizedStringResource = "Läuft"
    static let focusOff: LocalizedStringResource = "Aus"

    static let waterDescription: LocalizedStringResource = "Trägt Wasser ein, ohne Tagwerk zu öffnen."
    static let habitDescription: LocalizedStringResource = "Hakt eine Gewohnheit für heute ab, ohne Tagwerk zu öffnen."
    static let dictateDescription: LocalizedStringResource = "Öffnet eine neue Notiz in Brain Dump und startet das Diktat."
    static let focusDescription: LocalizedStringResource = "Startet oder beendet einen freien Fokus-Timer."
    static let captureDescription: LocalizedStringResource = "Öffnet Erfassen für Essen, Wasser und Training."
    static let routineDescription: LocalizedStringResource = "Öffnet morgens den Tagesstart, sonst den Tagesabschluss."
    static let shoppingDescription: LocalizedStringResource = "Öffnet die Einkaufsliste."

    /// "+250 ml": the amount of one tap, not the day's total.
    static func waterLabel(milliliters: Int) -> LocalizedStringResource {
        // Plain digits, no grouping, like the Siri answer: "+1000 ml".
        let amount = String(milliliters)
        return "+\(amount) ml"
    }

    /// Every fixed label and description, for the test that keeps them generic.
    static let allFixedTexts: [LocalizedStringResource] = [
        waterName, habitName, dictateName, focusName, captureName, routineName, shoppingName, focusOn, focusOff,
        waterDescription, habitDescription, dictateDescription, focusDescription, captureDescription, routineDescription,
        shoppingDescription,
    ]
}
