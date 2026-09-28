import SwiftUI
import UIKit

// MARK: - Entrar numa sala (Home)

/// Botão flutuante da Home: digitar o código que o amigo mandou.
struct EntrarNaSalaBotao: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @State private var aberto = false

  var body: some View {
    Button {
      aberto = true
    } label: {
      Image(systemName: "shareplay")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.plain)
    .background(.ultraThinMaterial, in: .circle)
    .overlay { Circle().stroke(.white.opacity(0.15)) }
    .accessibilityLabel("Entrar numa sala")
    .accessibilityIdentifier("joinRoomButton")
    .sheet(isPresented: $aberto) {
      EntrarNaSalaSheet(store: store, session: session)
        .presentationDetents([.height(340)])
    }
  }
}

struct EntrarNaSalaSheet: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  var codigoInicial = ""

  @Environment(PlaybackController.self) private var playback
  @Environment(\.dismiss) private var dismiss
  @State private var codigo = ""
  @State private var entrando = false
  @State private var erro: String?
  @FocusState private var focado: Bool

  var body: some View {
    VStack(spacing: 18) {
      VStack(spacing: 6) {
        Text("Assistir junto").font(.title3.weight(.semibold))
        Text("Digite o código da sala que te mandaram.")
          .font(.subheadline)
          .foregroundStyle(Color.ozMuted)
      }

      TextField("ABC123", text: $codigo)
        .font(.system(size: 34, weight: .bold, design: .monospaced))
        .multilineTextAlignment(.center)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .focused($focado)
        .padding(.vertical, 12)
        .background(Color.ozInk.opacity(0.06), in: .rect(cornerRadius: 14))
        .onChange(of: codigo) { _, novo in
          codigo = String(novo.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
        }
        .onSubmit(entrar)
        .accessibilityIdentifier("roomCodeField")

      if let erro {
        Text(erro).font(.footnote).foregroundStyle(Color.ozDanger)
      }

      Button(action: entrar) {
        Group {
          if entrando { ProgressView() } else { Text("Entrar na sala") }
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 50)
      }
      .buttonStyle(.borderedProminent)
      .disabled(codigo.count < 6 || entrando)
    }
    .padding(24)
    .onAppear {
      codigo = codigoInicial
      focado = codigoInicial.isEmpty
      if !codigoInicial.isEmpty { entrar() }
    }
  }

  private func entrar() {
    guard codigo.count == 6, !entrando else { return }
    entrando = true
    erro = nil
    Task {
      do {
        try await playback.sala.entrar(codigo: codigo, store: store, session: session)
        dismiss()
      } catch let e as APIClientError where e.statusCode == 404 {
        erro = "Essa sala não existe mais."
      } catch {
        erro = error.localizedDescription
      }
      entrando = false
    }
  }
}

// MARK: - Convite

struct ConviteSheet: View {
  let sala: SalaController
  @Environment(\.dismiss) private var dismiss
  @State private var copiado = false

  var body: some View {
    VStack(spacing: 20) {
      VStack(spacing: 6) {
        Text("Assistir junto").font(.title3.weight(.semibold))
        let pessoas = sala.estado?.presenca.count ?? 0
        Text(pessoas > 1 ? "\(pessoas) pessoas na sala" : "Mande o convite para quem vai assistir com você.")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.6))
      }

      VStack(spacing: 4) {
        Text(sala.codigo ?? "")
          .font(.system(size: 44, weight: .bold, design: .monospaced))
          .tracking(10)
          .textSelection(.enabled)
        Text("código da sala").font(.caption).foregroundStyle(.white.opacity(0.5))
      }

      ShareLink(item: sala.convite) {
        Label("Compartilhar convite", systemImage: "square.and.arrow.up")
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 50)
      }
      .buttonStyle(.borderedProminent)

      Button {
        UIPasteboard.general.string = sala.convite
        copiado = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
          try? await Task.sleep(for: .seconds(2))
          copiado = false
        }
      } label: {
        Label(copiado ? "Copiado" : "Copiar convite", systemImage: copiado ? "checkmark" : "doc.on.doc")
          .font(.subheadline.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.bordered)
      .tint(copiado ? .green : .white)
      .animation(.snappy, value: copiado)

      Text("Quem abrir precisa ter uma conta no Ozymandias.")
        .font(.caption)
        .foregroundStyle(.white.opacity(0.4))
    }
    .foregroundStyle(.white)
    .padding(24)
    .presentationDetents([.height(420)])
    .presentationBackground(.black.opacity(0.92))
    .preferredColorScheme(.dark)
  }
}

