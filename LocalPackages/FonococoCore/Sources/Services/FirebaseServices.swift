import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
import UIKit
import GoogleSignIn

@MainActor public final class FirebaseAuthService: EmailAuthServicing, SessionRestoringAuthServicing, GoogleAuthServicing {
    private let auth: Auth
    public init(auth: Auth) { self.auth = auth }
    public var isCurrentUserAnonymous: Bool { auth.currentUser?.isAnonymous ?? false }
    public var isGoogleLinked: Bool { auth.currentUser?.providerData.contains(where: { $0.providerID == "google.com" }) ?? false }
    public func signInAnonymously() async throws -> Player {
        if let user = auth.currentUser { return Player(id: user.uid, nickname: user.displayName ?? "") }
        let result = try await auth.signInAnonymously()
        return Player(id: result.user.uid, nickname: result.user.displayName ?? "")
    }
    public func signOut() throws { try auth.signOut() }
    public func restoreSession() async throws -> Player? {
        guard let user = auth.currentUser else { return nil }
        let nickname = user.providerData.contains(where: { $0.providerID == "google.com" }) ? "Jugador" : (user.displayName ?? user.email?.components(separatedBy: "@").first ?? "Jugador")
        return Player(id: user.uid, nickname: nickname)
    }
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
    public func updateNickname(_ nickname: String) async throws -> Player {
        guard let user = auth.currentUser, !user.isAnonymous else { throw ServiceError.unauthorized }
        let request = user.createProfileChangeRequest()
        request.displayName = nickname
        try await request.commitChanges()
        return Player(id: user.uid, nickname: nickname)
    }
    public func sendPasswordReset(to email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }
    public func changePassword(current: String, new: String) async throws {
        guard let user = auth.currentUser, let email = user.email else { throw ServiceError.unauthorized }
        let credential = EmailAuthProvider.credential(withEmail: email, password: current)
        try await user.reauthenticate(with: credential)
        try await user.updatePassword(to: new)
    }
    public func signInWithGoogle() async throws -> Player {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AppEnvironment.ConfigurationError.missing("CLIENT_ID de Google")
        }
        guard let controller = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { throw ServiceError.configuration }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller)
        guard let idToken = result.user.idToken?.tokenString else { throw ServiceError.invalidResponse }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        let signed = try await auth.signIn(with: credential)
        return Player(id: signed.user.uid, nickname: "Jugador")
    }
    public func linkGoogleToCurrentUser() async throws -> Player {
        guard let current = auth.currentUser,
              let clientID = FirebaseApp.app()?.options.clientID else { throw ServiceError.unauthorized }
        if isGoogleLinked { return Player(id: current.uid, nickname: current.displayName ?? "Jugador") }
        guard let controller = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { throw ServiceError.configuration }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller)
        guard let idToken = result.user.idToken?.tokenString else { throw ServiceError.invalidResponse }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        do {
            let linked = try await current.link(with: credential)
            return Player(id: linked.user.uid, nickname: linked.user.displayName ?? current.displayName ?? "Jugador")
        } catch {
            guard (error as NSError).code == AuthErrorCode.credentialAlreadyInUse.rawValue else { throw error }
            // The Google identity already belongs to another Firebase UID. Both identities
            // are proven by the current session and the fresh Google credential.
            let signed = try await auth.signIn(with: credential)
            return Player(id: signed.user.uid, nickname: signed.user.displayName ?? "Jugador")
        }
    }
    public func handleGoogleURL(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }
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
            return RoomSnapshot(id: room.id, phase: .lobby, players: room.players + [player], settings: room.settings, drawingTimeVotes: room.drawingTimeVotes, timeTieWinner: room.timeTieWinner, earlyStartVotes: room.earlyStartVotes, earlyStartTieWinner: room.earlyStartTieWinner, earlyStartDecision: room.earlyStartDecision)
        }
    }
    public func updatePlayerLimit(roomID: String, playerID: String, limit: Int) async throws {
        guard (2...8).contains(limit) else { throw ServiceError.invalidPayload }
        try await mutate(roomID: roomID) { room in
            guard let room else { throw ServiceError.missingRoom }
            guard room.players.first?.id == playerID else { throw ServiceError.unauthorized }
            guard room.phase == .lobby, limit >= room.players.count, let settings = room.settings else { throw ServiceError.invalidPayload }
            let nextSettings = RoomSettings(playerLimit: limit, writingSeconds: settings.writingSeconds, drawingSeconds: settings.drawingSeconds)
            return RoomSnapshot(id: room.id, phase: room.phase, players: room.players, turns: room.turns, chains: room.chains, deadline: room.deadline, settings: nextSettings, drawingTimeVotes: room.drawingTimeVotes, timeTieWinner: room.timeTieWinner, earlyStartVotes: room.earlyStartVotes, earlyStartTieWinner: room.earlyStartTieWinner, earlyStartDecision: room.earlyStartDecision)
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
    public func rate(roomID: String, drawingID: String, voterID: String, stars: Int) async throws {
        guard (0...5).contains(stars) else { throw ServiceError.invalidPayload }
        let coin = UInt64.random(in: UInt64.min...UInt64.max)
        try await mutate(roomID: roomID) { room in
            guard let room else { throw ServiceError.missingRoom }
            guard room.phase == .revealing, room.players.contains(where: { $0.id == voterID }),
                  room.chains.flatMap(\.entries).contains(where: { $0.id == drawingID && $0.drawingURL != nil && $0.authorID != voterID }) else { throw ServiceError.unauthorized }
            var ratings = room.ratings ?? [:]
            ratings[drawingID, default: [:]][voterID] = stars
            let ranks = room.podiumTieRanks ?? GameEngine.podiumTieRanks(room, ratings: ratings, coin: coin)
            return RoomSnapshot(id: room.id, phase: room.phase, players: room.players, turns: room.turns, chains: room.chains, deadline: room.deadline, settings: room.settings, ratings: ratings, podiumTieRanks: ranks)
        }
    }
    public func voteDrawingTime(roomID: String, voterID: String, seconds: Int) async throws {
        guard [30, 50, 80, 120].contains(seconds) else { throw ServiceError.invalidPayload }
        let coin = Bool.random()
        try await mutate(roomID: roomID) { room in
            guard let room, room.phase == .lobby, room.players.contains(where: { $0.id == voterID }), let old = room.settings else { throw ServiceError.unauthorized }
            var votes = room.drawingTimeVotes ?? [:]
            votes[voterID] = seconds
            let count = Dictionary(grouping: votes.values, by: { $0 }).mapValues(\.count)
            let highest = count.values.max() ?? 0
            let leaders = count.filter { $0.value == highest }.keys.sorted()
            let tie = leaders.count > 1
            let chosen = tie ? (room.timeTieWinner.flatMap { leaders.contains($0) ? $0 : nil } ?? leaders[coin ? 0 : leaders.count - 1]) : (leaders.first ?? seconds)
            let settings = RoomSettings(playerLimit: old.playerLimit, writingSeconds: old.writingSeconds, drawingSeconds: Double(chosen))
            return RoomSnapshot(id: room.id, phase: .lobby, players: room.players, settings: settings, drawingTimeVotes: votes, timeTieWinner: tie ? chosen : nil)
        }
    }
    public func voteEarlyStart(roomID: String, voterID: String, start: Bool) async throws {
        let coin = Bool.random()
        try await mutate(roomID: roomID) { room in
            guard let room, room.phase == .lobby, room.players.count >= 2,
                  room.players.contains(where: { $0.id == voterID }), room.earlyStartDecision == nil else { throw ServiceError.invalidPayload }
            var votes = room.earlyStartVotes ?? [:]
            votes[voterID] = start
            let finished = room.players.allSatisfy { votes[$0.id] != nil }
            let yes = votes.values.filter { $0 }.count
            let no = votes.count - yes
            let tie = finished && yes == no
            let decision: Bool? = finished ? (tie ? coin : yes > no) : nil
            return RoomSnapshot(id: room.id, phase: .lobby, players: room.players, settings: room.settings,
                                drawingTimeVotes: room.drawingTimeVotes, timeTieWinner: room.timeTieWinner,
                                earlyStartVotes: votes, earlyStartTieWinner: tie ? coin : nil, earlyStartDecision: decision)
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

@MainActor public final class FirebaseMatchmakingService {
    private let database: Database
    private let rooms: FirebaseRoomService
    public init(database: Database) { self.database = database; rooms = FirebaseRoomService(database: database) }

    public func match(player: Player) async throws -> (roomID: String, deadline: Date) {
        let queue = database.reference().child("matchmaking").child("current")
        let now = Date().timeIntervalSince1970
        let old = (try await queue.getData().value as? [String: Any]) ?? [:]
        if let id = old["roomID"] as? String, let started = old["started"] as? TimeInterval,
           let snapshot = try? await database.reference().child("rooms").child(id).child("snapshot").getData(),
           let room = try? RoomSnapshotCodec.decode(snapshot.value as Any), room.phase == .lobby,
           room.players.count < (room.settings?.playerLimit ?? 8) {
            try await rooms.join(roomID: id, player: player)
            return (id, Date(timeIntervalSince1970: started + 80))
        }
        let candidate = String(UUID().uuidString.prefix(8)).uppercased()
        try await rooms.create(roomID: candidate, player: player,
                               settings: RoomSettings(playerLimit: 8, writingSeconds: 60, drawingSeconds: 80))
        let staleID = old["roomID"] as? String
        let chosen: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            queue.runTransactionBlock({ data in
                let current = data.value as? [String: Any]
                if current == nil || current?["roomID"] as? String == staleID {
                    data.value = ["roomID": candidate, "started": now]
                }
                return TransactionResult.success(withValue: data)
            }, andCompletionBlock: { error, committed, snapshot in
                if let error { continuation.resume(throwing: error) }
                else if !committed || snapshot == nil { continuation.resume(throwing: ServiceError.invalidResponse) }
                else { continuation.resume(returning: snapshot?.value as? [String: Any] ?? [:]) }
            }, withLocalEvents: false)
        }
        guard let id = chosen["roomID"] as? String,
              let started = chosen["started"] as? TimeInterval else { throw ServiceError.invalidResponse }
        if id != candidate { try await rooms.join(roomID: id, player: player) }
        return (id, Date(timeIntervalSince1970: started + 80))
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
        let ratio = min(1, 2048 / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let compressed = image.jpegData(compressionQuality: 0.82), compressed.count <= 2_000_000 else { throw ServiceError.invalidPayload }
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
              encoded.count <= 2_800_000, let data = Data(base64Encoded: encoded), !data.isEmpty,
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
    public static func matchmaking() throws -> FirebaseMatchmakingService {
        guard let app = FirebaseApp.app() else { throw ServiceError.configuration }
        return FirebaseMatchmakingService(database: try database(app: app))
    }
    public static func social() throws -> FirebaseSocialService {
        guard let app = FirebaseApp.app() else { throw ServiceError.configuration }
        return FirebaseSocialService(database: try database(app: app))
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
