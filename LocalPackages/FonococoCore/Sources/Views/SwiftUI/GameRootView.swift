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
    @State private var brushColor: Color = .black
    @State private var brushSize: Double = 3
    @State private var showColorDisc = false
    @State private var recordPulse = false
    @State private var podiumCoinRotation = 0.0
    @State private var podiumRevealed = false

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
                    Button { album.cancelRecording(); game.leave() } label: {
                        Label("Salir de sala", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
                    }.accessibilityLabel("Salir de partida")

                }.card()
                if game.hasSubmittedCurrentTurn, game.state == .drawing || game.state == .writing {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.accent)
                        Text(game.state == .drawing ? "Dibujo enviado correctamente" : "Frase enviada")
                            .font(.title2.bold())
                        Text("Esperando a los demás jugadores…").font(.subheadline)
                    }.frame(maxWidth: .infinity).padding(32).card()
                } else if game.state == .revealing && game.allRatingsComplete { podiumScreen }
                else { gameContent }
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
            if let message = canvas.photoMessage { Text(message).font(.subheadline).card() }
            Text(album.message).font(.subheadline).foregroundStyle(.secondary)
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
        .overlay {
            if game.submissionFeedback != nil || game.submitting {
                ZStack {
                    Theme.cream.ignoresSafeArea()
                    VStack(spacing: 18) {
                        if let feedback = game.submissionFeedback {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 72)).foregroundStyle(Theme.accent)
                            Text(feedback)
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .multilineTextAlignment(.center)
                        } else {
                            ProgressView().controlSize(.large)
                            Text(game.state == .drawing ? "Enviando dibujo…" : "Enviando frase…")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                        }
                    }.padding(28)
                }
            }
        }
        .onChange(of: game.timeExpired) { _, expired in
            if expired, game.state == .drawing, let png = try? canvas.pngData() {
                Task { await game.autoSubmitDrawing(png: png) }
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
                              width: canvas.width, color: UIColor(brushColor), undoToken: canvas.undoToken, redoToken: canvas.redoToken,
                              onPoints: { canvas.capture(points: $0) }, onError: canvas.report)
                    .frame(height: 320).background(.white, in: RoundedRectangle(cornerRadius: 22))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay {
                        if showColorDisc {
                            Color.clear.contentShape(Rectangle())
                                .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { showColorDisc = false } }
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if showColorDisc {
                            ColorDisc(color: $brushColor)
                                .frame(width: 280, height: 280)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                .scaleEffect(0.82)
                                .frame(width: 232, height: 232)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                                .padding(.leading, 12).padding(.bottom, 12)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    .task(id: turn.id) {
                        await canvas.open(roomID: room.id, turnID: turn.id)
                        if game.timeExpired, let png = try? canvas.pngData() {
                            await game.autoSubmitDrawing(png: png)
                        }
                    }
                    .disabled(game.timeExpired || game.submitting || canvas.state == .loading || canvas.state == .error)
                HStack {
                    Button { canvas.tool = .pencil } label: { Image(systemName: "pencil.tip").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Lápiz")
                    Button { canvas.tool = .pen } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Bolígrafo")
                    Button { canvas.tool = .marker } label: { Image(systemName: "highlighter").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Marcador")
                    Button { canvas.tool = .eraser } label: { Image(systemName: "eraser").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Borrador")
                }.buttonStyle(.bordered).tint(Theme.violet)
                HStack {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { showColorDisc.toggle() } } label: {
                        Circle().fill(brushColor).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                            .shadow(color: .black.opacity(0.2), radius: 3)
                    }.accessibilityLabel("Seleccionar color")
                    Slider(value: $brushSize, in: 1...40).tint(Theme.accent)
                    Text("\(Int(brushSize))").font(.caption.monospacedDigit())
                }.onChange(of: brushSize) { _, value in canvas.width = CGFloat(value) }
                HStack {
                    Button { canvas.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .accessibilityLabel("Deshacer")
                    Button { canvas.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .accessibilityLabel("Rehacer")
                }.buttonStyle(.bordered).tint(Theme.violet)
                Button { Task { await canvas.saveToPhotos() } } label: {
                    Label(canvas.photoSaved ? "Guardado en Fotos" : "Guardar en Fotos", systemImage: canvas.photoSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                }.buttonStyle(OrangeButton())
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
                VStack(alignment: .leading, spacing: 12) {
                    let index = (game.room?.chains.firstIndex(where: { $0.id == chain.id }) ?? 0) + 1
                    Label("Libro creativo \(index)", systemImage: "book.closed.fill")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                    ForEach(chain.entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(game.playersByID[entry.authorID]?.nickname ?? "Jugador")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink.opacity(0.55))
                            if let text = entry.text {
                                Text(text).font(.system(size: 19, weight: .bold, design: .rounded))
                            }
                            if let url = entry.drawingURL {
                                DrawingPreview(url: url, album: album)
                                if entry.authorID != game.currentPlayerID {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Calificar").font(.subheadline.bold())
                                        let selected = game.room?.ratings?[entry.id]?[game.currentPlayerID ?? ""] ?? -1
                                        HStack(spacing: 1) {
                                        ForEach(0...5, id: \.self) { stars in
                                            Button { Task { await game.rate(drawingID: entry.id, stars: stars) } } label: {
                                                Image(systemName: stars == 0 ? "star.slash" : (stars <= selected ? "star.fill" : "star"))
                                                    .font(.system(size: 23, weight: .semibold))
                                                    .foregroundStyle(stars > 0 && stars <= selected ? Color.yellow : Theme.ink.opacity(0.45))
                                                    .frame(minWidth: 44, minHeight: 48)
                                                    .contentShape(Rectangle())
                                            }.accessibilityLabel("\(stars) estrellas")
                                        }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 17))
                    }
                }.card()
            }
            if let room = game.room {
                if game.allRatingsComplete {
                    VStack(spacing: 10) {
                        Text("Podio").font(.title.bold())
                        ForEach(Array(game.ranking.prefix(3).enumerated()), id: \.offset) { place, result in
                            HStack { Text(["🥇", "🥈", "🥉"][place]); Text(result.0.nickname); Spacer(); Text("\(result.1) ★") }
                                .font(.headline).padding(12).background(.white.opacity(0.7), in: Capsule())
                        }
                    }.card()
                } else {
                    Text("Esperando las calificaciones de todos…").font(.subheadline).card()
                }
                Button("Guardar álbum offline") { Task { if let ownerID = auth.player?.id { await album.archive(room: room, ownerID: ownerID, context: modelContext) } } }
                    .buttonStyle(OrangeButton(prominent: true))
                    .disabled(album.busy)
            }
        case .error:
            Text("No se pudo sincronizar la partida.").card()
            Button("Salir de sala") { game.leave() }.buttonStyle(OrangeButton(prominent: true))
        }
    }

    private var podiumScreen: some View {
        let winners = Array(game.ranking.prefix(3))
        let order = winners.count == 2 ? [1, 0] : [1, 0, 2]
        let tied = zip(winners, winners.dropFirst()).contains { $0.0.1 == $0.1.1 }
        return VStack(spacing: 24) {
            Text("Podio final").font(.system(size: 34, weight: .black, design: .rounded))
            if tied {
                VStack(spacing: 6) {
                    Text("🪙").font(.system(size: 64))
                        .rotation3DEffect(.degrees(podiumCoinRotation), axis: (x: 0, y: 1, z: 0))
                    Text(podiumRevealed ? "La moneda decidió el orden" : "Moneda al aire…").font(.subheadline.bold())
                }.onAppear {
                    podiumRevealed = false
                    withAnimation(.easeOut(duration: 1.4)) { podiumCoinRotation = 1440 }
                    Task { try? await Task.sleep(for: .seconds(1.8)); podiumRevealed = true }
                }
            }
            if !tied || podiumRevealed { HStack(alignment: .bottom, spacing: 8) {
                ForEach(order, id: \.self) { place in
                    if winners.indices.contains(place) {
                        VStack(spacing: 8) {
                            Text(["🥇", "🥈", "🥉"][place]).font(.system(size: 40))
                            Text(winners[place].0.nickname).font(.subheadline.bold()).lineLimit(1)
                            Text("\(winners[place].1) ★").font(.headline)
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(colors: [Theme.accent.opacity(0.8), Theme.aqua.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                                .frame(height: place == 0 ? 190 : place == 1 ? 145 : 105)
                                .overlay(alignment: .top) { Text("\(place + 1)").font(.largeTitle.bold()).foregroundStyle(.white).padding(.top, 16) }
                        }.frame(maxWidth: .infinity)
                    }
                }
            } }
            if let room = game.room {
                Button("Guardar álbum offline") {
                    Task { if let ownerID = auth.player?.id { await album.archive(room: room, ownerID: ownerID, context: modelContext) } }
                }.buttonStyle(OrangeButton(prominent: true)).disabled(album.busy)
            }
            Button("Salir de sala") { game.leave() }.buttonStyle(OrangeButton())
        }.frame(maxWidth: .infinity).padding(22).card()
    }

    private var countdown: some View {
        VStack(spacing: 8) {
            CountdownView(deadline: game.room?.deadline).frame(width: 220, height: 78)
            if game.timeExpired {
                Text(game.state == .drawing ? "Tiempo agotado. Enviando dibujo…" : "Tiempo agotado. Esperando al servidor.")
                    .font(.subheadline)
            }
        }.frame(maxWidth: .infinity).card()
    }

}

private struct DrawingPreview: View {
    let url: URL
    let album: AlbumViewModel
    @State private var data: Data?
    @State private var message = "Cargando dibujo…"
    @State private var saved = false
    var body: some View {
        VStack {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .onLongPressGesture(minimumDuration: 1.5) {
                        Task {
                            do { try await PhotoLibrarySaver().save(image); saved = true }
                            catch { message = error.localizedDescription }
                        }
                    }
                    .overlay(alignment: .bottom) { if saved { Label("Guardado en Fotos", systemImage: "checkmark.circle.fill").padding(8).background(.regularMaterial, in: Capsule()) } }
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
