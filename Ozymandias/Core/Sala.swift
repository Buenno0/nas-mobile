import AVFoundation
import Foundation
import Observation

// MARK: - Modelos

struct RoomState: Codable, Equatable, Sendable {
  let codigo: String
  let fileID: Int
  let tocando: Bool
  let posicao: Double
  let em: Int64
  let por: String?
  let dono: String
  let cliente: String?
  let seq: Int64?
  let presenca: [String]
  let aguardando: [String]?

  enum CodingKeys: String, CodingKey {
    case codigo, tocando, posicao, em, por, dono, cliente, seq, presenca, aguardando
    case fileID = "file_id"
  }

  func with(tocando: Bool? = nil, posicao: Double? = nil, em: Int64) -> RoomState {
    RoomState(
      codigo: codigo, fileID: fileID, tocando: tocando ?? self.tocando,
      posicao: posicao ?? self.posicao, em: em, por: por, dono: dono, cliente: cliente,
      seq: seq, presenca: presenca, aguardando: aguardando)
  }
}

struct RoomMessage: Codable, Sendable {
  let tipo: String
  let estado: RoomState?
  let de: String?
  let emoji: String?
  let agora: Int64
}

struct RoomCommand: Codable, Sendable {
  var tipo: String
  var posicao: Double? = nil
  var fileID: Int? = nil
  var emoji: String? = nil
  var cliente: String? = nil
  var seq: Int64? = nil

  enum CodingKeys: String, CodingKey {
    case tipo, posicao, emoji, cliente, seq
    case fileID = "file_id"
  }
}

struct RoomCreateRequest: Codable, Sendable {
  let fileID: Int
  let posicao: Double
  let tocando: Bool

  enum CodingKeys: String, CodingKey {
    case posicao, tocando
    case fileID = "file_id"
  }
}

// MARK: - Controlador

/// "Assistir junto" no app: o mesmo protocolo do site. A sala manda o estado
/// (tocando, posição, instante) e aqui o `AVPlayer` é mantido nesse ponto —
/// diferença pequena se corrige na velocidade, grande com um pulo.
///
/// Os comandos saem dos gestos do usuário (`PlaybackController.togglePlayback`
/// e `seek(to:)`), nunca de observar o player: o que a própria sala faz com o
/// player não volta para ela como eco.
@MainActor
@Observable
final class SalaController {
  static let reacoes = ["😂", "😱", "😍", "👏", "😢", "🔥", "🍿", "👀"]

  struct Reacao: Identifiable, Equatable {
    let id = UUID()
    let de: String
    let emoji: String
  }

  struct Aviso: Identifiable, Equatable {
    let id = UUID()
    let texto: String
  }

  private(set) var codigo: String?
  private(set) var estado: RoomState?
  private(set) var reacoes: [Reacao] = []
  private(set) var avisos: [Aviso] = []
  private(set) var erro: String?
  /// Quem encerrou a sala, para o aviso de fim.
  var encerradaPor: String?
  /// Abre a folha de convite (logo depois de criar a sala, ou pelo botão).
  var mostrandoConvite = false

  var ativa: Bool { codigo != nil }
  var souDono: Bool { estado.map { $0.dono == session?.user.username } ?? false }

  weak var playback: PlaybackController?

  private var store: SessionStore?
  private var session: AuthenticatedSession?
  private var eventosTask: Task<Void, Never>?
  private var relogioTask: Task<Void, Never>?
  private var puloTask: Task<Void, Never>?
  private var travaTask: Task<Void, Never>?
  private var saidas: [String: Task<Void, Never>] = [:]

  /// Diferença entre o relógio do servidor e o daqui, em ms. Cada mensagem
  /// chega atrasada pela rede, o que puxa a conta para baixo: fica a maior.
  private var desvio: Int64?
  private let cliente = UUID().uuidString
  private var seq: Int64 = 0
  /// Até alcançar o ponto da sala nada do que este aparelho faz vira comando.
  private var sincronizado = false
  private var avisouTrava = false
  private var avisouPronto = false

  private static let pulaAcima = 2.0
  private static let ajustaAcima = 0.3
  private static let ajuste: Float = 0.05

  // MARK: Entrar e sair

  /// Abre uma sala no ponto atual de quem está assistindo.
  func criar(fileID: Int, store: SessionStore, session: AuthenticatedSession) async {
    guard let playback else { return }
    do {
      let novo = try await store.createRoom(
        fileID: fileID, position: playback.currentTime, playing: playback.isPlaying,
        for: session)
      conectar(novo, store: store, session: session)
      mostrandoConvite = true
    } catch {
      erro = error.localizedDescription
    }
  }

  /// Entra pelo código: abre o arquivo da sala no player e se alinha.
  func entrar(codigo bruto: String, store: SessionStore, session: AuthenticatedSession) async throws {
    let codigo = bruto.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let sala = try await store.room(code: codigo, for: session)
    conectar(sala, store: store, session: session)
    await abrirArquivo(sala.fileID)
  }

