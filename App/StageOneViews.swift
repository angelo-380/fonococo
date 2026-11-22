import SwiftUI
import SwiftData
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

private struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
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
    var lastCompletedRoomID: String?
    var lastWonRoomID: String?
    var lastCreativeDay: Date?
    var creativeStreak: Int?
    var level: Int { StageOneRules.level(for: xp) }
    var levelXP: Int { StageOneRules.xpWithinLevel(for: xp) }
    static func load(for userID: String? = nil) -> GameProfile {
        let key = userID.map { "fonococo.profile.\($0)" } ?? UserDefaults.standard.string(forKey: "fonococo.lastProfileKey") ?? "fonococo.profile.v1"
        if let userID, UserDefaults.standard.data(forKey: key) == nil,
           let legacy = UserDefaults.standard.data(forKey: "fonococo.profile.v1"),
           let old = try? JSONDecoder().decode(GameProfile.self, from: legacy), old.userID == userID { return old }
        guard let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(GameProfile.self, from: data) else { return GameProfile() }
        return value
    }
    func save() { if let data = try? JSONEncoder().encode(self) { let key = "fonococo.profile.\(userID)"; UserDefaults.standard.set(data, forKey: key); UserDefaults.standard.set(key, forKey: "fonococo.lastProfileKey") } }
    mutating func recordCreativeDay() {
        let today = Calendar.current.startOfDay(for: Date())
        guard lastCreativeDay != today else { return }
        if let lastCreativeDay, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastCreativeDay), to: today).day == 1 { creativeStreak = (creativeStreak ?? 0) + 1 }
        else { creativeStreak = 1 }
        lastCreativeDay = today
    }
}

private typealias DemoFriend = StageOneFriend

private enum MainTab: String, CaseIterable { case home = "Inicio", friends = "Amigos", profile = "Perfil" }
private enum AppSheet: String, Identifiable { case createRoom, waitingRoom, matchmaking, editProfile, addFriend, signup, login, changePassword; var id: String { rawValue } }

public struct StageOneRootView: View {
    @Query(sort: \ArchivedAlbum.completedAt, order: .reverse) private var offlineAlbums: [ArchivedAlbum]
    @ObservedObject private var auth: AuthViewModel
    @ObservedObject private var game: GameViewModel
    @ObservedObject private var canvas: CanvasViewModel
    @ObservedObject private var album: AlbumViewModel
    private let firebaseConfigured: Bool
    @State private var profile = GameProfile.load()
    @State private var selectedTab: MainTab = .home
    @Namespace private var tabAnimation
    @State private var sheet: AppSheet?
    @State private var showJoin = false
    @State private var providerMessage = ""
    @State private var socialError: String?
    @State private var cloudStatus = ""
    @State private var accountMessage: String?
    @State private var linkingGoogle = false
    @State private var transferringGoogleProfile = false
    @State private var showProviderMessage = false
    @State private var roomCode = ""
    @State private var createdRoomName = ""
    @State private var booted = false
    @State private var profileLoading = false
    @State private var profileSyncBlocked = false
    @State private var friends = [DemoFriend]()
    @State private var incoming = [DemoFriend]()
    @State private var gameInvites = [GameInvite]()

    public init(auth: AuthViewModel, game: GameViewModel, canvas: CanvasViewModel, album: AlbumViewModel, firebaseConfigured: Bool = false) {
        self.auth = auth; self.game = game; self.canvas = canvas; self.album = album; self.firebaseConfigured = firebaseConfigured
    }

