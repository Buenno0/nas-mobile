import SwiftUI

struct ServerSelectionView: View {
  @Bindable var store: SessionStore
  @FocusState private var isServerFocused: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        BrandHeader()
        serverCard
      }
      .frame(maxWidth: 560)
      .padding(.horizontal, 20)
      .padding(.vertical, 28)
    }
    .scrollDismissesKeyboard(.interactively)
    .ozyScreenBackground()
    .accessibilityIdentifier("serverSelectionScreen")
    .onChange(of: store.serverInput) { _, _ in store.serverDidChange() }
  }

  private var serverCard: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Label("Escolha seu servidor", systemImage: "externaldrive.connected.to.line.below")
          .font(.title2.weight(.semibold))
        Text("Conecte-se ao NAS antes de entrar na sua conta.")
          .font(.subheadline)
          .foregroundStyle(Color.ozMuted)
      }

      if !store.recentServers.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Label("Servidores recentes", systemImage: "clock.arrow.circlepath")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ozMuted)

          ForEach(store.recentServers.prefix(3), id: \.self) { server in
            Button {
              isServerFocused = false
              store.selectRecentServer(server)
              Task { await store.validateServer() }
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "server.rack")
                  .foregroundStyle(Color.ozAccent)
                  .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                  Text(serverName(server))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ozInk)
                  Text(server)
                    .font(.caption)
                    .foregroundStyle(Color.ozMuted)
                    .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(Color.ozMuted)
              }
              .frame(minHeight: 52)
              .padding(.horizontal, 12)
            }
            .buttonStyle(ServerRowButtonStyle())
            .disabled(store.isValidatingServer)
            .accessibilityLabel("Conectar a \(server)")
          }
        }

        HStack(spacing: 12) {
          Rectangle().fill(Color.ozLine).frame(height: 1)
          Text("ou informe outro endereço")
            .font(.caption)
            .foregroundStyle(Color.ozMuted)
            .fixedSize()
          Rectangle().fill(Color.ozLine).frame(height: 1)
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("Endereço do servidor").font(.caption.weight(.semibold))
        TextField("http://localhost:8787", text: $store.serverInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
          .submitLabel(.go)
          .focused($isServerFocused)
          .textFieldStyle(OzymandiasTextFieldStyle(icon: "network"))
          .accessibilityIdentifier("serverField")
          .onSubmit { connect() }
      }

      if let message = store.errorMessage {
        ErrorBanner(message: message)
      }

      Button(action: connect) {
        HStack {
          if store.isValidatingServer { ProgressView().tint(.ozAccentInk) }
          Image(systemName: "antenna.radiowaves.left.and.right")
          Text(store.isValidatingServer ? "Conectando…" : "Conectar ao servidor")
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(PrimaryButtonStyle())
      .disabled(store.isValidatingServer)
      .accessibilityIdentifier("validateServerButton")

      Text("No Mac, inicie o NAS com “nas serve --local”.")
        .font(.caption)
        .foregroundStyle(Color.ozMuted)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .ozyCard()
  }

  private func connect() {
    isServerFocused = false
    Task { await store.validateServer() }
  }

  private func serverName(_ value: String) -> String {
    guard let url = URL(string: value), let host = url.host else { return value }
    return url.port.map { "\(host):\($0)" } ?? host
  }
}

struct LoginView: View {
  @Bindable var store: SessionStore
  let serverURL: URL
  @FocusState private var focusedField: Field?

  private enum Field { case username, password }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        BrandHeader()
        credentialsCard
      }
      .frame(maxWidth: 560)
      .padding(.horizontal, 20)
      .padding(.vertical, 28)
    }
    .scrollDismissesKeyboard(.interactively)
    .ozyScreenBackground()
    .accessibilityIdentifier("loginScreen")
  }

  private var credentialsCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Entrar")
          .font(.title2.weight(.semibold))
        Text("Use sua conta do servidor.")
          .font(.subheadline)
          .foregroundStyle(Color.ozMuted)
      }

      HStack(spacing: 12) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Color.ozOkay)
        VStack(alignment: .leading, spacing: 2) {
          Text("Servidor conectado")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ozOkay)
          Text(serverURL.absoluteString)
            .font(.caption)
            .foregroundStyle(Color.ozMuted)
            .lineLimit(1)
        }
        Spacer()
        Button("Trocar") { store.showServerSelection() }
          .font(.caption.weight(.semibold))
          .accessibilityIdentifier("changeServerButton")
      }
      .padding(12)
      .background(Color.ozOkay.opacity(0.1), in: .rect(cornerRadius: 10))
      .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.ozOkay.opacity(0.55)) }

      if let message = store.errorMessage {
        ErrorBanner(message: message)
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("Usuário").font(.caption.weight(.semibold))
        TextField("seu.usuario", text: $store.username)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.next)
          .focused($focusedField, equals: .username)
          .textFieldStyle(OzymandiasTextFieldStyle(icon: "person"))
          .accessibilityIdentifier("usernameField")
          .onSubmit { focusedField = .password }
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("Senha").font(.caption.weight(.semibold))
        HStack(spacing: 8) {
          Image(systemName: "lock").foregroundStyle(Color.ozMuted)
          Group {
            if store.isPasswordVisible {
              TextField("Senha", text: $store.password)
            } else {
              SecureField("Senha", text: $store.password)
            }
          }
          .textContentType(.password)
          .focused($focusedField, equals: .password)
          .submitLabel(.go)
          .accessibilityIdentifier("passwordField")
          .onSubmit { Task { await store.login() } }
          Button {
            store.isPasswordVisible.toggle()
          } label: {
            Image(systemName: store.isPasswordVisible ? "eye.slash" : "eye")
              .frame(width: 44, height: 44)
          }
          .accessibilityLabel(store.isPasswordVisible ? "Ocultar senha" : "Mostrar senha")
        }
        .padding(.leading, 12)
        .background(Color.ozElevated, in: .rect(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(Color.ozLine) }
      }

      Toggle("Manter conectado", isOn: $store.remember)
        .font(.subheadline)
        .accessibilityIdentifier("rememberToggle")

      Button {
        focusedField = nil
        Task { await store.login() }
      } label: {
        HStack {
          if store.isAuthenticating { ProgressView().tint(.ozAccentInk) }
          Text(store.isAuthenticating ? "Entrando…" : "Entrar")
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(PrimaryButtonStyle())
      .disabled(store.isAuthenticating)
      .accessibilityIdentifier("loginButton")

      DisclosureGroup("Esqueci a senha") {
        Text(
          "Quem administra o servidor pode redefinir a senha no terminal com “nas passwd seu.usuario”."
        )
        .font(.caption)
        .foregroundStyle(Color.ozMuted)
        .padding(.top, 6)
      }
      .font(.caption.weight(.medium))
    }
    .ozyCard()
  }
}

