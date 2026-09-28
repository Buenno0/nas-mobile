import Foundation

enum PlaybackFailure: LocalizedError, Equatable, Sendable {
  case missingURL
  case ffmpegUnavailable(String)
  case transcodingDisabled(String)
  case preparationFailed(String)
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case .unavailable(let reason):
      reason
    case .missingURL:
      "O servidor não informou uma URL de reprodução."
    case .ffmpegUnavailable(let reason):
      "Este arquivo precisa ser convertido, mas o FFmpeg não está disponível. \(reason)"
    case .transcodingDisabled(let reason):
      "Este arquivo precisa ser convertido, mas a transcodificação está desativada. \(reason)"
    case .preparationFailed(let reason):
      reason
    }
  }
}

enum PlaybackDecision: Equatable, Sendable {
  /// Caminho pronto para tocar, ainda sem o token de mídia.
  case play(String)
  /// O servidor precisa converter antes; o texto é o motivo a exibir.
  case prepare(String)
  case failure(PlaybackFailure)
}

/// Decisões de reprodução isoladas do AVFoundation, para poderem ser testadas
/// sem simulador nem player de verdade.
enum PlaybackPlanner {
  /// Margem de folga para renovar o token de mídia antes de ele vencer.
  static let tokenRenewalMargin: TimeInterval = 120

  static func decide(_ plan: PlaybackPlan) -> PlaybackDecision {
    if plan.unavailable == true { return .failure(.unavailable(unavailableMessage(plan))) }
    if !plan.url.isEmpty { return .play(plan.url) }
    if plan.mode == .direct { return .failure(.missingURL) }
    if !plan.ffmpegAvailable { return .failure(.ffmpegUnavailable(plan.reason)) }
    if !plan.transcodingEnabled { return .failure(.transcodingDisabled(plan.reason)) }
    return .prepare(plan.reason)
  }

  /// Texto para um item que existe mas não toca agora. O servidor manda o
  /// motivo; na falta dele, a localização diz de que lado está o arquivo.
  static func unavailableMessage(_ plan: PlaybackPlan) -> String {
    switch plan.location {
    case "nuvem", "baixando":
      return "Este arquivo está só na nuvem, e o Mac está no modo local. Ligue o híbrido no Mac para assistir."
    case "local", "enviando":
      return "Este arquivo está só no disco do Mac. Ele volta quando você estiver em casa, ou depois de enviado à nuvem."
    default:
      return plan.reason.isEmpty ? "Este arquivo não está disponível agora." : plan.reason
    }
  }

  /// O worker da nuvem não informa porcentagem: a barra só respira, e o texto
  /// explica que ele avisa quando terminar.
  static func isCloudPreparation(_ progress: PreparationProgress) -> Bool {
    progress.recipe == "nuvem"
  }

  /// O `AVPlayer` não manda cabeçalho `Authorization`, então o token de mídia
  /// viaja na query. Um token anterior no mesmo nome é substituído.
  static func authorizedMediaURL(
    path: String,
    relativeTo base: URL,
    token: String,
    parameter: String
  ) throws -> URL {
    guard
      let relative = URL(string: path, relativeTo: base)?.absoluteURL,
      var components = URLComponents(url: relative, resolvingAgainstBaseURL: true)
    else { throw PlaybackFailure.missingURL }

    var items = components.queryItems ?? []
    items.removeAll { $0.name == parameter }
    items.append(URLQueryItem(name: parameter, value: token))
    components.queryItems = items

    guard let url = components.url else { throw PlaybackFailure.missingURL }
    return url
  }

  /// Prefere a data absoluta do servidor e cai para a duração relativa.
  static func expiry(of token: MediaTokenResponse, now: Date) -> Date {
    ISO8601.date(from: token.expiresAt) ?? now.addingTimeInterval(TimeInterval(token.validFor))
  }

  static func needsRenewal(
    expiry: Date,
    now: Date,
    margin: TimeInterval = tokenRenewalMargin
  ) -> Bool {
    expiry.timeIntervalSince(now) <= margin
  }
}

// MARK: - Fila

/// A fila de reprodução, separada da view para sobreviver a ela. Uma fila vazia
/// vira o próprio arquivo, que é o que o player fazia à mão antes.
struct PlaybackQueue: Equatable, Sendable {
  private(set) var items: [MediaFileInfo]
  private(set) var index: Int

  init(items: [MediaFileInfo], startingAt file: MediaFileInfo) {
    let resolved = items.isEmpty ? [file] : items
    self.items = resolved
    self.index = resolved.firstIndex { $0.id == file.id } ?? 0
  }

  var current: MediaFileInfo? { items.indices.contains(index) ? items[index] : nil }
  var hasNext: Bool { items.indices.contains(index + 1) }
  var hasPrevious: Bool { items.indices.contains(index - 1) }

  mutating func advance() -> MediaFileInfo? {
    guard hasNext else { return nil }
    index += 1
    return items[index]
  }

  mutating func rewind() -> MediaFileInfo? {
    guard hasPrevious else { return nil }
    index -= 1
    return items[index]
  }
}