    public var body: some View {
        ZStack {
            Aero.backdrop.ignoresSafeArea()
            if !booted { SplashView { withAnimation(.spring(response: 0.65)) { booted = true } } }
            else if auth.player == nil { WelcomeView(auth: auth, configured: firebaseConfigured, onGuest: makeGuest, onSignup: { sheet = .signup }, onLogin: { sheet = .login }) }
            else if profileLoading { ProgressView("Cargando tu progreso…") }
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
        .buttonStyle(PressFeedbackStyle())
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "es"))
        .sheet(item: $sheet) { route in sheetContent(route).presentationDetents(route == .waitingRoom ? [.large] : [.medium, .large]).presentationDragIndicator(.visible) }
        .alert("Unirse a una sala", isPresented: $showJoin) {
            TextField("Código", text: $roomCode).textInputAutocapitalization(.characters)
            Button("Cancelar", role: .cancel) { }
            Button("Buscar") { joinRoom() }
        } message: { Text(firebaseConfigured ? "Ingresa un código de sala activo." : "Las salas locales solo funcionan en este dispositivo.") }
        .alert("Proveedor no configurado", isPresented: $showProviderMessage) { Button("Entendido", role: .cancel) { } } message: { Text(providerMessage) }
        .onAppear(perform: restoreProfile)
        .task(id: profile.userID) { await refreshSocial() }
        .onChange(of: selectedTab) { _, tab in
            if tab == .friends { Task { await refreshSocial() } }
        }
        .onChange(of: profile) { _, value in
            value.save()
            if auth.player?.nickname != value.nickname, !value.nickname.isEmpty { auth.updateLocalNickname(value.nickname) }
            if !profileLoading, !profileSyncBlocked, !value.isGuest, !value.userID.isEmpty,
               auth.player?.id == value.userID, firebaseConfigured {
                Task {
                    do { try await FirebaseServiceFactory.social().register(userID: value.userID, nickname: value.nickname, avatar: value.avatar, avatarImageData: value.avatarImageData, gamesPlayed: value.gamesPlayed, gamesWon: value.gamesWon, level: value.level, xp: value.xp, drawings: value.drawings, guesses: value.guesses, creativeStreak: value.creativeStreak ?? 0); socialError = nil; cloudStatus = auth.isGoogleLinked && value.gamesPlayed == 0 && value.xp == 0 ? "Esta cuenta de Google no tiene progreso. Vincula Google desde el dispositivo que lo conserva." : "Progreso guardado en Firebase" }
                    catch { socialError = error.localizedDescription; cloudStatus = "No se pudo guardar el progreso: \(error.localizedDescription)" }
                }
            }
        }
        .onChange(of: auth.player?.id) { _, id in
            if id == nil {
                profile = GameProfile(); friends = []; incoming = []
                cloudStatus = ""
                UserDefaults.standard.removeObject(forKey: "fonococo.lastProfileKey")
            } else if !transferringGoogleProfile {
                Task { await restoreCloudProfile() }
            }
        }
        .onChange(of: game.state) { _, phase in
            if phase == .writing || phase == .drawing || phase == .revealing { sheet = nil }
            if phase == .revealing, let room = game.room { recordCompletedGame(room) }
        }
        .onChange(of: game.allRatingsComplete) { _, complete in
            guard complete, let room = game.room, profile.lastWonRoomID != room.id else { return }
            profile.lastWonRoomID = room.id
            if game.ranking.first?.0.id == profile.userID { profile.gamesWon += 1 }
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
                }.buttonStyle(PressFeedbackStyle())
                Button { sheet = .matchmaking } label: {
                    HStack(spacing: 16) {
                        ZStack { Circle().fill(Aero.violet.opacity(0.1)).frame(width: 58, height: 58); Image(systemName: "shuffle").font(.system(size: 23, weight: .bold)).foregroundStyle(Aero.violet) }
                        VStack(alignment: .leading, spacing: 4) { Text("Partida aleatoria").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Aero.ink); Text("Encuentra nuevos jugadores").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.58)) }
                        Spacer(); Image(systemName: "arrow.right").foregroundStyle(Aero.violet).fontWeight(.bold)
                    }.padding(16).background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(.white, lineWidth: 2)).shadow(color: Aero.ink.opacity(0.08), radius: 14, y: 7)
                }.buttonStyle(PressFeedbackStyle())
                Button { showJoin = true } label: { Label("Unirse con código", systemImage: "number").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 56).background(Aero.coral, in: Capsule()).contentShape(Capsule()) }
                HStack(spacing: 12) { Text("🌈").font(.system(size: 24)); VStack(alignment: .leading, spacing: 2) { Text("Tu racha creativa").font(.system(size: 14, weight: .bold, design: .rounded)); Text("\(profile.creativeStreak ?? 0) días · Nivel \(profile.level) · \(profile.levelXP)/100 XP").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.6)) }; Spacer(); MiniXPBar(value: Double(profile.levelXP) / 100).frame(width: 68) }.padding(14).glass()
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 22)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { selectedTab = .profile } label: { AvatarBadge(emoji: profile.avatar, size: 52, imageData: profile.avatarImageData) }.buttonStyle(PressFeedbackStyle()).accessibilityLabel("Abrir perfil")
            VStack(alignment: .leading, spacing: 3) { Text(profile.nickname.isEmpty ? "¡Hola!" : profile.nickname).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(Aero.ink); HStack(spacing: 5) { Text("NIVEL \(profile.level)").font(.system(size: 10, weight: .heavy, design: .rounded)); MiniXPBar(value: Double(profile.levelXP) / 100).frame(width: 70, height: 6); Text("\(profile.levelXP)/100").font(.system(size: 10, weight: .bold, design: .rounded)) }.foregroundStyle(Aero.ink.opacity(0.6)) }
            Spacer()
            Text("✦").font(.system(size: 17, weight: .black)).foregroundStyle(Aero.violet).frame(width: 36, height: 36).background(.white.opacity(0.7), in: Circle())
        }.padding(.horizontal, 20).padding(.top, 12)
    }

    private var friendsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HStack { VStack(alignment: .leading, spacing: 4) { Text("Tu pandilla").font(.system(size: 30, weight: .heavy, design: .rounded)); Text(profile.isGuest ? "Crea una cuenta para añadir amigos" : "Tus amigos").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)) }; Spacer(); Button { if profile.isGuest { sheet = .signup } else { sheet = .addFriend } } label: { Image(systemName: "plus").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white).frame(width: 46, height: 46).background(Aero.violet, in: Circle()).shadow(color: Aero.violet.opacity(0.25), radius: 9, y: 5) }.accessibilityLabel("Agregar amigos") }
                FriendsList(profile: profile, friends: $friends, incoming: $incoming)
                if !gameInvites.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Invitaciones para jugar").font(.headline)
                        ForEach(gameInvites) { invite in
                            VStack(spacing: 10) {
                                Text("Hey! \(invite.hostNickname) quiere jugar contigo. ¿Aceptas?").font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    Button { Task { acceptGameInvite(invite) } } label: {
                                        Image(systemName: "checkmark").font(.title3.bold()).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48).background(Aero.aqua, in: Capsule()).glassEffectIfAvailable()
                                    }
                                    Button { Task { await dismissGameInvite(invite) } } label: {
                                        Image(systemName: "xmark").font(.title3.bold()).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48).background(Aero.coral, in: Capsule()).glassEffectIfAvailable()
                                    }
                                }
                            }.padding(14).glass()
                        }
                    }
                }
            }.foregroundStyle(Aero.ink).padding(20)
        }
    }

    private var profileView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                HStack { Text("Tu perfil").font(.system(size: 30, weight: .heavy, design: .rounded)); Spacer(); Button { sheet = profile.isGuest ? .signup : .editProfile } label: { Image(systemName: "pencil").fontWeight(.bold).frame(width: 42, height: 42).background(.white.opacity(0.7), in: Circle()) }.accessibilityLabel("Editar perfil") }
                VStack(spacing: 8) { AvatarBadge(emoji: profile.avatar, size: 104, imageData: profile.avatarImageData); Text(profile.nickname).font(.system(size: 23, weight: .heavy, design: .rounded)); HStack { Text("NIVEL \(profile.level)").font(.system(size: 12, weight: .heavy, design: .rounded)); Spacer(); Text("\(profile.levelXP) / 100 XP").font(.system(size: 12, weight: .bold, design: .rounded)) }.padding(.top, 8); MiniXPBar(value: Double(profile.levelXP) / 100).frame(height: 10) }.padding(20).frame(maxWidth: .infinity).glass()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) { StatTile(value: "\(profile.gamesPlayed)", label: "Partidas", icon: "gamecontroller.fill", color: Aero.sky); StatTile(value: "\(profile.gamesWon)", label: "Ganadas", icon: "trophy.fill", color: Aero.yellow); StatTile(value: "\(profile.drawings)", label: "Dibujos", icon: "paintbrush.fill", color: Aero.coral); StatTile(value: "\(profile.guesses)", label: "Aciertos", icon: "lightbulb.fill", color: Aero.violet) }
                if !profile.isGuest, let player = auth.player {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { UIPasteboard.general.string = player.id } label: {
                            Label("ID de cuenta: \(player.id.prefix(10))…", systemImage: "doc.on.doc")
                        }.font(.caption.monospaced())
                        Text(auth.isGoogleLinked ? "Google vinculado" : "Google sin vincular").font(.caption.bold())
                        Text(cloudStatus).font(.caption)
                        Button("Volver a cargar progreso") { Task { await restoreCloudProfile() } }.font(.caption.bold())
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14).glass()
                }
                if !profile.isGuest {
                    VStack(spacing: 10) {
                        Button { Task { await linkGoogleAndTransferProfile() } } label: {
                            HStack { if linkingGoogle { ProgressView() }; Label(linkingGoogle ? "Vinculando Google…" : "Vincular progreso a Google", systemImage: "g.circle.fill") }
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 54).background(.white.opacity(0.75), in: Capsule())
                        }.disabled(linkingGoogle || !firebaseConfigured)
                        Button { sheet = .changePassword } label: {
                            Label("Cambiar contraseña", systemImage: "key.fill").font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 54).background(.white.opacity(0.55), in: Capsule())
                        }
                        if let accountMessage { Text(accountMessage).font(.caption).multilineTextAlignment(.center) }
                    }.padding(14).glass()
                }
                if !profile.isGuest, !profile.userID.isEmpty {
                    Button { UIPasteboard.general.string = FirebaseSocialService.friendCode(for: profile.userID) } label: {
                        HStack { Label("Mi código de amigo", systemImage: "person.crop.circle.badge.plus"); Spacer(); Text(FirebaseSocialService.friendCode(for: profile.userID)).font(.system(.subheadline, design: .monospaced)); Image(systemName: "doc.on.doc") }
                            .font(.subheadline.bold()).padding(16).glass()
                    }.accessibilityHint("Copia tu código de amigo")
                    if let socialError { Text(socialError).font(.caption).foregroundStyle(.red) }
                }
                if profile.isGuest { VStack(alignment: .leading, spacing: 10) { Label("Guarda tu progreso", systemImage: "sparkles").font(.system(size: 16, weight: .heavy, design: .rounded)); Text("Vincula tu perfil cuando esté lista la configuración de cuenta.").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.6)); providerButton("Google", icon: "g.circle.fill"); if let authError = auth.errorMessage { Text(authError).font(.caption).foregroundStyle(.red) }; Button("Crear cuenta") { sheet = .signup }.font(.system(size: 14, weight: .bold, design: .rounded)).frame(maxWidth: .infinity).padding(12).foregroundStyle(.white).background(Aero.violet, in: Capsule()) }.padding(16).glass() }
                NavigationLink { OfflineDrawingGallery(albums: offlineAlbums.filter { $0.id.hasPrefix("\(profile.userID)|") }) } label: { Label("Mis dibujos", systemImage: "circle.hexagongrid.fill").font(.headline).frame(maxWidth: .infinity).padding(16).glass() }
                Button(role: .destructive) { album.cancelRecording(); game.leave(); auth.signOut() } label: { Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.7)).frame(maxWidth: .infinity).padding(14).background(.white.opacity(0.62), in: Capsule()) }
                if let error = game.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            }.foregroundStyle(Aero.ink).padding(20)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.rawValue) { tab in
                Button { withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) { selectedTab = tab } } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab == .home ? "house.fill" : tab == .friends ? "person.2.fill" : "person.crop.circle.fill")
                            .font(.system(size: selectedTab == tab ? 22 : 19, weight: .bold))
                        Text(tab.rawValue).font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == tab ? Color(red: 0.10, green: 0.48, blue: 0.95) : Aero.ink.opacity(0.54))
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .contentShape(Rectangle())
                    .background {
                        if selectedTab == tab {
                            Capsule().fill(Aero.sky.opacity(0.18)).activeTabGlass()
                                .shadow(color: Aero.sky.opacity(0.3), radius: 14, y: 3)
                                .padding(.horizontal, 5)
                                .matchedGeometryEffect(id: "selected-tab", in: tabAnimation)
                        }
                    }
                }.buttonStyle(PressFeedbackStyle())
            }
        }
        .padding(7)
        .tabGlass()
        .shadow(color: Aero.ink.opacity(0.12), radius: 20, y: 10)
        .padding(.horizontal, 30).padding(.top, 6).padding(.bottom, 8)
    }

    @ViewBuilder private func sheetContent(_ route: AppSheet) -> some View {
        switch route {
        case .createRoom: CreateRoomSheet(game: game, player: auth.player, configured: firebaseConfigured, friends: friends, onCreated: { roomName, invitees in
            createdRoomName = roomName
            if let host = auth.player, !invitees.isEmpty, firebaseConfigured {
                Task {
                    do {
                        let service = try FirebaseServiceFactory.social()
                        for friendID in invitees {
                            try await service.sendGameInvite(to: friendID, from: host.id, nickname: host.nickname, roomID: game.roomID)
                        }
                    } catch { socialError = "La sala se creó, pero no se pudieron enviar todas las invitaciones: \(error.localizedDescription)" }
                }
            }
            sheet = .waitingRoom
        })
        case .waitingRoom: WaitingRoomSheet(game: game, profile: profile, configured: firebaseConfigured, roomName: createdRoomName, onExit: { game.leave(); sheet = nil })
        case .matchmaking: MatchmakingSheet(game: game, player: auth.player, profile: profile, configured: firebaseConfigured)
        case .editProfile: EditProfileSheet(profile: $profile, auth: auth)
        case .addFriend: AddFriendSheet(profile: profile)
        case .signup: AccountSheet(auth: auth, configured: firebaseConfigured, isSignup: true, existingUsernames: friends.map(\.username) + incoming.map(\.username), onDone: { _ in sheet = nil })
        case .login: AccountSheet(auth: auth, configured: firebaseConfigured, isSignup: false, existingUsernames: [], onDone: { _ in sheet = nil })
        case .changePassword: ChangePasswordSheet(auth: auth, configured: firebaseConfigured)
        }
    }

    private func refreshSocial() async {
        guard let player = auth.player, !profile.isGuest, firebaseConfigured,
              let service = try? FirebaseServiceFactory.social() else { return }
        if let values = try? await service.friends(userID: player.id) {
            friends = values.map { DemoFriend(username: $0.userID, nickname: $0.nickname, avatar: $0.avatar, avatarImageData: $0.avatarImageData, gamesPlayed: $0.gamesPlayed, gamesWon: $0.gamesWon, level: $0.level) }
        }
        if let values = try? await service.incoming(userID: player.id) {
            incoming = values.map { DemoFriend(username: $0.userID, nickname: $0.nickname, avatar: $0.avatar, avatarImageData: $0.avatarImageData, gamesPlayed: $0.gamesPlayed, gamesWon: $0.gamesWon, level: $0.level) }
        }
        gameInvites = (try? await service.gameInvites(userID: player.id)) ?? []
    }
    private func acceptGameInvite(_ invite: GameInvite) {
        guard let player = auth.player else { return }
        Task {
            do {
                try await FirebaseServiceFactory.social().removeGameInvite(userID: player.id, roomID: invite.roomID)
                gameInvites.removeAll { $0.id == invite.id }
                game.roomID = invite.roomID
                game.connect(player: player)
                sheet = .waitingRoom
                createdRoomName = "Sala de \(invite.hostNickname)"
            } catch { socialError = error.localizedDescription }
        }
    }
    private func dismissGameInvite(_ invite: GameInvite) async {
        guard let userID = auth.player?.id else { return }
        do {
            try await FirebaseServiceFactory.social().removeGameInvite(userID: userID, roomID: invite.roomID)
            gameInvites.removeAll { $0.id == invite.id }
        } catch { socialError = error.localizedDescription }
    }
    private func restoreProfile() {
        let saved = GameProfile.load()
        let savedGuest = saved.isGuest || saved.userID.hasPrefix("guest-") || saved.userID.hasPrefix("local-")
        if !saved.userID.isEmpty, savedGuest {
            let restored = GameProfile.load(for: saved.userID)
            profile = restored
            auth.restoreLocalGuest(Player(id: restored.userID, nickname: restored.nickname.isEmpty ? "Invitado" : restored.nickname))
        } else {
            Task { await auth.restoreSession() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { withAnimation { booted = true } }
    }
    private func restoreCloudProfile() async {
        guard let player = auth.player else { return }
        profileLoading = true
        cloudStatus = "Cargando progreso de Firebase…"
        defer { profileLoading = false }
        let local = GameProfile.load(for: player.id)
        guard firebaseConfigured, (try? FirebaseServiceFactory.auth().isCurrentUserAnonymous) != true else {
            profile = local; syncProfile(); cloudStatus = "Progreso local de invitado"; return
        }
        do {
            guard let cloud = try await FirebaseServiceFactory.social().profileIfExists(userID: player.id) else {
                profileSyncBlocked = false
                profile = local
                syncProfile()
                cloudStatus = auth.isGoogleLinked
                    ? "Esta cuenta de Google aún no tiene progreso. Vincula Google desde el dispositivo que conserva tus datos."
                    : "No había progreso guardado para este ID"
                return
            }
            profileSyncBlocked = false
            var restored = local
            restored.userID = player.id
            let localHasIdentity = local.userID == player.id && !local.nickname.isEmpty && local.nickname != "Jugador"
            if !localHasIdentity {
                restored.nickname = cloud.nickname
                restored.username = cloud.nickname
                restored.avatar = cloud.avatar
                restored.avatarImageData = cloud.avatarImageData
            }
            restored.gamesPlayed = max(local.gamesPlayed, cloud.gamesPlayed)
            restored.gamesWon = max(local.gamesWon, cloud.gamesWon)
            restored.xp = max(local.xp, cloud.xp)
            restored.drawings = max(local.drawings, cloud.drawings)
            restored.guesses = max(local.guesses, cloud.guesses)
            restored.creativeStreak = max(local.creativeStreak ?? 0, cloud.creativeStreak)
            restored.isGuest = false
            profile = restored
            profile.save()
            auth.updateLocalNickname(restored.nickname)
            cloudStatus = auth.isGoogleLinked && restored.gamesPlayed == 0 && restored.xp == 0
                ? "Esta cuenta de Google no tiene progreso. Vincula Google desde el dispositivo que lo conserva."
                : "Progreso cargado de Firebase"
        } catch {
            profileSyncBlocked = true
            profile = local
            socialError = error.localizedDescription
            cloudStatus = "No se pudo cargar Firebase: \(error.localizedDescription)"
        }
        await refreshSocial()
    }
    private func linkGoogleAndTransferProfile() async {
        guard !linkingGoogle, let sourceID = auth.player?.id, sourceID == profile.userID else { return }
        linkingGoogle = true
        transferringGoogleProfile = true
        profileSyncBlocked = true
        cloudStatus = "Vinculando Google…"
        defer { linkingGoogle = false; transferringGoogleProfile = false }
        let source = profile
        do {
            let linked = try await auth.linkGoogleToCurrentUser()
            if linked.id == sourceID {
                profileSyncBlocked = false
                accountMessage = "Google quedó vinculado a esta cuenta. Tu progreso se conserva."
                cloudStatus = "Google vinculado a este ID"
                return
            }
            // Google was already associated with a separate Firebase account. Move the
            // proven current session's progress to that account before displaying it.
            let target = try await FirebaseServiceFactory.social().profileIfExists(userID: linked.id)
            var merged = source
            merged.userID = linked.id
            merged.isGuest = false
            if let target {
                merged.gamesPlayed = max(source.gamesPlayed, target.gamesPlayed)
                merged.gamesWon = max(source.gamesWon, target.gamesWon)
                merged.xp = max(source.xp, target.xp)
                merged.drawings = max(source.drawings, target.drawings)
                merged.guesses = max(source.guesses, target.guesses)
                merged.creativeStreak = max(source.creativeStreak ?? 0, target.creativeStreak)
            }
            try await FirebaseServiceFactory.social().register(userID: linked.id, nickname: merged.nickname,
                avatar: merged.avatar, avatarImageData: merged.avatarImageData,
                gamesPlayed: merged.gamesPlayed, gamesWon: merged.gamesWon, level: merged.level,
                xp: merged.xp, drawings: merged.drawings, guesses: merged.guesses,
                creativeStreak: merged.creativeStreak ?? 0)
            profile = merged
            profile.save()
            auth.updateLocalNickname(merged.nickname)
            profileSyncBlocked = false
            cloudStatus = "Progreso copiado y guardado en Firebase"
            accountMessage = "Tu progreso ya está en la cuenta de Google. Inicia sesión con ella en el otro dispositivo."
            await refreshSocial()
        } catch {
            if let currentID = auth.player?.id, currentID != sourceID {
                var pending = source
                pending.userID = currentID
                pending.isGuest = false
                profile = pending
                profile.save()
                cloudStatus = "Transferencia pendiente: \(error.localizedDescription)"
                accountMessage = "No se guardó aún en Google. Conserva esta sesión y vuelve a cargar el progreso para reintentar."
            } else {
                profileSyncBlocked = false
                cloudStatus = "No se pudo vincular Google"
                accountMessage = error.localizedDescription
            }
        }
    }
    private func recordCompletedGame(_ room: RoomSnapshot) {
        guard profile.lastCompletedRoomID != room.id else { return }
        profile.gamesPlayed += 1
        profile.recordCreativeDay()
        profile.xp += StageOneRules.xpPerCompletedGame
        profile.drawings += room.chains.flatMap(\.entries).filter {
            $0.authorID == profile.userID && $0.drawingURL != nil
        }.count
        profile.lastCompletedRoomID = room.id
    }
    private func makeGuest() {
        let name = StageOneRules.guestName(randomIndex: Int.random(in: 0...4), number: Int.random(in: 10...99))
        Task {
            await auth.signInAsGuest(nickname: name)
            guard let player = auth.player else { return }
            let localOnly = player.id.hasPrefix("local-")
            profile = GameProfile(userID: player.id, username: name, nickname: name, isGuest: true)
            profile.save()
            if localOnly { cloudStatus = "Invitado local · el progreso queda en este dispositivo" }
        }
    }
    private func syncProfile(username: String? = nil) {
        guard let player = auth.player else { return }
        if profile.userID != player.id { profile = GameProfile.load(for: player.id) }; profile.userID = player.id; if profile.nickname.isEmpty { profile.nickname = player.nickname }
        if let username, !username.isEmpty { profile.username = username }
        else if profile.username.isEmpty { profile.username = player.nickname }
        profile.isGuest = player.id.hasPrefix("guest-") || player.id.hasPrefix("local-") || (firebaseConfigured && (try? FirebaseServiceFactory.auth().isCurrentUserAnonymous) == true)
        profile.save()
        if !profile.isGuest, firebaseConfigured {
            let currentProfile = profile
            Task {
                do { try await FirebaseServiceFactory.social().register(userID: player.id, nickname: currentProfile.nickname, avatar: currentProfile.avatar, avatarImageData: currentProfile.avatarImageData, gamesPlayed: currentProfile.gamesPlayed, gamesWon: currentProfile.gamesWon, level: currentProfile.level, xp: currentProfile.xp, drawings: currentProfile.drawings, guesses: currentProfile.guesses, creativeStreak: currentProfile.creativeStreak ?? 0); socialError = nil }
                catch { socialError = error.localizedDescription }
            }
        }
    }
    private func joinRoom() {
        let code = roomCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard firebaseConfigured else {
            providerMessage = "Las salas locales no conectan otros dispositivos. Configura Firebase para unirte con código."
            showProviderMessage = true
            return
        }
        game.roomID = code
        if let player = auth.player { game.connect(player: player); sheet = .waitingRoom }
    }
    private func providerButton(_ title: String, icon: String) -> some View { Button { Task { await auth.signInWithGoogle() } } label: { Label(title, systemImage: icon).font(.system(size: 11, weight: .bold, design: .rounded)).frame(maxWidth: .infinity).padding(9).background(.white.opacity(0.75), in: Capsule()) }.accessibilityHint("Muestra el estado de configuración del proveedor") }
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
    var body: some View { VStack(spacing: 16) { Spacer(minLength: 18); Text("🫧").font(.system(size: 84)); Text("Dibuja. Adivina.\nRíete en grupo.").multilineTextAlignment(.center).font(.system(size: 32, weight: .black, design: .rounded)).foregroundStyle(Aero.ink); Text("La creatividad se pega.").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)); Spacer(); Button(action: onGuest) { Label("Jugar como invitado", systemImage: "sparkles").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(17).background(LinearGradient(colors: [Aero.sky, Aero.aqua], startPoint: .leading, endPoint: .trailing), in: Capsule()).shadow(color: Aero.sky.opacity(0.35), radius: 13, y: 6) }; Button(action: onSignup) { Text("Crear cuenta").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Aero.violet).frame(maxWidth: .infinity, minHeight: 56).background(.white.opacity(0.78), in: Capsule()).contentShape(Capsule()) }; Button(action: onLogin) { Text("Ya tengo cuenta · Iniciar sesión").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.75)).frame(maxWidth: .infinity, minHeight: 54).background(.white.opacity(0.55), in: Capsule()).contentShape(Capsule()) }; provider("Google", symbol: "g.circle.fill"); if !configured { Text("Modo local · Firebase no configurado").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.48)) }; if let message = auth.errorMessage { Text(message).font(.caption).foregroundStyle(.red) }; Spacer(minLength: 18) }.padding(.horizontal, 28).padding(.vertical, 22).alert("Proveedor no configurado", isPresented: $showProviderMessage) { Button("Entendido", role: .cancel) { } } message: { Text(providerMessage) } }
    private func provider(_ title: String, symbol: String) -> some View { Button { Task { await auth.signInWithGoogle() } } label: { Label(title, systemImage: symbol).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)).frame(maxWidth: .infinity).padding(12).background(.white.opacity(0.72), in: Capsule()) }.accessibilityHint("Muestra el estado de configuración del proveedor") }
}

