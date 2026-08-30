import Foundation

struct HealthResponse: Codable, Equatable, Sendable {
  let status: String
  let time: String
}

struct LoginRequest: Codable, Equatable, Sendable {
  let username: String
  let password: String
  let remember: Bool
  let tokenNaResposta: Bool

  enum CodingKeys: String, CodingKey {
    case username, password, remember
    case tokenNaResposta = "token_na_resposta"
  }
}

struct UserResponse: Codable, Equatable, Sendable {
  let username: String
  let mustChangePassword: Bool
  let isAdmin: Bool
  let token: String?
  let expiraEm: String?

  enum CodingKeys: String, CodingKey {
    case username, token
    case mustChangePassword = "must_change_password"
    case isAdmin = "is_admin"
    case expiraEm = "expira_em"
  }
}

struct APIErrorResponse: Codable, Equatable, Sendable {
  let error: String
}

struct LogoutResponse: Codable, Equatable, Sendable {
  let ok: Bool
}

struct SessionCredential: Codable, Equatable, Sendable {
  let serverURL: URL
  let token: String
  let expiresAt: Date
}

struct AuthenticatedSession: Equatable, Sendable {
  let user: UserResponse
  let credential: SessionCredential
}

enum Loadable<Value: Equatable & Sendable>: Equatable, Sendable {
  case idle
  case loading
  case loaded(Value)
  case failed(String)

  var value: Value? {
    if case .loaded(let value) = self { return value }
    return nil
  }

  /// Entra em `.loading` sem descartar conteúdo já carregado, para que um
  /// "puxar para atualizar" mantenha a tela no lugar em vez de virar spinner.
  mutating func beginLoading() {
    if case .loaded = self { return }
    self = .loading
  }
}

enum ISO8601 {
  /// O servidor envia tanto `2026-08-28T12:00:00Z` quanto
  /// `2026-08-28T12:00:00.123Z`; aceitar só um dos dois quebra o login.
  static func date(from value: String) -> Date? {
    let variants: [ISO8601DateFormatter.Options] = [
      [.withInternetDateTime, .withFractionalSeconds],
      [.withInternetDateTime],
    ]
    for options in variants {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = options
      if let date = formatter.date(from: value) { return date }
    }
    return nil
  }
}

enum TitleKind: String, Codable, Equatable, Hashable, Sendable {
  case movie, tv, album, photos
}

struct TitleCard: Codable, Equatable, Identifiable, Sendable {
  let id: Int
  let libraryID: Int
  let kind: TitleKind
  let name: String
  let year: Int?
  let artist: String?
  let rating: Double?
  let poster: String?
  let backdrop: String?
  let genres: String?
  let files: Int
  let duration: Double?
  let metaState: String

  enum CodingKeys: String, CodingKey {
    case id, kind, name, year, artist, rating, poster, backdrop, genres, files, duration
    case libraryID = "library_id"
    case metaState = "meta_state"
  }
}

struct ContinueItem: Codable, Equatable, Identifiable, Sendable {
  let fileID: Int
  let titleID: Int
  let titleName: String
  let kind: TitleKind
  let label: String?
  let poster: String?
  let backdrop: String?
  let position: Double
  let duration: Double

  var id: Int { fileID }

  enum CodingKeys: String, CodingKey {
    case kind, label, poster, backdrop, position, duration
    case fileID = "file_id"
    case titleID = "title_id"
    case titleName = "title_name"
  }
}

struct HomeRow: Codable, Equatable, Identifiable, Sendable {
  let key: String
  let title: String
  let items: [TitleCard]
  var id: String { key }
}

struct HomeResponse: Codable, Equatable, Sendable {
  let hero: TitleCard?
  let continueItems: [ContinueItem]
  let forgotten: [ContinueItem]?
  let rows: [HomeRow]

  enum CodingKeys: String, CodingKey {
    case hero, rows
    case continueItems = "continue"
    case forgotten = "esquecidos"
  }
}

struct ArtistCard: Codable, Equatable, Identifiable, Sendable {
  let name: String
  let albums: Int
  let tracks: Int
  let duration: Double
  let poster: String?