enum PlaybackQueueBuilder {
  /// Tocar uma faixa de dentro de um álbum enfileira o álbum inteiro, como a
  /// tela de artista já fazia — antes, a mesma faixa se comportava de um jeito
  /// em cada tela.
  ///
  /// Vídeo fica de fora de propósito: quem decide o próximo episódio é o
  /// servidor, em `/api/files/{id}/next`, que sabe de coisas que uma lista local
  /// não sabe. Montar uma fila de temporada aqui atropelaria essa decisão.
  static func queue(for detail: TitleDetail, startingAt file: MediaFileInfo) -> [MediaFileInfo] {
    guard file.mediaType == .audio else { return [] }
    let tracks = detail.files.filter { $0.mediaType == .audio }
    guard tracks.count > 1 else { return [] }
    return tracks.sorted { left, right in
      switch (left.track, right.track) {
      case let (leftTrack?, rightTrack?): leftTrack < rightTrack
      case (nil, _?): false
      case (_?, nil): true
      case (nil, nil): left.id < right.id
      }
    }
  }
}

// MARK: - Faixa de áudio

/// Distingue "o servidor escolhe" de "o usuário escolheu". Só a segunda vira
/// parâmetro na requisição: o servidor chaveia o material já preparado pela
/// faixa de áudio, então mandar um índice onde antes não se mandava nada faria
/// o acervo inteiro ser transcodificado de novo.
enum AudioSelection: Equatable, Sendable {
  case automatic(resolved: Int?)
  case explicit(Int)

  var requestValue: Int? {
    if case .explicit(let index) = self { return index }
    return nil
  }

  var displayIndex: Int? {
    switch self {
    case .automatic(let resolved): resolved
    case .explicit(let index): index
    }
  }

  var isAutomatic: Bool {
    if case .automatic = self { return true }
    return false
  }
}

extension PlaybackPlanner {
  /// A faixa que o servidor marca como padrão; senão a do idioma do aparelho,
  /// com mais canais em caso de empate; senão a de mais canais. Faixa forçada
  /// nunca ganha sozinha — ela existe para cobrir trechos, não para ser a trilha.
  static func preferredAudioTrack(
    in tracks: [MediaTrack],
    preferredLanguages: [String] = Locale.preferredLanguages
  ) -> MediaTrack? {
    let candidates = tracks.filter { $0.isForced != true }
    guard !candidates.isEmpty else { return nil }
    if let serverDefault = candidates.first(where: { $0.isDefault == true }) { return serverDefault }

    for language in preferredLanguages.compactMap(normalizedLanguage) {
      let matching = candidates.filter { normalizedLanguage($0.language) == language }
      if let best = matching.max(by: { ($0.channels ?? 0) < ($1.channels ?? 0) }) { return best }
    }
    return candidates.max(by: { ($0.channels ?? 0) < ($1.channels ?? 0) })
  }

  /// O ffprobe entrega ISO 639-2/B (`por`, `eng`) e o sistema fala BCP-47
  /// (`pt-BR`, `en`). Sem normalizar, nenhuma comparação de idioma acerta.
  static func normalizedLanguage(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    let language = Locale.Language(identifier: raw)
    return language.languageCode?.identifier(.alpha2)
  }

  /// Dobra no rótulo o que o servidor já mandava e o app jogava fora: número de
  /// canais, marca de padrão e de forçada.
  static func audioTrackLabel(for track: MediaTrack) -> String {
    var parts = [track.label]
    if let channels = track.channels {
      let text = channelLabel(channels)
      if !track.label.localizedCaseInsensitiveContains(text) { parts.append(text) }
    }
    if track.isDefault == true { parts.append("padrão") }
    if track.isForced == true { parts.append("forçada") }
    return parts.joined(separator: " · ")
  }

  static func channelLabel(_ channels: Int) -> String {
    switch channels {
    case ...1: "mono"
    case 2: "estéreo"
    case 6: "5.1"
    case 8: "7.1"
    default: "\(channels) canais"
    }
  }
}

// MARK: - Sessão de áudio

enum AudioInterruption: Equatable, Sendable {
  case began
  case ended(shouldResume: Bool)
}

enum AudioRouteChange: Equatable, Sendable {
  case outputDisconnected
  case outputConnected
  case other
}

enum AudioSessionEvent: Equatable, Sendable {
  case interruption(AudioInterruption)
  case routeChanged(AudioRouteChange)
  case mediaServicesReset
}

enum PlaybackCommand: Equatable, Sendable {
  case none
  case pause
  case resume
  case reload
}

enum InterruptionPolicy {
  /// Uma ligação pausa e devolve a reprodução ao desligar; tirar o fone pausa e
  /// não retoma sozinho, para o som não sair no alto-falante.
  static func command(for event: AudioSessionEvent, wasPlaying: Bool) -> PlaybackCommand {
    switch event {
    case .interruption(.began):
      wasPlaying ? .pause : .none
    case .interruption(.ended(let shouldResume)):
      shouldResume && wasPlaying ? .resume : .none
    case .routeChanged(.outputDisconnected):
      .pause
    case .routeChanged:
      .none
    case .mediaServicesReset:
      .reload
    }
  }
}

// MARK: - Progresso

enum ProgressCheckpoint {
  /// Abaixo disso não vale a ida ao servidor: o laço grava a cada 10 s e o
  /// usuário também gera gravação ao pausar, trocar de faixa e sair.
  static let minimumDelta: Double = 3

  static func shouldPersist(position: Double, duration: Double, lastPersisted: Double?) -> Bool {
    guard position.isFinite, duration.isFinite, position >= 0, duration > 0 else { return false }
    guard let lastPersisted else { return true }
    if position >= duration { return true }
    return abs(position - lastPersisted) >= minimumDelta
  }
}
