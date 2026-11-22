import Foundation

/// Fonococo rules. Round is zero-based: first phrase r=0, then book (i+r)%N.
public enum GameEngine {
    public static func podiumTieRanks(_ room: RoomSnapshot, ratings: [String: [String: Int]], coin: UInt64) -> [String: Int]? {
        let drawings = room.chains.flatMap(\.entries).filter { $0.drawingURL != nil }
        guard drawings.allSatisfy({ drawing in
            room.players.filter { $0.id != drawing.authorID }.allSatisfy { ratings[drawing.id]?[$0.id] != nil }
        }) else { return nil }
        func coinKey(_ id: String) -> UInt64 {
            id.utf8.reduce(coin) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
        let scores = room.players.map { player in
            (player.id, drawings.filter { $0.authorID == player.id }.reduce(0) { $0 + (ratings[$1.id]?.values.reduce(0, +) ?? 0) })
        }
        let sorted = scores.sorted { $0.1 == $1.1 ? coinKey($0.0) < coinKey($1.0) : $0.1 > $1.1 }
        return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($0.element.0, $0.offset) })
    }
    /// Gives an automatic drawing upload time to finish after the visible timer reaches zero.
    public static let drawingSubmissionGrace: TimeInterval = 15
    public static func start(_ room: RoomSnapshot, now: Date) throws -> RoomSnapshot {
        guard room.phase == .lobby, room.players.count >= 2,
              let settings = room.settings, room.players.count <= settings.playerLimit else { throw ServiceError.invalidPayload }
        return round(room, index: 0, chains: room.players.map { GameChain(id: $0.id) }, now: now)
    }
    public static func contribute(_ room: RoomSnapshot, entry: ChainEntry, turnID: String, now: Date) throws -> RoomSnapshot {
        guard let deadline = room.deadline,
              let turn = room.turns.first(where: { $0.id == turnID && $0.playerID == entry.authorID }),
              now < deadline.addingTimeInterval(turn.kind == .drawing ? drawingSubmissionGrace : 0),
              entry.id == turn.id else { throw ServiceError.invalidPayload }
        var chains = room.chains
        guard let index = chains.firstIndex(where: { $0.id == turn.chainID }) else { throw ServiceError.invalidPayload }
        if chains[index].entries.contains(where: { $0.id == turnID }) { return room }
        switch turn.kind {
        case .writing: guard entry.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, entry.drawingURL == nil else { throw ServiceError.invalidPayload }
        case .drawing: guard entry.drawingURL?.scheme == "rtdb-media", entry.text == nil else { throw ServiceError.invalidPayload }
        }
        chains[index].entries.append(entry)
        let updated = copy(room, chains: chains)
        return advance(updated, now: now)
    }
    public static func advance(_ room: RoomSnapshot, now: Date) -> RoomSnapshot {
        guard room.phase == .writing || room.phase == .drawing,
              let current = room.turns.first?.round else { return room }
        let ids = Set(room.chains.flatMap(\.entries).map(\.id))
        let complete = room.turns.allSatisfy { ids.contains($0.id) }
        let grace = room.phase == .drawing ? drawingSubmissionGrace : 0
        guard complete || (room.deadline.map { now >= $0.addingTimeInterval(grace) } ?? false) else { return room }
        var chains = room.chains
        for turn in room.turns where !ids.contains(turn.id) {
            if let index = chains.firstIndex(where: { $0.id == turn.chainID }) {
                chains[index].entries.append(ChainEntry(id: turn.id, authorID: turn.playerID))
            }
        }
        if current + 1 == room.players.count {
            return RoomSnapshot(id: room.id, phase: .revealing, players: room.players, chains: chains, settings: room.settings)
        }
        return round(room, index: current + 1, chains: chains, now: now)
    }
    private static func round(_ room: RoomSnapshot, index: Int, chains: [GameChain], now: Date) -> RoomSnapshot {
        let writing = index % 2 == 0
        let turns = room.players.enumerated().map { i, player in
            GameTurn(id: "r\(index)-p\(i)", playerID: player.id, chainID: room.players[(i + index) % room.players.count].id, round: index, kind: writing ? .writing : .drawing)
        }
        let seconds = writing ? room.settings?.writingSeconds : room.settings?.drawingSeconds
        return RoomSnapshot(id: room.id, phase: writing ? .writing : .drawing, players: room.players, turns: turns, chains: chains, deadline: now.addingTimeInterval(seconds ?? 60), settings: room.settings)
    }
    private static func copy(_ room: RoomSnapshot, chains: [GameChain]) -> RoomSnapshot {
        RoomSnapshot(id: room.id, phase: room.phase, players: room.players, turns: room.turns, chains: chains, deadline: room.deadline, settings: room.settings)
    }
}