private struct BrandHeader: View {
  var body: some View {
    VStack(spacing: 12) {
      MarkView(size: 72)
      Text("Ozymandias")
        .font(.largeTitle.weight(.bold))
        .tracking(-1)
      Text("Seu acervo, na sua rede.")
        .font(.subheadline)
        .foregroundStyle(Color.ozMuted)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

private struct ErrorBanner: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .foregroundStyle(Color.ozDanger)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(Color.ozDanger.opacity(0.12), in: .rect(cornerRadius: 10))
      .accessibilityIdentifier("errorBanner")
  }
}

private struct OzymandiasTextFieldStyle: TextFieldStyle {
  var icon: String?

  init(icon: String? = nil) { self.icon = icon }

  func _body(configuration: TextField<Self._Label>) -> some View {
    HStack(spacing: 10) {
      if let icon { Image(systemName: icon).foregroundStyle(Color.ozMuted) }
      configuration
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 50)
    .background(Color.ozElevated, in: .rect(cornerRadius: 11))
    .overlay { RoundedRectangle(cornerRadius: 11).stroke(Color.ozLine) }
  }
}

private struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Color.ozAccentInk)
      .frame(minHeight: 50)
      .background(
        Color.ozAccent.opacity(configuration.isPressed ? 0.82 : 1), in: .rect(cornerRadius: 11)
      )
      .scaleEffect(configuration.isPressed ? 0.99 : 1)
      .opacity(isEnabled ? 1 : 0.45)
  }
}

private struct ServerRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        Color.ozElevated.opacity(configuration.isPressed ? 0.65 : 1),
        in: .rect(cornerRadius: 11)
      )
      .overlay { RoundedRectangle(cornerRadius: 11).stroke(Color.ozLine) }
  }
}

extension View {
  fileprivate func ozyScreenBackground() -> some View {
    background {
      LinearGradient(
        colors: [.ozBackground, .ozElevated.opacity(0.48), .ozBackground],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()
    }
  }
}
