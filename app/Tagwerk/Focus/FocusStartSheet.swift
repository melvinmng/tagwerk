import SwiftUI
import TagwerkCore

/// The start sheet (FO7b): pick the duration before the focus session begins. Siri, the control and shortcuts never show
/// it; they start with the settings (`FocusTimerModel.start`).
struct FocusStartSheet: View {
    private enum Selection: Hashable {
        case preset(Int), blockEnd, other
    }

    @Environment(AppEnvironment.self) private var environment
    let request: FocusTimerModel.StartRequest
    @State private var selection: Selection
    @State private var customMinutes: Int
    @State private var usesPomodoro: Bool

    init(request: FocusTimerModel.StartRequest, base: FocusTimerSettings, lastMinutes: Int?) {
        self.request = request
        let preselected = FocusStart.preselected(base: base, lastMinutes: lastMinutes, hasBlock: request.block != nil)
        var selection = Selection.preset(FocusStart.presets.contains(base.workMinutes) ? base.workMinutes : 25)
        var custom = base.workMinutes
        switch preselected {
        case .untilBlockEnd: selection = .blockEnd
        case .minutes(let minutes):
            custom = minutes
            selection = FocusStart.presets.contains(minutes) ? .preset(minutes) : .other
        case .pomodoro: break
        }
        _selection = State(initialValue: selection)
        _customMinutes = State(initialValue: custom)
        _usesPomodoro = State(initialValue: preselected == .pomodoro)
    }

    private var base: FocusTimerSettings { environment.settings.focusTimerSettings }

    private var blockMinutes: Int? {
        request.block.map { FocusStart.remainingMinutes(blockStart: $0.start, blockEnd: $0.end, now: environment.focus.now()) }
    }

    private var choice: FocusStartChoice {
        if usesPomodoro { return .pomodoro }
        switch selection {
        case .preset(let minutes): return .minutes(minutes)
        case .blockEnd: return .untilBlockEnd
        case .other: return .minutes(customMinutes)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], alignment: .leading, spacing: 10) {
                            ForEach(FocusStart.presets, id: \.self) { minutes in
                                capsule(String(localized: "\(minutes) min"), isSelected: selection == .preset(minutes)) { selection = .preset(minutes) }
                            }
                            if let blockMinutes {
                                capsule(String(localized: "Bis Blockende · \(blockMinutes) min"), isSelected: selection == .blockEnd) { selection = .blockEnd }
                            }
                            capsule(String(localized: "Andere …"), isSelected: selection == .other) { selection = .other }
                        }
                        .disabled(usesPomodoro)
                        .opacity(usesPomodoro ? 0.4 : 1)
                        if selection == .other && !usesPomodoro {
                            ValueStepper("Dauer", value: $customMinutes, in: FocusTimerSettings.workRange, step: 5, kind: .durationMinutes,
                                         unit: "min", display: ValueStepper.minutesText)
                        }
                    }
                    Toggle(String(localized: "Pomodoro (\(FocusTimerText.pomodoroSummary(base)))"), isOn: $usesPomodoro)
                    Button(action: start) {
                        Label("Starten", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    NavigationLink { FocusSettingsView() } label: {
                        Text("Fokus-Einstellungen").frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .navigationTitle("Fokus starten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Schließen") { environment.focus.pendingStart = nil } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(request.task?.title ?? request.block?.title ?? String(localized: "Fokus"))
                .font(.title3.weight(.semibold))
            if let block = request.block {
                let from = block.start.formatted(date: .omitted, time: .shortened)
                let to = block.end.formatted(date: .omitted, time: .shortened)
                Text("Zeitblock \(from)–\(to)").font(.subheadline).foregroundStyle(.secondaryText)
            }
        }
    }

    private func capsule(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 44)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemFill)))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Remembers a choice in minutes, closes the sheet and starts after it is gone (no sheet over a sheet).
    private func start() {
        let choice = choice
        if case .minutes(let minutes) = choice { environment.settings.focusLastStartMinutes = minutes }
        let focus = environment.focus
        let request = request
        focus.pendingStart = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await focus.start(task: request.task, block: request.block, choice: choice)
        }
    }
}
