import Foundation

/// Application states defined for Fonococo; these are not Gartic protocol events.
public enum GamePhase: String, Codable, Sendable {
    case idle, loading, lobby, writing, drawing, revealing, error
}
public struct Player: Identifiable, Codable, Sendable {
    public let id: String
    public var nickname: String
    public init(id: String, nickname: String) { self.id = id; self.nickname = nickname }
}
public struct GameTurn: Identifiable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case writing, drawing }
    public let id: String
    public let playerID: String
    public let chainID: String
    public let round: Int
    public let kind: Kind
    public init(id: String, playerID: String, chainID: String, round: Int, kind: Kind) {
        self.id = id; self.playerID = playerID; self.chainID = chainID; self.round = round; self.kind = kind
    }
}
public struct ChainEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let authorID: String
    public var text: String?
    public var drawingURL: URL?
    public var audioURL: URL?
    public init(id: String, authorID: String, text: String? = nil, drawingURL: URL? = nil, audioURL: URL? = nil) {
        self.id = id; self.authorID = authorID; self.text = text
        self.drawingURL = drawingURL; self.audioURL = audioURL
    }
}
public struct GameChain: Identifiable, Codable, Sendable {
    public let id: String
    public var entries: [ChainEntry]
    public init(id: String, entries: [ChainEntry] = []) { self.id = id; self.entries = entries }
}
public struct RoomSettings: Codable, Sendable {
    public let playerLimit: Int
    public let writingSeconds: TimeInterval
    public let drawingSeconds: TimeInterval
    public init(playerLimit: Int, writingSeconds: TimeInterval, drawingSeconds: TimeInterval) {
        self.playerLimit = playerLimit; self.writingSeconds = writingSeconds; self.drawingSeconds = drawingSeconds
    }
}
public struct RoomSnapshot: Identifiable, Codable, Sendable {
    public let id: String
    public let phase: GamePhase
    public let players: [Player]
    public let turns: [GameTurn]
    public let chains: [GameChain]
    public let deadline: Date?
    public let settings: RoomSettings?
    public let ratings: [String: [String: Int]]?
    public let drawingTimeVotes: [String: Int]?
    public let timeTieWinner: Int?
    public let podiumTieRanks: [String: Int]?
    public let earlyStartVotes: [String: Bool]?
    public let earlyStartTieWinner: Bool?
    public let earlyStartDecision: Bool?
    public init(id: String, phase: GamePhase, players: [Player] = [], turns: [GameTurn] = [], chains: [GameChain] = [], deadline: Date? = nil, settings: RoomSettings? = nil, ratings: [String: [String: Int]]? = nil, drawingTimeVotes: [String: Int]? = nil, timeTieWinner: Int? = nil, podiumTieRanks: [String: Int]? = nil, earlyStartVotes: [String: Bool]? = nil, earlyStartTieWinner: Bool? = nil, earlyStartDecision: Bool? = nil) {
        self.id = id; self.phase = phase; self.players = players; self.turns = turns
        self.chains = chains; self.deadline = deadline; self.settings = settings; self.ratings = ratings; self.drawingTimeVotes = drawingTimeVotes; self.timeTieWinner = timeTieWinner; self.podiumTieRanks = podiumTieRanks; self.earlyStartVotes = earlyStartVotes; self.earlyStartTieWinner = earlyStartTieWinner; self.earlyStartDecision = earlyStartDecision
    }
}
public struct Phrase: Codable, Sendable {
    public let text: String
    public init(text: String) { self.text = text }
}
public struct Avatar: Identifiable, Codable, Sendable {
    public let id: String
    public let url: URL
    public init(id: String, url: URL) { self.id = id; self.url = url }
}
