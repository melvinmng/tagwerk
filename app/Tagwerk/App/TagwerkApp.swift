import AppIntents
import HealthBridge
import SwiftData
import SwiftUI
import UserNotifications

@main
struct TagwerkApp: App {
    @State private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let container = try ModelContainerFactory.make(inMemory: false)
            var health: (any HealthStoring)?
            #if DEBUG && targetEnvironment(simulator)
            if DemoData.isRequested { health = DemoHealthStore() }
            #endif
            // Hosted unit tests never write into the real App Group container.
            let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            let environment = try AppEnvironment(modelContainer: container, health: health,
                                                 snapshotWriter: isTestHost ? nil : .live())
            _environment = State(initialValue: environment)
            // App Intents run in this process and share the one model container (phase 4 design §8).
            let services = IntentServices(environment: environment)
            AppDependencyManager.shared.add(dependency: services)
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
                .task {
                    #if DEBUG && targetEnvironment(simulator)
                    await DemoData.seedIfRequested(environment)
                    #endif
                    // Reads the keychain only; nothing is sent to OpenAI at start (§8.4).
                    await environment.ai.refreshAccount()
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
                    environment.startSnapshotUpdates()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task {
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
                            await environment.habits.reload(day: environment.habits.today)
                            await environment.capture.syncPending()
                        }
                    case .background:
                        // Directly, not debounced: the app may be suspended before a delayed run starts.
                        // The snapshot reads the store directly, so it is written first, before any await.
                        environment.writeSnapshot()
                        Task {
                            await environment.makeBackgroundRefresh().submitNext()
                            await environment.notifications.reschedule()
                            // Health entries that could not be written or deleted earlier.
                            await environment.capture.reload()  // follows to the new day after midnight
                            await environment.habits.reload(day: environment.habits.today)
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
