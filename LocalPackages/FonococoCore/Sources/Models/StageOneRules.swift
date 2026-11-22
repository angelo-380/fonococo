import Foundation

/// Small deterministic rules shared by the Stage 1 UI and its local checks.
public enum StageOneRules {
    public static let playerLimits = Array(2...8)
    public static let xpPerLevel = 100
    public static let xpPerCompletedGame = 10

    public static func guestName(randomIndex: Int, number: Int) -> String {
        let names = ["PandaPixel", "BurbujaMax", "NinjaDoodle", "AeroPanda", "PincelVeloz"]
        return "\(names[((randomIndex % names.count) + names.count) % names.count])\(abs(number) % 90 + 10)"
    }

    public static func usernameIsValid(_ username: String) -> Bool {
        username.range(of: "^[A-Za-z0-9_]{3,18}$", options: .regularExpression) != nil
    }

    public static func usernameIsLocallyAvailable(_ username: String, existing: [String]) -> Bool {
        !existing.contains { $0.caseInsensitiveCompare(username) == .orderedSame }
    }

    public static func level(for totalXP: Int) -> Int { max(1, totalXP / xpPerLevel + 1) }
    public static func xpWithinLevel(for totalXP: Int) -> Int { max(0, totalXP) % xpPerLevel }

    public static func filterFriends(_ friends: [StageOneFriend], query: String) -> [StageOneFriend] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return friends }
        return friends.filter { $0.username.localizedCaseInsensitiveContains(text) || $0.nickname.localizedCaseInsensitiveContains(text) }
    }
}

public struct StageOneFriend: Identifiable, Codable, Equatable, Sendable {
    public var id: String { username }
    public let username: String
    public let nickname: String
    public let avatar: String
    public let avatarImageData: String?
    public let gamesPlayed: Int?
    public let gamesWon: Int?
    public let level: Int?
    public let drawings: Int?
    public let guesses: Int?
    public let xp: Int?
    public let creativeStreak: Int?
    public init(username: String, nickname: String, avatar: String, avatarImageData: String? = nil,
                gamesPlayed: Int? = nil, gamesWon: Int? = nil, level: Int? = nil,
                drawings: Int? = nil, guesses: Int? = nil, xp: Int? = nil, creativeStreak: Int? = nil) {
        self.username = username; self.nickname = nickname; self.avatar = avatar; self.avatarImageData = avatarImageData
        self.gamesPlayed = gamesPlayed; self.gamesWon = gamesWon; self.level = level
        self.drawings = drawings; self.guesses = guesses; self.xp = xp; self.creativeStreak = creativeStreak
    }
}
