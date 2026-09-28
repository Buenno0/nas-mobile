import SwiftUI

struct SessionView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  let requiresPasswordChange: Bool

  @Environment(PlaybackController.self) private var playback
  @State private var codigoDoLink: CodigoDeSala?

  var body: some View {
    @Bindable var playback = playback
    return TabView {
      Tab("Início", systemImage: "house.fill") {
        NavigationStack {
          HomeView(store: store, session: session)
        }
      }

      Tab("Acervo", systemImage: "rectangle.grid.2x2.fill") {
        NavigationStack {
          CatalogView(store: store, session: session)
        }
      }

      Tab("Coleções", systemImage: "rectangle.stack.fill") {
        NavigationStack {
          CollectionsView(store: store, session: session)
        }
      }
      .accessibilityIdentifier("collectionsTab")

      Tab("Artistas", systemImage: "music.mic") {
        NavigationStack {
          ArtistsView(store: store, session: session)
        }
      }
      .accessibilityIdentifier("artistsTab")

      Tab("Perfil", systemImage: "person.crop.circle") {
        NavigationStack {
          ProfileView(
            store: store,
            session: session,
            requiresPasswordChange: requiresPasswordChange
          )
        }
      }
      .accessibilityIdentifier("profileTab")
    }
    // O acessório é o mecanismo do iOS 26 para isto: fica acima da tab bar sem
    // roubar a área de toque dela, e acompanha a minimização ao rolar.
    .tabViewBottomAccessory {
      // A sobrecarga com `isEnabled:` só existe no iOS 26.1; o alvo é 26.0.
      if playback.hasItem { MiniPlayerBar(playback: playback) }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .fullScreenCover(isPresented: $playback.isPresentingFullScreen) {
      PlayerView(playback: playback)
    }
    // ozymandias://sala/CÓDIGO: o convite abre o app direto na sala.
    .onOpenURL { url in
      guard url.scheme == "ozymandias", url.host() == "sala" else { return }
      let codigo = url.lastPathComponent.uppercased()
      guard codigo.count == 6 else { return }
      codigoDoLink = CodigoDeSala(id: codigo)
    }
    .sheet(item: $codigoDoLink) { codigo in
      EntrarNaSalaSheet(store: store, session: session, codigoInicial: codigo.id)
        .presentationDetents([.height(340)])
    }
    .alert(
      "A sala foi encerrada",
      isPresented: Binding(
        // Com o player aberto, quem mostra o aviso é ele: um alerta aqui
        // ficaria escondido atrás do fullScreenCover.
        get: { playback.sala.encerradaPor != nil && !playback.isPresentingFullScreen },
        set: { if !$0 { playback.sala.encerradaPor = nil } })
    ) {
      Button("Continuar sozinho") { playback.sala.encerradaPor = nil }
    } message: {
      Text("\(playback.sala.encerradaPor ?? "") encerrou a sessão. Você pode continuar assistindo sozinho.")
    }
    .accessibilityIdentifier("authenticatedApp")
  }
}

/// A barra que prova que a reprodução sobreviveu ao fechamento do player.
private struct MiniPlayerBar: View {
  let playback: PlaybackController

