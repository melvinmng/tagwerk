/// Accessibility identifiers the UI tests use to find elements. They are not texts and not localized.
/// Naming scheme: `area.element`, English. This file is also compiled into the UI test target (UI tests
/// cannot import the app module), so it must not import anything from the app.
enum AccessibilityID {
    enum App {
        /// Invisible marker that appears once the demo data of the UI test mode exists.
        static let demoReady = "app.demoReady"
    }

    enum Tasks {
        /// A task row (task list, search results); the title makes it unique.
        static func row(_ title: String) -> String { "tasks.row.\(title)" }
        /// The title field of the task editor (a filled field has no placeholder to find it by).
        static let editorTitle = "tasks.editorTitle"
    }
}
