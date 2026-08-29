import SwiftUI

struct SessionView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  let requiresPasswordChange: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          MarkView(size: 72)

          if requiresPasswordChange {
            passwordWarning
          } else {
            Label("Sessão confirmada", systemImage: "checkmark.seal.fill")
              .font(.title2.weight(.semibold))
              .foregroundStyle(Color.ozOkay)
              .accessibilityIdentifier("sessionConfirmed")
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
              icon: "calendar.badge.clock")
          }
          .ozyCard()

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
      .navigationTitle("Ozymandias")
    }
  }

  private var passwordWarning: some View {
    VStack(spacing: 10) {
      Image(systemName: "key.fill").font(.largeTitle)
      Text("Sua senha precisa ser alterada")
        .font(.title2.weight(.semibold))
      Text(
        "Por enquanto, redefina no servidor com “nas passwd \(session.user.username)” e entre novamente."
      )
      .font(.subheadline)
      .multilineTextAlignment(.center)
    }
    .foregroundStyle(Color.ozWarning)
    .padding()
    .accessibilityIdentifier("passwordChangeRequired")
  }

  private func detailRow(_ title: String, value: String, icon: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: icon).foregroundStyle(Color.ozAccent).frame(width: 22)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.caption).foregroundStyle(Color.ozMuted)
        Text(value).font(.subheadline).textSelection(.enabled)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 12)
  }
}
