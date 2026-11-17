import SwiftUI
import SwiftData

private enum Theme {
    static let accent = Color(red: 91/255, green: 200/255, blue: 245/255)
    static let aqua = Color(red: 69/255, green: 222/255, blue: 197/255)
    static let violet = Color(red: 128/255, green: 87/255, blue: 231/255)
    static let ink = Color(red: 32/255, green: 43/255, blue: 82/255)
    static let cream = Color(red: 0.88, green: 0.97, blue: 1)
}

private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.8)))
        }
    }
}

private extension View {
    func card() -> some View {
        padding(18).frame(maxWidth: .infinity, alignment: .leading).modifier(GlassCard())
    }
}

private struct OrangeButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(prominent ? .white : Theme.ink)
            .background(prominent ? LinearGradient(colors: [Theme.accent, Theme.aqua], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [.white.opacity(0.78), .white.opacity(0.58)], startPoint: .top, endPoint: .bottom), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.7)))
            .shadow(color: Theme.accent.opacity(prominent ? 0.25 : 0.07), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

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
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if let player = auth.player {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.nickname).font(.system(size: 23, weight: .black, design: .rounded))
                        Text(game.state == .drawing ? "Tu turno de dibujo" : game.state == .writing ? "Tu turno de frase" : "Partida en curso")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink.opacity(0.56))
                    }
                    Spacer(minLength: 8)
                    Button { album.cancelRecording(); game.leave(); auth.signOut() } label: {
                        Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(.white.opacity(0.8), in: Capsule())
                    }.fixedSize().accessibilityLabel("Cerrar sesión")
                }.card()
                gameContent
            } else {
                Spacer(minLength: 70)
                TextField("Apodo", text: $auth.nickname)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain).padding(18)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
                Button("Entrar") { Task { await auth.signIn() } }
                    .buttonStyle(OrangeButton(prominent: true))
                    .disabled(auth.state == .loading)
                if let message = auth.errorMessage { Text(message) }
            }
            if let message = game.errorMessage { Text(message).foregroundStyle(.red).card() }
            if let message = canvas.errorMessage { Text(message).foregroundStyle(.red).card() }
            Text(album.message).font(.subheadline).foregroundStyle(.secondary)
            Text("Álbumes guardados").font(.system(size: 27, weight: .black, design: .rounded))
            Button("Alternar historial UIKit") { showUIKitHistory.toggle() }
                .buttonStyle(OrangeButton())
            if showUIKitHistory { HistoryControllerView(albums: albums).frame(height: 300).card() }
            ForEach(albums) { album in
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
                }.card()
            }
          }
          .frame(maxWidth: 680).padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 45)
          .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                Theme.cream
                Circle().fill(Theme.accent.opacity(0.27)).frame(width: 330).blur(radius: 75).offset(x: 170, y: -280)
                Circle().fill(Theme.aqua.opacity(0.27)).frame(width: 320).blur(radius: 80).offset(x: -180, y: 260)
            }.ignoresSafeArea()
        }
        .foregroundStyle(Theme.ink)
        .scrollDismissesKeyboard(.interactively)
        .onDisappear {
            Task { await canvas.saveDraft() }
            game.leave()
            album.cancelRecording()
        }
    }

    @ViewBuilder private var gameContent: some View {
        switch game.state {
        case .idle: Text("Conecta una sala existente para comenzar.").font(.headline).card()
        case .loading: Text("Cargando sala…").font(.headline).card()
        case .lobby:
            Text("Lobby").font(.system(size: 30, weight: .black, design: .rounded))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(game.room?.players ?? []) { player in
                    Text(player.nickname).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                }
            }.card()
            Text("Sala: \(game.roomID)").font(.footnote.monospaced()).textSelection(.enabled).card()
            if game.isHost {
                Button("Iniciar partida") { Task { await game.start() } }
                    .buttonStyle(OrangeButton(prominent: true))
                    .disabled((game.room?.players.count ?? 0) < 2)
            }
        case .writing:
            countdown
            VStack(alignment: .leading, spacing: 15) {
                Text("Ronda \((game.activeTurn?.round ?? 0) + 1) de \(game.room?.players.count ?? 0)")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                if let url = game.previousEntry?.drawingURL { DrawingPreview(url: url, album: album) }
                Text(game.activeTurn?.round == 0 ? "Escribe tu frase" : "Describe el dibujo").font(.headline)
                TextField("Frase", text: $game.sentence).textFieldStyle(.plain).padding(16)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 17))
                Button("Enviar frase") { Task { await game.submitWriting() } }
                    .buttonStyle(OrangeButton(prominent: true)).disabled(!game.canSubmit)
            }.card()
        case .drawing:
            countdown
            Text(game.previousEntry?.text ?? "Sin frase: el turno anterior quedó vacío.")
                .font(.system(size: 25, weight: .bold, design: .rounded)).card()
            if let turn = game.activeTurn, let room = game.room {
                CanvasSurface(drawingData: $canvas.drawingData, tool: canvas.tool,
                              width: canvas.width, undoToken: canvas.undoToken,
                              onPoints: { canvas.capture(points: $0) }, onError: canvas.report)
                    .frame(height: 320).background(.white, in: RoundedRectangle(cornerRadius: 22))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .task(id: turn.id) { await canvas.open(roomID: room.id, turnID: turn.id) }
                    .disabled(game.timeExpired || game.submitting || canvas.state == .loading || canvas.state == .error)
                HStack {
                    Button("Lápiz") { canvas.tool = .pen }
                    Button("Borrador") { canvas.tool = .eraser }
                    Button("Deshacer") { canvas.undo() }
                }.buttonStyle(.bordered).tint(Theme.violet)
                Button("Guardar en Fotos") { Task { await canvas.saveToPhotos() } }
                    .buttonStyle(OrangeButton())
                Button("Enviar dibujo") {
                    Task {
                        do { try await game.submitDrawing(png: canvas.pngData()) }
                        catch { canvas.report(error) }
                    }
                }.buttonStyle(OrangeButton(prominent: true)).disabled(!game.canSubmit)
            } else { Text("Esperando asignación de dibujo.") }
        case .revealing:
            Text("Álbum final").font(.system(size: 30, weight: .black, design: .rounded))
            ForEach(game.room?.chains ?? []) { chain in
                VStack {
                    Text("Cadena \(chain.id)")
                    ForEach(chain.entries) { entry in
                        Text(entry.text ?? "Dibujo de \(entry.authorID)")
                        if let url = entry.drawingURL { DrawingPreview(url: url, album: album) }
                        if let url = entry.audioURL { Text(url.absoluteString) }
                    }
                }.card()
            }
            if let room = game.room {
                Button("Grabar reacción") { Task { await album.startRecording(roomID: room.id) } }
                    .buttonStyle(OrangeButton())
                    .disabled(album.recording || album.busy)
                Button("Terminar y subir reacción") { Task { await album.stopAndUpload() } }
                    .buttonStyle(OrangeButton())
                    .disabled(!album.recording || album.busy)
                Button("Guardar álbum offline") { Task { await album.archive(room: room, context: modelContext) } }
                    .buttonStyle(OrangeButton(prominent: true))
                    .disabled(album.busy || album.recording)
            }
        case .error:
            Text("No se pudo sincronizar la partida.").card()
            Button("Salir de sala") { game.leave() }.buttonStyle(OrangeButton(prominent: true))
        }
    }

    private var countdown: some View {
        HStack {
            Text(game.timeExpired ? "Tiempo agotado. Esperando al servidor." : "Segundos: \(game.remainingSeconds)")
                .font(.headline)
            Spacer()
            CountdownView(deadline: game.room?.deadline).frame(width: 64, height: 64)
        }.card()
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
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .task(id: url) {
            data = nil
            do { let result = try await album.loadMedia(url); try Task.checkCancellation(); data = result }
            catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
}
