import Foundation

/// RTDB removes empty collections and can return indexed collections as maps or arrays.
/// Stable nonnumeric keys keep ordering without relying on Firebase's array heuristics.
public enum RoomSnapshotCodec {
    public static func encode(_ room: RoomSnapshot) throws -> [String: Any] {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let json = try JSONSerialization.jsonObject(with: encoder.encode(room))
        guard let result = pack(json) as? [String: Any] else { throw ServiceError.invalidPayload }
        return result
    }
    public static func decode(_ value: Any) throws -> RoomSnapshot {
        guard var object = value as? [String: Any] else { throw ServiceError.missingRoom }
        for key in ["players", "turns", "chains"] { object[key] = try collection(object[key]) }
        var chains = object["chains"] as? [[String: Any]] ?? []
        for i in chains.indices { chains[i]["entries"] = try collection(chains[i]["entries"]) }
        object["chains"] = chains
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let room = try decoder.decode(RoomSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        guard Set(room.players.map(\.id)).count == room.players.count,
              Set(room.turns.map(\.id)).count == room.turns.count,
              Set(room.chains.map(\.id)).count == room.chains.count else { throw ServiceError.invalidPayload }
        return room
    }
    private static func collection(_ value: Any?) throws -> [Any] {
        guard let value, !(value is NSNull) else { return [] }
        if let array = value as? [Any] { return array.filter { !($0 is NSNull) } }
        guard let map = value as? [String: Any] else { throw ServiceError.invalidPayload }
        guard map.keys.allSatisfy({ $0.hasPrefix("item") ? Int($0.dropFirst(4)) != nil : Int($0) != nil }) else { throw ServiceError.invalidPayload }
        return map.keys.sorted { index($0) < index($1) }.compactMap { map[$0] }.filter { !($0 is NSNull) }
    }
    private static func index(_ key: String) -> Int { Int(key.hasPrefix("item") ? String(key.dropFirst(4)) : key) ?? 0 }
    private static func pack(_ value: Any) -> Any? {
        if value is NSNull { return nil }
        if let array = value as? [Any] {
            guard !array.isEmpty else { return nil }
            return Dictionary(uniqueKeysWithValues: array.enumerated().compactMap { i, value in
                pack(value).map { (String(format: "item%06d", i), $0) }
            })
        }
        if let map = value as? [String: Any] {
            let result = map.compactMapValues(pack)
            return result.isEmpty ? nil : result
        }
        return value
    }
}
