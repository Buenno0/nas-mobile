import SwiftUI

struct RootView: View {
  @Bindable var store: SessionStore

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Group {
        switch store.phase {
        case .restoring:
          restoringView
        case .restoreFailed(let message):
          RestoreFailedView(store: store, message: message)
        case .signedOut:
          switch store.authenticationStep {
          case .serverSelection:
            ServerSelectionView(store: store)
          case .login(let serverURL):
            LoginView(store: store, serverURL: serverURL)
          }
        case .authenticated(let session):
          SessionView(store: store, session: session, requiresPasswordChange: false)
        case .passwordChangeRequired(let session):
          SessionView(store: store, session: session, requiresPasswordChange: true)
        }
      }

      AppearanceToggle()
        .padding(.top, 8)
        .padding(.trailing, 16)
    }
    .tint(.ozAccent)
    .foregroundStyle(Color.ozInk)
    .background(Color.ozBackground.ignoresSafeArea())
  }

  private var restoringView: some View {
    VStack(spacing: 18) {
      MarkView(size: 64)
      ProgressView()
        .controlSize(.large)
      Text("Restaurando sessão…")
        .font(.subheadline)
        .foregroundStyle(Color.ozMuted)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct AppearanceToggle: View {
  @AppStorage("appearancePreference") private var appearancePreference = "dark"
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      withAnimation(reduceMotion ? nil : .snappy(duration: 0.35, extraBounce: 0.08)) {
        appearancePreference = appearancePreference == "dark" ? "light" : "dark"
      }
    } label: {
      Image(systemName: appearancePreference == "dark" ? "moon.fill" : "sun.max.fill")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Color.ozAccent)
        .frame(width: 44, height: 44)
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.plain)
    .background(.thinMaterial, in: .circle)
    .overlay { Circle().stroke(Color.ozLine) }
    .contentShape(.circle)
    .accessibilityIdentifier("appearanceToggle")
    .accessibilityLabel(appearancePreference == "dark" ? "Usar modo claro" : "Usar modo escuro")
    .accessibilityValue(appearancePreference == "dark" ? "Escuro" : "Claro")
  }
}

private struct RestoreFailedView: View {
  @Bindable var store: SessionStore
  let message: String

  var body: some View {
    VStack(spacing: 18) {
      MarkView(size: 64)
      Image(systemName: "wifi.exclamationmark")
        .font(.largeTitle)
        .foregroundStyle(Color.ozWarning)
      Text("Servidor indisponível")
        .font(.title2.weight(.semibold))
      Text(message)
        .font(.subheadline)
        .foregroundStyle(Color.ozMuted)
        .multilineTextAlignment(.center)
      Button("Tentar novamente") {
        Task { await store.retryRestore() }
      }
      .buttonStyle(.borderedProminent)
      Button("Entrar com outra conta") {
        store.discardStoredSession()
      }
      .buttonStyle(.bordered)
    }
    .padding(24)
    .frame(maxWidth: 420)
  }
}
