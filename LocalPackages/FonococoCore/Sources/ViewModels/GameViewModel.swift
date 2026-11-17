import Combine
import Foundation

/// State and turn assignments come from our backend. No Gartic event names or rotation are assumed.
@MainActor public final class GameViewModel: ObservableObject {
    @Published public private(set) var state: GamePhase = .idle
    @Published public private(set) var room: RoomSnapshot?
    @Published public private(set) var playersByID: [String: Player] = [:]
    @Published public private(set) var remainingSeconds = 0
    @Published public private(set) var timeExpired = false
    @Published public private(set) var submitting = false
    @Published public private(set) var errorMessage: String?
    @Published public var roomID = ""
    @Published public var sentence = ""
    private let service: any RoomServicing
    private let storage: any MediaStorageServicing
    private var observation: Task<Void, Never>?
    private var advancing = false
    private var timer: Timer?
    private var generation = UUID()
    private var playerID: String?
    private var submittedTurnIDs = Set<String>()

    public init(service: any RoomServicing, storage: any MediaStorageServicing) {
        self.service = service
        self.storage = storage
    }

    public var isHost: Bool { room?.players.first?.id == playerID }
    public var previousEntry: ChainEntry? {
        guard let turn = activeTurn else { return nil }
        return room?.chains.first(where: { $0.id == turn.chainID })?.entries.last(where: { $0.id != turn.id })
    }
    public func create(player: Player, playerLimit: Int = 4, roomID customID: String? = nil) async {
        let id = customID ?? String(UUID().uuidString.prefix(6)).uppercased()
        do {
            try await service.create(roomID: id, player: player, settings: RoomSettings(playerLimit: min(8, max(2, playerLimit)), writingSeconds: 60, drawingSeconds: 90))
            roomID = id; connect(player: player)
        } catch { fail(error.localizedDescription) }
    }
    public func start() async {
        guard let room, let playerID, isHost else { return }
        do { try await service.start(roomID: room.id, playerID: playerID) }
        catch { errorMessage = error.localizedDescription }
    }

    public func updatePlayerLimit(_ limit: Int) async {
        guard let room, let playerID, isHost, room.phase == .lobby,
              (2...8).contains(limit), limit >= room.players.count else { return }
        do { try await service.updatePlayerLimit(roomID: room.id, playerID: playerID, limit: limit) }
        catch { errorMessage = error.localizedDescription }
    }

    public var activeTurn: GameTurn? {
        guard let playerID else { return nil }
        return room?.turns.filter {
            $0.playerID == playerID && (($0.kind == .writing && state == .writing) || ($0.kind == .drawing && state == .drawing))
        }.max(by: { $0.round < $1.round })
    }

    public var canSubmit: Bool {
        guard let turn = activeTurn else { return false }
        return !submitting && !timeExpired && !submittedTurnIDs.contains(turn.id) && !(room?.chains.flatMap(\.entries).contains(where: { $0.id == turn.id }) ?? false)
    }

    public func connect(player: Player) {
        let id = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { fail("Escribe el identificador de una sala provisionada por el backend."); return }
        leave()
        roomID = id
        playerID = player.id
        state = .loading
        let token = generation
        observation = Task { [weak self, service] in
            do {
                try await service.join(roomID: id, player: player)
                guard !Task.isCancelled else { return }
                let stream = service.observe(roomID: id)
                for try await snapshot in stream {
                    guard !Task.isCancelled else { return }
                    guard let self, self.generation == token else { return }
                    self.apply(snapshot)
                }
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.fail("La sincronización de la sala terminó. Vuelve a conectarte.")
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func apply(_ snapshot: RoomSnapshot) {
        guard snapshot.id == roomID,
              Set(snapshot.players.map(\.id)).count == snapshot.players.count,
              Set(snapshot.turns.map(\.id)).count == snapshot.turns.count,
              Set(snapshot.chains.map(\.id)).count == snapshot.chains.count else {
            fail("El servidor devolvió una sala inconsistente."); return
        }
        switch snapshot.phase {
        case .lobby, .writing, .drawing, .revealing:
            room = snapshot
            playersByID = Dictionary(uniqueKeysWithValues: snapshot.players.map { ($0.id, $0) })
            state = snapshot.phase
            errorMessage = nil
            updateDeadline()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateDeadline() }
            }
        case .idle, .loading, .error:
            fail("El backend no ha publicado una fase de partida válida.")
        }
    }

    private func updateDeadline() {
        guard let deadline = room?.deadline, state == .writing || state == .drawing else {
            remainingSeconds = 0; timeExpired = false; return
        }
        remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        timeExpired = remainingSeconds == 0
        if timeExpired, !advancing, let roomID = room?.id {
            advancing = true
            let token = generation
            Task { [weak self, service] in
                do { try await service.advance(roomID: roomID) }
                catch { if self?.generation == token { self?.errorMessage = error.localizedDescription } }
                if self?.generation == token { self?.advancing = false }
            }
        }
    }

    public func submitWriting() async {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == .writing, !text.isEmpty else { return }
        await submit(text: text, png: nil)
    }

    public func submitDrawing(png: Data) async {
        guard state == .drawing, !png.isEmpty else { return }
        await submit(text: nil, png: png)
    }

    private func submit(text: String?, png: Data?) async {
        guard canSubmit, let turn = activeTurn, let playerID, let room else { return }
        let token = generation
        submitting = true
        defer { if generation == token { submitting = false } }
        do {
            var drawingURL: URL?
            if let png { drawingURL = try await storage.uploadPNG(png, roomID: room.id) }
            guard generation == token, activeTurn?.id == turn.id, !timeExpired else { return }
            let entry = ChainEntry(id: turn.id, authorID: playerID, text: text, drawingURL: drawingURL, audioURL: nil)
            try await service.submit(roomID: room.id, entry: entry, turnID: turn.id)
            guard generation == token else { return }
            submittedTurnIDs.insert(turn.id)
            sentence = ""
        } catch {
            guard generation == token else { return }
            // Keep the server phase so the user can retry without losing the draft.
            errorMessage = error.localizedDescription
        }
    }

    public func leave() {
        generation = UUID()
        observation?.cancel(); observation = nil
        timer?.invalidate(); timer = nil
        room = nil; playerID = nil; playersByID = [:]
        submittedTurnIDs.removeAll(); sentence = ""
        remainingSeconds = 0; timeExpired = false; submitting = false; advancing = false
        errorMessage = nil; state = .idle
    }

    private func fail(_ message: String) { errorMessage = message; state = .error; timer?.invalidate() }
    deinit { observation?.cancel(); timer?.invalidate() }
}
