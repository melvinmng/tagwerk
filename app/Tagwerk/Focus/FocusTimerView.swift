import SwiftUI
import TagwerkCore

/// The focus timer sheet (FO1b, FO2b, FO6b): the task on top, the remaining time in a ring with its end, three round
/// buttons, and below them what comes next today.
struct FocusTimerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var askingToStop = false
    /// Today's timeline for the section "Danach"; loaded once per session, read only.
    @State private var timeline: [TimelineRow] = []
    @State private var dayStart: Date?

    private var focus: FocusTimerModel { environment.focus }

    var body: some View {
        NavigationStack {
            Group {
                if let session = focus.session {
                    // One update per second, only while this sheet is on screen.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let snapshot = focus.snapshot(at: context.date) {
                            content(session: session, snapshot: snapshot, date: context.date)
                        }
                    }
                } else {
                    ContentUnavailableView("Kein Fokus läuft", systemImage: "timer")
                }
            }
            .navigationTitle("Fokus-Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Schließen") { focus.isPresented = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { FocusSettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(Text("Fokus-Einstellungen"))
                }
            }
            .confirmationDialog("Fokus beenden?", isPresented: $askingToStop, titleVisibility: .visible) {
                Button("Beenden", role: .destructive) { Task { await focus.stop() } }
                Button("Weitermachen", role: .cancel) {}
            } message: {
                Text(FocusTimerText.stopMessage(focusedSeconds: focus.snapshot(at: focus.now())?.focusedSeconds ?? 0,
                                                title: focus.session?.title ?? ""))
            }
            .task(id: focus.session?.id) { await loadToday() }
        }
    }

    // MARK: Content

    private func content(session: FocusTimerModel.Session, snapshot: FocusTimerSnapshot, date: Date) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(session.title.isEmpty ? String(localized: "Fokus") : session.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(FocusTimerText.phaseLine(phase: snapshot.phase, settings: session.state.settings))
                        .font(.subheadline)
                        .foregroundStyle(.secondaryText)
                }
                if snapshot.phase == .finished {
                    Text(FocusTimerText.focusedText(seconds: snapshot.focusedSeconds))
                        .font(.largeTitle.weight(.semibold))
                    finishedChoices(session: session)
                } else {
                    FocusRing(remainingSeconds: snapshot.remainingSeconds, phaseSeconds: snapshot.phaseSeconds,
                              isBreak: snapshot.phase.isBreak, isPaused: snapshot.isPaused,
                              endsAt: FocusTimerText.endsAt(snapshot.phaseEnd, calendar: environment.planning.calendar),
                              diameter: typeSize.isAccessibilitySize ? 170 : 240)
                    buttons(session: session, snapshot: snapshot)
                    if snapshot.phase.isBreak {
                        Button { Task { await focus.skipBreak() } } label: {
                            Label("Pause überspringen", systemImage: "forward.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                upNextSection(session: session, date: date)
            }
            .padding()
        }
    }

    /// Beenden, Pausieren/Fortsetzen and Erledigt; "Erledigt" only for a session with a task (nothing to tick off otherwise).
    private func buttons(session: FocusTimerModel.Session, snapshot: FocusTimerSnapshot) -> some View {
        let stop = FocusRoundButton(title: "Beenden", systemImage: "stop.fill", identifier: AccessibilityID.Focus.stop) { askToStop(snapshot) }
        let pause = FocusRoundButton(title: snapshot.isPaused ? "Fortsetzen" : "Pausieren",
                                     systemImage: snapshot.isPaused ? "play.fill" : "pause.fill", isProminent: true,
                                     identifier: AccessibilityID.Focus.pause) {
            Task { await snapshot.isPaused ? focus.resume() : focus.pause() }
        }
        let done = FocusRoundButton(title: "Erledigt", systemImage: "checkmark", identifier: AccessibilityID.Focus.done) {
            Task { await focus.finish(.complete) }
        }
        let hasTask = session.taskKey != nil
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                stop; pause
                if hasTask { done }
            }
            // Large text: the buttons wrap into two rows.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .center, spacing: 16) {
                stop; pause
                if hasTask { done }
            }
        }
    }

    /// After the whole session: the four choices of before.
    @ViewBuilder
    private func finishedChoices(session: FocusTimerModel.Session) -> some View {
        VStack(spacing: 12) {
            if session.taskKey != nil {
                Button { Task { await focus.finish(.complete) } } label: {
                    Label("Erledigt", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button { Task { await focus.finish(.keepGoing) } } label: {
                Label("Weiter", systemImage: "forward.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if session.taskKey != nil {
                Button { Task { await focus.finish(.postpone) } } label: {
                    Label("Verschieben", systemImage: "calendar").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button("Beenden") { Task { await focus.stop() } }
                .buttonStyle(.borderless)
        }
    }

    // MARK: Danach

    @ViewBuilder
    private func upNextSection(session: FocusTimerModel.Session, date: Date) -> some View {
        let calendar = environment.planning.calendar
        if let dayStart {
            let nowMinutes = Int(date.timeIntervalSince(dayStart) / 60)
            let rows = FocusUpNext.rows(timeline: timeline, blockEventID: session.blockEventID, nowMinutes: nowMinutes, dayStart: dayStart)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Danach").font(.headline)
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(DateText.time(minutes: row.startMinutes, calendar: calendar))
                                .monospacedDigit()
                                .foregroundStyle(.secondaryText)
                            rowText(row, calendar: calendar)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func rowText(_ row: FocusUpNextRow, calendar: Calendar) -> some View {
        switch row.kind {
        case .blockEnd(let title):
            VStack(alignment: .leading, spacing: 2) {
                Text("Blockende")
                Text(title).font(.caption).foregroundStyle(.secondaryText)
            }
        case .departure(let minutes):
            Label("Losfahren · \(minutes) min", systemImage: "car.fill")
        case .entry(let title, let endMinutes):
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(DateText.time(minutes: row.startMinutes, calendar: calendar))–\(DateText.time(minutes: endMinutes, calendar: calendar))")
                    .font(.caption).foregroundStyle(.secondaryText)
            }
        }
    }

    /// Reads today's plan once; the section stays out when there is no plan.
    private func loadToday() async {
        let planning = environment.planning
        guard focus.session != nil, let page = await planning.dayPage(planning.today) else {
            timeline = []
            dayStart = nil
            return
        }
        timeline = planning.timelineWithGaps(for: page.plan)
        dayStart = page.plan.day.startDate(in: planning.calendar)
    }

    // MARK: Stopping

    /// Within the first minute nothing is left of the session, so no question is needed.
    private func askToStop(_ snapshot: FocusTimerSnapshot) {
        if snapshot.focusedSeconds < FocusReward.discardSeconds {
            Task { await focus.stop() }
        } else {
            askingToStop = true
        }
    }
}

/// The remaining time of the phase as a ring, with the time of its end inside.
struct FocusRing: View {
    let remainingSeconds: Int
    let phaseSeconds: Int
    let isBreak: Bool
    let isPaused: Bool
    let endsAt: String?
    let diameter: Double

    private var fraction: Double {
        guard phaseSeconds > 0 else { return 0 }
        return min(1, max(0, Double(remainingSeconds) / Double(phaseSeconds)))
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 14)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(isBreak ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(FocusTimerText.clock(remainingSeconds))
                    .font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if isPaused {
                    Text("Pausiert").font(.subheadline).foregroundStyle(.secondaryText)
                } else if let endsAt {
                    Text(endsAt).font(.subheadline).foregroundStyle(.secondaryText)
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(width: diameter, height: diameter)
        .padding(7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(FocusTimerText.spoken(remainingSeconds)))
        .accessibilityValue(Text(isPaused ? String(localized: "Pausiert") : endsAt ?? ""))
    }
}

/// A round button with its caption below.
struct FocusRoundButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isProminent = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                    .font(.title2.weight(.semibold))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(isProminent ? Color.accentColor : Color(.secondarySystemFill)))
                    .foregroundStyle(isProminent ? Color.white : Color.primary)
                Text(title).font(.caption).foregroundStyle(.primary)
            }
            .frame(minWidth: 72)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
