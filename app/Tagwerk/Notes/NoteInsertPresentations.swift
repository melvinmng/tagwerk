import PencilKit
import SwiftUI
import TagwerkCore
import UIKit

/// What the insert features of the note editor put on screen on top of the page: the document camera, the drawing canvas and
/// viewer, the share sheet and the rename prompt for an attachment. The editor holds one of these, so the page itself carries
/// a single property and a single modifier for all of them.
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

    /// A full-screen cover. One at a time: they share one slot, so SwiftUI never has to present two covers of one view.
    enum Cover: Identifiable {
        case scan
        case drawing(DrawingSession)
        /// The large view of the drawing with this attachment ID.
        case drawingViewer(UUID)

        var id: String {
            switch self {
            case .scan: "scan"
            case .drawing(let session): "drawing-\(session.id)"
            case .drawingViewer(let id): "viewer-\(id)"
            }
        }
    }

    var cover: Cover?
    /// Counts what changed about the attachments without the text changing (the text of a scan was recognised, a drawing was
    /// edited), so the page shows it again.
    var revision = 0
    var renaming: Renaming?
    var sharing: Sharing?
    /// The table editor sheet, and the hint for a table that is too wide for it.
    var tableSession: TableSession?
    var wideTable: WideTableHint?

    /// Whether something covers the page. A cover makes SwiftUI report the page as gone, and the page must not remove an
    /// empty note or trim its attachments then (the result of the cover is what goes into the note).
    var isPresenting: Bool { cover != nil || sharing != nil || tableSession != nil || wideTable != nil }
}

/// What the covers and prompts report back to the editor.
struct NoteInsertActions {
    /// The pages of a finished scan, none when it was cancelled.
    var onScanFinished: ([UIImage]) -> Void
    /// A finished drawing of the canvas, for a new drawing (`editing` is `nil`) or an existing one.
    var onDrawingFinished: (_ editing: UUID?, _ drawing: PKDrawing) -> Void
    var onRename: (_ id: UUID, _ name: String) -> Void
    /// The table editor finished with this table.
    var onTableFinished: (_ session: TableSession, _ table: MarkdownTable) -> Void
    /// "Im Text bearbeiten" of the hint for a wide table: the cursor goes to this line.
    var onEditTableAsText: (_ firstLine: Int) -> Void
}

/// Presents the covers and prompts of `NoteInsertState`; the editor adds it once.
struct NoteInsertPresentations: ViewModifier {
    @Bindable var state: NoteInsertState
    let attachments: NoteAttachmentStore?
    let actions: NoteInsertActions

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $state.cover) { cover in
                switch cover {
                case .scan:
                    DocumentScanner { pages in
                        state.cover = nil
                        actions.onScanFinished(pages)
                    }
                    .ignoresSafeArea()
                case .drawing(let session):
                    DrawingCanvasView(session: session, onCancel: { state.cover = nil }, onDone: { drawing in
                        state.cover = nil
                        actions.onDrawingFinished(session.editing, drawing)
                    })
                case .drawingViewer(let id):
                    if let attachments {
                        DrawingViewer(id: id, store: attachments, onEdited: { state.revision += 1 }, onClose: { state.cover = nil })
                    }
                }
            }
            .sheet(item: $state.sharing) { sharing in
                ShareSheet(items: sharing.urls).presentationDetents([.medium, .large])
            }
            .sheet(item: $state.tableSession) { session in
                TableEditorSheet(table: session.table, onCancel: { state.tableSession = nil }, onDone: { table in
                    state.tableSession = nil
                    actions.onTableFinished(session, table)
                })
                .presentationDetents([.large])
            }
            .alert("Tabelle", isPresented: Binding(get: { state.wideTable != nil }, set: { if !$0 { state.wideTable = nil } })) {
                Button("Im Text bearbeiten") {
                    if let hint = state.wideTable { actions.onEditTableAsText(hint.firstLine) }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Diese Tabelle hat mehr als 8 Spalten. Bearbeite sie im Text.")
            }
            .alert("Umbenennen", isPresented: renamingBinding) {
                TextField("Name", text: renamingName)
                Button("Abbrechen", role: .cancel) {}
                Button("Sichern") {
                    if let renaming = state.renaming { actions.onRename(renaming.id, renaming.name) }
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
    func noteInsertPresentations(_ state: NoteInsertState, attachments: NoteAttachmentStore?, actions: NoteInsertActions) -> some View {
        modifier(NoteInsertPresentations(state: state, attachments: attachments, actions: actions))
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
