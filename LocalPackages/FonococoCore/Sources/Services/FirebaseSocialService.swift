import Foundation
import FirebaseCore
import FirebaseDatabase
import CryptoKit

public struct SocialProfile: Sendable {
    public let userID: String
    public let nickname: String
    public let avatar: String
    public let avatarImageData: String?
    public let gamesPlayed: Int
    public let gamesWon: Int
    public let level: Int
    public let xp: Int
    public let drawings: Int
    public let guesses: Int
    public let creativeStreak: Int
}

public struct GameInvite: Identifiable, Sendable {
    public let id: String
    public let roomID: String
    public let hostID: String
    public let hostNickname: String
}

@MainActor public final class FirebaseSocialService {
    private let root: DatabaseReference
    public init(database: Database) { root = database.reference() }

    public static func friendCode(for userID: String) -> String {
        let digest = SHA256.hash(data: Data(userID.utf8))
        return digest.prefix(4).map { String(format: "%02X", $0) }.joined()
    }

    public func register(userID: String, nickname: String, avatar: String, avatarImageData: String?,
                         gamesPlayed: Int, gamesWon: Int, level: Int, xp: Int = 0,
                         drawings: Int = 0, guesses: Int = 0, creativeStreak: Int = 0) async throws {
        try validateIdentifier(userID)
        let code = Self.friendCode(for: userID)
        let reference = root.child("friendCodes").child(code)
        let snapshot = try await reference.getData()
        if let existing = snapshot.value as? [String: String], existing["userID"] != userID {
            throw ServiceError.invalidIdentifier
        }
        var profile: [String: Any] = ["nickname": nickname, "avatar": avatar,
                                      "gamesPlayed": gamesPlayed, "gamesWon": gamesWon, "level": level,
                                      "xp": xp, "drawings": drawings, "guesses": guesses,
                                      "creativeStreak": creativeStreak]
        if let avatarImageData { profile["avatarImageData"] = avatarImageData }
        try await root.updateChildValues([
            "friendCodes/\(code)": ["userID": userID, "nickname": nickname],
            "profiles/\(userID)": profile
        ])
    }

    public func requestFriend(code: String, from userID: String, nickname: String) async throws -> String {
        try validateIdentifier(userID)
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count == 8, clean.allSatisfy(\.isHexDigit) else { throw ServiceError.invalidIdentifier }
        let snapshot = try await root.child("friendCodes").child(clean).getData()
        guard let info = snapshot.value as? [String: String], let target = info["userID"], target != userID else { throw ServiceError.invalidIdentifier }
        try validateIdentifier(target)
        try await root.child("friendRequests").child(target).child(userID)
            .setValue(["nickname": nickname, "code": Self.friendCode(for: userID)])
        return info["nickname"] ?? "Jugador"
    }
    public func profileIfExists(userID: String) async throws -> SocialProfile? {
        try validateIdentifier(userID)
        let snapshot = try await root.child("profiles").child(userID).getData()
        if !snapshot.exists() { return nil }
        guard let value = snapshot.value as? [String: Any], let nickname = value["nickname"] as? String else {
            throw ServiceError.invalidPayload
        }
        return SocialProfile(userID: userID, nickname: nickname, avatar: value["avatar"] as? String ?? "🫧",
                             avatarImageData: value["avatarImageData"] as? String,
                             gamesPlayed: value["gamesPlayed"] as? Int ?? 0,
                             gamesWon: value["gamesWon"] as? Int ?? 0,
                             level: value["level"] as? Int ?? 1,
                             xp: value["xp"] as? Int ?? 0,
                             drawings: value["drawings"] as? Int ?? 0,
                             guesses: value["guesses"] as? Int ?? 0,
                             creativeStreak: value["creativeStreak"] as? Int ?? 0)
    }
    public func sendGameInvite(to targetID: String, from hostID: String, nickname: String, roomID: String) async throws {
        try validateIdentifier(targetID); try validateIdentifier(hostID); try validateIdentifier(roomID)
        try await root.child("gameInvites").child(targetID).child(roomID)
            .setValue(["hostID": hostID, "hostNickname": nickname, "roomID": roomID])
    }
    public func gameInvites(userID: String) async throws -> [GameInvite] {
        try validateIdentifier(userID)
        let snapshot = try await root.child("gameInvites").child(userID).getData()
        let values = snapshot.value as? [String: [String: String]] ?? [:]
        return values.compactMap { roomID, value in
            guard let hostID = value["hostID"], let nickname = value["hostNickname"] else { return nil }
            return GameInvite(id: roomID, roomID: roomID, hostID: hostID, hostNickname: nickname)
        }.sorted { $0.roomID < $1.roomID }
    }
    public func removeGameInvite(userID: String, roomID: String) async throws {
        try validateIdentifier(userID); try validateIdentifier(roomID)
        try await root.child("gameInvites").child(userID).child(roomID).removeValue()
    }
    public func profile(userID: String) async throws -> SocialProfile {
        guard let value = try await profileIfExists(userID: userID) else { throw ServiceError.invalidPayload }
        return value
    }
    public func incoming(userID: String) async throws -> [SocialProfile] {
        try validateIdentifier(userID)
        let snapshot = try await root.child("friendRequests").child(userID).getData()
        let values = snapshot.value as? [String: [String: String]] ?? [:]
        var result: [SocialProfile] = []
        for id in values.keys.sorted() { if let item = try? await profile(userID: id) { result.append(item) } }
        return result
    }
    public func friends(userID: String) async throws -> [SocialProfile] {
        try validateIdentifier(userID)
        let snapshot = try await root.child("friends").child(userID).getData()
        let values = snapshot.value as? [String: [String: String]] ?? [:]
        var result: [SocialProfile] = []
        for id in values.keys.sorted() { if let item = try? await profile(userID: id) { result.append(item) } }
        return result
    }
    public func accept(friendID: String, userID: String, nickname: String) async throws {
        try validateIdentifier(friendID); try validateIdentifier(userID)
        let request = root.child("friendRequests").child(userID).child(friendID)
        let snapshot = try await request.getData()
        guard let info = snapshot.value as? [String: String] else { throw ServiceError.invalidPayload }
        let friendName = info["nickname"] ?? "Jugador"
        try await root.updateChildValues([
            "friends/\(userID)/\(friendID)": ["nickname": friendName],
            "friends/\(friendID)/\(userID)": ["nickname": nickname],
            "friendRequests/\(userID)/\(friendID)": NSNull()
        ])
    }
    public func reject(friendID: String, userID: String) async throws {
        try validateIdentifier(friendID); try validateIdentifier(userID)
        try await root.child("friendRequests").child(userID).child(friendID).removeValue()
    }
}
