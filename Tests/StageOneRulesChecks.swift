import Foundation

@main struct StageOneRulesChecks {
    static func main() {
        let names = (0..<5).map { StageOneRules.guestName(randomIndex: $0, number: 42) }
        assert(Set(names).count == 5)
        assert(names.allSatisfy { $0.range(of: "[0-9]{2}$", options: .regularExpression) != nil })

        assert(StageOneRules.usernameIsValid("Aero_Panda7"))
        assert(!StageOneRules.usernameIsValid("ab"))
        assert(!StageOneRules.usernameIsValid("not allowed"))
        assert(StageOneRules.usernameIsLocallyAvailable("NewName", existing: ["Existing"]))
        assert(!StageOneRules.usernameIsLocallyAvailable("existing", existing: ["Existing"]))

        assert(StageOneRules.playerLimits == Array(2...8))
        assert(StageOneRules.xpPerCompletedGame == 10)
        assert(StageOneRules.level(for: 0) == 1 && StageOneRules.xpWithinLevel(for: 0) == 0)
        assert(StageOneRules.level(for: 100) == 2 && StageOneRules.xpWithinLevel(for: 100) == 0)
        assert(StageOneRules.level(for: 245) == 3 && StageOneRules.xpWithinLevel(for: 245) == 45)

        let friends = [StageOneFriend(username: "NubeDibuja", nickname: "Nube", avatar: "🦊"), StageOneFriend(username: "PixelLima", nickname: "Mati", avatar: "🐸")]
        assert(StageOneRules.filterFriends(friends, query: "nube").map(\.username) == ["NubeDibuja"])
        assert(StageOneRules.filterFriends(friends, query: "MATI").map(\.username) == ["PixelLima"])
        assert(StageOneRules.filterFriends(friends, query: " ").count == 2)
        print("StageOneRules: guest names, username checks, XP, capacity choices and friend search passed")
    }
}
