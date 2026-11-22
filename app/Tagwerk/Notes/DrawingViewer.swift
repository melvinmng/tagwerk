import PencilKit
import SwiftUI
import UIKit

/// A drawing large and zoomable. A tap on a drawing in the page opens it here; "Bearbeiten" opens the canvas with the
/// strokes, so a touch while looking never draws.
struct DrawingViewer: View {
    let id: UUID
    let store: NoteAttachmentStore
    /// The picture changed (after editing): the page loads it again.
    let onEdited: () -> Void
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var strokes: PKDrawing?
    @State private var editing: DrawingSession?
    @State private var sharing: NoteInsertState.Sharing?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image {
                    ZoomableImage(image: image).ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Die Zeichnung ließ sich nicht lesen.", systemImage: "scribble")
                }
                if strokes == nil, image != nil {
                    Text("Die Strichdaten fehlen. Die Zeichnung lässt sich nur ansehen.")
                        .font(.footnote).foregroundStyle(.secondaryText).padding(12).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Zeichnung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig", action: onClose) }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        if let url = store.exportURL(for: id) { sharing = NoteInsertState.Sharing(urls: [url]) }
                    } label: { Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Teilen")
                    Button("Bearbeiten") {
                        if let strokes { editing = DrawingSession(editing: id, drawing: strokes) }
                    }
                    .disabled(strokes == nil)
                    .accessibilityIdentifier(AccessibilityID.NoteEditor.drawingEdit)
                }
            }
            .task { load() }
            .fullScreenCover(item: $editing) { session in
                DrawingCanvasView(session: session, onCancel: { editing = nil }, onDone: { drawing in
                    editing = nil
                    do {
                        try DrawingAttachment.update(drawing, id: id, store: store)
                        load()
                        onEdited()
                    } catch {
                        failure = String(localized: "Die Zeichnung ließ sich nicht sichern.")
                    }
                })
            }
            .sheet(item: $sharing) { ShareSheet(items: $0.urls).presentationDetents([.medium, .large]) }
            .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("OK", role: .cancel) {} }
        }
    }

    private func load() {
        image = store.data(for: id).flatMap { UIImage(data: $0) }
        strokes = DrawingAttachment.strokes(of: id, store: store)
    }
}

/// A picture in a scroll view that zooms by pinch and double tap.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .systemBackground
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        context.coordinator.imageView = imageView
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            scrollView.setZoomScale(scrollView.zoomScale > 1 ? 1 : 3, animated: true)
        }
    }
}