  var id: String { name }

  enum CodingKeys: String, CodingKey {
    case duration = "duracao"
    case name = "nome"
    case albums = "albuns"
    case tracks = "faixas"
    case poster
  }
}

struct ArtistDetail: Codable, Equatable, Sendable {
  let name: String
  let albums: [TitleCard]
  let tracks: [MediaFileInfo]
  let duration: Double

  enum CodingKeys: String, CodingKey {
    case duration = "duracao"
    case name = "nome"
    case albums = "albuns"
    case tracks = "faixas"
  }
}

struct MediaLibrary: Codable, Equatable, Identifiable, Sendable {
  let id: Int
  let name: String
  let path: String?
  let kind: String
  let enabled: Bool
  let scannedAt: String?

  enum CodingKeys: String, CodingKey {
    case id, name, path, kind, enabled
    case scannedAt = "scanned_at"
  }
}

struct TitlesResponse: Codable, Equatable, Sendable {
  let items: [TitleCard]
  let total: Int
  let offset: Int
  let limit: Int
}

struct CatalogContent: Equatable, Sendable {
  let libraries: [MediaLibrary]
  private(set) var items: [TitleCard]
  private(set) var total: Int
  private(set) var loadedCount: Int

  init(libraries: [MediaLibrary], titles: TitlesResponse) {
    self.libraries = libraries
    self.items = titles.items
    self.total = titles.total
    self.loadedCount = titles.offset + titles.items.count
  }

  var canLoadMore: Bool { loadedCount < total }

  /// Anexa a próxima página. Uma página vazia encerra a paginação para que a
  /// rolagem não fique pedindo o mesmo offset para sempre.
  mutating func append(_ page: TitlesResponse) {
    guard !page.items.isEmpty else {
      total = items.count
      loadedCount = items.count
      return
    }
    let known = Set(items.map(\.id))
    items.append(contentsOf: page.items.filter { !known.contains($0.id) })
    total = page.total
    loadedCount = max(loadedCount, page.offset + page.items.count)
  }
}

enum CatalogSort: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case name, year, recent

  var label: String {
    switch self {
    case .name: "Nome"
    case .year: "Ano"
    case .recent: "Recentes"
    }
  }
}

struct CatalogQuery: Equatable, Hashable, Sendable {
  var libraryID: Int?
  var kind: TitleKind?
  var text: String
  var sort: CatalogSort
  var limit: Int
  var offset: Int

  init(
    libraryID: Int? = nil,
    kind: TitleKind? = nil,
    text: String = "",
    sort: CatalogSort = .recent,
    limit: Int = 60,
    offset: Int = 0
  ) {
    self.libraryID = libraryID
    self.kind = kind
    self.text = text
    self.sort = sort
    self.limit = limit
    self.offset = offset
  }
}

struct MediaCollection: Codable, Equatable, Identifiable, Sendable {
  let id: Int
  let name: String
  let itemCount: Int
  let poster: String?
  let createdAt: Int64
  let updatedAt: Int64

  enum CodingKeys: String, CodingKey {
    case id, poster
    case name = "nome"
    case itemCount = "itens"
    case createdAt = "criada_em"
    case updatedAt = "atualizada_em"
  }
}

struct CollectionContent: Codable, Equatable, Sendable {
  let collection: MediaCollection
  let items: [TitleCard]

  enum CodingKeys: String, CodingKey {
    case collection = "colecao"
    case items = "itens"
  }
}

struct CollectionNameRequest: Codable, Equatable, Sendable {
  let name: String

  enum CodingKeys: String, CodingKey { case name = "nome" }
}

struct OperationResponse: Codable, Equatable, Sendable {
  let ok: Bool
}

struct TitleCollectionsResponse: Codable, Equatable, Sendable {
  let collectionIDs: [Int]

  enum CodingKeys: String, CodingKey { case collectionIDs = "colecoes" }
}

struct ScanStatus: Codable, Equatable, Sendable {
  let running: Bool
  let stage: String?
  let library: String?
  let current: Int?
  let total: Int?
  let file: String?
  let lastStats: String?
  let lastRun: String?
  let lastError: String?

