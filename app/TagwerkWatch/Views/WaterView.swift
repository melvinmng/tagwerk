import SwiftUI
import TagwerkCore

/// Today's water as a ring, buttons for the quick amounts and the Digital Crown for any amount in steps of 50 ml.
struct WaterView: View {
    @Environment(WatchStore.self) private var store
    @State private var crownAmount = 250.0

    var body: some View {
        let water = store.display()?.water
        ScrollView {
            VStack(spacing: 8) {
                UndoRow()
                if let water {
                    ring(water)
                    HStack {
                        ForEach(water.quickAmounts, id: \.self) { amount in
                            Button("+\(amount)") { store.logWater(milliliters: amount) }
                        }
                    }
                    Button {
                        store.logWater(milliliters: Int(crownAmount))
                    } label: {
                        Label("\(Int(crownAmount)) ml", systemImage: "digitalcrown.horizontal.arrow.clockwise")
                    }
                    .focusable()
                    .digitalCrownRotation($crownAmount, from: 50, through: 1000, by: 50, sensitivity: .medium,
                                          isContinuous: false, isHapticFeedbackEnabled: true)
                } else {
                    Text("Öffne Tagwerk auf dem iPhone").font(.footnote).foregroundStyle(.secondary)
                }
                SyncHint()
            }
        }
        .navigationTitle("Wasser")
    }

    private func ring(_ water: WatchWater) -> some View {
        let fraction = WatchComplicationText.fraction(done: water.milliliters, goal: water.goalMilliliters)
        return ZStack {
            Circle().stroke(Color.blue.opacity(0.25), lineWidth: 8)
            Circle().trim(from: 0, to: fraction).stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(WatchComplicationText.liters(milliliters: water.milliliters)).font(.headline)
                Text("von \(WatchComplicationText.liters(milliliters: water.goalMilliliters))").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Wasser heute"))
        .accessibilityValue(Text("\(WatchComplicationText.liters(milliliters: water.milliliters)) von \(WatchComplicationText.liters(milliliters: water.goalMilliliters))"))
    }
}