// MARK: - Sobreposição no player

struct SalaOverlay: View {
  @Bindable var sala: SalaController
  let controlesVisiveis: Bool
  @State private var saindo = false

  var body: some View {
    ZStack {
      // Reações subindo
      ZStack {
        ForEach(Array(sala.reacoes.enumerated()), id: \.element.id) { i, r in
          ReacaoFlutuante(emoji: r.emoji).offset(x: CGFloat((i * 23) % 50) - 25)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      .padding(.trailing, 40)
      .padding(.bottom, 150)
      .allowsHitTesting(false)

      // Toasts de entrada e saída
      VStack(spacing: 8) {
        ForEach(sala.avisos) { a in
          Text(a.texto)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.black.opacity(0.75), in: .capsule)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .frame(maxHeight: .infinity, alignment: .bottom)
      .padding(.bottom, 150)
      .animation(.snappy, value: sala.avisos)
      .allowsHitTesting(false)

      // Esperando alguém carregar / erro
      VStack(spacing: 8) {
        if let aguardando = sala.estado?.aguardando, !aguardando.isEmpty {
          faixa("Esperando \(aguardando.joined(separator: ", ")) carregar…", cor: .black.opacity(0.75))
        }
        if let erro = sala.erro {
          faixa(erro, cor: Color.ozDanger.opacity(0.85))
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)
      .padding(.top, 70)
      .allowsHitTesting(false)

      // Mensagens novas com o chat fechado aparecem um instante no canto.
      UltimasDoChat(sala: sala)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, 16)
        .padding(.bottom, 150)

      if sala.faltaParaComecar > 0 { ContagemRegressiva(sala: sala) }

      if controlesVisiveis { painel }
    }
    .foregroundStyle(.white)
    .sheet(isPresented: $sala.mostrandoConvite) { ConviteSheet(sala: sala) }
    .sheet(isPresented: $sala.chatAberto) { ChatDaSala(sala: sala) }
    .confirmationDialog("Sair da sala?", isPresented: $saindo, titleVisibility: .visible) {
      Button("Sair da sala") { sala.sairDeProposito() }
      if sala.souDono {
        Button("Encerrar para todos", role: .destructive) { Task { await sala.encerrar() } }
      }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text(
        sala.souDono
          ? "Você abriu esta sala. Pode sair e deixar os outros assistindo, ou encerrar para todo mundo."
          : "O vídeo continua daqui, só que sem sincronizar com a sala.")
    }
  }

  private var painel: some View {
    VStack(alignment: .trailing, spacing: 8) {
      HStack(spacing: 8) {
        Text(sala.codigo ?? "").font(.caption.monospaced().weight(.semibold)).tracking(2)
        HStack(spacing: -6) {
          ForEach(sala.estado?.presenca ?? [], id: \.self) { nome in
            Text(String(nome.prefix(1)).uppercased())
              .font(.caption2.weight(.bold))
              .foregroundStyle(.black)
              .frame(width: 24, height: 24)
              .background(Color.ozAccent, in: .circle)
              .overlay { Circle().stroke(.black.opacity(0.6), lineWidth: 2) }
              .overlay(alignment: .bottomTrailing) {
                if nome != sala.eu {
                  Circle()
                    .fill(corDaConexao(sala.conexoes[nome]))
                    .frame(width: 9, height: 9)
                    .overlay { Circle().stroke(.black.opacity(0.7), lineWidth: 1.5) }
                    .offset(x: 2, y: 2)
                }
              }
              .accessibilityLabel("\(nome), \(descreverConexao(nome == sala.eu ? nil : sala.conexoes[nome]))")
          }
        }
        Button {
          sala.chatAberto = true
        } label: {
          Text("Chat")
            .overlay(alignment: .topTrailing) {
              if sala.naoLidas > 0 {
                Text("\(sala.naoLidas)")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(.black)
                  .padding(.horizontal, 4)
                  .frame(minWidth: 16, minHeight: 16)
                  .background(Color.ozAccent, in: .capsule)
                  .offset(x: 14, y: -10)
              }
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.18), in: .capsule)
        if sala.souDono {
          Button("🎬") { sala.alternarModoCinema() }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(sala.modoCinema ? Color.ozAccent : .white.opacity(0.18), in: .capsule)
            .accessibilityLabel(sala.modoCinema ? "Desligar modo cinema" : "Modo cinema: só você controla")
        }
        Button("Convidar") { sala.mostrandoConvite = true }
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(.white.opacity(0.18), in: .capsule)
        Button("Sair") { saindo = true }
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(.white.opacity(0.18), in: .capsule)
      }
      .padding(.leading, 12)
      .padding(.trailing, 6)
      .padding(.vertical, 6)
      .background(.black.opacity(0.6), in: .capsule)

      HStack(spacing: 2) {
        ForEach(SalaController.reacoes, id: \.self) { emoji in
          Button {
            sala.reagir(emoji)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
          } label: {
            Text(emoji).font(.title3).frame(width: 36, height: 36)
          }
          .accessibilityLabel("Reagir com \(emoji)")
        }
      }
      .padding(3)
      .background(.black.opacity(0.6), in: .capsule)

      if sala.modoCinema, !sala.souDono {
        Text("🎬 \(sala.estado?.dono ?? "") controla o vídeo")
          .font(.caption)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(.black.opacity(0.6), in: .capsule)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    .padding(.trailing, 14)
    .padding(.bottom, 120)
    .transition(.opacity)
  }

  private func faixa(_ texto: String, cor: Color) -> some View {
    Text(texto)
      .font(.subheadline)
      .padding(.horizontal, 16)
      .padding(.vertical, 9)
      .background(cor, in: .capsule)
  }
}

private struct ReacaoFlutuante: View {
  let emoji: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var subiu = false

  var body: some View {
    Text(emoji)
      .font(.system(size: 40))
      .offset(y: subiu && !reduceMotion ? -260 : 0)
      .opacity(subiu ? 0 : 1)
      .scaleEffect(subiu ? 1 : 0.6)
      .onAppear {
        withAnimation(.easeOut(duration: 3.6)) { subiu = true }
      }
  }
}

private func corDaConexao(_ c: (conexao: RoomConnection, em: Date)?) -> Color {
  guard let c, Date().timeIntervalSince(c.em) < 15 else { return .gray }
  if c.conexao.travado || abs(c.conexao.dif) > 2 { return .red }
  if abs(c.conexao.dif) > 0.5 { return .yellow }
  return .green
}

private func descreverConexao(_ c: (conexao: RoomConnection, em: Date)?) -> String {
  guard let c else { return "você" }
  if Date().timeIntervalSince(c.em) > 15 { return "sem notícias" }
  if c.conexao.travado { return "carregando" }
  let s = abs(c.conexao.dif).formatted(.number.precision(.fractionLength(0...1)))
  return abs(c.conexao.dif) < 0.5 ? "em sincronia" : "\(s) s \(c.conexao.dif > 0 ? "atrás" : "à frente")"
}

/// "3, 2, 1" antes do play que vem depois de uma pausa longa.
private struct ContagemRegressiva: View {
  let sala: SalaController

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
      let falta = sala.faltaParaComecar
      if falta > 0 {
        let n = Int((Double(falta) / 1000).rounded(.up))
        Text("\(n)")
          .font(.system(size: 120, weight: .bold, design: .rounded).monospacedDigit())
          .foregroundStyle(.white)
          .shadow(radius: 20)
          .contentTransition(.numericText(countsDown: true))
          .animation(.snappy, value: n)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.black.opacity(0.4))
          .allowsHitTesting(false)
          .accessibilityLabel("Começa em \(n)")
      }
    }
  }
}

private struct UltimasDoChat: View {
  let sala: SalaController
  @State private var visiveis: [RoomChatLine] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(visiveis, id: \.em) { l in
        (Text(l.de).bold() + Text(": \(l.texto)"))
          .font(.subheadline)
          .lineLimit(2)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(.black.opacity(0.75), in: .rect(cornerRadius: 14))
          .transition(.move(edge: .leading).combined(with: .opacity))
      }
    }
    .frame(maxWidth: 280, alignment: .leading)
    .animation(.snappy, value: visiveis)
    .onTapGesture { sala.chatAberto = true }
    .onChange(of: sala.chat.count) { _, _ in
      guard !sala.chatAberto, let ultima = sala.chat.last, ultima.de != sala.eu else { return }
      visiveis = Array((visiveis + [ultima]).suffix(3))
      Task {
        try? await Task.sleep(for: .seconds(6))
        visiveis.removeAll { $0 == ultima }
      }
    }
  }
}

