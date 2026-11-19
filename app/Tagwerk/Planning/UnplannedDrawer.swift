import SwiftUI
import TagwerkCore

/// Drawer of unplanned tasks for week and month (mockup D1): three heights, search, tasks due in the shown
/// range first. Rows can be dragged onto days; "＋" plans without dragging. An inset panel instead of a sheet,
/// so dragging onto the days behind it keeps working.
struct UnplannedDrawer: View {
    let model: PlanningModel
    @State private var height: Height = .collapsed
    @State private var search = ""
    @FocusState private var isSearching: Bool
    @GestureState private var dragOffset: CGFloat = 0

    enum Height: CaseIterable {
        case collapsed, medium, large

        var points: CGFloat {
            switch self {
            case .collapsed: 64
            case .medium: 320
            case .large: 560
            }
        }
    }

    /// Fixed height, moved by an offset: the views behind keep their layout while the drawer follows the finger.
    var body: some View {
        if !model.unplanned.isEmpty {
            let full = Height.large.points
            VStack(spacing: 0) {
                handle
                content
            }
            .frame(height: full, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(.bar, in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
            .offset(y: min(full - Height.collapsed.points, max(0, full - height.points + dragOffset)))
            .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.86), value: height)
            // The keyboard covers the lower part of the list instead of pushing the drawer (and its search
            // field) off the top of the screen; searching opens the drawer fully.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: isSearching) { _, searching in if searching { height = .large } }
        }
    }

    private var handle: some View {
        VStack(spacing: 6) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 6)
            HStack {
                Text("Ungeplant").font(.headline)
                Text("\(model.unplanned.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                let due = model.unplannedSections(search: "").dueInRange.count
                if due > 0 {
                    Text("\(due) fällig in diesem Zeitraum").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                Image(systemName: height == .large ? "chevron.down" : "chevron.up").foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture { height = height == .collapsed ? .medium : (height == .medium ? .large : .collapsed) }
        .gesture(DragGesture(coordinateSpace: .global)
            .updating($dragOffset) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                // Throw: the predicted end decides, so a quick flick opens or closes without dragging far.
                let target = height.points - value.predictedEndTranslation.height
                height = Height.allCases.min { abs($0.points - target) < abs($1.points - target) } ?? .collapsed
            })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(height == .collapsed ? "Ablage öffnen" : "Ablage vergrößern oder schließen")
    }

    private var content: some View {
        let sections = model.unplannedSections(search: search)
        return VStack(spacing: 0) {
            TextField("Ungeplante suchen", text: $search)
                .focused($isSearching)
                .submitLabel(.search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .keepsKeyboardOnTap()
            list(sections)
        }
    }

    private func list(_ sections: (dueInRange: [TaskItem], other: [TaskItem])) -> some View {
        List {
            if !sections.dueInRange.isEmpty {
                Section("Fällig in diesem Zeitraum") { ForEach(sections.dueInRange) { row($0) } }
            }
            Section(sections.dueInRange.isEmpty ? "Alle ungeplanten" : "Weitere") {
                ForEach(sections.other.prefix(200)) { row($0) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ task: TaskItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(2)
                HStack(spacing: 6) {
                    if let due = task.due {
                        Text(DueText.text(due, now: model.now(), calendar: model.calendar))
                    }
                    Text(EstimateHours.text(minutes: task.estimateMinutes))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(daysInRange, id: \.self) { day in
                    Button(day.startDate(in: model.calendar).formatted(.dateTime.weekday(.wide).day().month())) {
                        Task { await model.assign(task.id, to: day) }
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .accessibilityLabel("Auf einen Tag einplanen")
        }
        .draggable(task.id.key)
        .listRowBackground(Color.clear)
    }

    /// Week: its seven days; month: the days of the shown month from today on.
    private var daysInRange: [PlanDay] {
        let days = model.days.map(\.day)
        if model.scope == .month {
            return days.filter { $0.month == model.anchor.month && $0 >= model.today }
        }
        return days
    }
}
