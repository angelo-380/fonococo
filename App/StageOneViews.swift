import SwiftUI
import PhotosUI
import UIKit
import FonococoCore

private enum Aero {
    static let sky = Color(red: 91/255, green: 200/255, blue: 245/255)
    static let aqua = Color(red: 69/255, green: 222/255, blue: 197/255)
    static let violet = Color(red: 128/255, green: 87/255, blue: 231/255)
    static let yellow = Color(red: 1, green: 211/255, blue: 105/255)
    static let coral = Color(red: 1, green: 120/255, blue: 153/255)
    static let ink = Color(red: 32/255, green: 43/255, blue: 82/255)
    static let backdrop = LinearGradient(colors: [Color(red: 0.84, green: 0.97, blue: 1), Color(red: 0.82, green: 1, blue: 0.94), Color(red: 0.92, green: 0.91, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct GameProfile: Codable, Equatable {
    var userID: String = ""
    var username = ""
    var nickname = ""
    var avatar = "🐼"
    var avatarImageData: String?
    var xp = 0
    var gamesPlayed = 0
    var gamesWon = 0
    var drawings = 0
    var guesses = 0
    var isGuest = true
    var level: Int { StageOneRules.level(for: xp) }
    var levelXP: Int { StageOneRules.xpWithinLevel(for: xp) }
    static func load() -> GameProfile {
        guard let data = UserDefaults.standard.data(forKey: "fonococo.profile.v1"), let value = try? JSONDecoder().decode(GameProfile.self, from: data) else { return GameProfile() }
        return value
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "fonococo.profile.v1") } }
}

private typealias DemoFriend = StageOneFriend

private enum MainTab: String, CaseIterable { case home = "Inicio", friends = "Amigos", profile = "Perfil" }
private enum AppSheet: String, Identifiable { case createRoom, waitingRoom, matchmaking, editProfile, addFriend, signup, login; var id: String { rawValue } }

public struct StageOneRootView: View {
    @ObservedObject private var auth: AuthViewModel
    @ObservedObject private var game: GameViewModel
    @ObservedObject private var canvas: CanvasViewModel
    @ObservedObject private var album: AlbumViewModel
    private let firebaseConfigured: Bool
    @State private var profile = GameProfile.load()
    @State private var selectedTab: MainTab = .home
    @State private var sheet: AppSheet?
    @State private var showJoin = false
    @State private var providerMessage = ""
    @State private var showProviderMessage = false
    @State private var roomCode = ""
    @State private var createdRoomName = ""
    @State private var booted = false
    @State private var friends = [DemoFriend(username: "NubeDibuja", nickname: "Nube", avatar: "🦊"), DemoFriend(username: "PixelLima", nickname: "Mati", avatar: "🐸")]
    @State private var incoming = [DemoFriend(username: "TintaLunar", nickname: "Luna", avatar: "🐱")]
    @State private var outgoingFriends: [DemoFriend] = []

    public init(auth: AuthViewModel, game: GameViewModel, canvas: CanvasViewModel, album: AlbumViewModel, firebaseConfigured: Bool = false) {
        self.auth = auth; self.game = game; self.canvas = canvas; self.album = album; self.firebaseConfigured = firebaseConfigured
    }

    public var body: some View {
        ZStack {
            Aero.backdrop.ignoresSafeArea()
            if !booted { SplashView { withAnimation(.spring(response: 0.65)) { booted = true } } }
            else if auth.player == nil { WelcomeView(auth: auth, configured: firebaseConfigured, onGuest: makeGuest, onSignup: { sheet = .signup }, onLogin: { sheet = .login }) }
            else if game.state == .writing || game.state == .drawing || game.state == .revealing {
                GameRootView(auth: auth, game: game, canvas: canvas, album: album)
                    .transition(.opacity)
            }
            else {
                NavigationStack {
                    Group {
                        switch selectedTab {
                        case .home: lobby
                        case .friends: friendsView
                        case .profile: profileView
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .tint(Aero.ink)
        .preferredColorScheme(.light)
        .sheet(item: $sheet) { route in sheetContent(route).presentationDetents(route == .waitingRoom ? [.large] : [.medium, .large]).presentationDragIndicator(.visible) }
        .alert("Unirse a una sala", isPresented: $showJoin) {
            TextField("Código", text: $roomCode).textInputAutocapitalization(.characters)
            Button("Cancelar", role: .cancel) { }
            Button("Buscar") { joinRoom() }
        } message: { Text(firebaseConfigured ? "Ingresa un código de sala activo." : "Las salas locales solo funcionan en este dispositivo.") }
        .alert("Proveedor no configurado", isPresented: $showProviderMessage) { Button("Entendido", role: .cancel) { } } message: { Text(providerMessage) }
        .onAppear(perform: restoreProfile)
        .onChange(of: profile) { _, value in
            value.save()
            if auth.player?.nickname != value.nickname, !value.nickname.isEmpty { auth.updateLocalNickname(value.nickname) }
        }
        .onChange(of: auth.player?.id) { _, id in if id == nil { profile = GameProfile(); UserDefaults.standard.removeObject(forKey: "fonococo.profile.v1") } }
        .onChange(of: game.state) { _, phase in
            if phase == .writing || phase == .drawing || phase == .revealing { sheet = nil }
        }
    }

    private var lobby: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                header
                HStack(spacing: 7) { Image(systemName: "sparkles"); Text("¿Listo para dibujar?") }.font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.65)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                Button { sheet = .createRoom } label: {
                    HStack(spacing: 16) {
                        ZStack { Circle().fill(.white.opacity(0.24)).frame(width: 58, height: 58); Image(systemName: "person.2.fill").font(.system(size: 23, weight: .bold)) }
                        VStack(alignment: .leading, spacing: 4) { Text("Jugar con amigos").font(.system(size: 21, weight: .heavy, design: .rounded)); Text("Crea una sala privada").font(.system(size: 13, weight: .medium, design: .rounded)).opacity(0.85) }
                        Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold))
                    }.foregroundStyle(.white).padding(18).background(LinearGradient(colors: [Aero.sky, Aero.aqua], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 27)).overlay(alignment: .topTrailing) { Circle().fill(.white.opacity(0.14)).frame(width: 90).offset(x: 18, y: -32).blur(radius: 1) }.shadow(color: Aero.sky.opacity(0.35), radius: 16, y: 9)
                }.buttonStyle(.plain)
                Button { sheet = .matchmaking } label: {
                    HStack(spacing: 16) {
                        ZStack { Circle().fill(Aero.violet.opacity(0.1)).frame(width: 58, height: 58); Image(systemName: "shuffle").font(.system(size: 23, weight: .bold)).foregroundStyle(Aero.violet) }
                        VStack(alignment: .leading, spacing: 4) { Text("Partida aleatoria").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Aero.ink); Text("Encuentra nuevos jugadores").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.58)) }
                        Spacer(); Image(systemName: "arrow.right").foregroundStyle(Aero.violet).fontWeight(.bold)
                    }.padding(16).background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(.white, lineWidth: 2)).shadow(color: Aero.ink.opacity(0.08), radius: 14, y: 7)
                }.buttonStyle(.plain)
                Button { showJoin = true } label: { Label("Unirse con código", systemImage: "number") }.font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.7)).padding(.vertical, 13).frame(maxWidth: .infinity).background(.white.opacity(0.48), in: Capsule())
                HStack(spacing: 12) { Text("🌈").font(.system(size: 24)); VStack(alignment: .leading, spacing: 2) { Text("Tu racha creativa").font(.system(size: 14, weight: .bold, design: .rounded)); Text("Nivel \(profile.level) · \(profile.levelXP)/100 XP").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.6)) }; Spacer(); MiniXPBar(value: Double(profile.levelXP) / 100).frame(width: 68) }.padding(14).glass()
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 22)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { selectedTab = .profile } label: { AvatarBadge(emoji: profile.avatar, size: 52, imageData: profile.avatarImageData) }.buttonStyle(.plain).accessibilityLabel("Abrir perfil")
            VStack(alignment: .leading, spacing: 3) { Text(profile.nickname.isEmpty ? "¡Hola!" : profile.nickname).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(Aero.ink); HStack(spacing: 5) { Text("NIVEL \(profile.level)").font(.system(size: 10, weight: .heavy, design: .rounded)); MiniXPBar(value: Double(profile.levelXP) / 100).frame(width: 70, height: 6); Text("\(profile.levelXP)/100").font(.system(size: 10, weight: .bold, design: .rounded)) }.foregroundStyle(Aero.ink.opacity(0.6)) }
            Spacer()
            Text("✦").font(.system(size: 17, weight: .black)).foregroundStyle(Aero.violet).frame(width: 36, height: 36).background(.white.opacity(0.7), in: Circle())
        }.padding(.horizontal, 20).padding(.top, 12)
    }

    private var friendsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HStack { VStack(alignment: .leading, spacing: 4) { Text("Tu pandilla").font(.system(size: 30, weight: .heavy, design: .rounded)); Text("Amigos de demostración").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)) }; Spacer(); Button { sheet = .addFriend } label: { Image(systemName: "plus").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white).frame(width: 46, height: 46).background(Aero.violet, in: Circle()).shadow(color: Aero.violet.opacity(0.25), radius: 9, y: 5) }.accessibilityLabel("Agregar amigos") }
                FriendsList(friends: $friends, incoming: $incoming, outgoing: $outgoingFriends)
            }.foregroundStyle(Aero.ink).padding(20)
        }
    }

    private var profileView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                HStack { Text("Tu perfil").font(.system(size: 30, weight: .heavy, design: .rounded)); Spacer(); Button { sheet = .editProfile } label: { Image(systemName: "pencil").fontWeight(.bold).frame(width: 42, height: 42).background(.white.opacity(0.7), in: Circle()) }.accessibilityLabel("Editar perfil") }
                VStack(spacing: 8) { AvatarBadge(emoji: profile.avatar, size: 104, imageData: profile.avatarImageData); Text(profile.nickname).font(.system(size: 23, weight: .heavy, design: .rounded)); Text("@\(profile.username)").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.54)); HStack { Text("NIVEL \(profile.level)").font(.system(size: 12, weight: .heavy, design: .rounded)); Spacer(); Text("\(profile.levelXP) / 100 XP").font(.system(size: 12, weight: .bold, design: .rounded)) }.padding(.top, 8); MiniXPBar(value: Double(profile.levelXP) / 100).frame(height: 10) }.padding(20).frame(maxWidth: .infinity).glass()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) { StatTile(value: "\(profile.gamesPlayed)", label: "Partidas", icon: "gamecontroller.fill", color: Aero.sky); StatTile(value: "\(profile.gamesWon)", label: "Ganadas", icon: "trophy.fill", color: Aero.yellow); StatTile(value: "\(profile.drawings)", label: "Dibujos", icon: "paintbrush.fill", color: Aero.coral); StatTile(value: "\(profile.guesses)", label: "Aciertos", icon: "lightbulb.fill", color: Aero.violet) }
                if profile.isGuest { VStack(alignment: .leading, spacing: 10) { Label("Guarda tu progreso", systemImage: "sparkles").font(.system(size: 16, weight: .heavy, design: .rounded)); Text("Vincula tu perfil cuando esté lista la configuración de cuenta.").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.6)); HStack { providerButton("Google", icon: "g.circle.fill"); providerButton("Facebook", icon: "f.circle.fill"); providerButton("Apple", icon: "apple.logo") }; Button("Crear cuenta") { sheet = .signup }.font(.system(size: 14, weight: .bold, design: .rounded)).frame(maxWidth: .infinity).padding(12).foregroundStyle(.white).background(Aero.violet, in: Capsule()) }.padding(16).glass() }
                Button(role: .destructive) { album.cancelRecording(); game.leave(); auth.signOut() } label: { Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.7)).frame(maxWidth: .infinity).padding(14).background(.white.opacity(0.62), in: Capsule()) }
                if let error = game.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            }.foregroundStyle(Aero.ink).padding(20)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.rawValue) { tab in Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = tab } } label: { VStack(spacing: 5) { Image(systemName: tab == .home ? "house.fill" : tab == .friends ? "person.2.fill" : "person.crop.circle.fill").font(.system(size: 19, weight: .bold)); Text(tab.rawValue).font(.system(size: 10, weight: .bold, design: .rounded)) }.foregroundStyle(selectedTab == tab ? Aero.violet : Aero.ink.opacity(0.45)).frame(maxWidth: .infinity).padding(.vertical, 10).background { if selectedTab == tab { Capsule().fill(Aero.violet.opacity(0.1)).padding(.horizontal, 7) } } }.buttonStyle(.plain) }
        }.padding(6).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.5)).shadow(color: Aero.ink.opacity(0.12), radius: 16, y: 8).padding(.horizontal, 30).padding(.top, 6).padding(.bottom, 8)
    }

    @ViewBuilder private func sheetContent(_ route: AppSheet) -> some View {
        switch route {
        case .createRoom: CreateRoomSheet(game: game, player: auth.player, configured: firebaseConfigured, onCreated: { createdRoomName = $0; sheet = .waitingRoom })
        case .waitingRoom: WaitingRoomSheet(game: game, profile: profile, configured: firebaseConfigured, roomName: createdRoomName, onExit: { game.leave(); sheet = nil })
        case .matchmaking: MatchmakingSheet(profile: profile, configured: firebaseConfigured)
        case .editProfile: EditProfileSheet(profile: $profile)
        case .addFriend: AddFriendSheet(profile: profile, friends: $friends, outgoing: $outgoingFriends)
        case .signup: AccountSheet(auth: auth, configured: firebaseConfigured, isSignup: true, onDone: { sheet = nil; syncProfile() })
        case .login: AccountSheet(auth: auth, configured: firebaseConfigured, isSignup: false, onDone: { sheet = nil; syncProfile() })
        }
    }

    private func restoreProfile() {
        let saved = GameProfile.load()
        if !saved.userID.isEmpty { profile = saved; auth.restoreLocalGuest(Player(id: saved.userID, nickname: saved.nickname)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { withAnimation { booted = true } }
    }
    private func makeGuest() {
        let name = StageOneRules.guestName(randomIndex: Int.random(in: 0...4), number: Int.random(in: 10...99))
        if firebaseConfigured {
            auth.nickname = name
            Task {
                await auth.signIn()
                if let player = auth.player {
                    profile = GameProfile(userID: player.id, username: name, nickname: name, isGuest: true)
                    profile.save()
                } else { createLocalGuest(name) }
            }
        } else { createLocalGuest(name) }
    }
    private func createLocalGuest(_ name: String) { let id = "guest-\(UUID().uuidString)"; profile = GameProfile(userID: id, username: name, nickname: name, isGuest: true); profile.save(); auth.playAsLocalGuest(nickname: name) }
    private func syncProfile() {
        guard let player = auth.player else { return }
        profile.userID = player.id; profile.nickname = player.nickname
        if profile.username.isEmpty { profile.username = player.nickname }
        profile.isGuest = player.id.hasPrefix("guest-") || player.id.hasPrefix("local-")
        profile.save()
    }
    private func joinRoom() {
        let code = roomCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard firebaseConfigured else { return }
        game.roomID = code
        if let player = auth.player { game.connect(player: player); sheet = .waitingRoom }
    }
    private func providerButton(_ title: String, icon: String) -> some View { Button { providerMessage = "\(title) necesita configurar su proveedor en Firebase."; showProviderMessage = true } label: { Label(title, systemImage: icon).font(.system(size: 11, weight: .bold, design: .rounded)).frame(maxWidth: .infinity).padding(9).background(.white.opacity(0.75), in: Capsule()) }.accessibilityHint("Muestra el estado de configuración del proveedor") }
}

private struct SplashView: View {
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View { ZStack { LinearGradient(colors: [Aero.sky, Aero.aqua, Color(red: 0.72, green: 0.83, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea(); ForEach(0..<9) { i in Circle().fill(.white.opacity(0.2)).frame(width: CGFloat(14 + (i * 11) % 46)).blur(radius: 1).offset(x: CGFloat((i * 47) % 320 - 160), y: pulse ? CGFloat((i * 39) % 580 - 290) : CGFloat((i * 53) % 580 - 290)).animation(reduceMotion ? nil : .easeInOut(duration: Double(3 + i % 3)).repeatForever(autoreverses: true).delay(Double(i) * 0.12), value: pulse) }; VStack(spacing: 18) { ZStack { Circle().fill(.white.opacity(0.3)).frame(width: 124, height: 124); Text("🐼").font(.system(size: 69)).scaleEffect(pulse && !reduceMotion ? 1.05 : 1) }; Text("fonococo").font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white).shadow(color: Aero.ink.opacity(0.14), radius: 9, y: 4); ProgressView().tint(.white).scaleEffect(1.2).padding(.top, 6) }.onAppear { pulse = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { onComplete() } } } }
}

private struct WelcomeView: View {
    @ObservedObject var auth: AuthViewModel
    let configured: Bool
    let onGuest: () -> Void
    let onSignup: () -> Void
    let onLogin: () -> Void
    @State private var providerMessage = ""
    @State private var showProviderMessage = false
    var body: some View { VStack(spacing: 16) { Spacer(minLength: 18); Text("🫧").font(.system(size: 84)); Text("Dibuja. Adivina.\nRíete en grupo.").multilineTextAlignment(.center).font(.system(size: 32, weight: .black, design: .rounded)).foregroundStyle(Aero.ink); Text("La creatividad se pega.").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)); Spacer(); Button(action: onGuest) { Label("Jugar como invitado", systemImage: "sparkles").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(17).background(LinearGradient(colors: [Aero.sky, Aero.aqua], startPoint: .leading, endPoint: .trailing), in: Capsule()).shadow(color: Aero.sky.opacity(0.35), radius: 13, y: 6) }; Button(action: onSignup) { Text("Crear cuenta").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Aero.violet).padding(7) }; Button(action: onLogin) { Text("Ya tengo cuenta · Iniciar sesión").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.6)) }; HStack { provider("Google", symbol: "g.circle.fill"); provider("Facebook", symbol: "f.circle.fill"); provider("Apple", symbol: "apple.logo") }; if !configured { Text("Modo local · Firebase no configurado").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.48)) }; if let message = auth.errorMessage { Text(message).font(.caption).foregroundStyle(.red) }; Spacer(minLength: 18) }.padding(.horizontal, 28).padding(.vertical, 22).alert("Proveedor no configurado", isPresented: $showProviderMessage) { Button("Entendido", role: .cancel) { } } message: { Text(providerMessage) } }
    private func provider(_ title: String, symbol: String) -> some View { Button { providerMessage = "\(title) requiere configuración de OAuth en Firebase."; showProviderMessage = true } label: { Label(title, systemImage: symbol).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)).frame(maxWidth: .infinity).padding(12).background(.white.opacity(0.72), in: Capsule()) }.accessibilityHint("Muestra el estado de configuración del proveedor") }
}

