import SwiftUI
import SwiftData
import FonococoCore

@main
@MainActor
struct FonococoApp: App {
    var body: some Scene { WindowGroup { BootstrapView() } }
}

@MainActor
private struct BootstrapView: View {
    @State private var dependencies: Dependencies?
    @State private var message = "Cargando configuración…"
    var body: some View {
        VStack {
            if let dependencies {
                GameRootView(auth: dependencies.auth, game: dependencies.game, canvas: dependencies.canvas, album: dependencies.album)
                    .modelContainer(dependencies.albums)
            } else {
                Text(message)
                Button("Reintentar") { Task { await prepare() } }
            }
        }
        .task { await prepare() }
    }
    private func prepare() async {
        guard dependencies == nil else { return }
        do {
            try AppEnvironment.configureFirebase()
            let albums = try ModelContainer(for: ArchivedAlbum.self)
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true)
            let drafts = try await StrokeDraftStore.make(storeURL: directory.appendingPathComponent("StrokeDrafts.sqlite"))
            let auth = AuthViewModel(service: try FirebaseServiceFactory.auth())
            let game = GameViewModel(service: try FirebaseServiceFactory.rooms(), storage: try FirebaseServiceFactory.sessionMedia())
            dependencies = Dependencies(auth: auth, game: game, canvas: CanvasViewModel(drafts: drafts), album: AlbumViewModel(storage: try FirebaseServiceFactory.sessionMedia()), albums: albums)
        } catch { message = error.localizedDescription }
    }
}

@MainActor
private final class Dependencies {
    let auth: AuthViewModel
    let game: GameViewModel
    let canvas: CanvasViewModel
    let albums: ModelContainer
    let album: AlbumViewModel
    init(auth: AuthViewModel, game: GameViewModel, canvas: CanvasViewModel, album: AlbumViewModel, albums: ModelContainer) {
        self.auth = auth; self.game = game; self.canvas = canvas; self.album = album; self.albums = albums
    }
}
