import AppIntents
import SwiftUI
import TagwerkCore
import WidgetKit

// The controls of Tagwerk for Control Center, the lock screen and the Action button (#167). They show generic
// texts only: no habit name, no figures of the day, no task title (see `ControlText`).

/// "Wasser": a tap adds the configured amount (250 ml by default) without opening the app.
struct WaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: ControlKind.water, intent: WaterControlConfiguration.self) { configuration in
            ControlWidgetButton(action: ControlLogWaterIntent(milliliters: configuration.milliliters)) {
                Label(ControlText.waterLabel(milliliters: configuration.milliliters), systemImage: "drop.fill")
            }
        }
        .displayName(ControlText.waterName)
        .description(ControlText.waterDescription)
    }
}

struct WaterControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Wasser"

    @Parameter(title: "Menge (ml)", default: 250, inclusiveRange: (50, 1000))
    var milliliters: Int
}

/// "Gewohnheit": a tap checks the chosen habit off for today. The habit's name is only shown in the configuration
/// dialog, which the system opens when the control is added; the control itself stays generic.
struct HabitControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: ControlKind.habit, intent: HabitControlConfiguration.self) { configuration in
            ControlWidgetButton(action: ControlCheckHabitIntent(habit: configuration.habit)) {
                Label(ControlText.habitName, systemImage: configuration.habit?.symbol ?? "checkmark.circle")
            }
        }
        .displayName(ControlText.habitName)
        .description(ControlText.habitDescription)
        .promptsForUserConfiguration()
    }
}

struct HabitControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Gewohnheit"

    @Parameter(title: "Gewohnheit")
    var habit: HabitEntity?
}

/// "Notiz diktieren": opens a new note in Brain Dump with the recording running.
struct DictateControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.dictate) {
            ControlWidgetButton(action: OpenURLIntent(AppRoute.notesDictate.url)) {
                Label(ControlText.dictateName, systemImage: "mic.fill")
            }
        }
        .displayName(ControlText.dictateName)
        .description(ControlText.dictateDescription)
    }
}

/// "Fokus": starts a free focus session or ends the running one. The value comes from the state the app keeps in the
/// App Group; it never names the task.
struct FocusControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            ControlState.live()?.isFocusOn(at: .now) ?? false
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.focus, provider: Provider()) { isOn in
            ControlWidgetToggle(isOn: isOn, action: ControlSetFocusIntent()) {
                Label(ControlText.focusName, systemImage: "timer")
            } valueLabel: { isOn in
                Text(isOn ? ControlText.focusOn : ControlText.focusOff)
            }
        }
        .displayName(ControlText.focusName)
        .description(ControlText.focusDescription)
    }
}

/// "Erfassen": opens the capture tab.
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.capture) {
            ControlWidgetButton(action: OpenURLIntent(AppRoute.capture.url)) {
                Label(ControlText.captureName, systemImage: "plus.circle")
            }
        }
        .displayName(ControlText.captureName)
        .description(ControlText.captureDescription)
    }
}

/// "Tagesroutine": the app decides when it opens: the morning start before noon, the wrap-up otherwise.
struct RoutineControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.routine) {
            ControlWidgetButton(action: OpenURLIntent(AppRoute.routineNow.url)) {
                Label(ControlText.routineName, systemImage: "sun.horizon")
            }
        }
        .displayName(ControlText.routineName)
        .description(ControlText.routineDescription)
    }
}

/// "Einkaufsliste": opens the shopping list.
struct ShoppingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.shopping) {
            ControlWidgetButton(action: OpenURLIntent(AppRoute.shopping.url)) {
                Label(ControlText.shoppingName, systemImage: "cart")
            }
        }
        .displayName(ControlText.shoppingName)
        .description(ControlText.shoppingDescription)
    }
}
