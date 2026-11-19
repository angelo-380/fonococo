import PencilKit
import SwiftUI
import UIKit

public enum CanvasTool { case pencil, pen, marker, eraser }

public struct CanvasSurface: UIViewRepresentable {
    @Binding private var drawingData: Data
    private let tool: CanvasTool
    private let width: CGFloat
    private let color: UIColor
    private let undoToken: Int
    private let redoToken: Int
    private let onPoints: ([CGPoint]) -> Void
    private let onError: (Error) -> Void

    public init(drawingData: Binding<Data>, tool: CanvasTool = .pen, width: CGFloat = 3, color: UIColor = .label,
                undoToken: Int = 0, redoToken: Int = 0, onPoints: @escaping ([CGPoint]) -> Void = { _ in },
                onError: @escaping (Error) -> Void = { _ in }) {
        _drawingData = drawingData
        self.tool = tool
        self.width = width
        self.color = color
        self.undoToken = undoToken
        self.redoToken = redoToken
        self.onPoints = onPoints
        self.onError = onError
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    public func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawingPolicy = .anyInput
        view.delegate = context.coordinator
        let undoGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.undoGesture(_:)))
        undoGesture.numberOfTouchesRequired = 2
        let redoGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.redoGesture(_:)))
        redoGesture.numberOfTouchesRequired = 3
        view.addGestureRecognizer(undoGesture)
        view.addGestureRecognizer(redoGesture)
        return view
    }

    public func updateUIView(_ view: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        switch tool {
        case .pencil: view.tool = PKInkingTool(.pencil, color: color, width: max(1, width))
        case .pen: view.tool = PKInkingTool(.pen, color: color, width: max(1, width))
        case .marker: view.tool = PKInkingTool(.marker, color: color, width: max(1, width))
        case .eraser: view.tool = PKEraserTool(.bitmap, width: max(5, width))
        }
        if coordinator.undoToken != undoToken {
            coordinator.undoToken = undoToken
            view.undoManager?.undo()
            return
        }
        if coordinator.redoToken != redoToken {
            coordinator.redoToken = redoToken
            view.undoManager?.redo()
            return
        }
        guard coordinator.lastData != drawingData, !coordinator.isDrawing else { return }
        do {
            let drawing = drawingData.isEmpty ? PKDrawing() : try PKDrawing(data: drawingData)
            coordinator.isApplying = true
            coordinator.lastData = drawingData
            view.drawing = drawing
            coordinator.isApplying = false
        } catch {
            coordinator.lastData = drawingData
            DispatchQueue.main.async { onError(error) }
        }
    }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasSurface
        var lastData = Data()
        var undoToken: Int
        var redoToken: Int
        var isApplying = false
        var isDrawing = false
        init(parent: CanvasSurface) { self.parent = parent; undoToken = parent.undoToken; redoToken = parent.redoToken }
        @objc func undoGesture(_ gesture: UITapGestureRecognizer) { if gesture.state == .ended { gesture.view?.undoManager?.undo() } }
        @objc func redoGesture(_ gesture: UITapGestureRecognizer) { if gesture.state == .ended { gesture.view?.undoManager?.redo() } }
        public func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { isDrawing = true }
        public func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = false
            canvasViewDrawingDidChange(canvasView)
        }
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplying else { return }
            let data = canvasView.drawing.dataRepresentation()
            guard data != lastData else { return }
            lastData = data
            parent.drawingData = data
            let points = canvasView.drawing.strokes.flatMap { stroke in
                stroke.path.map { $0.location.applying(stroke.transform) }
            }
            parent.onPoints(points)
        }
    }
}
