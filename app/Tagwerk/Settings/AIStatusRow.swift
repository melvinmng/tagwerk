import SwiftUI

/// A status line in a list: ⚠︎ for warnings, plain grey otherwise.
struct AIStatusRow: View {
    let message: AIStatusMessage

    var body: some View {
        if message.isWarning {
            Label(message.text, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orangeText)
        } else {
            Text(message.text)
                .font(.footnote)
                .foregroundStyle(.secondaryText)
        }
    }
}
