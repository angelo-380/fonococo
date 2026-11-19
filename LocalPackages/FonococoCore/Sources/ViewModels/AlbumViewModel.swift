import Combine
import Foundation
import SwiftData

public struct OfflineAlbumPayload: Codable {
    public let room: RoomSnapshot
    /// Keys are source URL strings; values contain complete downloaded media for offline use.
    public let media: [String: Data]
    public let localReactionURLs: [URL]
}

@MainActor public final class AlbumViewModel: ObservableObject {
    @Published public private(set) var message = ""
    @Published public private(set) var busy = false
    @Published public private(set) var recording = false
    @Published public private(set) var reactionReady = false
    private let storage: any MediaStorageServicing
    private let recorder = ReactionAudioRecorder()
    private var reactionURLs: [String: [URL]] = [:]
    private var recordingRoomID: String?
    private var pendingReaction: URL?

    public init(storage: any MediaStorageServicing) {
        self.storage = storage
    }

    public func startRecording(roomID: String) async {
        guard !busy, !recording else { return }
        discardReaction()
        do {
            try await recorder.start()
            recording = true; recordingRoomID = roomID; message = "Grabando reacción."
        } catch { message = error.localizedDescription }
    }

    public func stopRecording() {
        guard recording else { return }
        do { pendingReaction = try recorder.stop(); reactionReady = true; recording = false; message = "Reacción lista para subir." }
        catch { message = error.localizedDescription }
    }

    public func discardReaction() {
        if recording { recorder.cancel() }
        if let pendingReaction { try? FileManager.default.removeItem(at: pendingReaction) }
        pendingReaction = nil; reactionReady = false; recording = false; recordingRoomID = nil
    }

    public func stopAndUpload() async {
        guard reactionReady, let localURL = pendingReaction, let roomID = recordingRoomID else { return }
        busy = true
        defer { busy = false }
        do {
            let url = try await storage.uploadAudio(fileURL: localURL, roomID: roomID)
            reactionURLs[roomID, default: []].append(url)
            discardReaction()
            message = "Reacción subida; se incluirá en tu copia local del álbum."
        } catch { message = error.localizedDescription }
    }

    public func loadMedia(_ url: URL) async throws -> Data { try await storage.download(url) }

    public func cancelRecording() {
        discardReaction()
    }

    public func archive(room: RoomSnapshot, context: ModelContext) async {
        guard room.phase == .revealing, !busy, !recording else { return }
        busy = true
        defer { busy = false }
        do {
            let reactions = reactionURLs[room.id] ?? []
            let urls = Set(room.chains.flatMap(\.entries).flatMap { [$0.drawingURL, $0.audioURL].compactMap { $0 } } + reactions)
            var media: [String: Data] = [:]
            for url in urls {
                let data = try await storage.download(url)
                media[url.absoluteString] = data
            }
            let payload = OfflineAlbumPayload(room: room, media: media, localReactionURLs: reactions)
            try AlbumRepository(context: context).save(id: room.id, title: "Partida \(room.id)", payload: JSONEncoder().encode(payload))
            message = "Álbum y \(media.count) archivos guardados offline."
        } catch { message = error.localizedDescription }
    }

    public enum ArchiveError: LocalizedError {
        case invalidMedia, failedDownload
        public var errorDescription: String? {
            switch self {
            case .invalidMedia: return "El álbum contiene una URL de medios inválida."
            case .failedDownload: return "No se pudo descargar todo el álbum. No se guardó una copia incompleta."
            }
        }
    }
}