  enum CodingKeys: String, CodingKey {
    case running, stage, library, current, total, file
    case lastStats = "last_stats"
    case lastRun = "last_run"
    case lastError = "last_error"
  }
}

struct StartedResponse: Codable, Equatable, Sendable {
  let started: Bool
}

struct ProcessSample: Codable, Equatable, Sendable {
  let cpuPercent: Double
  let cpuCores: Double
  let heapBytes: UInt64
  let peakRSSBytes: UInt64
  let goroutines: Int
  let cores: Int

  enum CodingKeys: String, CodingKey {
    case goroutines
    case cpuPercent = "cpu_percent"
    case cpuCores = "cpu_nucleos"
    case heapBytes = "heap_bytes"
    case peakRSSBytes = "rss_pico_bytes"
    case cores = "nucleos"
  }
}

struct RouteMetric: Codable, Equatable, Identifiable, Sendable {
  let route: String
  let total: Int64
  let clientErrors: Int64
  let serverErrors: Int64
  let errorRate: Double
  let averageMS: Double
  let maximumMS: Double
  let p50MS: Double
  let p95MS: Double

  var id: String { route }

  enum CodingKeys: String, CodingKey {
    case total
    case route = "rota"
    case clientErrors = "erros_4xx"
    case serverErrors = "erros_5xx"
    case errorRate = "taxa_erro"
    case averageMS = "media_ms"
    case maximumMS = "max_ms"
    case p50MS = "p50_ms"
    case p95MS = "p95_ms"
  }
}

struct TrafficSummary: Codable, Equatable, Sendable {
  let total: Int64
  let errors: Int64
  let errorRate: Double
  let discarded: Int64?
  let routes: [RouteMetric]

  enum CodingKeys: String, CodingKey {
    case total
    case errors = "erros"
    case errorRate = "taxa_erro"
    case discarded = "descartadas"
    case routes = "rotas"
  }
}

struct MetricsSnapshot: Codable, Equatable, Sendable {
  let uptimeSeconds: Int64
  let mode: String
  let process: ProcessSample
  let freeDiskBytes: Int64
  let totalDiskBytes: Int64
  let reservedDiskBytes: Int64
  let usedCacheBytes: Int64
  let cacheLimitBytes: Int64
  let traffic: TrafficSummary

  enum CodingKeys: String, CodingKey {
    case uptimeSeconds = "uptime_segundos"
    case mode = "modo"
    case process = "processo"
    case freeDiskBytes = "disco_livre_bytes"
    case totalDiskBytes = "disco_total_bytes"
    case reservedDiskBytes = "disco_reserva_bytes"
    case usedCacheBytes = "cache_usado_bytes"
    case cacheLimitBytes = "cache_limite_bytes"
    case traffic = "trafego"
  }
}

struct ServerSettings: Codable, Equatable, Sendable {
  let port: Int
  let tmdbConfigured: Bool
  let tmdbLanguage: String
  let scanInterval: String
  let tunnelName: String?
  let ffmpegAvailable: Bool

  enum CodingKeys: String, CodingKey {
    case port
    case tmdbConfigured = "tmdb_configured"
    case tmdbLanguage = "tmdb_lang"
    case scanInterval = "scan_every"
    case tunnelName = "tunnel_name"
    case ffmpegAvailable = "ffmpeg"
  }
}

struct SettingsUpdateRequest: Encodable, Equatable, Sendable {
  let tmdbKey: String?
  let tmdbLanguage: String?
  let scanInterval: String?

  enum CodingKeys: String, CodingKey {
    case tmdbKey = "tmdb_key"
    case tmdbLanguage = "tmdb_lang"
    case scanInterval = "scan_every"
  }
}

struct MatchCandidate: Codable, Equatable, Identifiable, Sendable {
  let tmdbID: Int
  let name: String
  let year: Int?
  let overview: String?
  let rating: Double?
  let poster: String?

  var id: Int { tmdbID }

  enum CodingKeys: String, CodingKey {
    case name, year, overview, rating, poster
    case tmdbID = "tmdb_id"
  }
}

