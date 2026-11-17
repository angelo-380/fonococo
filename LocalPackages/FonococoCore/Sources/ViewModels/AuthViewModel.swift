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

    public func signIn(email: String, password: String) async {
        guard state != .loading else { return }
        guard let service = service as? any EmailAuthServicing else { fail("El inicio con correo requiere Firebase configurado."); return }
        state = .loading; errorMessage = nil
        do { player = try await service.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password); state = .lobby }
        catch { fail(error.localizedDescription) }
    }

    public func createAccount(email: String, password: String, nickname: String) async {
        guard state != .loading else { return }
        guard let service = service as? any EmailAuthServicing else { fail("El registro requiere Firebase configurado."); return }
        state = .loading; errorMessage = nil
        do { player = try await service.createAccount(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, nickname: nickname); state = .lobby }
        catch { fail(error.localizedDescription) }
    }

    /// Creates a clearly local profile for UI demonstrations when Firebase is unavailable.
    public func playAsLocalGuest(nickname: String) {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { fail("Escribe un apodo."); return }
        let profile = Player(id: "local-\(UUID().uuidString)", nickname: name)
        player = profile
        self.nickname = name
        errorMessage = nil
        state = .lobby
    }

    public func restoreLocalGuest(_ player: Player) {
        self.player = player
        nickname = player.nickname
        errorMessage = nil
        state = .lobby
    }

    public func updateLocalNickname(_ nickname: String) {
        guard let current = player else { return }
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        player = Player(id: current.id, nickname: name)
        self.nickname = name
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
