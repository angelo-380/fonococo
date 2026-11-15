import SwiftUI
import SwiftData

public struct GameRootView: View {
    @ObservedObject private var auth: AuthViewModel
    @ObservedObject private var game: GameViewModel
    @ObservedObject private var canvas: CanvasViewModel
    @ObservedObject private var album: AlbumViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchivedAlbum.completedAt, order: .reverse) private var albums: [ArchivedAlbum]

    @State private var showUIKitHistory = false

    public init(auth: AuthViewModel, game: GameViewModel, canvas: CanvasViewModel, album: AlbumViewModel) {
        self.auth = auth; self.game = game; self.canvas = canvas; self.album = album
    }

    public var body: some View {
        VStack {
            if let player = auth.player {
                Text(player.nickname)
                TextField("Identificador de sala", text: $game.roomID)
                Button("Crear sala") { Task { await game.create(player: player) } }
                Button("Conectar a sala") { game.connect(player: player) }
                Button("Cerrar sesión") { album.cancelRecording(); game.leave(); auth.signOut() }
                gameContent
            } else {
                TextField("Apodo", text: $auth.nickname)
                Button("Entrar") { Task { await auth.signIn() } }
                    .disabled(auth.state == .loading)
                if let message = auth.errorMessage { Text(message) }
            }
            if let message = game.errorMessage { Text(message) }
            if let message = canvas.errorMessage { Text(message) }
            Text(album.message)
            Button("Alternar historial UIKit") { showUIKitHistory.toggle() }
            if showUIKitHistory { HistoryControllerView(albums: albums) }
            Text("Álbumes guardados")
            List(albums) { album in
                VStack {
                    Text(album.title)
                    Text(album.completedAt.formatted())
                    if let payload = try? album.decode(OfflineAlbumPayload.self) {
                        Text("Archivos disponibles offline: \(payload.media.count)")
                        ForEach(payload.room.chains) { chain in
                            ForEach(chain.entries) { entry in
                                Text(entry.text ?? "Dibujo de \(entry.authorID)")
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            Task { await canvas.saveDraft() }
            game.leave()
            album.cancelRecording()
        }
    }

    @ViewBuilder private var gameContent: some View {
        switch game.state {
        case .idle: Text("Conecta una sala existente para comenzar.")
        case .loading: Text("Cargando sala…")
        case .lobby:
            Text("Lobby")
            List(game.room?.players ?? []) { player in Text(player.nickname) }
            Text("Sala: \(game.roomID)")
            if game.isHost {
                Button("Iniciar partida") { Task { await game.start() } }
                    .disabled((game.room?.players.count ?? 0) < 2)
            }
        case .writing:
            countdown
            Text("Ronda \((game.activeTurn?.round ?? 0) + 1) de \(game.room?.players.count ?? 0)")
            if let url = game.previousEntry?.drawingURL { DrawingPreview(url: url, album: album) }
            Text(game.activeTurn?.round == 0 ? "Escribe tu frase" : "Describe el dibujo")
            TextField("Frase", text: $game.sentence)
            Button("Enviar frase") { Task { await game.submitWriting() } }.disabled(!game.canSubmit)
        case .drawing:
            countdown
            Text(game.previousEntry?.text ?? "Sin frase: el turno anterior quedó vacío.")
            if let turn = game.activeTurn, let room = game.room {
                CanvasSurface(drawingData: $canvas.drawingData, tool: canvas.tool,
                              width: canvas.width, undoToken: canvas.undoToken,
                              onPoints: { canvas.capture(points: $0) }, onError: canvas.report)
                    .task(id: turn.id) { await canvas.open(roomID: room.id, turnID: turn.id) }
                    .disabled(!game.canSubmit)
                Button("Lápiz") { canvas.tool = .pen }
                Button("Borrador") { canvas.tool = .eraser }
                Button("Deshacer") { canvas.undo() }
                Button("Guardar en Fotos") { Task { await canvas.saveToPhotos() } }
                Button("Enviar dibujo") {
                    Task {
                        do { try await game.submitDrawing(png: canvas.pngData()) }
                        catch { canvas.report(error) }
                    }
                }.disabled(!game.canSubmit)
            } else { Text("Esperando asignación de dibujo.") }
        case .revealing:
            Text("Álbum final")
            List(game.room?.chains ?? []) { chain in
                VStack {
                    Text("Cadena \(chain.id)")
                    ForEach(chain.entries) { entry in
                        Text(entry.text ?? "Dibujo de \(entry.authorID)")
                        if let url = entry.drawingURL { DrawingPreview(url: url, album: album) }
                        if let url = entry.audioURL { Text(url.absoluteString) }
                    }
                }
            }
            if let room = game.room {
                Button("Grabar reacción") { Task { await album.startRecording(roomID: room.id) } }
                    .disabled(album.recording || album.busy)
                Button("Terminar y subir reacción") { Task { await album.stopAndUpload() } }
                    .disabled(!album.recording || album.busy)
                Button("Guardar álbum offline") { Task { await album.archive(room: room, context: modelContext) } }
                    .disabled(album.busy || album.recording)
            }
        case .error:
            Text("No se pudo sincronizar la partida.")
            Button("Salir de sala") { game.leave() }
        }
    }

    private var countdown: some View {
        VStack {
            Text(game.timeExpired ? "Tiempo agotado. Esperando al servidor." : "Segundos: \(game.remainingSeconds)")
            CountdownView(deadline: game.room?.deadline)
        }
    }

}

private struct DrawingPreview: View {
    let url: URL
    let album: AlbumViewModel
    @State private var data: Data?
    @State private var message = "Cargando dibujo…"
    var body: some View {
        VStack {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else { Text(message) }
        }
        .task(id: url) {
            data = nil
            do { let result = try await album.loadMedia(url); try Task.checkCancellation(); data = result }
            catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
}
