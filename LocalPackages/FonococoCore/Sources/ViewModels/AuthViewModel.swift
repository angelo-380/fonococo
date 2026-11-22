import Combine
import Foundation

@MainActor public final class AuthViewModel: ObservableObject {
    @Published public private(set) var state: GamePhase = .idle
    @Published public private(set) var player: Player?
    @Published public private(set) var errorMessage: String?
    @Published public var nickname = ""
    private let service: any AuthServicing

    public init(service: any AuthServicing) { self.service = service }
    public var isGoogleLinked: Bool { (service as? any GoogleAuthServicing)?.isGoogleLinked ?? false }

    public func restoreSession() async {
        guard player == nil, state != .loading,
              let service = service as? any SessionRestoringAuthServicing else { return }
        state = .loading
        errorMessage = nil
        do {
            if let restored = try await service.restoreSession() {
                player = restored
                nickname = restored.nickname
                state = .lobby
            } else {
                state = .idle
            }
        } catch { fail(error.localizedDescription) }
    }

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

    /// Enters the app as a local guest when Firebase anonymous auth is unavailable.
    public func signInAsGuest(nickname: String) async {
        guard state != .loading else { return }
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { fail("No se pudo generar el apodo de invitado."); return }
        state = .loading
        errorMessage = nil
        do {
            let identity = try await service.signInAnonymously()
            player = Player(id: identity.id, nickname: name)
            self.nickname = name
            state = .lobby
        } catch {
            playAsLocalGuest(nickname: name)
        }
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
    public func updateNickname(_ nickname: String) async throws {
        guard let service = service as? any EmailAuthServicing else { throw ServiceError.configuration }
        let updated = try await service.updateNickname(nickname)
        player = updated
        self.nickname = updated.nickname
    }
    public func sendPasswordReset(to email: String) async throws {
        guard let service = service as? any EmailAuthServicing else { throw ServiceError.configuration }
        try await service.sendPasswordReset(to: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    public func changePassword(current: String, new: String) async throws {
        guard let service = service as? any EmailAuthServicing else { throw ServiceError.configuration }
        try await service.changePassword(current: current, new: new)
    }
    public func signInWithGoogle() async {
        guard let service = service as? any GoogleAuthServicing else { fail("Google requiere Firebase configurado."); return }
        state = .loading; errorMessage = nil
        do { player = try await service.signInWithGoogle(); state = .lobby }
        catch { fail(error.localizedDescription) }
    }
    @discardableResult public func linkGoogleToCurrentUser() async throws -> Player {
        guard let service = service as? any GoogleAuthServicing else { throw ServiceError.configuration }
        guard let current = player else { throw ServiceError.unauthorized }
        let linked = try await service.linkGoogleToCurrentUser()
        let active = Player(id: linked.id, nickname: current.nickname)
        player = active
        return active
    }
    public func handleGoogleURL(_ url: URL) -> Bool {
        (service as? any GoogleAuthServicing)?.handleGoogleURL(url) ?? false
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