struct ChatDaSala: View {
  let sala: SalaController
  @State private var texto = ""
  @FocusState private var focado: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollViewReader { rolagem in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            if sala.chat.isEmpty {
              Text("Ninguém falou nada ainda.")
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            ForEach(Array(sala.chat.enumerated()), id: \.offset) { i, l in
              let meu = l.de == sala.eu
              VStack(alignment: meu ? .trailing : .leading, spacing: 2) {
                Text(meu ? "você" : l.de).font(.caption2).foregroundStyle(.white.opacity(0.45))
                Text(l.texto)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 8)
                  .background(meu ? Color.ozAccent : .white.opacity(0.12), in: .rect(cornerRadius: 16))
                  .foregroundStyle(meu ? .black : .white)
              }
              .frame(maxWidth: .infinity, alignment: meu ? .trailing : .leading)
              .id(i)
            }
          }
          .padding()
        }
        .onChange(of: sala.chat.count) { _, n in
          withAnimation { rolagem.scrollTo(n - 1, anchor: .bottom) }
        }
        .onAppear { rolagem.scrollTo(sala.chat.count - 1, anchor: .bottom) }
      }
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 8) {
          TextField("Escreva algo…", text: $texto)
            .focused($focado)
            .submitLabel(.send)
            .onSubmit(mandar)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.1), in: .capsule)
          Button(action: mandar) {
            Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
          }
          .disabled(texto.trimmingCharacters(in: .whitespaces).isEmpty)
          .accessibilityLabel("Enviar")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.black)
      }
      .navigationTitle("Chat da sala")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } }
      }
    }
    .foregroundStyle(.white)
    .presentationDetents([.medium, .large])
    .presentationBackground(.black.opacity(0.94))
    .preferredColorScheme(.dark)
    .onAppear { focado = true }
  }

  private func mandar() {
    sala.falar(texto)
    texto = ""
  }
}