private struct CreateRoomSheet: View {
    @ObservedObject var game: GameViewModel
    let player: Player?
    let configured: Bool
    let friends: [DemoFriend]
    let onCreated: (String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var capacity = 4
    @State private var selectedFriends = Set<String>()
    private let options = StageOneRules.playerLimits
    var body: some View { VStack(spacing: 18) { HStack { Text("Sala privada").font(.system(size: 25, weight: .black, design: .rounded)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.bold).padding(10).background(.white, in: Circle()) } }.foregroundStyle(Aero.ink); TextField("Nombre de sala (opcional)", text: $roomName).padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16)); Text("¿Cuántos juegan?").font(.system(size: 15, weight: .bold, design: .rounded)).frame(maxWidth: .infinity, alignment: .leading); HStack { Text("2"); Slider(value: Binding(get: { Double(capacity) }, set: { capacity = Int($0.rounded()) }), in: 2...8, step: 1).tint(Color(hue: 0.60 - Double(capacity - 2) * 0.013, saturation: 0.95, brightness: 1)); Text("\(capacity)").font(.title3.bold()) }; if !friends.isEmpty { Text("Invitar amigos").font(.headline).frame(maxWidth: .infinity, alignment: .leading); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(friends) { friend in Button { if selectedFriends.contains(friend.username) { selectedFriends.remove(friend.username) } else { selectedFriends.insert(friend.username) } } label: { HStack(spacing: 7) { AvatarBadge(emoji: friend.avatar, size: 34, imageData: friend.avatarImageData); Text(friend.nickname); if selectedFriends.contains(friend.username) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Aero.aqua) } }.padding(8).background(.white.opacity(0.8), in: Capsule()) } } } } } else { Text("Agrega amigos desde la pestaña Amigos para invitarlos aquí.").font(.caption).foregroundStyle(Aero.ink.opacity(0.6)) }; Button { Task { guard let player else { return }; await game.create(player: player, playerLimit: capacity); if game.errorMessage == nil { onCreated(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sala de \(player.nickname)" : roomName.trimmingCharacters(in: .whitespacesAndNewlines), Array(selectedFriends)) } } } label: { Label("Crear sala", systemImage: "sparkles").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(16).background(LinearGradient(colors: [Aero.sky, Aero.aqua], startPoint: .leading, endPoint: .trailing), in: Capsule()) }.disabled(game.state == .loading); if !configured { Text("Sala local de demostración · Este código no conecta otros dispositivos").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)).multilineTextAlignment(.center) }; if let error = game.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }; Spacer(minLength: 0) }.padding(22).background(Aero.backdrop) }
}

private struct WaitingRoomSheet: View {
    @ObservedObject var game: GameViewModel
    let profile: GameProfile
    let configured: Bool
    let roomName: String
    let onExit: () -> Void
    @State private var capacity: Int = 4
    @State private var copied = false
    @State private var showTieCoin = false
    @State private var tieCoinRevealed = false
    @State private var coinRotation = 0.0
    init(game: GameViewModel, profile: GameProfile, configured: Bool, roomName: String, onExit: @escaping () -> Void) {
        self.game = game; self.profile = profile; self.configured = configured; self.roomName = roomName; self.onExit = onExit
        _capacity = State(initialValue: game.room?.settings?.playerLimit ?? 4)
    }
    var body: some View { VStack(spacing: 17) { HStack { Button(action: onExit) { Image(systemName: "xmark").fontWeight(.bold).padding(10).background(.white.opacity(0.78), in: Circle()) }; Spacer(); Text(roomName.uppercased()).font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.2); Spacer().frame(width: 32) }.foregroundStyle(Aero.ink); VStack(spacing: 7) { Text("Tu código").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.56)); Text(game.roomID).font(.system(size: 34, weight: .black, design: .monospaced)).tracking(4).foregroundStyle(Aero.ink); HStack { Button { UIPasteboard.general.string = game.roomID; copied = true } label: { Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc") }.buttonStyle(.borderedProminent).tint(Aero.violet); ShareLink(item: "¡Juega Fonococo conmigo! Código: \(game.roomID)") { Label("Compartir", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered) } }.frame(maxWidth: .infinity).padding(20).glass(); HStack { Text("Jugadores").font(.system(size: 18, weight: .heavy, design: .rounded)); Spacer(); Text("\(game.room?.players.count ?? 1)/\(game.room?.settings?.playerLimit ?? capacity)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Aero.violet) }; VStack(spacing: 10) { ForEach(game.room?.players ?? []) { p in HStack { AvatarBadge(emoji: p.id == profile.userID ? profile.avatar : "🫧", size: 42, imageData: p.id == profile.userID ? profile.avatarImageData : nil); VStack(alignment: .leading) { Text(p.nickname).font(.system(size: 15, weight: .bold, design: .rounded)); Text(p.id == game.room?.players.first?.id ? "Anfitrión" : p.id.hasPrefix("local-demo-opponent-") ? "Rival de prueba · demo" : "Jugador").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.55)) }; Spacer(); if p.id == game.room?.players.first?.id { Image(systemName: "crown.fill").foregroundStyle(Aero.yellow) } }.padding(10).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 17)) } }; if game.isHost { HStack { Text("Máximo de jugadores").font(.system(size: 13, weight: .bold, design: .rounded)); Spacer(); Picker("Capacidad", selection: Binding(get: { game.room?.settings?.playerLimit ?? capacity }, set: { value in capacity = value; Task { await game.updatePlayerLimit(value) } })) { ForEach(max(2, game.room?.players.count ?? 1)...8, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.menu) }.padding(.horizontal, 4) }; VStack(alignment: .leading, spacing: 8) {
            Text("Tiempo para dibujar: \(showTieCoin && !tieCoinRevealed ? "?" : String(Int(game.room?.settings?.drawingSeconds ?? 90))) s").font(.subheadline.bold())
            HStack { ForEach([30, 50, 80, 120], id: \.self) { seconds in
                Button(seconds == 120 ? "2 min" : "\(seconds) s") { Task { await game.voteDrawingTime(seconds) } }
                    .font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(game.room?.drawingTimeVotes?[profile.userID] == seconds ? Aero.sky.opacity(0.55) : .white.opacity(0.7), in: Capsule())
            } }
            Text("\(game.room?.drawingTimeVotes?.count ?? 0) votos").font(.caption)
        }; Spacer(); if game.isHost { Button { Task { await game.start() } } label: { Label("Iniciar partida", systemImage: "play.fill").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(16).background(Aero.violet, in: Capsule()) }.disabled((game.room?.players.count ?? 0) < 2) } else { Text("Esperando al anfitrión…").font(.headline).frame(maxWidth: .infinity) }; if !configured { Text("Demostración local · rival de prueba, sin conexión a otros dispositivos").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Aero.ink.opacity(0.5)).multilineTextAlignment(.center) }; if let error = game.errorMessage { Text(error).font(.caption).foregroundStyle(.red) } }.padding(20).background(Aero.backdrop)
        .overlay {
            if showTieCoin, let winner = game.room?.timeTieWinner {
                VStack(spacing: 14) {
                    Text("🪙").font(.system(size: 76))
                        .rotation3DEffect(.degrees(coinRotation), axis: (x: 0, y: 1, z: 0))
                    Text("Empate: moneda al aire").font(.title3.bold())
                    if tieCoinRevealed { Text("Tiempo elegido: \(winner) segundos").font(.headline) }
                    else { Text("Girando…").font(.headline) }
                }.padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
            }
        }
        .onChange(of: game.room?.timeTieWinner) { _, winner in
            guard winner != nil else { return }
            showTieCoin = true; tieCoinRevealed = false; coinRotation = 0
            withAnimation(.easeOut(duration: 1.4)) { coinRotation = 1440 }
            Task {
                try? await Task.sleep(for: .seconds(1.7)); tieCoinRevealed = true
                try? await Task.sleep(for: .seconds(1.6)); showTieCoin = false
            }
        }
    }
}

