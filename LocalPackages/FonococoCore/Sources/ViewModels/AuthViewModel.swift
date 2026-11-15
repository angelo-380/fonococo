import Combine
import Foundation

@MainActor public final class AuthViewModel: ObservableObject {
    @Published public private(set) var state: GamePhase = .idle
    @Published public private(set) var player: Player?
    @Published public private(set) var errorMessage: String?
    @Published public var nickname = ""
    private let service: any AuthServicing

    public init(service: any AuthServicing) { self.service = service }

    public func signIn() async {
        guard state != .loading else { return }
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { fail("Escribe un apodo."); return }
        state = .loading
        errorMessage = nil
        do {
            let identity = try await service.signInAnonymously()
            player = Player(id: identity.id, nickname: name)
            state = .lobby
        } catch { fail(error.localizedDescription) }
    }

    public func signOut() {
        do {
            try service.signOut()
            player = nil
            errorMessage = nil
            state = .idle
        } catch { fail(error.localizedDescription) }
    }

    private func fail(_ message: String) { errorMessage = message; state = .error }
}