private struct CreateRoomSheet: View {
    @ObservedObject var game: GameViewModel
    let player: Player?
    let configured: Bool
    let onCreated: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var capacity = 4
    private let options = StageOneRules.playerLimits
    var body: some View { VStack(spacing: 18) { HStack { Text("Sala privada").font(.system(size: 25, weight: .black, design: .rounded)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.bold).padding(10).background(.white, in: Circle()) } }.foregroundStyle(Aero.ink); TextField("Nombre de sala (opcional)", text: $roomName).padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16)); Text("¿Cuántos juegan?").font(.system(size: 15, weight: .bold, design: .rounded)).frame(maxWidth: .infinity, alignment: .leading); HStack(spacing: 8) { ForEach(options, id: \.self) { n in Button { withAnimation(.spring(response: 0.25)) { capacity = n } } label: { Text("\(n)").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(capacity == n ? .white : Aero.ink).frame(maxWidth: .infinity).padding(.vertical, 14).background(capacity == n ? Aero.violet : .white.opacity(0.76), in: RoundedRectangle(cornerRadius: 14)) } } }; Button { Task { guard let player else { return }; await game.create(player: player, playerLimit: capacity); if game.errorMessage == nil { onCreated(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sala de \(player.nickname)" : roomName.trimmingCharacters(in: .whitespacesAndNewlines)) } } } label: { Label("Crear sala", systemImage: "sparkles").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(16).background(LinearGradient(colors: [Aero.sky, Aero.aqua], startPoint: .leading, endPoint: .trailing), in: Capsule()) }.disabled(game.state == .loading); if !configured { Text("Sala local de demostración · Este código no conecta otros dispositivos").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)).multilineTextAlignment(.center) }; if let error = game.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }; Spacer(minLength: 0) }.padding(22).background(Aero.backdrop) }
}

private struct WaitingRoomSheet: View {
    @ObservedObject var game: GameViewModel
    let profile: GameProfile
    let configured: Bool
    let roomName: String
    let onExit: () -> Void
    @State private var capacity: Int = 4
    @State private var copied = false
    init(game: GameViewModel, profile: GameProfile, configured: Bool, roomName: String, onExit: @escaping () -> Void) {
        self.game = game; self.profile = profile; self.configured = configured; self.roomName = roomName; self.onExit = onExit
        _capacity = State(initialValue: game.room?.settings?.playerLimit ?? 4)
    }
    var body: some View { VStack(spacing: 17) { HStack { Button(action: onExit) { Image(systemName: "xmark").fontWeight(.bold).padding(10).background(.white.opacity(0.78), in: Circle()) }; Spacer(); Text(roomName.uppercased()).font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.2); Spacer(); Image(systemName: "ellipsis").padding(10).background(.white.opacity(0.7), in: Circle()) }.foregroundStyle(Aero.ink); VStack(spacing: 7) { Text("Tu código").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.56)); Text(game.roomID).font(.system(size: 34, weight: .black, design: .monospaced)).tracking(4).foregroundStyle(Aero.ink); HStack { Button { UIPasteboard.general.string = game.roomID; copied = true } label: { Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc") }.buttonStyle(.borderedProminent).tint(Aero.violet); ShareLink(item: "¡Juega Fonococo conmigo! Código: \(game.roomID)") { Label("Compartir", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered) } }.frame(maxWidth: .infinity).padding(20).glass(); HStack { Text("Jugadores").font(.system(size: 18, weight: .heavy, design: .rounded)); Spacer(); Text("\(game.room?.players.count ?? 1)/\(game.room?.settings?.playerLimit ?? capacity)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Aero.violet) }; VStack(spacing: 10) { ForEach(game.room?.players ?? []) { p in HStack { AvatarBadge(emoji: p.id == profile.userID ? profile.avatar : "🫧", size: 42, imageData: p.id == profile.userID ? profile.avatarImageData : nil); VStack(alignment: .leading) { Text(p.nickname).font(.system(size: 15, weight: .bold, design: .rounded)); Text(p.id == game.room?.players.first?.id ? "Anfitrión" : p.id.hasPrefix("local-demo-opponent-") ? "Rival de prueba · demo" : "Jugador").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)) }; Spacer(); if p.id == game.room?.players.first?.id { Image(systemName: "crown.fill").foregroundStyle(Aero.yellow) } }.padding(10).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 17)) } }; if game.isHost { HStack { Text("Máximo de jugadores").font(.system(size: 13, weight: .bold, design: .rounded)); Spacer(); Picker("Capacidad", selection: Binding(get: { capacity }, set: { value in capacity = value; Task { await game.updatePlayerLimit(value) } })) { ForEach(max(2, game.room?.players.count ?? 1)...8, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.menu) }.padding(.horizontal, 4) }; Spacer(); Button { Task { await game.start() } } label: { Label("Iniciar partida", systemImage: "play.fill").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(16).background(Aero.violet, in: Capsule()) }.disabled(!game.isHost || (configured && (game.room?.players.count ?? 0) < 2)); if !configured { Text("Demostración local · rival de prueba, sin conexión a otros dispositivos").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.5)).multilineTextAlignment(.center) }; if let error = game.errorMessage { Text(error).font(.caption).foregroundStyle(.red) } }.padding(20).background(Aero.backdrop) }
}