  func sair() {
    eventosTask?.cancel()
    relogioTask?.cancel()
    puloTask?.cancel()
    travaTask?.cancel()
    saidas.values.forEach { $0.cancel() }
    saidas = [:]
    eventosTask = nil
    relogioTask = nil
    codigo = nil
    estado = nil
    reacoes = []
    avisos = []
    erro = nil
    mostrandoConvite = false
    desvio = nil
    sincronizado = false
    // Desfaz um ajuste fino de velocidade que tenha ficado pela metade.
    if let playback, playback.player.rate != 0 { playback.player.rate = playback.playbackRate }
  }

  func encerrar() {
    enviar(RoomCommand(tipo: "encerrar"))
    sair()
  }

  func reagir(_ emoji: String) { enviar(RoomCommand(tipo: "reacao", emoji: emoji)) }

  /// Link para colar numa conversa: o do site abre no navegador, o do app
  /// abre direto aqui.
  var convite: String {
    guard let codigo, let session, let estado else { return "" }
    var site = session.credential.serverURL
    site.append(path: "watch/\(estado.fileID)")
    let web = "\(site.absoluteString)?sala=\(codigo)"
    return
      "Vem assistir comigo no Ozymandias! Sala \(codigo)\n\nNo app: ozymandias://sala/\(codigo)\nNo navegador: \(web)"
  }

