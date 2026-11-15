import Combine
import Foundation
import PencilKit
import UIKit

@MainActor public final class CanvasViewModel: ObservableObject {
    @Published public private(set) var state: GamePhase = .idle
    @Published public var drawingData = PKDrawing().dataRepresentation() {
        didSet { scheduleBackup() }
    }
    @Published public var tool: CanvasTool = .pen
    @Published public var width: CGFloat = 3
    @Published public var undoToken = 0
    @Published public private(set) var points: [CGPoint] = []
    @Published public private(set) var errorMessage: String?
    private let drafts: StrokeDraftStore?
    private var roomID: String?
    private var turnID: String?
    private var restoring = false
    private var backupTask: Task<Void, Never>?

    public init(drafts: StrokeDraftStore? = nil) { self.drafts = drafts }

    public func open(roomID: String, turnID: String) async {
        guard self.roomID != roomID || self.turnID != turnID else { return }
        await saveDraft()
        guard !Task.isCancelled else { return }
        backupTask?.cancel()
        self.roomID = roomID; self.turnID = turnID
        state = .loading; restoring = true
        defer { restoring = false }
        do {
            let saved = try await drafts?.load(roomID: roomID, turnID: turnID)
            guard self.roomID == roomID, self.turnID == turnID else { return }
            drawingData = saved ?? PKDrawing().dataRepresentation()
            _ = try PKDrawing(data: drawingData)
            state = .drawing; errorMessage = nil
        } catch { report(error) }
    }

    public func capture(points: [CGPoint]) { self.points = points }
    public func undo() { undoToken += 1 }
    public func clear() { drawingData = PKDrawing().dataRepresentation() }
    public func report(_ error: Error) { errorMessage = error.localizedDescription; state = .error }

    public func pngData() throws -> Data {
        let drawing = try PKDrawing(data: drawingData)
        guard !drawing.strokes.isEmpty, !drawing.bounds.isEmpty,
              let data = drawing.image(from: drawing.bounds.insetBy(dx: -8, dy: -8), scale: 1).pngData() else {
            throw CanvasError.emptyDrawing
        }
        return data
    }

    public func saveToPhotos() async {
        do {
            let data = try pngData()
            guard let image = UIImage(data: data) else { throw CanvasError.emptyDrawing }
            try await PhotoLibrarySaver().save(image)
            errorMessage = nil
        } catch { report(error) }
    }

    public func saveDraft() async {
        guard let drafts, let roomID, let turnID else { return }
        let data = drawingData
        do { try await drafts.save(roomID: roomID, turnID: turnID, data: data) }
        catch { report(error) }
    }

    private func scheduleBackup() {
        guard !restoring, let drafts, let roomID, let turnID else { return }
        backupTask?.cancel()
        let data = drawingData
        backupTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                try await drafts.save(roomID: roomID, turnID: turnID, data: data)
            } catch is CancellationError { } catch { self?.report(error) }
        }
    }

    deinit { backupTask?.cancel() }
    public enum CanvasError: LocalizedError {
        case emptyDrawing
        public var errorDescription: String? { "El dibujo está vacío o no se puede exportar." }
    }
}