private struct MatchmakingSheet: View {
    @ObservedObject var game: GameViewModel
    let player: Player?
    let profile: GameProfile
    let configured: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var deadline: Date?
    @State private var status = "Buscando jugadores..."
    @State private var remaining = 80
    @State private var searchTask: Task<Void, Never>?
    @State private var showVoteCoin = false
    @State private var voteCoinRevealed = false
    @State private var voteCoinRotation = 0.0

    var body: some View {
        VStack(spacing: 22) {
            HStack { Spacer(); Button { searchTask?.cancel(); game.leave(); dismiss() } label: {
                Image(systemName: "xmark").fontWeight(.bold).padding(10).background(.white, in: Circle())
            } }
            Spacer()
            Text("🔎").font(.system(size: 80))
            Text(status).font(.system(size: 24, weight: .heavy, design: .rounded))
            if let room = game.room {
                Text("\(room.players.count)/8 jugadores · \(remaining) s").font(.headline)
                ForEach(room.players) { participant in Text(participant.nickname).font(.subheadline) }
                if room.players.count >= 2 { Text("La partida comenzará al terminar la espera").font(.caption) }
                if room.players.count >= 2, room.earlyStartDecision == nil {
                    Text("¿Empezamos ahora?").font(.headline)
                    HStack {
                        Button("Empezar") { Task { await game.voteEarlyStart(true) } }
                        Button("Seguir esperando") { Task { await game.voteEarlyStart(false) } }
                    }.buttonStyle(.borderedProminent).tint(Aero.sky)
                    Text("\(room.earlyStartVotes?.count ?? 0)/\(room.players.count) votos").font(.caption)
                } else if room.earlyStartDecision == false, !showVoteCoin || voteCoinRevealed {
                    Text("La votación decidió seguir esperando").font(.caption)
                }
            }
            if let error = game.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
            Spacer()
            Button("Cancelar búsqueda") { searchTask?.cancel(); game.leave(); dismiss() }
                .font(.headline).frame(maxWidth: .infinity).padding(15).background(.white.opacity(0.72), in: Capsule())
        }.padding(24).foregroundStyle(Aero.ink).background(Aero.backdrop)
            .overlay {
                if showVoteCoin, let decision = game.room?.earlyStartTieWinner {
                    VStack(spacing: 10) {
                        Text("🪙").font(.system(size: 80))
                            .rotation3DEffect(.degrees(voteCoinRotation), axis: (x: 0, y: 1, z: 0))
                        Text("Empate: moneda al aire").font(.headline)
                        if voteCoinRevealed { Text(decision ? "Empezar" : "Seguir esperando") }
                        else { Text("Girando…") }
                    }.padding(26).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
                }
            }
            .onChange(of: game.room?.earlyStartTieWinner) { _, decision in
                guard decision != nil else { return }
                showVoteCoin = true; voteCoinRevealed = false; voteCoinRotation = 0
                withAnimation(.easeOut(duration: 1.4)) { voteCoinRotation = 1440 }
                Task {
                    try? await Task.sleep(for: .seconds(1.7)); voteCoinRevealed = true
                    try? await Task.sleep(for: .seconds(1.6)); showVoteCoin = false
                }
            }
            .onAppear { searchTask = Task { await search() } }
            .onDisappear { searchTask?.cancel() }
    }
    private func search() async {
        guard configured, let player else { status = "Firebase no está configurado"; return }
        do {
            let result = try await FirebaseServiceFactory.matchmaking().match(player: player)
            guard !Task.isCancelled else { return }
            deadline = result.deadline
            game.roomID = result.roomID
            game.connect(player: player)
            while !Task.isCancelled {
                remaining = max(0, Int(result.deadline.timeIntervalSinceNow.rounded(.up)))
                status = (game.room?.players.count ?? 0) >= 2 ? "Jugadores encontrados" : "Buscando jugadores..."
                if game.room?.earlyStartDecision == true, game.isHost {
                    if game.room?.earlyStartTieWinner != nil { try? await Task.sleep(for: .seconds(3.4)) }
                    await game.start(); return
                }
                if (remaining == 0 || (game.room?.players.count ?? 0) >= 8), game.isHost,
                   (game.room?.players.count ?? 0) >= 2 { await game.start(); return }
                if remaining == 0 { status = "Esperando más jugadores..." }
                try? await Task.sleep(for: .seconds(1))
            }
        } catch { status = error.localizedDescription }
    }
}

