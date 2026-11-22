import SwiftUI
import UIKit

/// What the insert features of the note editor put on screen on top of the page: the document camera, the share sheet and
/// the rename prompt for an attachment. The editor holds one of these, so the page itself carries a single property and a
/// single modifier for all of them.
@MainActor @Observable
final class NoteInsertState {
    struct Renaming: Identifiable, Equatable {
        let id: UUID
        var name: String
    }

    struct Sharing: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    var isScanning = false
    var renaming: Renaming?
    var sharing: Sharing?

    /// Whether something covers the page. A cover makes SwiftUI report the page as gone, and the page must not remove an
    /// empty note or trim its attachments then (the result of the cover is what goes into the note).
    var isPresenting: Bool { isScanning || sharing != nil }
}

/// Presents the covers and prompts of `NoteInsertState`; the editor adds it once.
struct NoteInsertPresentations: ViewModifier {
    @Bindable var state: NoteInsertState
    /// The pages of a finished scan, none when it was cancelled.
    let onScanFinished: ([UIImage]) -> Void
    let onRename: (_ id: UUID, _ name: String) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $state.isScanning) {
                DocumentScanner { pages in
                    state.isScanning = false
                    onScanFinished(pages)
                }
                .ignoresSafeArea()
            }
            .sheet(item: $state.sharing) { sharing in
                ShareSheet(items: sharing.urls).presentationDetents([.medium, .large])
            }
            .alert("Umbenennen", isPresented: renamingBinding) {
                TextField("Name", text: renamingName)
                Button("Abbrechen", role: .cancel) {}
                Button("Sichern") {
                    if let renaming = state.renaming { onRename(renaming.id, renaming.name) }
                }
            }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { state.renaming != nil }, set: { if !$0 { state.renaming = nil } })
    }

    private var renamingName: Binding<String> {
        Binding(get: { state.renaming?.name ?? "" }, set: { state.renaming?.name = $0 })
    }
}

extension View {
    func noteInsertPresentations(_ state: NoteInsertState, onScanFinished: @escaping ([UIImage]) -> Void,
                                 onRename: @escaping (UUID, String) -> Void) -> some View {
        modifier(NoteInsertPresentations(state: state, onScanFinished: onScanFinished, onRename: onRename))
    }
}

/// The system share sheet for files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
