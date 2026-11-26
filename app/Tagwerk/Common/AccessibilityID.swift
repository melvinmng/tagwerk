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

    enum Shopping {
        /// The entries "Erledigte entfernen (N)" and "Liste leeren (N) …" of the menu; the number in the title changes.
        static let removeCompleted = "shopping.removeCompleted"
        static let clearList = "shopping.clearList"
        /// The two buttons that end the recipe input: "Zutaten auf die Einkaufsliste" and "Nur als Rezept speichern".
        static let recipeToList = "shopping.recipeToList"
        static let recipeSaveOnly = "shopping.recipeSaveOnly"
    }

    enum Tasks {
        /// A task row (task list, search results); the title makes it unique.
        static func row(_ title: String) -> String { "tasks.row.\(title)" }
        /// The title field of the task editor (a filled field has no placeholder to find it by).
        static let editorTitle = "tasks.editorTitle"
    }

    enum Search {
        /// A hit among the repositories of the GitHub account in the search; the full name "owner/name" makes it unique.
        static func repositoryHit(_ fullName: String) -> String { "search.repository.\(fullName)" }
        /// A hit among the GitHub projects in the search; the title makes it unique.
        static func projectHit(_ title: String) -> String { "search.project.\(title)" }
    }

    enum Travel {
        /// The capsule "10 min zu früh" of a trip that starts before the previous event ends.
        static let warningCapsule = "travel.warningCapsule"
    }

    enum Capture {
        /// The budget line of the day head ("Ziel + Aktiv − Gegessen = Noch"): one element with a spoken sentence.
        static let budgetLine = "capture.budgetLine"
        /// The "Aktiv" term of the budget line, which opens the breakdown.
        static let budgetActive = "capture.budgetActive"
        /// "Erlauben" for the active energy in the settings.
        static let allowActiveEnergy = "capture.allowActiveEnergy"
        /// The note "Aktivität nicht verbunden" under the budget line.
        static let activeEnergyNotConnected = "capture.activeEnergyNotConnected"
        /// The sheet "Aktiv heute".
        static let breakdown = "capture.breakdown"
        /// The quick button "Gewicht", the number field of the weight sheet and its "Sichern" button.
        static let quickWeight = "capture.quickWeight"
        static let weightField = "capture.weightField"
        static let weightSave = "capture.weightSave"
        /// The weight row of the morning start.
        static let morningWeight = "capture.morningWeight"
    }

    enum Trend {
        /// The row "Verlauf und Ziele" in the capture tab, the period picker and the weight row of the trends page.
        static let entry = "trend.entry"
        static let period = "trend.period"
        static let weightRow = "trend.weightRow"
    }

    enum WeekReview {
        /// The link from the weight section of the weekly review to "Verlauf und Ziele".
        static let trendLink = "weekReview.trendLink"
        /// The line under the weight figures when the week holds no measurement.
        static let noWeight = "weekReview.noWeight"
    }

    enum BodyProfile {
        /// The section "Körper" in Einstellungen › Erfassen.
        static let readButton = "bodyProfile.readButton"
        static let heightField = "bodyProfile.heightField"
        static let birthYearField = "bodyProfile.birthYearField"
        static let sexPicker = "bodyProfile.sexPicker"
        /// "Geburtsdatum und Geschlecht in Health ändern" (opens the Health app).
        static let openHealthButton = "bodyProfile.openHealthButton"
        /// The sentence after a reading that delivered nothing.
        static let nothingDelivered = "bodyProfile.nothingDelivered"
    }

    enum GoalPlanning {
        /// The entries "Ziele planen" and "Fortschritt besprechen", the switch of the consent, and the buttons of the two sheets.
        static let planEntry = "goalPlanning.planEntry"
        static let reviewEntry = "goalPlanning.reviewEntry"
        static let consentSwitch = "goalPlanning.consentSwitch"
        static let consentAgree = "goalPlanning.consentAgree"
        static let begin = "goalPlanning.begin"
        static let packageJSON = "goalPlanning.packageJSON"
        static let signInHint = "goalPlanning.signInHint"
        static func groupSwitch(_ group: String) -> String { "goalPlanning.group.\(group)" }
        /// The second confirmation of a goal card with a warning.
        static let confirmAnyway = "goalPlanning.confirmAnyway"
    }

    enum Food {
        /// A row of "Meine Lebensmittel" in the meal sheet.
        static let row = "food.row"
        static let newButton = "food.new"
        static let nameField = "food.name"
        static let saveButton = "food.save"
        static let amountField = "food.amount"
        static let addButton = "food.add"
        static let searchField = "food.search"
        static let labelCamera = "food.labelCamera"
    }

    enum FoodLookup {
        /// The contact address field of the consent sheet and of the settings.
        static let contactField = "foodLookup.contact"
        static let agreeButton = "foodLookup.agree"
        static let toggle = "foodLookup.toggle"
        /// The row "Online suchen" below the own foods.
        static let searchRow = "foodLookup.searchRow"
        static let results = "foodLookup.results"
        static let searchButton = "foodLookup.searchButton"
        static let saveFood = "foodLookup.saveFood"
        /// The row "Strichcode scannen" in the food list, and the scan icon in the search field.
        static let scanRow = "foodLookup.scanRow"
        static let scanIcon = "foodLookup.scanIcon"
        /// The scan sheet: switch to typed digits, the field and its button, and the ways on after a result.
        static let manualEntryButton = "foodLookup.manualEntry"
        static let manualField = "foodLookup.manualField"
        static let manualSubmit = "foodLookup.manualSubmit"
        static let scanCreateFood = "foodLookup.scanCreateFood"
        static let scanAgain = "foodLookup.scanAgain"
        static let scanRetry = "foodLookup.scanRetry"
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
        /// "Als Aufgabe" of the bar above the keyboard in a Bible Study note.
        static let checkboxTaskButton = "noteEditor.checkboxTask"
    }

    enum Common {
        /// The symbol button above the keyboard that closes it.
        static let hideKeyboard = "common.hideKeyboard"
    }
}