private struct EditProfileSheet: View {
    @Binding var profile: GameProfile
    @ObservedObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var photo: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var selectedAvatar: String
    @State private var error: String?
    @State private var saving = false
    @State private var cropScale: CGFloat = 1
    @State private var cropOffset: CGSize = .zero
    private let avatars = ["🐼", "🦊", "🐸", "🐱", "🐻", "🐯", "🐰", "🐙"]
    init(profile: Binding<GameProfile>, auth: AuthViewModel) {
        _profile = profile; self.auth = auth
        _nickname = State(initialValue: profile.wrappedValue.nickname)
        _selectedAvatar = State(initialValue: profile.wrappedValue.avatar)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Editar perfil").font(.system(size: 24, weight: .black, design: .rounded))
                if let image = pendingImage {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 190, height: 190)
                        .scaleEffect(cropScale).offset(cropOffset).frame(width: 190, height: 190)
                        .clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 3))
                        .gesture(DragGesture().onChanged { cropOffset = $0.translation })
                    Slider(value: $cropScale, in: 1...3).tint(Aero.sky)
                    Text("Mueve y amplía la foto para centrarla").font(.caption)
                } else {
                    AvatarBadge(emoji: selectedAvatar, size: 90, imageData: profile.avatarImageData)
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Elegir foto", systemImage: "camera.fill").padding(12).glass()
                }
                HStack { ForEach(avatars, id: \.self) { avatar in
                    Button { selectedAvatar = avatar; pendingImage = nil } label: {
                        Text(avatar).font(.system(size: 26)).padding(5)
                            .background(selectedAvatar == avatar ? Aero.sky.opacity(0.35) : .clear, in: Circle())
                    }
                } }
                TextField("Apodo", text: $nickname).keyboardType(.default).textInputAutocapitalization(.words).autocorrectionDisabled().padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Button { Task { await save() } } label: {
                    Text(saving ? "Guardando…" : "Guardar cambios").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(15).background(Aero.violet, in: Capsule())
                }.disabled(saving)
            }.padding(22).foregroundStyle(Aero.ink)
        }.background(Aero.backdrop)
            .onChange(of: photo) { _, item in Task {
                if let data = try? await item?.loadTransferable(type: Data.self) { pendingImage = UIImage(data: data) }
            } }
    }
    private func save() async {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 24 else { error = "El apodo debe tener entre 1 y 24 caracteres."; return }
        saving = true; defer { saving = false }
        do {
            if name != profile.nickname { try await auth.updateNickname(name) }
            var newProfile = profile
            newProfile.nickname = name
            newProfile.avatar = selectedAvatar
            if let image = pendingImage {
                let size = CGSize(width: 320, height: 320)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let cropped = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    let factor = max(size.width / image.size.width, size.height / image.size.height) * cropScale
                    let drawn = CGSize(width: image.size.width * factor, height: image.size.height * factor)
                    image.draw(in: CGRect(x: (size.width - drawn.width) / 2 + cropOffset.width * size.width / 190,
                                          y: (size.height - drawn.height) / 2 + cropOffset.height * size.height / 190,
                                          width: drawn.width, height: drawn.height))
                }
                newProfile.avatarImageData = cropped.jpegData(compressionQuality: 0.8)?.base64EncodedString()
                newProfile.avatar = "📷"
            } else if selectedAvatar != profile.avatar { newProfile.avatarImageData = nil }
            profile = newProfile
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct FriendsList: View {
    let profile: GameProfile
    @Binding var friends: [DemoFriend]
    @Binding var incoming: [DemoFriend]
    @State private var query = ""
    @State private var errorMessage: String?
    private var filtered: [DemoFriend] { StageOneRules.filterFriends(friends, query: query) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Buscar amigos", text: $query).keyboardType(.default).textInputAutocapitalization(.never).autocorrectionDisabled()
            }.padding(13).background(.white.opacity(0.78), in: Capsule())
            VStack(spacing: 9) {
                ForEach(filtered) { friend in
                    NavigationLink { FriendProfileView(friend: friend) } label: {
                        HStack(spacing: 12) {
                            AvatarBadge(emoji: friend.avatar, size: 50, imageData: friend.avatarImageData)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.nickname).font(.headline)
                                Text("Código \(FirebaseSocialService.friendCode(for: friend.username))").font(.caption)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.padding(10).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 17))
                    }.buttonStyle(.plain)
                }
                if filtered.isEmpty { Text("Aún no hay amigos").font(.subheadline).padding() }
            }.padding(12).glass()
            if !incoming.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Solicitudes recibidas").font(.headline)
                    ForEach(incoming) { friend in
                        HStack(spacing: 10) {
                            AvatarBadge(emoji: friend.avatar, size: 42, imageData: friend.avatarImageData)
                            Text(friend.nickname).font(.subheadline.bold())
                            Spacer()
                            Button { Task { await respond(to: friend, accept: true) } } label: {
                                Image(systemName: "checkmark").frame(width: 42, height: 42)
                                    .background(Aero.aqua, in: Circle())
                            }.accessibilityLabel("Aceptar solicitud")
                            Button { Task { await respond(to: friend, accept: false) } } label: {
                                Image(systemName: "xmark").frame(width: 42, height: 42)
                                    .background(Aero.coral.opacity(0.65), in: Circle())
                            }.accessibilityLabel("Rechazar solicitud")
                        }
                    }
                }.padding(14).glass()
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }.foregroundStyle(Aero.ink)
    }

    private func respond(to friend: DemoFriend, accept: Bool) async {
        do {
            let service = try FirebaseServiceFactory.social()
            if accept {
                try await service.accept(friendID: friend.username, userID: profile.userID, nickname: profile.nickname)
                friends.append(friend)
            } else {
                try await service.reject(friendID: friend.username, userID: profile.userID)
            }
            incoming.removeAll { $0.id == friend.id }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct FriendProfileView: View {
    let friend: DemoFriend
    @State private var latest: SocialProfile?
    var body: some View {
        VStack(spacing: 20) {
            AvatarBadge(emoji: latest?.avatar ?? friend.avatar, size: 150,
                        imageData: latest?.avatarImageData ?? friend.avatarImageData)
            Text(latest?.nickname ?? friend.nickname).font(.system(size: 30, weight: .heavy, design: .rounded))
            Text("Código \(FirebaseSocialService.friendCode(for: friend.username))")
                .font(.system(.subheadline, design: .monospaced))
            HStack(spacing: 12) {
                StatTile(value: "\(latest?.level ?? friend.level ?? 1)", label: "Nivel", icon: "sparkles", color: Aero.sky)
                StatTile(value: "\(latest?.gamesWon ?? friend.gamesWon ?? 0)", label: "Ganadas", icon: "trophy.fill", color: Aero.yellow)
            }
            StatTile(value: "\(latest?.gamesPlayed ?? friend.gamesPlayed ?? 0)", label: "Partidas", icon: "gamecontroller.fill", color: Aero.aqua)
            Spacer()
        }.frame(maxWidth: .infinity).padding(24).background(Aero.backdrop)
            .task { latest = try? await FirebaseServiceFactory.social().profile(userID: friend.username) }
            .navigationTitle("Perfil de amigo")
            .toolbar(.visible, for: .navigationBar)
    }
}

private struct AddFriendSheet: View {
    let profile: GameProfile
    @State private var code = ""
    @State private var message: String?
    var body: some View {
        VStack(spacing: 18) {
            Text("Agregar amigo").font(.title2.bold())
            Text("Tu código: \(FirebaseSocialService.friendCode(for: profile.userID))")
                .font(.system(.headline, design: .monospaced))
            HStack(spacing: 12) {
                Button { UIPasteboard.general.string = FirebaseSocialService.friendCode(for: profile.userID) } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                ShareLink(item: "Agrégame en Fonococo con el código \(FirebaseSocialService.friendCode(for: profile.userID))") {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
            }.buttonStyle(.borderedProminent).tint(Aero.sky)
            TextField("Código de amigo", text: $code).keyboardType(.asciiCapable).textInputAutocapitalization(.characters)
                .autocorrectionDisabled().padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16))
            Button("Enviar solicitud") { Task {
                do {
                    let name = try await FirebaseServiceFactory.social().requestFriend(code: code, from: profile.userID, nickname: profile.nickname)
                    message = "Solicitud enviada a \(name)"
                } catch { message = error.localizedDescription }
            } }.font(.headline).frame(maxWidth: .infinity).padding(14).background(Aero.sky, in: Capsule())
            if let message { Text(message).font(.caption) }
            Spacer()
        }.padding(22).foregroundStyle(Aero.ink).background(Aero.backdrop)
    }
}

private struct AccountSheet: View {
    @ObservedObject var auth: AuthViewModel
    let configured: Bool
    let isSignup: Bool
    let existingUsernames: [String]
    let onDone: (String?) -> Void
    @State private var nickname = ""
    @State private var email = ""
    @State private var password = ""
    @State private var message: String?
    @State private var resetSent = false
    @State private var submitting = false

    var body: some View {
        VStack(spacing: 13) {
            Text(isSignup ? "Crear cuenta" : "Iniciar sesión")
                .font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Aero.ink)
            if isSignup { field("Apodo", text: $nickname) }
            field("Correo electrónico", text: $email)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Contraseña", text: $password)
                .padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14))
            Button { submit() } label: {
                HStack(spacing: 9) { if submitting { ProgressView().tint(.white) }; Text(isSignup ? "Crear cuenta" : "Entrar").font(.system(size: 17, weight: .heavy, design: .rounded)) }
                    .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 56).background(Aero.violet, in: Capsule()).contentShape(Capsule())
            }.disabled(submitting)
            if !isSignup {
                Button("¿Olvidaste tu contraseña?") { Task { await resetPassword() } }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Aero.violet).frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle()).disabled(resetSent)
            }
            if !configured {
                Text("Firebase no está configurado. El modo invitado sigue disponible.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Aero.ink.opacity(0.55)).multilineTextAlignment(.center)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            Spacer(minLength: 0)
        }.padding(22).background(Aero.backdrop)
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
            TextField(title, text: text).keyboardType(title == "Correo electrónico" ? .emailAddress : .default)
                .textInputAutocapitalization(title == "Correo electrónico" ? .never : .words)
                .autocorrectionDisabled(title == "Correo electrónico")
                .padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
    private func submit() {
        guard configured else { message = "Servicio no configurado."; return }
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@"), cleanEmail.contains(".") else {
            message = "Escribe un correo electrónico válido."; return
        }
        if isSignup {
            let cleanNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanNickname.isEmpty, cleanNickname.count <= 24 else {
                message = "Escribe un apodo de hasta 24 caracteres."; return
            }
            guard password.count >= 8 else {
                message = "La contraseña debe tener al menos 8 caracteres."; return
            }
            message = nil; submitting = true
            Task {
                await auth.createAccount(email: cleanEmail, password: password, nickname: cleanNickname)
                submitting = false
                if auth.player != nil { onDone(cleanNickname) }
                else { message = auth.errorMessage }
            }
        } else {
            message = nil; submitting = true
            Task {
                await auth.signIn(email: cleanEmail, password: password)
                submitting = false
                if auth.player != nil { onDone(nil) }
                else { message = auth.errorMessage }
            }
        }
    }
    private func resetPassword() async {
        guard configured else { message = "Firebase no está configurado."; return }
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@"), cleanEmail.contains(".") else {
            message = "Escribe primero el correo de tu cuenta."; return
        }
        do {
            try await auth.sendPasswordReset(to: cleanEmail)
            resetSent = true
            message = "Si existe una cuenta con ese correo, recibirás un enlace para restablecer la contraseña."
        } catch { message = error.localizedDescription }
    }
}

