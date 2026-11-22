import PencilKit
import SwiftUI
import TagwerkCore
import UIKit
import UniformTypeIdentifiers

/// A drawing in a note: the picture (PNG, on white) that the page shows and, as a companion file, the strokes that make it
/// editable again. The note holds one reference, `![Zeichnung](attachment:<id>)`, like a photo.
@MainActor
enum DrawingAttachment {
    enum Failure: Error, Equatable {
        /// A drawing without a stroke is not stored.
        case empty
    }

    /// The margin around the strokes, in points.
    static let margin: CGFloat = 16
    static let pictureName = "Zeichnung.png"
    static let strokesName = "Zeichnung.strokes"

    /// The drawing on white paper as PNG, never transparent, with a margin of 16 pt around the strokes. Dark ink that adapts to
    /// the interface style is drawn as in light mode, the way the canvas shows it.
    static func png(of drawing: PKDrawing, scale: CGFloat) -> Data {
        let bounds = drawing.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 1, height: 1) : drawing.bounds
        let area = bounds.insetBy(dx: -margin, dy: -margin)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: area.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: area.size))
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                drawing.image(from: area, scale: scale).draw(in: CGRect(origin: .zero, size: area.size))
            }
        }
        return image.pngData() ?? Data()
    }

    /// Stores picture and stroke data and returns the reference line `![Zeichnung](attachment:<id>)`. A drawing without strokes
    /// throws `.empty` and stores nothing.
    static func insert(_ drawing: PKDrawing, into noteID: UUID, store: NoteAttachmentStore) throws -> (id: UUID, reference: String) {
        guard !drawing.strokes.isEmpty else { throw Failure.empty }
        let picture = try store.addData(png(of: drawing, scale: 2), fileName: pictureName, type: .png, role: .drawing, to: noteID)
        do {
            try store.addData(drawing.dataRepresentation(), fileName: strokesName, type: .data, role: .strokes, to: noteID, companionOf: picture.id)
        } catch {
            // Without its strokes the picture would be a drawing that cannot be edited; the attempt leaves nothing behind.
            store.delete(ids: [picture.id])
            throw error
        }
        return (picture.id, MarkdownText.reference(for: picture.id, name: String(localized: "Zeichnung"), isImage: true))
    }

    /// Replaces picture and stroke data of an existing drawing; the ID and the reference stay. A drawing whose strokes are
    /// missing gets a new companion file.
    static func update(_ drawing: PKDrawing, id: UUID, store: NoteAttachmentStore) throws {
        try store.replaceData(png(of: drawing, scale: 2), for: id)
        let strokes = drawing.dataRepresentation()
        if let companion = store.companion(of: id, role: .strokes) {
            try store.replaceData(strokes, for: companion.id)
        } else if let noteID = store.record(id: id)?.noteID {
            try store.addData(strokes, fileName: strokesName, type: .data, role: .strokes, to: noteID, companionOf: id)
        }
    }

    /// The strokes of a drawing; `nil` when the companion is missing or unreadable (the drawing then opens as a picture only).
    static func strokes(of id: UUID, store: NoteAttachmentStore) -> PKDrawing? {
        guard let companion = store.companion(of: id, role: .strokes), let data = store.data(for: companion.id) else { return nil }
        return try? PKDrawing(data: data)
    }
}

/// What the full-screen canvas starts with: a new drawing, or the strokes of the drawing with this ID.
struct DrawingSession: Identifiable {
    let id = UUID()
    /// The drawing that is edited; `nil` for a new one.
    let editing: UUID?
    let drawing: PKDrawing
}

/// The full-screen canvas: strokes with finger or pencil, the tool palette of the system, undo and redo. The paper is light
/// in both appearances, so the strokes look as they will in the note. "Abbrechen" asks first when something was drawn.
struct DrawingCanvasView: View {
    let session: DrawingSession
    let onCancel: () -> Void
    let onDone: (PKDrawing) -> Void

    @State private var model: DrawingCanvasModel
    @State private var isConfirmingDiscard = false

    init(session: DrawingSession, onCancel: @escaping () -> Void, onDone: @escaping (PKDrawing) -> Void) {
        self.session = session
        self.onCancel = onCancel
        self.onDone = onDone
        _model = State(initialValue: DrawingCanvasModel(initial: session.drawing))
    }

    var body: some View {
        NavigationStack {
            CanvasRepresentable(model: model)
                .ignoresSafeArea(edges: .bottom)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") {
                            if model.hasChanges { isConfirmingDiscard = true } else { onCancel() }
                        }
                    }
                    ToolbarItemGroup(placement: .principal) {
                        Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                            .disabled(!model.canUndo).accessibilityLabel("Rückgängig")
                        Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                            .disabled(!model.canRedo).accessibilityLabel("Wiederholen")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { onDone(model.canvas.drawing) }
                            .accessibilityIdentifier(AccessibilityID.NoteEditor.drawingDone)
                    }
                }
                .confirmationDialog("Zeichnung verwerfen?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                    Button("Verwerfen", role: .destructive) { onCancel() }
                    Button("Weiter zeichnen", role: .cancel) {}
                }
        }
    }
}

/// The canvas view and what the toolbar needs to know about it.
@MainActor @Observable
final class DrawingCanvasModel: NSObject, PKCanvasViewDelegate {
    @ObservationIgnored let canvas = PKCanvasView()
    @ObservationIgnored let toolPicker = PKToolPicker()
    @ObservationIgnored private let initialData: Data
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var hasChanges = false

    init(initial: PKDrawing) {
        initialData = initial.dataRepresentation()
        super.init()
        canvas.drawing = initial
        canvas.drawingPolicy = .anyInput
        // The same paper in both appearances.
        canvas.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.delegate = self
    }

    func undo() { canvas.undoManager?.undo(); refresh() }
    func redo() { canvas.undoManager?.redo(); refresh() }

    nonisolated func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        MainActor.assumeIsolated { refresh() }
    }

    private func refresh() {
        canUndo = canvas.undoManager?.canUndo ?? false
        canRedo = canvas.undoManager?.canRedo ?? false
        hasChanges = canvas.drawing.dataRepresentation() != initialData
    }
}

private struct CanvasRepresentable: UIViewRepresentable {
    let model: DrawingCanvasModel

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = model.canvas
        model.toolPicker.addObserver(canvas)
        model.toolPicker.setVisible(true, forFirstResponder: canvas)
        // The canvas has to be in a window before it can take the tool palette.
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {}
}
