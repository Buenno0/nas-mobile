import Foundation

enum PlaybackFailure: LocalizedError, Equatable, Sendable {
  case missingURL
  case ffmpegUnavailable(String)
  case transcodingDisabled(String)
  case preparationFailed(String)

  var errorDescription: String? {
    switch self {
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
    if !plan.url.isEmpty { return .play(plan.url) }
    if plan.mode == .direct { return .failure(.missingURL) }
    if !plan.ffmpegAvailable { return .failure(.ffmpegUnavailable(plan.reason)) }
    if !plan.transcodingEnabled { return .failure(.transcodingDisabled(plan.reason)) }
    return .prepare(plan.reason)
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
