import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
import UIKit

@MainActor public final class FirebaseAuthService: EmailAuthServicing {
    private let auth: Auth
    public init(auth: Auth) { self.auth = auth }
    public func signInAnonymously() async throws -> Player {
        if let user = auth.currentUser { return Player(id: user.uid, nickname: user.displayName ?? "") }
        let result = try await auth.signInAnonymously()
        return Player(id: result.user.uid, nickname: result.user.displayName ?? "")
    }
    public func signOut() throws { try auth.signOut() }
    public func signIn(email: String, password: String) async throws -> Player {
        let result = try await auth.signIn(withEmail: email, password: password)
        return Player(id: result.user.uid, nickname: result.user.displayName ?? email.components(separatedBy: "@").first ?? "Jugador")
    }
    public func createAccount(email: String, password: String, nickname: String) async throws -> Player {
        let result = try await auth.createUser(withEmail: email, password: password)
        let request = result.user.createProfileChangeRequest()
        request.displayName = nickname
        try await request.commitChanges()
        return Player(id: result.user.uid, nickname: nickname)
    }
}

@MainActor public final class FirebaseRoomService: RoomServicing {
    private let root: DatabaseReference
    public init(database: Database) { root = database.reference() }
    /// Own backend contract: rooms/{id}/snapshot is an atomic, server-authored snapshot.
    /// Collections use ordered maps; deadline is Unix seconds. Rules must restrict snapshot reads
    /// to members and expose only the chain entries appropriate to each phase.
    public func observe(roomID: String) -> AsyncThrowingStream<RoomSnapshot, Error> {
        do { try validateIdentifier(roomID) }
        catch { return AsyncThrowingStream { $0.finish(throwing: error) } }
        let reference = root.child("rooms").child(roomID).child("snapshot")
        return AsyncThrowingStream { continuation in
            let handle = reference.observe(.value, with: { snapshot in
                do {
                    let room = try RoomSnapshotCodec.decode(snapshot.value as Any)
                    guard room.id == roomID else { throw ServiceError.invalidPayload }
                    continuation.yield(room)
                } catch { continuation.finish(throwing: error) }
            }, withCancel: { continuation.finish(throwing: $0) })
            continuation.onTermination = { @Sendable _ in reference.removeObserver(withHandle: handle) }
        }
    }
    public func create(roomID: String, player: Player, settings: RoomSettings) async throws {
        guard settings.playerLimit >= 2, settings.playerLimit <= 8,
              settings.writingSeconds.isFinite, settings.drawingSeconds.isFinite,
              (5...3600).contains(settings.writingSeconds), (5...3600).contains(settings.drawingSeconds) else { throw ServiceError.invalidPayload }
        try await mutate(roomID: roomID) { existing in
            guard existing == nil else { throw ServiceError.invalidPayload }
            return RoomSnapshot(id: roomID, phase: .lobby, players: [player], settings: settings)
        }
    }
    public func join(roomID: String, player: Player) async throws {
        try await mutate(roomID: roomID) { room in
            guard let room else { throw ServiceError.missingRoom }
            if room.players.contains(where: { $0.id == player.id }) { return room }
            guard room.phase == .lobby, let limit = room.settings?.playerLimit,
                  (2...8).contains(limit), room.players.count < limit else { throw ServiceError.invalidPayload }
            return RoomSnapshot(id: room.id, phase: .lobby, players: room.players + [player], settings: room.settings)
        }
    }
    public func updatePlayerLimit(roomID: String, playerID: String, limit: Int) async throws {
        guard (2...8).contains(limit) else { throw ServiceError.invalidPayload }
        try await mutate(roomID: roomID) { room in
            guard let room else { throw ServiceError.missingRoom }
            guard room.players.first?.id == playerID else { throw ServiceError.unauthorized }
            guard room.phase == .lobby, limit >= room.players.count, let settings = room.settings else { throw ServiceError.invalidPayload }
            let nextSettings = RoomSettings(playerLimit: limit, writingSeconds: settings.writingSeconds, drawingSeconds: settings.drawingSeconds)
            return RoomSnapshot(id: room.id, phase: room.phase, players: room.players, turns: room.turns, chains: room.chains, deadline: room.deadline, settings: nextSettings)
        }
    }
    public func start(roomID: String, playerID: String) async throws {
        try await mutate(roomID: roomID) { room in
            guard let room else { throw ServiceError.missingRoom }
            guard room.players.first?.id == playerID else { throw ServiceError.unauthorized }
            return try GameEngine.start(room, now: Date())
        }
    }
    public func advance(roomID: String) async throws {
        try await mutate(roomID: roomID) { room in
            guard let room else { throw ServiceError.missingRoom }
            return GameEngine.advance(room, now: Date())
        }
    }
    public func submit(roomID: String, entry: ChainEntry, turnID: String) async throws {
        try await mutate(roomID: roomID) { room in
            guard let room else { throw ServiceError.missingRoom }
            return try GameEngine.contribute(room, entry: entry, turnID: turnID, now: Date())
        }
    }
    /// RTDB retries this transformation on concurrent writes; media uploads stay outside it.
    private func mutate(roomID: String, transform: @escaping (RoomSnapshot?) throws -> RoomSnapshot) async throws {
        try validateIdentifier(roomID)
        let reference = root.child("rooms").child(roomID).child("snapshot")
        let failure = TransactionFailure()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.runTransactionBlock({ data in
                do {
                    failure.set(nil)
                    let room: RoomSnapshot?
                    if data.value == nil || data.value is NSNull { room = nil }
                    else { room = try RoomSnapshotCodec.decode(data.value as Any) }
                    let next: RoomSnapshot
                    do { next = try transform(room) }
                    catch ServiceError.missingRoom where room == nil {
                        // Empty local cache: let RTDB compare with server and retry.
                        return TransactionResult.success(withValue: data)
                    }
                    data.value = try RoomSnapshotCodec.encode(next)
                    return TransactionResult.success(withValue: data)
                } catch { failure.set(error); return TransactionResult.abort() }
            }, andCompletionBlock: { error, committed, snapshot in
                if let error { continuation.resume(throwing: error) }
                else if !committed { continuation.resume(throwing: failure.get() ?? ServiceError.invalidPayload) }
                else if snapshot?.exists() != true { continuation.resume(throwing: ServiceError.missingRoom) }
                else { continuation.resume() }
            }, withLocalEvents: false)
        }
    }

}