private struct ChangePasswordSheet: View {
    @ObservedObject var auth: AuthViewModel
    let configured: Bool
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var saving = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Cambiar contraseña").font(.title2.bold())
            SecureField("Contraseña actual", text: $currentPassword).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
            SecureField("Nueva contraseña", text: $newPassword).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
            SecureField("Repetir nueva contraseña", text: $confirmation).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
            Button { Task { await save() } } label: {
                HStack { if saving { ProgressView().tint(.white) }; Text("Actualizar contraseña") }
                    .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 54).background(Aero.violet, in: Capsule())
            }.disabled(saving)
            if let message { Text(message).font(.caption).multilineTextAlignment(.center) }
            Text("Confirma tu contraseña actual para proteger la cuenta.").font(.caption).foregroundStyle(Aero.ink.opacity(0.6))
            Spacer()
        }.padding(22).background(Aero.backdrop)
    }
    private func save() async {
        guard configured else { message = "Firebase no está configurado."; return }
        guard !currentPassword.isEmpty, newPassword.count >= 8, newPassword == confirmation else {
            message = "Escribe la contraseña actual y confirma una nueva de al menos 8 caracteres."; return
        }
        saving = true; defer { saving = false }
        do { try await auth.changePassword(current: currentPassword, new: newPassword); message = "Contraseña actualizada." }
        catch { message = error.localizedDescription }
    }
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

