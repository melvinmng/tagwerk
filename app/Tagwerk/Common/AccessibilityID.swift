/// Accessibility identifiers the UI tests use to find elements. They are not texts and not localized.
/// Naming scheme: `area.element`, English. This file is also compiled into the UI test target (UI tests
/// cannot import the app module), so it must not import anything from the app.
enum AccessibilityID {
    enum App {
        /// Invisible marker that appears once the demo data of the UI test mode exists.
        static let demoReady = "app.demoReady"
    }

    enum Focus {
        /// The bar above the tab bar while a focus session runs.
        static let bar = "focus.bar"
        /// The round buttons of the focus sheet.
        static let stop = "focus.stop"
        static let pause = "focus.pause"
        static let done = "focus.done"
        /// "▶ Fokus" on a time block in the plan.
        static let planButton = "focus.planButton"
    }

    enum Tasks {
        /// A task row (task list, search results); the title makes it unique.
        static func row(_ title: String) -> String { "tasks.row.\(title)" }
        /// The title field of the task editor (a filled field has no placeholder to find it by).
        static let editorTitle = "tasks.editorTitle"
    }

    enum Travel {
        /// The capsule "10 min zu früh" of a trip that starts before the previous event ends.
        static let warningCapsule = "travel.warningCapsule"
    }

    enum NoteEditor {
        /// The "+" button of the bar above the keyboard (the "Einfügen" menu).
        static let insertMenu = "noteEditor.insertMenu"
        /// "Fertig" of the full-screen drawing canvas (the note editor behind it has a "Fertig" too).
        static let drawingDone = "noteEditor.drawingDone"
        /// "Bearbeiten" of the drawing viewer.
        static let drawingEdit = "noteEditor.drawingEdit"
        /// "Fertig" of the table editor sheet.
        static let tableDone = "noteEditor.tableDone"
        /// The table button of the bar above the keyboard, shown while the cursor is in a table.
        static let tableButton = "noteEditor.tableButton"
    }

    enum Common {
        /// The symbol button above the keyboard that closes it.
        static let hideKeyboard = "common.hideKeyboard"
    }
}