  var body: some View {
    HStack(spacing: 12) {
      artwork

      VStack(alignment: .leading, spacing: 1) {
        Text(playback.currentTitle)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(Color.ozMuted)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(.rect)
      .onTapGesture { playback.presentFullScreen() }

      Button(action: playback.togglePlayback) {
        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 15, weight: .bold))
          .frame(width: 32, height: 32)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(playback.isPlaying ? "Pausar" : "Reproduzir")
      .accessibilityIdentifier("miniPlayerPlayPauseButton")

      Button {
        Task { await playback.stop() }
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold))
          .frame(width: 32, height: 32)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Encerrar reprodução")
      .accessibilityIdentifier("miniPlayerCloseButton")
    }
    .padding(.horizontal, 12)
    .foregroundStyle(Color.ozInk)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("miniPlayerBar")
  }

  private var artwork: some View {
    RoundedRectangle(cornerRadius: 6)
      .fill(
        LinearGradient(
          colors: [Color.ozElevated, Color.ozAccent.opacity(0.48)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(width: 32, height: 32)
      .overlay {
        if let image = playback.artwork {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          Image(systemName: "music.note")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.ozInk.opacity(0.7))
        }
      }
      .clipShape(.rect(cornerRadius: 6))
      .accessibilityHidden(true)
  }

  /// O rótulo do episódio, e "Preparando" enquanto o servidor transcodifica —
  /// senão a barra mostraria um play que não faz nada.
  private var subtitle: String {
    switch playback.phase {
    case .preparing(let progress, _): "Preparando · \(progress.percentage)%"
    case .loading, .idle: "Carregando…"
    case .failed: "Não foi possível reproduzir"
    case .ready: playback.episodeLabel
    }
  }
}

private struct ProfileView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  let requiresPasswordChange: Bool
  @AppStorage("appearancePreference") private var appearancePreference = "dark"

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        MarkView(size: 72)

        Label("Sessão confirmada", systemImage: "checkmark.seal.fill")
          .font(.title2.weight(.semibold))
          .foregroundStyle(Color.ozOkay)
          .accessibilityIdentifier("sessionConfirmed")

        if requiresPasswordChange {
          VStack(alignment: .leading, spacing: 6) {
            Label("Altere sua senha inicial", systemImage: "key.fill")
              .font(.subheadline.weight(.semibold))
            Text(
              "Quem administra o servidor faz isso no terminal com “nas passwd \(session.user.username)”."
            )
            .font(.caption)
            .textSelection(.enabled)
          }
          .foregroundStyle(Color.ozWarning)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.ozWarning.opacity(0.1), in: .rect(cornerRadius: 12))
          .accessibilityIdentifier("passwordChangeNotice")
        }

        if expiresSoon {
          VStack(alignment: .leading, spacing: 6) {
            Label("Sua sessão está perto de vencer", systemImage: "clock.badge.exclamationmark")
              .font(.subheadline.weight(.semibold))
            Text("Ela vence \(expiryRelativeDescription). Depois disso o app pede a senha de novo.")
              .font(.caption)
          }
          .foregroundStyle(Color.ozWarning)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.ozWarning.opacity(0.1), in: .rect(cornerRadius: 12))
          .accessibilityIdentifier("sessionExpiryWarning")
        }

        VStack(spacing: 0) {
          detailRow("Usuário", value: session.user.username, icon: "person")
          Divider().overlay(Color.ozLine)
          detailRow(
            "Perfil", value: session.user.isAdmin ? "Administrador" : "Usuário",
            icon: "person.badge.key")
          Divider().overlay(Color.ozLine)
          detailRow(
            store.isAway ? "Servidor · pela nuvem" : "Servidor",
            value: session.credential.serverURL.host()
              ?? session.credential.serverURL.absoluteString,
            icon: store.isAway ? "cloud" : "server.rack")
          Divider().overlay(Color.ozLine)
          detailRow(
            "Sessão válida até",
            value: session.credential.expiresAt.formatted(date: .abbreviated, time: .shortened),
            icon: "calendar.badge.clock",
            tint: expiresSoon ? .ozWarning : .ozAccent)
        }
        .ozyCard()

        VStack(alignment: .leading, spacing: 10) {
          Label("Aparência", systemImage: "circle.lefthalf.filled")
            .font(.caption)
            .foregroundStyle(Color.ozMuted)
          Picker("Aparência", selection: $appearancePreference) {
            Text("Escuro").tag("dark")
            Text("Claro").tag("light")
            Text("Sistema").tag("system")
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("appearancePicker")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ozyCard()

        NavigationLink {
          ServerDashboardView(store: store, session: session)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "server.rack").foregroundStyle(Color.ozAccent)
            VStack(alignment: .leading, spacing: 3) {
              Text("Servidor").font(.headline)
              Text("Acervo, varredura e métricas")
                .font(.caption)
                .foregroundStyle(Color.ozMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.ozMuted)
          }
          .padding(16)
          .ozyCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("serverDashboardButton")

        NavigationLink {
          TVPairingView(store: store, session: session)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "qrcode.viewfinder").foregroundStyle(Color.ozAccent)
            VStack(alignment: .leading, spacing: 3) {
              Text("Conectar uma TV").font(.headline)
              Text("Escaneie o QR Code mostrado no Fire TV")
                .font(.caption)
                .foregroundStyle(Color.ozMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.ozMuted)
          }
          .padding(16)
          .ozyCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pairTVButton")

        NavigationLink {
          ServerSettingsView(store: store, session: session)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "gearshape.fill").foregroundStyle(Color.ozAccent)
            VStack(alignment: .leading, spacing: 3) {
              Text("Configurações").font(.headline)
              Text("TMDB, FFmpeg e varredura automática")
                .font(.caption)
                .foregroundStyle(Color.ozMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.ozMuted)
          }
          .padding(16)
          .ozyCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("serverSettingsButton")

        Button(role: .destructive) {
          Task { await store.logout() }
        } label: {
          HStack {
            if store.isLoggingOut { ProgressView() }
            Text(store.isLoggingOut ? "Saindo…" : "Sair")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(store.isLoggingOut)
        .accessibilityIdentifier("logoutButton")
      }
      .frame(maxWidth: 560)
      .padding(20)
    }
    .background(Color.ozBackground)
    .navigationTitle("Perfil")
  }

  /// Um dia de antecedência é tempo de sobra para reentrar sem ser pego de
  /// surpresa por um 401 no meio de um filme.
  private var expiresSoon: Bool {
    session.credential.expiresAt.timeIntervalSinceNow < 24 * 60 * 60
  }

  private var expiryRelativeDescription: String {
    session.credential.expiresAt.formatted(
      .relative(presentation: .named, unitsStyle: .wide))
  }

  private func detailRow(
    _ title: String,
    value: String,
    icon: String,
    tint: Color = .ozAccent
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.caption).foregroundStyle(Color.ozMuted)
        Text(value).font(.subheadline).textSelection(.enabled)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 12)
  }
}

private struct CodigoDeSala: Identifiable {
  let id: String
}