private struct MatchmakingSheet: View {
    let profile: GameProfile
    let configured: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searching = true
    @State private var pulse = false
    @State private var status = "Buscando jugadores..."
    var body: some View { VStack(spacing: 22) { HStack { Spacer(); Button { searching = false; dismiss() } label: { Image(systemName: "xmark").fontWeight(.bold).padding(10).background(.white, in: Circle()) } }; Spacer(); ZStack { Circle().stroke(Aero.sky.opacity(0.24), lineWidth: 2).frame(width: 210, height: 210); Circle().stroke(Aero.aqua.opacity(0.38), lineWidth: 2).frame(width: 155, height: 155).scaleEffect(pulse && !reduceMotion ? 1.18 : 0.9); Circle().fill(LinearGradient(colors: [Aero.sky, Aero.aqua], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 108, height: 108).shadow(color: Aero.sky.opacity(0.3), radius: 20); Text(profile.avatar).font(.system(size: 60)); ForEach(0..<5) { i in Circle().fill([Aero.violet, Aero.coral, Aero.yellow, .white, Aero.aqua][i]).frame(width: 13, height: 13).offset(x: CGFloat([0, 82, 0, -82, 0][i]), y: CGFloat([-90, 0, 90, 0, 0][i])).rotationEffect(.degrees(pulse && !reduceMotion ? 360 : 0)).animation(reduceMotion ? nil : .linear(duration: 8).repeatForever(autoreverses: false), value: pulse) } }; Text(status).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Aero.ink); Text(configured ? "La búsqueda pública todavía no está habilitada" : "El servidor de matchmaking aún no está configurado").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)).multilineTextAlignment(.center); Spacer(); Button { searching = false; dismiss() } label: { Text("Cancelar búsqueda").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.75)).frame(maxWidth: .infinity).padding(15).background(.white.opacity(0.72), in: Capsule()) }; Spacer() }.padding(24).background(Aero.backdrop).onAppear { pulse = true; DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { if searching { status = configured ? "Función en preparación" : "Servidor no configurado" } } } }
}

