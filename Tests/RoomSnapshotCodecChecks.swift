import Foundation
@main struct CodecChecks {
 static func main() throws {
  let player = Player(id: "p0", nickname: "Prueba")
  let lobby = RoomSnapshot(id: "room", phase: .lobby, players: [player], settings: RoomSettings(playerLimit: 12, writingSeconds: 60, drawingSeconds: 90))
  let encoded = try RoomSnapshotCodec.encode(lobby)
  assert(encoded["turns"] == nil && encoded["chains"] == nil)
  assert(encoded["players"] is [String: Any])
  let decoded = try RoomSnapshotCodec.decode(encoded)
  assert(decoded.players.first?.id == "p0" && decoded.turns.isEmpty)
  let entry = ChainEntry(id: "turn", authorID: "p0")
  let room = RoomSnapshot(id: "room", phase: .drawing, players: [player], chains: [GameChain(id: "p0", entries: [entry]), GameChain(id: "empty")], deadline: Date(timeIntervalSince1970: 1234))
  let roundtrip = try RoomSnapshotCodec.decode(RoomSnapshotCodec.encode(room))
  assert(roundtrip.chains.count == 2 && roundtrip.chains[1].entries.isEmpty)
  assert(roundtrip.chains[0].entries[0].text == nil && roundtrip.deadline == room.deadline)
  var legacy = encoded
  legacy["players"] = ["0": ["id": "p0", "nickname": "Prueba"]]
  legacy["chains"] = NSNull()
  let countMap = try RoomSnapshotCodec.decode(legacy).players.count
  assert(countMap == 1)
  legacy["players"] = [["id": "p0", "nickname": "Prueba"]]
  let countArray = try RoomSnapshotCodec.decode(legacy).players.count
  assert(countArray == 1)
  print("Codec: lobby, empty collections, ordered maps, legacy arrays, deadline and empty timeout entries passed")
 }
}
