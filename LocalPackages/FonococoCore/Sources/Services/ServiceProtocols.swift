import Foundation

public enum ServiceError: LocalizedError {
    case configuration, invalidIdentifier, invalidPayload, missingRoom, unauthorized, http(Int), invalidResponse, permissionDenied, recordingFailed
    public var errorDescription: String? {
        switch self {
        case .configuration: return "El servicio aún no está configurado."
        case .invalidIdentifier: return "El identificador no es válido."
        case .invalidPayload: return "Los datos no son válidos."
        case .missingRoom: return "No se encontró la sala."
        case .unauthorized: return "Inicia sesión para continuar."
        case .http(let status): return "El servidor respondió con código \(status)."
        case .invalidResponse: return "La respuesta del servidor no es válida."
        case .permissionDenied: return "No se concedió el permiso requerido."
        case .recordingFailed: return "No se pudo grabar el audio."
        }
    }
}
@MainActor public protocol AuthServicing {
    func signInAnonymously() async throws -> Player
    func signOut() throws
}
@MainActor public protocol RoomServicing {
    func create(roomID: String, player: Player, settings: RoomSettings) async throws
    func join(roomID: String, player: Player) async throws
    func start(roomID: String, playerID: String) async throws
    func advance(roomID: String) async throws
    func observe(roomID: String) -> AsyncThrowingStream<RoomSnapshot, Error>
    func submit(roomID: String, entry: ChainEntry, turnID: String) async throws
}
@MainActor public protocol MediaStorageServicing {
    func download(_ url: URL) async throws -> Data
    func uploadPNG(_ data: Data, roomID: String) async throws -> URL
    func uploadAudio(fileURL: URL, roomID: String) async throws -> URL
}
public protocol ContentServicing {
    func randomPhrase() async throws -> Phrase
    func avatars() async throws -> [Avatar]
}
func validateIdentifier(_ value: String) throws {
    guard !value.isEmpty, value.utf8.count <= 128,
          value.rangeOfCharacter(from: CharacterSet(charactersIn: ".#$[]/\n\r")) == nil else {
        throw ServiceError.invalidIdentifier
    }
}