private struct EditProfileSheet: View {
    @Binding var profile: GameProfile
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var nickname: String
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    private let avatars = ["🐼", "🦊", "🐸", "🐱", "🐻", "🐯", "🐰", "🐙"]
    init(profile: Binding<GameProfile>) { _profile = profile; _username = State(initialValue: profile.wrappedValue.username); _nickname = State(initialValue: profile.wrappedValue.nickname) }
    var body: some View { VStack(spacing: 15) { Text("Editar perfil").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Aero.ink); PhotosPicker(selection: $photo, matching: .images) { AvatarBadge(emoji: profile.avatar, size: 76, imageData: profile.avatarImageData).overlay(alignment: .bottomTrailing) { Image(systemName: "camera.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).padding(7).background(Aero.violet, in: Circle()) } }; HStack { ForEach(avatars, id: \.self) { avatar in Button { profile.avatar = avatar; profile.avatarImageData = nil } label: { Text(avatar).font(.system(size: 26)).padding(6).background(profile.avatar == avatar ? Aero.sky.opacity(0.3) : .clear, in: Circle()) } } }; TextField("Nombre de usuario", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14)); TextField("Apodo", text: $nickname).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14)); if let error { Text(error).font(.caption).foregroundStyle(.red) }; Button("Guardar cambios") { save() }.font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(14).background(Aero.violet, in: Capsule()); Text("El nombre se valida localmente; la disponibilidad global requiere backend.").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.5)).multilineTextAlignment(.center) }.padding(22).background(Aero.backdrop).onChange(of: photo) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data), let compressed = image.jpegData(compressionQuality: 0.7) { profile.avatar = "📷"; profile.avatarImageData = compressed.base64EncodedString() } } } }
    private func save() { let user = username.trimmingCharacters(in: .whitespacesAndNewlines); let nick = nickname.trimmingCharacters(in: .whitespacesAndNewlines); let valid = StageOneRules.usernameIsValid(user); guard valid, !nick.isEmpty, nick.count <= 24 else { error = "Usa 3–18 caracteres en el usuario y un apodo de hasta 24."; return }; guard user.caseInsensitiveCompare(profile.username) == .orderedSame || StageOneRules.usernameIsLocallyAvailable(user, existing: ["PandaPixel", "NubeDibuja", "PixelLima", "TintaLunar", "DoodleLima", "MentaPixel"]) else { error = "Ese nombre ya aparece en los datos locales de demostración."; return }; profile.username = user; profile.nickname = nick; dismiss() }
}

private struct FriendsList: View {
    @Binding var friends: [DemoFriend]
    @Binding var incoming: [DemoFriend]
    @Binding var outgoing: [DemoFriend]
    @State private var query = ""
    var filtered: [DemoFriend] { StageOneRules.filterFriends(friends, query: query) }
    var body: some View { VStack(spacing: 14) { HStack { Image(systemName: "magnifyingglass").foregroundStyle(Aero.ink.opacity(0.45)); TextField("Buscar amigos", text: $query).font(.system(size: 14, weight: .medium, design: .rounded)) }.padding(13).background(.white.opacity(0.78), in: Capsule()); VStack(spacing: 9) { ForEach(filtered) { friend in friendRow(friend) }; if filtered.isEmpty { Text("No hay coincidencias").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.5)).padding() } }.padding(12).glass(); if !outgoing.isEmpty { VStack(alignment: .leading, spacing: 10) { Text("Solicitudes pendientes · demo").font(.system(size: 14, weight: .heavy, design: .rounded)); ForEach(outgoing) { friend in HStack { Text(friend.avatar); Text("@\(friend.username)").font(.system(size: 13, weight: .semibold, design: .rounded)); Spacer(); Text("Pendiente").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Aero.violet) }.padding(10) } }.padding(13).glass() }; VStack(alignment: .leading, spacing: 10) { Text("Solicitudes recibidas · demo").font(.system(size: 14, weight: .heavy, design: .rounded)); ForEach(incoming) { friend in HStack { Text(friend.avatar).font(.system(size: 27)); VStack(alignment: .leading) { Text(friend.nickname).font(.system(size: 14, weight: .bold, design: .rounded)); Text("@\(friend.username)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.5)) }; Spacer(); Button { friends.append(friend); incoming.removeAll { $0.id == friend.id } } label: { Image(systemName: "checkmark").foregroundStyle(.white).padding(9).background(Aero.aqua, in: Circle()) }; Button { incoming.removeAll { $0.id == friend.id } } label: { Image(systemName: "xmark").foregroundStyle(Aero.ink.opacity(0.5)).padding(8).background(.white, in: Circle()) } } }.padding(13).glass() } }.foregroundStyle(Aero.ink) }
    private func friendRow(_ friend: DemoFriend) -> some View { HStack(spacing: 12) { AvatarBadge(emoji: friend.avatar, size: 46); VStack(alignment: .leading, spacing: 2) { Text(friend.nickname).font(.system(size: 15, weight: .bold, design: .rounded)); Text("@\(friend.username)").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.5)) }; Spacer(); Circle().fill(Aero.aqua).frame(width: 9, height: 9) }.padding(9).background(.white.opacity(0.63), in: RoundedRectangle(cornerRadius: 17)) }
}

private struct AddFriendSheet: View {
    let profile: GameProfile
    @Binding var friends: [DemoFriend]
    @Binding var outgoing: [DemoFriend]
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var result: DemoFriend?
    @State private var message: String?
    private let directory = [DemoFriend(username: "DoodleLima", nickname: "Doodle", avatar: "🦁"), DemoFriend(username: "MentaPixel", nickname: "Menta", avatar: "🐨"), DemoFriend(username: "TintaLunar", nickname: "Luna", avatar: "🐱")]
    var body: some View { VStack(spacing: 17) { Text("Agregar amigos").font(.system(size: 24, weight: .black, design: .rounded)); HStack { TextField("Nombre de usuario", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14)); Button("Buscar") { search() }.font(.system(size: 14, weight: .bold, design: .rounded)).padding(12).background(Aero.sky.opacity(0.35), in: RoundedRectangle(cornerRadius: 14)) }; if let friend = result { HStack { Text(friend.avatar).font(.system(size: 35)); VStack(alignment: .leading) { Text(friend.nickname).fontWeight(.bold); Text("@\(friend.username)").font(.caption).foregroundStyle(Aero.ink.opacity(0.55)) }; Spacer(); Button("Agregar") { outgoing.append(friend); message = "Solicitud enviada · demostración"; result = nil }.buttonStyle(.borderedProminent).tint(Aero.violet) }.padding(14).glass() }; if let message { Text(message).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.65)) }; Spacer() }.padding(22).foregroundStyle(Aero.ink).background(Aero.backdrop) }
    private func search() { let key = username.trimmingCharacters(in: .whitespacesAndNewlines); guard !key.isEmpty else { message = "Escribe un usuario."; return }; guard key.lowercased() != profile.username.lowercased() else { message = "No puedes agregarte a ti mismo."; return }; guard !friends.contains(where: { $0.username.lowercased() == key.lowercased() }) else { message = "Ya es tu amigo."; return }; result = directory.first { $0.username.lowercased() == key.lowercased() }; message = result == nil ? "No encontrado en el directorio local de demostración." : "Usuario encontrado · datos demo" }
}

private struct AccountSheet: View {
    @ObservedObject var auth: AuthViewModel
    let configured: Bool
    let isSignup: Bool
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var nickname = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var message: String?
    var body: some View { VStack(spacing: 13) { Text(isSignup ? "Crear cuenta" : "Iniciar sesión").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Aero.ink); if isSignup { field("Nombre de usuario", text: $username); field("Apodo", text: $nickname) }; field("Correo electrónico", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never); SecureField("Contraseña", text: $password).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14)); if isSignup { SecureField("Confirmar contraseña", text: $confirmation).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14)) }; Button(isSignup ? "Crear cuenta" : "Entrar") { submit() }.font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(14).background(Aero.violet, in: Capsule()).disabled(auth.state == .loading); if !configured { Text("Firebase no está configurado. El modo invitado sigue disponible.").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)).multilineTextAlignment(.center) }; if let message { Text(message).font(.caption).foregroundStyle(.red) }; Spacer(minLength: 0) }.padding(22).background(Aero.backdrop) }
    private func field(_ title: String, text: Binding<String>) -> some View { TextField(title, text: text).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14)) }
    private func submit() { guard configured else { message = "Servicio no configurado."; return }; if isSignup { guard username.range(of: "^[A-Za-z0-9_]{3,18}$", options: .regularExpression) != nil, !nickname.trimmingCharacters(in: .whitespaces).isEmpty, password.count >= 8, password == confirmation else { message = "Revisa usuario, apodo y contraseña (mínimo 8 caracteres)."; return }; Task { await auth.createAccount(email: email, password: password, nickname: nickname); if auth.player != nil { onDone() } else { message = auth.errorMessage } } } else { Task { await auth.signIn(email: email, password: password); if auth.player != nil { onDone() } else { message = auth.errorMessage } } } }
}