  private func conectar(_ sala: RoomState, store: SessionStore, session: AuthenticatedSession) {
    sair()
    self.store = store
    self.session = session
    codigo = sala.codigo
    estado = sala
    eventosTask = Task { await ouvir(codigo: sala.codigo) }
    relogioTask = Task {
      while !Task.isCancelled {
        alinhar()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  private func ouvir(codigo: String) async {
    var tentativas = 0
    while !Task.isCancelled, self.codigo == codigo {
      guard let store, let session else { return }
      do {
        let eventos = try store.roomEvents(code: codigo, for: session)
        for try await m in eventos {
          tentativas = 0
          receber(m)
          if m.tipo == "fim" { return }
        }
      } catch is CancellationError {
        return
      } catch let e as APIClientError where e.statusCode == 404 {
        erro = "Essa sala não existe mais."
        return
      } catch {
        if await store.handleEventStreamError(error) { return }
      }
      // Caiu a conexão (troca de rede, app em segundo plano): volta.
      tentativas += 1
      try? await Task.sleep(for: .seconds(min(Double(tentativas), 5)))
    }
  }

  private func receber(_ m: RoomMessage) {
    let d = m.agora - Int64(Date().timeIntervalSince1970 * 1000)
    if desvio == nil || d > desvio! { desvio = d }

    switch m.tipo {
    case "fim":
      encerradaPor = m.de ?? "Quem abriu a sala"
      sair()
    case "reacao":
      guard let de = m.de, let emoji = m.emoji else { return }
      let r = Reacao(de: de, emoji: emoji)
      reacoes = Array((reacoes + [r]).suffix(12))
      Task {
        try? await Task.sleep(for: .seconds(4))
        reacoes.removeAll { $0.id == r.id }
      }
    case "estado":
      guard let novo = m.estado else { return }
      if estado?.fileID != novo.fileID {
        sincronizado = false
        if let playback, playback.currentFile?.id != novo.fileID {
          Task { await abrirArquivo(novo.fileID) }
        }
      }
      avisarPresenca(antes: estado?.presenca ?? [], depois: novo.presenca)
      // Eco de um comando nosso mais velho que o último aplicado: vale a
      // presença, não o ponto (era isso que desfazia o pulo no site).
      if novo.cliente == cliente, (novo.seq ?? 0) < seq, let atual = estado {
        estado = RoomState(
          codigo: novo.codigo, fileID: novo.fileID, tocando: atual.tocando,
          posicao: atual.posicao, em: atual.em, por: novo.por, dono: novo.dono,
          cliente: novo.cliente, seq: novo.seq, presenca: novo.presenca,
          aguardando: novo.aguardando)
      } else {
        estado = novo
      }
      erro = nil
      alinhar()
    default:
      break
    }
  }

  private func avisarPresenca(antes: [String], depois: [String]) {
    guard !antes.isEmpty else { return }
    for nome in depois where !antes.contains(nome) {
      if let pendente = saidas.removeValue(forKey: nome) {
        pendente.cancel()
      } else {
        avisar("\(nome) entrou na sala")
      }
    }
    // Só vira "saiu" se durar: uma conexão que cai e volta não conta.
    for nome in antes where !depois.contains(nome) && saidas[nome] == nil {
      saidas[nome] = Task {
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { return }
        saidas[nome] = nil
        avisar("\(nome) saiu da sala")
      }
    }
  }

  private func avisar(_ texto: String) {
    let a = Aviso(texto: texto)
    avisos = Array((avisos + [a]).suffix(4))
    Task {
      try? await Task.sleep(for: .seconds(4))
      avisos.removeAll { $0.id == a.id }
    }
  }

  private func abrirArquivo(_ fileID: Int) async {
    guard let playback, let store, let session else { return }
    do {
      let file = try await store.playbackFile(id: fileID, for: session)
      playback.startForRoom(file: file, store: store, session: session)
    } catch {
      erro = error.localizedDescription
    }
  }

  // MARK: Alinhamento

  private var agoraServidor: Int64 {
    Int64(Date().timeIntervalSince1970 * 1000) + (desvio ?? 0)
  }

  private func alvo() -> Double {
    guard let e = estado else { return 0 }
    guard e.tocando else { return e.posicao }
    return e.posicao + Double(max(0, agoraServidor - e.em)) / 1000
  }

  func alinhar() {
    guard let playback, let e = estado, playback.phase == .ready,
      let item = playback.player.currentItem, item.status == .readyToPlay,
      playback.currentFile?.id == e.fileID
    else { return }
    let player = playback.player
    let agora = player.currentTime().seconds
    guard agora.isFinite else { return }
    let onde = alvo()
    let dif = onde - agora
    let tocando = player.timeControlStatus != .paused

    if abs(dif) < 1, tocando == e.tocando { sincronizado = true }

    if !e.tocando {
      // A sala espera por nós (depois de um pulo, ou travados): avisa quando
      // der para tocar do ponto novo sem engasgar.
      let eu = session?.user.username ?? ""
      let esperando = (e.aguardando ?? []).contains(eu)
      if !esperando {
        avisouPronto = false
      } else if !avisouPronto, abs(dif) < 0.5, item.isPlaybackLikelyToKeepUp {
        avisouPronto = true
        enviar(RoomCommand(tipo: "pronto"))
      }
      if tocando { player.pause() }
      if abs(dif) > 0.5 { pular(para: onde) }
      return
    }

    if abs(dif) > Self.pulaAcima {
      pular(para: onde)
      if !tocando { player.playImmediately(atRate: 1) }
    } else {
      let taxa: Float = abs(dif) > Self.ajustaAcima ? 1 + (dif > 0 ? Self.ajuste : -Self.ajuste) : 1
      if !tocando || player.rate != taxa { player.playImmediately(atRate: taxa) }
    }
  }

  private func pular(para segundos: Double) {
    guard let player = playback?.player else { return }
    player.seek(
      to: CMTime(seconds: segundos, preferredTimescale: 600),
      toleranceBefore: .zero, toleranceAfter: .zero)
  }

  // MARK: Gestos do usuário

  /// O comando vale na hora, sem esperar a volta do servidor: senão o relógio
  /// de alinhamento, com o estado velho, desfazia o gesto no segundo seguinte.
  private func assumir(tocando: Bool? = nil, posicao: Double) {
    seq += 1
    estado = estado?.with(tocando: tocando, posicao: posicao, em: agoraServidor)
  }

  func usuarioTocou(em posicao: Double) {
    guard ativa, sincronizado, estado?.tocando == false else { return }
    assumir(tocando: true, posicao: posicao)
    enviar(RoomCommand(tipo: "play", posicao: posicao))
  }

  func usuarioPausou(em posicao: Double) {
    guard ativa, sincronizado, estado?.tocando == true else { return }
    assumir(tocando: false, posicao: posicao)
    enviar(RoomCommand(tipo: "pause", posicao: posicao))
  }

  /// Arrastando a barra, só o ponto onde o dedo parou vai para a sala.
  func usuarioPulou(para posicao: Double) {
    guard ativa, sincronizado else { return }
    assumir(posicao: posicao)
    puloTask?.cancel()
    puloTask = Task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      enviar(RoomCommand(tipo: "seek", posicao: posicao))
    }
  }

  func usuarioPediuProximo(_ fileID: Int) {
    enviar(RoomCommand(tipo: "arquivo", fileID: fileID))
  }

  /// O player travou carregando: só avisa a sala se durar.
  func estadoDoPlayerMudou(_ status: AVPlayer.TimeControlStatus) {
    guard ativa else { return }
    if status == .waitingToPlayAtSpecifiedRate {
      travaTask?.cancel()
      travaTask = Task {
        try? await Task.sleep(for: .milliseconds(1500))
        guard !Task.isCancelled, estado?.tocando == true else { return }
        avisouTrava = true
        enviar(RoomCommand(tipo: "carregando"))
      }
    } else {
      travaTask?.cancel()
      if status == .playing, avisouTrava {
        avisouTrava = false
        enviar(RoomCommand(tipo: "pronto"))
      }
    }
  }

  private func enviar(_ comando: RoomCommand) {
    guard let codigo, let store, let session else { return }
    var c = comando
    if ["play", "pause", "seek"].contains(c.tipo) {
      c.cliente = cliente
      c.seq = seq
    }
    Task {
      do {
        try await store.sendRoomCommand(c, code: codigo, for: session)
      } catch {
        erro = error.localizedDescription
      }
    }
  }
}