// MARK: - Voltar para a sala (Home)

/// Depois de fechar o app no meio de uma sala, a Home oferece voltar —
/// se a sala ainda existir no servidor.
struct VoltarParaSalaBanner: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @Environment(PlaybackController.self) private var playback
  @State private var sala: RoomState?
  @State private var entrando = false

  var body: some View {
    Group {
      if let sala, !playback.sala.ativa {
        HStack(spacing: 10) {
          Image(systemName: "shareplay").foregroundStyle(Color.ozAccent)
          VStack(alignment: .leading, spacing: 1) {
            Text("Sala \(sala.codigo) aberta").font(.subheadline.weight(.semibold))
            if !sala.presenca.isEmpty {
              Text("com \(sala.presenca.joined(separator: ", "))")
                .font(.caption).foregroundStyle(Color.ozMuted).lineLimit(1)
            }
          }
          Spacer(minLength: 4)
          Button {
            entrando = true
            Task {
              try? await playback.sala.entrar(codigo: sala.codigo, store: store, session: session)
              entrando = false
            }
          } label: {
            if entrando { ProgressView() } else { Text("Voltar") }
          }
          .buttonStyle(.borderedProminent)
          Button {
            UltimaSala.esquecer()
            self.sala = nil
          } label: {
            Image(systemName: "xmark").font(.caption.weight(.bold))
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.ozMuted)
          .accessibilityLabel("Agora não")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
      }
    }
    .task(id: playback.sala.ativa) {
      guard !playback.sala.ativa, let ultima = UltimaSala.atual else {
        sala = nil
        return
      }
      do {
        sala = try await store.room(code: ultima.codigo, for: session)
      } catch {
        UltimaSala.esquecer()
        sala = nil
      }
    }
  }
}