private struct AvatarBadge: View {
    let emoji: String
    let size: CGFloat
    var imageData: String? = nil
    var body: some View {
        Group {
            if let imageData, let data = Data(base64Encoded: imageData), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipped()
            } else {
                Text(emoji).font(.system(size: size * 0.55)).frame(width: size, height: size)
                    .background(LinearGradient(colors: [.white, Aero.sky.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size).clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: Aero.sky.opacity(0.18), radius: 8, y: 4)
    }
}
private struct MiniXPBar: View { let value: Double; var body: some View { GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(Aero.ink.opacity(0.1)); Capsule().fill(LinearGradient(colors: [Aero.aqua, Aero.sky], startPoint: .leading, endPoint: .trailing)).frame(width: proxy.size.width * min(1, max(0, value))).animation(.easeOut(duration: 0.5), value: value) } } } }
private struct StatTile: View { let value: String; let label: String; let icon: String; let color: Color; var body: some View { HStack(spacing: 11) { Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Aero.ink).frame(width: 38, height: 38).background(color.opacity(0.46), in: Circle()); VStack(alignment: .leading, spacing: 2) { Text(value).font(.system(size: 20, weight: .black, design: .rounded)); Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)) }; Spacer(minLength: 0) }.padding(11).glass() } }

private extension View { func glass() -> some View { background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.9), lineWidth: 1.4)).shadow(color: Aero.ink.opacity(0.07), radius: 12, y: 6) } }

