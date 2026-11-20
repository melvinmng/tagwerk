import SwiftUI

/// The four pages of the watch app, stacked vertically (turn the Digital Crown to move between them).
struct WatchRootView: View {
    var body: some View {
        TabView {
            TodayView()
            TasksView()
            HabitsView()
            WaterView()
        }
        .tabViewStyle(.verticalPage)
    }
}
