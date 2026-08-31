import SwiftUI

struct SessionView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  let requiresPasswordChange: Bool

  var body: some View {
    TabView {
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
    .accessibilityIdentifier("authenticatedApp")
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
            "Servidor",
            value: session.credential.serverURL.host()
              ?? session.credential.serverURL.absoluteString, icon: "server.rack")
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