@MainActor public final class LocalDemoAuthService: AuthServicing {
    public init() {}
    public func signInAnonymously() async throws -> Player { Player(id: "local-\(UUID().uuidString)", nickname: "Invitado") }
    public func signOut() throws { }
}

@MainActor public final class LocalDemoRoomService: RoomServicing {
    private var rooms: [String: RoomSnapshot] = [:]
    private var streams: [String: [UUID: AsyncThrowingStream<RoomSnapshot, Error>.Continuation]] = [:]
    public init() {}
    public func create(roomID: String, player: Player, settings: RoomSettings) async throws { guard (2...8).contains(settings.playerLimit) else { throw ServiceError.invalidPayload }; let snapshot = RoomSnapshot(id: roomID, phase: .lobby, players: [player], settings: settings); rooms[roomID] = snapshot; publish(snapshot) }
    public func join(roomID: String, player: Player) async throws { guard let room = rooms[roomID] else { throw ServiceError.missingRoom }; if !room.players.contains(where: { $0.id == player.id }) { throw ServiceError.configuration } }
    public func updatePlayerLimit(roomID: String, playerID: String, limit: Int) async throws {
        guard let room = rooms[roomID] else { throw ServiceError.missingRoom }
        guard room.players.first?.id == playerID, room.phase == .lobby, (2...8).contains(limit), limit >= room.players.count,
              let old = room.settings else { throw ServiceError.invalidPayload }
        let settings = RoomSettings(playerLimit: limit, writingSeconds: old.writingSeconds, drawingSeconds: old.drawingSeconds)
        let updated = RoomSnapshot(id: room.id, phase: room.phase, players: room.players, turns: room.turns, chains: room.chains, deadline: room.deadline, settings: settings)
        rooms[roomID] = updated; publish(updated)
    }
    public func start(roomID: String, playerID: String) async throws {
        guard let room = rooms[roomID] else { throw ServiceError.missingRoom }
        guard room.players.first?.id == playerID, room.phase == .lobby, let settings = room.settings else { throw ServiceError.invalidPayload }
        let players: [Player]
        if room.players.count == 1 {
            guard settings.playerLimit >= 2 else { throw ServiceError.invalidPayload }
            let practiceOpponent = Player(id: "local-demo-opponent-\(UUID().uuidString)", nickname: "Rival de prueba")
            players = room.players + [practiceOpponent]
        } else {
            players = room.players
        }
        guard players.count <= settings.playerLimit else { throw ServiceError.invalidPayload }
        let readyRoom = RoomSnapshot(id: room.id, phase: room.phase, players: players, settings: settings)
        let next = try GameEngine.start(readyRoom, now: Date())
        rooms[roomID] = next
        publish(next)
    }
    public func advance(roomID: String) async throws { guard let room = rooms[roomID] else { throw ServiceError.missingRoom }; let next = GameEngine.advance(room, now: Date()); rooms[roomID] = next; publish(next) }
    public func observe(roomID: String) -> AsyncThrowingStream<RoomSnapshot, Error> { AsyncThrowingStream { continuation in let key = UUID(); streams[roomID, default: [:]][key] = continuation; if let room = rooms[roomID] { continuation.yield(room) }; continuation.onTermination = { @Sendable _ in Task { @MainActor [weak self] in self?.streams[roomID]?.removeValue(forKey: key) } } } }
    public func submit(roomID: String, entry: ChainEntry, turnID: String) async throws {
        guard let room = rooms[roomID] else { throw ServiceError.missingRoom }
        var updated = try GameEngine.contribute(room, entry: entry, turnID: turnID, now: Date())
        if let practicePlayer = room.players.first(where: { $0.id.hasPrefix("local-demo-opponent-") }) {
            let pendingTurns = updated.turns.filter { turn in
                turn.playerID == practicePlayer.id &&
                !updated.chains.flatMap(\.entries).contains(where: { $0.id == turn.id })
            }
            for turn in pendingTurns {
                let practiceEntry: ChainEntry
                switch turn.kind {
                case .writing:
                    practiceEntry = ChainEntry(id: turn.id, authorID: practicePlayer.id, text: "Rival de prueba")
                case .drawing:
                    let url = URL(string: "rtdb-media://local-demo/practice-opponent.png")!
                    practiceEntry = ChainEntry(id: turn.id, authorID: practicePlayer.id, drawingURL: url)
                }
                updated = try GameEngine.contribute(updated, entry: practiceEntry, turnID: turn.id, now: Date())
            }
        }
        rooms[roomID] = updated
        publish(updated)
    }
    private func publish(_ room: RoomSnapshot) { streams[room.id]?.values.forEach { $0.yield(room) } }
}