struct MatchResultsResponse: Codable, Equatable, Sendable {
  let results: [MatchCandidate]
}

struct MatchRequest: Codable, Equatable, Sendable {
  let tmdbID: Int

  enum CodingKeys: String, CodingKey {
    case tmdbID = "tmdb_id"
  }
}

enum MediaType: String, Codable, Equatable, Sendable {
  case video, audio, photo
}

struct MediaFileInfo: Codable, Equatable, Identifiable, Sendable {
  let id: Int
  let relPath: String
  let name: String
  let ext: String
  let mediaType: MediaType
  let size: Int64
  let duration: Double
  let width: Int?
  let height: Int?
  let videoCodec: String?
  let audioCodec: String?
  let track: Int?
  let thumb: String?
  let position: Double?
  let finished: Bool?
  let season: Int?
  let episode: Int?
  let episodeName: String?
  let capturedAt: Int64?
  let titleID: Int?
  let titleName: String?
  let titleKind: TitleKind?
  let poster: String?

  enum CodingKeys: String, CodingKey {
    case id, name, ext, size, duration, width, height, track, thumb, position, finished, season,
      episode, poster
    case relPath = "rel_path"
    case mediaType = "media_type"
    case videoCodec = "vcodec"
    case audioCodec = "acodec"
    case episodeName = "episode_name"
    case capturedAt = "quando"
    case titleID = "title_id"
    case titleName = "title_name"
    case titleKind = "kind"
  }
}

struct MediaSeason: Codable, Equatable, Identifiable, Sendable {
  let number: Int
  let episodes: [MediaFileInfo]
  var id: Int { number }
}

struct TitleDetail: Codable, Equatable, Identifiable, Sendable {
  let id: Int
  let libraryID: Int
  let kind: TitleKind
  let name: String
  let year: Int?
  let overview: String?
  let rating: Double?
  let genres: String?
  let artist: String?
  let metaState: String
  let posterURL: String?
  let backdropURL: String?
  let library: String
  let favorite: Bool
  let files: [MediaFileInfo]
  let seasons: [MediaSeason]?

  enum CodingKeys: String, CodingKey {
    case id, kind, name, year, overview, rating, genres, artist, library, favorite, files, seasons
    case libraryID = "library_id"
    case metaState = "meta_state"
    case posterURL = "poster_url"
    case backdropURL = "backdrop_url"
  }
}

extension TitleDetail {
  /// O que o botão principal deve tocar: primeiro o que está em andamento,
  /// senão o primeiro não terminado, senão o primeiro de todos.
  var preferredPlayableFile: MediaFileInfo? {
    let playable = files.filter { $0.mediaType != .photo }
    return playable.first { ($0.position ?? 0) > 0 && $0.finished != true }
      ?? playable.first { $0.finished != true }
      ?? playable.first
  }
}

struct FavoriteResponse: Codable, Equatable, Sendable {
  let favorite: Bool
}

enum PlaybackMode: String, Codable, Equatable, Sendable {
  case direct, remux, audio, video
}

enum PreparationState: String, Codable, Equatable, Sendable {
  case absent = "ausente"
  case queued = "fila"
  case working = "trabalhando"
  case ready = "pronto"
  case failed = "erro"
}

struct PreparationProgress: Codable, Equatable, Sendable {
  let state: PreparationState
  let recipe: String?
  let readySeconds: Double
  let totalSeconds: Double
  let percentage: Int
  let speed: Double
  let remainingSeconds: Int
  let error: String?

  enum CodingKeys: String, CodingKey {
    case recipe = "receita"
    case state = "estado"
    case readySeconds = "segundos_prontos"
    case totalSeconds = "segundos_total"
    case percentage = "percentual"
    case speed = "velocidade"
    case remainingSeconds = "restante_segundos"
    case error = "erro"
  }
}

struct PlaybackPlan: Codable, Equatable, Sendable {
  let mode: PlaybackMode
  let reason: String
  let url: String
  let directURL: String
  let preparation: PreparationProgress?
  let ffmpegAvailable: Bool
  let transcodingEnabled: Bool

