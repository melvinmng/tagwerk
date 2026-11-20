import AppIntents
import HealthBridge
import SwiftData
import SwiftUI
import TagwerkCore
import UserNotifications

@main
struct TagwerkApp: App {
    @State private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let container = try ModelContainerFactory.make(inMemory: UITestMode.isActive)
            var health: (any HealthStoring)?
            #if DEBUG && targetEnvironment(simulator)
            if DemoData.isRequested { health = DemoHealthStore() }
            #endif
            // Hosted unit tests never write into the real App Group container.
            // The UI tests start the app itself, so they get the same protection through their launch argument.
            let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || UITestMode.isActive
            if UITestMode.isActive { UIView.setAnimationsEnabled(false) }
            let environment = try AppEnvironment(modelContainer: container, health: health,
                                                 snapshotWriter: isTestHost ? nil : .live(),
                                                 shareInbox: isTestHost ? nil : AppGroup.shareInboxDirectory.map { ShareInbox(directory: $0) },
                                                 controlState: isTestHost ? nil : .live(),
                                                 controlReloader: isTestHost ? nil : SystemControlReloader())
            _environment = State(initialValue: environment)
            // App Intents run in this process and share the one model container (phase 4 design §8).
            let services = IntentServices(environment: environment)
            AppDependencyManager.shared.add(dependency: services)
            // The controls run their intents here, also when the system starts the app in the background for one.
            ControlActionRouter(writer: services, focus: environment.focus).install()
            HabitEntitySource.activeHabits = { services.activeHabits() }
            // New article names become speakable, also after a Siri add that launched the app in the background
            // (`RootView.task` does not run then). Hosted unit tests do not talk to the system.
            if !isTestHost {
                environment.shopping.onNamesChanged = { TagwerkShortcuts.updateAppShortcutParameters() }
            }
            // Set before launch ends, so a tap that launched the app is not lost.
            UNUserNotificationCenter.current().delegate = environment.notificationDelegate
        } catch {
            // A broken store makes the app unusable; fail loudly instead of losing data silently.
            fatalError("Failed to open the SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modifier(UITestAppearance())
                .task {
                    // A focus session that survived the app being closed or killed; first, before the slow network calls.
                    await environment.focus.restore()
                    #if DEBUG && targetEnvironment(simulator)
                    await DemoData.seedIfRequested(environment)
                    #endif
                    // Reads the keychain only; nothing is sent to OpenAI at start (§8.4).
                    await environment.ai.refreshAccount()
                    // Notes in "Zuletzt gelöscht" go for good after 30 days.
                    environment.notes.purgeExpired(calendar: environment.planning.calendar)
                    environment.startObservingChanges()
                    // The "Planen" tab is shown first; it needs the tasks without waiting for the task tab.
                    if environment.settings.setupCompleted {
                        await environment.taskList.reload()
                        await environment.planning.reload()
                        await environment.shopping.reload()
                    }
                    await environment.activateGitHubIfSignedIn()
                    environment.startReconnectWatch()
                    environment.startNotificationUpdates()
                    environment.startRoutineReminderUpdates()
                    environment.startFocusUpdates()
                    environment.startHabitSourceUpdates()
                    environment.startSnapshotUpdates()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Items shared from other apps; the root view opens their sheets once nothing else is open.
                        environment.shareInbox.appBecameActive()
                        Task {
                            await environment.focus.restore()
                            // A start before the first unlock could not read the GitHub sign-in; try again.
                            await environment.activateGitHubIfSignedIn()
                            await environment.retryGitHubIfNeeded()
                            // Remaining time and "today" move on while the app is in the background.
                            await environment.planning.reload()
                            // The permission may have changed in the iOS settings; the time zone may have changed.
                            await environment.notifications.reschedule()
                            await environment.routineNotifications.reschedule()
                            // Health entries that could not be written or deleted earlier.
                            await environment.capture.reload()  // follows to the new day after midnight
                            await environment.habits.reload(day: environment.capture.day)
                            await environment.capture.syncPending()
                        }
                    case .background:
                        // Directly, not debounced: the app may be suspended before a delayed run starts.
                        // The snapshot reads the store directly, so it is written first, before any await.
                        environment.writeSnapshot()
                        // The automatic backup reads the store directly; a background task keeps the app alive until it is written.
                        var backupTask = UIBackgroundTaskIdentifier.invalid
                        backupTask = UIApplication.shared.beginBackgroundTask(withName: "tagwerk.backup") {
                            UIApplication.shared.endBackgroundTask(backupTask)
                        }
                        environment.backup.runAutomaticBackupIfDue()
                        if backupTask != .invalid { UIApplication.shared.endBackgroundTask(backupTask) }
                        Task {
                            await environment.makeBackgroundRefresh().submitNext()
                            await environment.notifications.reschedule()
                            // Health entries that could not be written or deleted earlier.
                            await environment.capture.reload()  // follows to the new day after midnight
                            await environment.habits.reload(day: environment.capture.day)
                            await environment.capture.syncPending()
                            // Again after the reload, in case Health catch-up or the new day changed something.
                            environment.writeSnapshot()
                        }
                    default:
                        break
                    }
                }
        }
        .modelContainer(environment.modelContainer)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [environment] in
            await environment.makeBackgroundRefresh().run()
        }
    }
}