private struct OfflineDrawingGallery: View {
    let albums: [ArchivedAlbum]
    @State private var message = ""
    @State private var selectedImage: UIImage?
    private var drawings: [UIImage] {
        albums.flatMap { album in
            guard let payload = try? album.decode(OfflineAlbumPayload.self) else { return [UIImage]() }
            return payload.media.keys.sorted().compactMap { key in
                guard let data = payload.media[key] else { return nil }
                return UIImage(data: data)
            }
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    Text("Mis dibujos").font(.system(size: 28, weight: .heavy, design: .rounded))
                    if drawings.isEmpty { Text("Aún no guardaste dibujos").foregroundStyle(Aero.ink.opacity(0.6)) }
                    let width = min(geometry.size.width - 24, 450.0)
                    let radius = width * 0.34
                    ForEach(Array(stride(from: 0, to: drawings.count, by: 8)), id: \.self) { start in
                        ZStack {
                            Circle().fill(Aero.sky.opacity(0.16)).frame(width: width * 0.35)
                            ForEach(start..<min(start + 8, drawings.count), id: \.self) { index in
                                let angle = 2 * Double.pi * Double(index - start) / Double(min(8, drawings.count - start)) - Double.pi / 2
                                Button { selectedImage = drawings[index] } label: {
                                    Image(uiImage: drawings[index]).resizable().scaledToFill()
                                        .frame(width: 78, height: 78).clipShape(Circle())
                                        .padding(5).glassEffectIfAvailable()
                                }
                                .offset(x: radius * cos(angle), y: radius * sin(angle))
                            }
                        }.frame(width: width, height: width)
                    }
                    if !message.isEmpty { Text(message).font(.caption) }
                }.frame(maxWidth: .infinity).padding(12)
            }
        }
        .background(Aero.backdrop)
        .sheet(item: Binding(get: { selectedImage.map { SelectedDrawing(image: $0) } }, set: { if $0 == nil { selectedImage = nil } })) { chosen in
            VStack(spacing: 20) {
                Image(uiImage: chosen.image).resizable().scaledToFit()
                Button("Guardar en Fotos") { Task {
                    do { try await PhotoLibrarySaver().save(chosen.image); message = "Guardado en Fotos"; selectedImage = nil }
                    catch { message = error.localizedDescription }
                } }.buttonStyle(.borderedProminent).tint(Aero.sky)
            }.padding().presentationDetents([.medium, .large])
        }
    }
}