  enum CodingKeys: String, CodingKey {
    case url
    case mode = "modo"
    case reason = "motivo"
    case directURL = "url_direta"
    case preparation = "preparo"
    case ffmpegAvailable = "ffmpeg"
    case transcodingEnabled = "transcodificacao_ativa"
  }
}

struct MediaTokenResponse: Codable, Equatable, Sendable {
  let token: String
  let expiresAt: String
  let validFor: Int
  let parameter: String

  enum CodingKeys: String, CodingKey {
    case token
    case expiresAt = "expira_em"
    case validFor = "valido_por"
    case parameter = "param"
  }
}

struct ProgressRequest: Codable, Equatable, Sendable {
  let position: Double
  let duration: Double
}

struct MediaTrack: Codable, Equatable, Identifiable, Sendable {
  let index: Int
  let codec: String?
  let language: String?
  let label: String
  let channels: Int?
  let isDefault: Bool?
  let isForced: Bool?
  let isExternal: Bool?
  let url: String?
  let unavailableReason: String?

  var id: Int { index }

  enum CodingKeys: String, CodingKey {
    case codec, url
    case index = "idx"
    case language = "lang"
    case label = "rotulo"
    case channels = "canais"
    case isDefault = "padrao"
    case isForced = "forcada"
    case isExternal = "externa"
    case unavailableReason = "indisponivel"
  }
}

struct MediaTracks: Codable, Equatable, Sendable {
  let audio: [MediaTrack]
  let subtitles: [MediaTrack]

  enum CodingKeys: String, CodingKey {
    case audio
    case subtitles = "legendas"
  }
}

struct NextEpisodeResponse: Codable, Equatable, Sendable {
  let next: Int?
}

struct SubtitleCue: Equatable, Sendable {
  let start: Double
  let end: Double
  let text: String

  func contains(_ time: Double) -> Bool { time >= start && time < end }
}

/// Cues ordenadas por início, consultadas por busca binária. A varredura linear
/// anterior percorria as milhares de falas de um filme a cada quadro de vídeo.
struct SubtitleTimeline: Equatable, Sendable {
  private let cues: [SubtitleCue]

  init(_ cues: [SubtitleCue] = []) {
    self.cues = cues.sorted { $0.start < $1.start }
  }

  var isEmpty: Bool { cues.isEmpty }

  func text(at time: Double) -> String? {
    var low = 0
    var high = cues.count - 1
    var candidate: SubtitleCue?

    // Última cue cujo início é <= time; cues sobrepostas mantêm a mais recente.
    while low <= high {
      let middle = (low + high) / 2
      if cues[middle].start <= time {
        candidate = cues[middle]
        low = middle + 1
      } else {
        high = middle - 1
      }
    }

    guard let candidate, candidate.contains(time) else { return nil }
    return candidate.text
  }
}

enum WebVTTParser {
  static func parse(_ source: String) -> [SubtitleCue] {
    source
      .replacingOccurrences(of: "\r\n", with: "\n")
      .components(separatedBy: "\n\n")
      .compactMap(parseBlock)
      .sorted { $0.start < $1.start }
  }

  private static func parseBlock(_ block: String) -> SubtitleCue? {
    let lines = block.components(separatedBy: .newlines)
    guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
    let timing = lines[timingIndex].components(separatedBy: "-->")
    guard timing.count == 2,
      let start = parseTime(timing[0]),
      let end = parseTime(timing[1].split(separator: " ").first.map(String.init) ?? timing[1])
    else { return nil }
    let text = lines.dropFirst(timingIndex + 1)
      .joined(separator: "\n")
      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, end > start else { return nil }
    return SubtitleCue(start: start, end: end, text: text)
  }

  private static func parseTime(_ value: String) -> Double? {
    let parts = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
      .split(separator: ":")
    guard parts.count == 2 || parts.count == 3 else { return nil }
    let numbers = parts.compactMap { Double($0) }
    guard numbers.count == parts.count else { return nil }
    if numbers.count == 3 { return numbers[0] * 3600 + numbers[1] * 60 + numbers[2] }
    return numbers[0] * 60 + numbers[1]
  }
}