@MainActor public final class LocalDemoMediaService: MediaStorageServicing {
    public init() {}
    public func download(_ url: URL) async throws -> Data {
        guard url.scheme == "rtdb-media", url.host == "local-demo" else { throw ServiceError.configuration }
        if url.lastPathComponent == "practice-opponent.png" { return Self.practiceDrawing() }
        return try Data(contentsOf: mediaDirectory().appendingPathComponent(url.lastPathComponent))
    }
    public func uploadPNG(_ data: Data, roomID: String) async throws -> URL { try store(data, fileExtension: "png") }
    public func uploadAudio(fileURL: URL, roomID: String) async throws -> URL {
        try store(Data(contentsOf: fileURL), fileExtension: fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension)
    }
    private func store(_ data: Data, fileExtension: String) throws -> URL {
        let name = "\(UUID().uuidString).\(fileExtension)"
        try data.write(to: mediaDirectory().appendingPathComponent(name), options: .atomic)
        guard let url = URL(string: "rtdb-media://local-demo/\(name)") else { throw ServiceError.invalidResponse }
        return url
    }
    private func mediaDirectory() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = documents.appendingPathComponent("FonococoDemoMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private static func practiceDrawing() -> Data {
        let size = CGSize(width: 640, height: 400)
        return UIGraphicsImageRenderer(size: size).pngData { renderer in
            let context = renderer.cgContext
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            context.setLineCap(.round); context.setLineJoin(.round); context.setLineWidth(20)
            context.setStrokeColor(UIColor(red: 0.27, green: 0.72, blue: 0.81, alpha: 1).cgColor)
            context.move(to: CGPoint(x: 55, y: 315)); context.addLine(to: CGPoint(x: 215, y: 145)); context.addLine(to: CGPoint(x: 350, y: 315)); context.strokePath()
            context.move(to: CGPoint(x: 265, y: 315)); context.addLine(to: CGPoint(x: 420, y: 125)); context.addLine(to: CGPoint(x: 585, y: 315)); context.strokePath()
            context.setFillColor(UIColor(red: 1, green: 0.78, blue: 0.30, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: 460, y: 35, width: 90, height: 90))
        }
    }
}