private struct SelectedDrawing: Identifiable {
    let image: UIImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}

private extension View {
    @ViewBuilder func glassEffectIfAvailable() -> some View {
        if #available(iOS 26, *) { glassEffect(.regular.interactive(), in: Circle()) }
        else { background(.ultraThinMaterial, in: Circle()) }
    }
    @ViewBuilder func glass() -> some View {
        if #available(iOS 26, *) { glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22)) }
        else { background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.9), lineWidth: 1.4)).shadow(color: Aero.ink.opacity(0.07), radius: 12, y: 6) }
    }
    @ViewBuilder func tabGlass() -> some View {
        if #available(iOS 26, *) { glassEffect(.clear.interactive(), in: Capsule()) }
        else { background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.5)) }
    }
    @ViewBuilder func activeTabGlass() -> some View {
        if #available(iOS 26, *) { glassEffect(.clear.tint(Color(red: 0.48, green: 0.77, blue: 1).opacity(0.28)).interactive(), in: Capsule()) }
        else { background(Color(red: 0.48, green: 0.77, blue: 1).opacity(0.24), in: Capsule()) }
    }
}

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
        let updated = RoomSnapshot(id: room.id, phase: room.phase, players: room.players, turns: room.turns, chains: room.chains, deadline: room.deadline, settings: settings, drawingTimeVotes: room.drawingTimeVotes, timeTieWinner: room.timeTieWinner, earlyStartVotes: room.earlyStartVotes, earlyStartTieWinner: room.earlyStartTieWinner, earlyStartDecision: room.earlyStartDecision)
        rooms[roomID] = updated; publish(updated)
    }
    public func start(roomID: String, playerID: String) async throws {
        guard let room = rooms[roomID] else { throw ServiceError.missingRoom }
        guard room.players.first?.id == playerID, room.phase == .lobby, let settings = room.settings else { throw ServiceError.invalidPayload }
        let players: [Player]
        guard room.players.count >= 2 else { throw ServiceError.invalidPayload }
        players = room.players
        guard players.count <= settings.playerLimit else { throw ServiceError.invalidPayload }
        let readyRoom = RoomSnapshot(id: room.id, phase: room.phase, players: players, settings: settings, drawingTimeVotes: room.drawingTimeVotes, timeTieWinner: room.timeTieWinner, earlyStartVotes: room.earlyStartVotes, earlyStartTieWinner: room.earlyStartTieWinner, earlyStartDecision: room.earlyStartDecision)
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
    public func rate(roomID: String, drawingID: String, voterID: String, stars: Int) async throws {
        guard let room = rooms[roomID], (0...5).contains(stars), room.phase == .revealing,
              room.players.contains(where: { $0.id == voterID }),
              room.chains.flatMap(\.entries).contains(where: { $0.id == drawingID && $0.drawingURL != nil && $0.authorID != voterID }) else { throw ServiceError.invalidPayload }
        var ratings = room.ratings ?? [:]
        ratings[drawingID, default: [:]][voterID] = stars
        let ranks = room.podiumTieRanks ?? GameEngine.podiumTieRanks(room, ratings: ratings, coin: UInt64.random(in: UInt64.min...UInt64.max))
        let updated = RoomSnapshot(id: room.id, phase: room.phase, players: room.players, turns: room.turns, chains: room.chains, deadline: room.deadline, settings: room.settings, ratings: ratings, podiumTieRanks: ranks)
        rooms[roomID] = updated
        publish(updated)
    }
    public func voteDrawingTime(roomID: String, voterID: String, seconds: Int) async throws {
        guard let room = rooms[roomID], room.phase == .lobby, room.players.contains(where: { $0.id == voterID }),
              let old = room.settings, [30, 50, 80, 120].contains(seconds) else { throw ServiceError.invalidPayload }
        var votes = room.drawingTimeVotes ?? [:]; votes[voterID] = seconds
        let counts = Dictionary(grouping: votes.values, by: { $0 }).mapValues(\.count)
        let highest = counts.values.max() ?? 0
        let leaders = counts.filter { $0.value == highest }.keys.sorted()
        let tie = leaders.count > 1
        let chosen = tie ? (room.timeTieWinner.flatMap { leaders.contains($0) ? $0 : nil } ?? leaders.randomElement() ?? seconds) : (leaders.first ?? seconds)
        let settings = RoomSettings(playerLimit: old.playerLimit, writingSeconds: old.writingSeconds, drawingSeconds: Double(chosen))
        let updated = RoomSnapshot(id: room.id, phase: room.phase, players: room.players, settings: settings, drawingTimeVotes: votes, timeTieWinner: tie ? chosen : nil)
        rooms[roomID] = updated; publish(updated)
    }
    public func voteEarlyStart(roomID: String, voterID: String, start: Bool) async throws {
        guard let room = rooms[roomID], room.phase == .lobby, room.players.count >= 2,
              room.players.contains(where: { $0.id == voterID }), room.earlyStartDecision == nil else { throw ServiceError.invalidPayload }
        var votes = room.earlyStartVotes ?? [:]; votes[voterID] = start
        let finished = room.players.allSatisfy { votes[$0.id] != nil }
        let yes = votes.values.filter { $0 }.count
        let no = votes.count - yes
        let tie = finished && yes == no
        let coin = Bool.random()
        let decision: Bool? = finished ? (tie ? coin : yes > no) : nil
        let updated = RoomSnapshot(id: room.id, phase: .lobby, players: room.players, settings: room.settings,
                                   drawingTimeVotes: room.drawingTimeVotes, timeTieWinner: room.timeTieWinner,
                                   earlyStartVotes: votes, earlyStartTieWinner: tie ? coin : nil, earlyStartDecision: decision)
        rooms[roomID] = updated; publish(updated)
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