@MainActor public final class RealtimeMediaService: MediaStorageServicing {
    private let database: Database
    private let userID: String
    public init(database: Database, userID: String) throws {
        try validateIdentifier(userID); self.database = database; self.userID = userID
    }
    public func uploadPNG(_ data: Data, roomID: String) async throws -> URL {
        guard data.count <= 20_000_000, let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else { throw ServiceError.invalidPayload }
        let ratio = min(1, 1024 / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let compressed = image.jpegData(compressionQuality: 0.65), compressed.count <= 512_000 else { throw ServiceError.invalidPayload }
        return try await write(compressed, type: "image/jpeg", roomID: roomID)
    }
    public func uploadAudio(fileURL: URL, roomID: String) async throws -> URL {
        guard fileURL.isFileURL, fileURL.pathExtension == "m4a",
              let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000 else { throw ServiceError.invalidPayload }
        return try await write(Data(contentsOf: fileURL), type: "audio/mp4", roomID: roomID)
    }
    private func write(_ data: Data, type: String, roomID: String) async throws -> URL {
        try validateIdentifier(roomID)
        guard !data.isEmpty else { throw ServiceError.invalidPayload }
        let id = UUID().uuidString
        let reference = database.reference().child("rooms").child(roomID).child("media").child(id)
        let payload: [String: Any] = ["ownerID": userID, "mimeType": type, "encoding": "base64", "byteCount": data.count, "base64": data.base64EncodedString()]
        try await reference.setValue(payload)
        guard let url = URL(string: "rtdb-media://rooms/\(roomID)/media/\(id)") else { throw ServiceError.invalidIdentifier }
        return url
    }
    public func download(_ url: URL) async throws -> Data {
        guard url.scheme == "rtdb-media", url.host == "rooms" else { throw ServiceError.invalidPayload }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3, parts[1] == "media" else { throw ServiceError.invalidPayload }
        try validateIdentifier(parts[0]); try validateIdentifier(parts[2])
        let snapshot = try await database.reference().child("rooms").child(parts[0]).child("media").child(parts[2]).getData()
        guard let object = snapshot.value as? [String: Any], let encoded = object["base64"] as? String,
              encoded.count <= 2_700_000, let data = Data(base64Encoded: encoded), !data.isEmpty,
              data.count == (object["byteCount"] as? NSNumber)?.intValue else { throw ServiceError.invalidPayload }
        return data
    }
}

private final class TransactionFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var error: Error?
    func set(_ value: Error?) { lock.lock(); defer { lock.unlock() }; error = value }
    func get() -> Error? { lock.lock(); defer { lock.unlock() }; return error }
}

/// Call only after AppEnvironment.configureFirebase succeeds.
@MainActor public enum FirebaseServiceFactory {
    static func database(app: FirebaseApp) throws -> Database {
        guard let raw = app.options.databaseURL, let url = URL(string: raw),
              url.scheme == "https", url.host != nil else { throw AppEnvironment.ConfigurationError.invalid("DATABASE_URL") }
        return Database.database(app: app, url: raw)
    }
    /// Can be constructed before login; each upload resolves the current user.
    public static func sessionMedia() throws -> any MediaStorageServicing {
        guard let app = FirebaseApp.app() else { throw ServiceError.configuration }
        return SessionMediaService(app: app)
    }
    public static func auth() throws -> FirebaseAuthService {
        guard let app = FirebaseApp.app() else { throw ServiceError.configuration }
        return FirebaseAuthService(auth: Auth.auth(app: app))
    }
    public static func rooms() throws -> FirebaseRoomService {
        guard let app = FirebaseApp.app() else { throw ServiceError.configuration }
        return FirebaseRoomService(database: try database(app: app))
    }
    public static func media(userID: String) throws -> RealtimeMediaService {
        guard let app = FirebaseApp.app() else { throw ServiceError.configuration }
        return try RealtimeMediaService(database: try FirebaseServiceFactory.database(app: app), userID: userID)
    }
}

@MainActor private final class SessionMediaService: MediaStorageServicing {
    private let app: FirebaseApp
    init(app: FirebaseApp) { self.app = app }
    private func authenticatedService() throws -> RealtimeMediaService {
        guard let userID = Auth.auth(app: app).currentUser?.uid else { throw ServiceError.unauthorized }
        return try RealtimeMediaService(database: try FirebaseServiceFactory.database(app: app), userID: userID)
    }
    func download(_ url: URL) async throws -> Data { try await authenticatedService().download(url) }
    func uploadPNG(_ data: Data, roomID: String) async throws -> URL {
        try await authenticatedService().uploadPNG(data, roomID: roomID)
    }
    func uploadAudio(fileURL: URL, roomID: String) async throws -> URL {
        try await authenticatedService().uploadAudio(fileURL: fileURL, roomID: roomID)
    }
}
