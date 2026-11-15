import Foundation
@main struct Checks {
 static func main() throws {
  for n in 2...8 {
   let players = (0..<n).map { Player(id: "p\($0)", nickname: "P\($0)") }
   let now = Date(timeIntervalSince1970: 1000)
   var room = try GameEngine.start(RoomSnapshot(id: "test", phase: .lobby, players: players, settings: RoomSettings(playerLimit: 12, writingSeconds: 60, drawingSeconds: 90)), now: now)
   for round in 0..<n {
    assert(room.turns.count == n)
    assert(Set(room.turns.map(\.chainID)).count == n)
    for (i, turn) in room.turns.enumerated() { assert(turn.chainID == players[(i+round)%n].id) }
    if round % 2 == 0 {
     let turns = room.turns
     for turn in turns {
      room = try GameEngine.contribute(room, entry: ChainEntry(id: turn.id, authorID: turn.playerID, text: "phrase"), turnID: turn.id, now: room.deadline!.addingTimeInterval(-1))
     }
    } else { room = GameEngine.advance(room, now: room.deadline!) }
   }
   assert(room.phase == .revealing)
   assert(room.chains.allSatisfy { $0.entries.count == n && Set($0.entries.map(\.authorID)).count == n })
  }
  print("GameEngine: N=2...8, rotation, completion, timeout and book authors passed")
 }
}
