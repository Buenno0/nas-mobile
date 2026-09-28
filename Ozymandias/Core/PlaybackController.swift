import AVKit
import Foundation
import MediaPlayer
import Observation
import SwiftUI
import UIKit

/// A reprodução vive aqui, e não dentro do `PlayerView`, porque o tempo de vida
/// dela não é o tempo de vida de uma tela: fechar o player não pode parar a
/// música, e a fila, a renovação do token de mídia e os observadores de
/// interrupção precisam de um lugar que sobreviva ao `fullScreenCover`.
@MainActor
@Observable
final class PlaybackController {
  enum Phase: Equatable {
    case idle
    case loading
    case preparing(PreparationProgress, String)
    case ready
    case failed(String)
  }

  /// Com os controles ocultos e sem legenda ninguém lê o tempo fracionado. Como
  /// este objeto vive acima da `TabView`, publicar a 4 Hz reavaliaria o app
  /// inteiro, não só a tela do player.
  enum TimeResolution {
    case coarse
    case fine
  }

  private(set) var phase: Phase = .idle
  private(set) var currentFile: MediaFileInfo?
  private(set) var currentTitle = ""
  private(set) var tracks = MediaTracks(audio: [], subtitles: [])
  private(set) var selectedAudioIndex: Int?
  private(set) var selectedSubtitle: MediaTrack?
  private(set) var subtitles = SubtitleTimeline()
  private(set) var currentTime = 0.0
  private(set) var duration = 0.0
  private(set) var isPlaying = false
  private(set) var actionError: String?
  private(set) var nextFileID: Int?
  private(set) var artwork: UIImage?

  var isPresentingFullScreen = false
  var timeResolution: TimeResolution = .coarse

  var playbackRate: Float = 1 {
    didSet {
      guard playbackRate != oldValue else { return }
      player.defaultRate = playbackRate
      if isPlaying { player.playImmediately(atRate: playbackRate) }
      updateNowPlayingInfo()
    }
  }

  /// Um `AVPlayer` só, do início ao fim do app: trocar de faixa é
  /// `replaceCurrentItem`, nunca um player novo.
  let player = AVPlayer()

  /// "Assistir junto": quando ativa, quem manda no ponto e no play é a sala.
  let sala = SalaController()

  var hasItem: Bool { currentFile != nil }
  var hasNextItem: Bool { queue.hasNext || nextFileID != nil }
  var activeSubtitle: String? { subtitles.text(at: currentTime) }

  var episodeLabel: String {
    guard let file = currentFile else { return "" }
    if let season = file.season, let episode = file.episode, season > 0 || episode > 0 {
      let name = file.episodeName.map { " · \($0)" } ?? ""
      return "T\(season) · E\(episode)\(name)"
    }
    return file.name
  }

  private let now: @Sendable () -> Date
  private var store: SessionStore?
  private var session: AuthenticatedSession?
  private var queue = PlaybackQueue(items: [], startingAt: MediaFileInfo.placeholder)
  private var artworkPath: String?
  private var streamPath: String?
  private var mediaTokenExpiry: Date?
  private var pendingResumePosition: Double?
  private var lastPersistedPosition: Double?
  private var loadTask: Task<Void, Never>?
  private var subtitleTask: Task<Void, Never>?
  private var monitorTask: Task<Void, Never>?
  /// Substitui a checagem de obsolescência por identidade de arquivo: uma troca
  /// de faixa de áudio no mesmo arquivo também precisa invalidar a carga antiga.
  private var loadGeneration = 0
  private var statusObservation: NSKeyValueObservation?
  private var endOfItemObserver: (any NSObjectProtocol)?
  private var sessionObservers: [any NSObjectProtocol] = []
  private var nowPlayingArtwork: MPMediaItemArtwork?
  private var wasPlayingBeforeInterruption = false
  private let remoteCommands = RemoteCommandController()

  init(now: @escaping @Sendable () -> Date = { .now }) {
    self.now = now
    // Uma vez só. Antes isto era refeito a cada item, e a renovação do token
    // (que só troca o item) deixava o AirPlay cair silenciosamente.
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true
    observePlayer()
    observeAudioSession()
    sala.playback = self
  }

  // MARK: - Ciclo de vida

  func start(
    file: MediaFileInfo,
    title: String,
    queue items: [MediaFileInfo] = [],
    artworkPath: String? = nil,
    store: SessionStore,
    session: AuthenticatedSession
  ) {
    self.store = store
    self.session = session

    // Tocar de novo o que já está tocando só devolve a tela cheia.
    if let currentFile, currentFile.id == file.id, phase != .idle {
      isPresentingFullScreen = true
      return
    }

    self.artworkPath = artworkPath
    queue = PlaybackQueue(items: items, startingAt: file)
    currentTitle = title
    load(file: file)
    isPresentingFullScreen = true
  }

  /// Encerrar é ação explícita do usuário (o "x" do mini player) ou consequência
  /// de sair da conta — nunca de fechar a tela cheia.
  func stop() async {
    sala.sair()
    await persistProgress()
    player.pause()
    loadTask?.cancel()
    subtitleTask?.cancel()
    monitorTask?.cancel()
    loadTask = nil
    subtitleTask = nil
    monitorTask = nil
    loadGeneration &+= 1
    player.replaceCurrentItem(with: nil)

    remoteCommands.deactivate()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped

    let store = self.store
    let session = self.session
    currentFile = nil
    currentTitle = ""
    tracks = MediaTracks(audio: [], subtitles: [])
    selectedAudioIndex = nil
    selectedSubtitle = nil
    subtitles = SubtitleTimeline()
    nextFileID = nil
    streamPath = nil
    mediaTokenExpiry = nil
    pendingResumePosition = nil
    lastPersistedPosition = nil
    artworkPath = nil
    artwork = nil
    nowPlayingArtwork = nil
    wasPlayingBeforeInterruption = false
    currentTime = 0
    duration = 0
    isPlaying = false
    actionError = nil
    phase = .idle
    isPresentingFullScreen = false
    timeResolution = .coarse
    self.store = nil
    self.session = nil

    // A metade que faltava: sem desativar, o sistema não devolve o áudio a
    // quem estava tocando antes. Só aqui — desativar ao pausar entregaria a
    // sessão ao Spotify toda vez que o usuário desse uma pausa.
    await deactivateAudioSession()

    if let store, let session {
      await store.refreshHomeAfterPlayback(for: session)
    }
  }

  /// Fechar a tela cheia não pausa e não limpa a tela de bloqueio. Era isto que
  /// matava o áudio.
  func dismissFullScreen() {
    isPresentingFullScreen = false
    timeResolution = .coarse
  }

  func presentFullScreen() {
    isPresentingFullScreen = true
  }

  func scenePhaseChanged(_ phase: ScenePhase) {
    guard phase != .active else { return }
    Task { await persistProgress() }
  }

  // MARK: - Transporte

  func togglePlayback() {
    // Modo cinema: vale também para a tela de bloqueio e os fones.
    guard !sala.soAssiste else { return }
    if isPlaying { pause() } else { play() }
  }

  private func play() {
    guard !sala.soAssiste else { return }
    player.playImmediately(atRate: playbackRate)
    sala.usuarioTocou(em: currentTime)
  }

  private func pause() {
    guard !sala.soAssiste else { return }
    player.pause()
    sala.usuarioPausou(em: player.currentTime().seconds)
  }

  /// Abre o arquivo da sala: sem retomar do progresso salvo e sem dar play —
  /// o ponto e o play vêm da sala.
  func startForRoom(file: MediaFileInfo, store: SessionStore, session: AuthenticatedSession) {
    self.store = store
    self.session = session
    isPresentingFullScreen = true
    if currentFile?.id == file.id, phase != .idle {
      sala.alinhar()
      return
    }
    queue = PlaybackQueue(items: [], startingAt: file)
    currentTitle = file.titleName ?? file.name
    load(file: file)
  }

  /// Para a sala abrir uma sessão com a mesma conta e servidor do player.
  var contexto: (store: SessionStore, session: AuthenticatedSession)? {
    guard let store, let session else { return nil }
    return (store, session)
  }

  func seek(by delta: Double) { seek(to: currentTime + delta) }

  func seek(to target: Double) {
    guard !sala.soAssiste else { return }
    let bounded = min(max(target, 0), max(duration, 0))
    currentTime = bounded
    sala.usuarioPulou(para: bounded)
    Task {
      _ = await player.seek(
        to: CMTime(seconds: bounded, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }
  }

  func playNext() async {
    actionError = nil
    await persistProgress()
    // Na sala, o próximo episódio é para todo mundo: quem troca é a sala.
    if sala.ativa {
      if let nextFileID { sala.usuarioPediuProximo(nextFileID) }
      return
    }
    if let next = queue.advance() {
      load(file: next)
      return
    }
    guard let nextFileID, let store, let session else { return }
    do {
      let next = try await store.playbackFile(id: nextFileID, for: session)
      currentTitle = next.titleName ?? currentTitle
      load(file: next)
    } catch {
      actionError = error.localizedDescription
    }
  }

  func selectAudio(_ index: Int?) {
    guard selectedAudioIndex != index else { return }
    Task {
      await persistProgress()
      pendingResumePosition = currentTime
      selectedAudioIndex = index
      restartPlayback()
    }
  }

  func selectSubtitle(_ track: MediaTrack?) {
    guard selectedSubtitle?.index != track?.index else { return }
    selectedSubtitle = track
    subtitleTask?.cancel()
    subtitleTask = Task { await loadSelectedSubtitle() }
  }

  // MARK: - Carga

  private func load(file: MediaFileInfo) {
    loadTask?.cancel()
    subtitleTask?.cancel()
    player.pause()

    currentFile = file
    tracks = MediaTracks(audio: [], subtitles: [])
    selectedAudioIndex = nil
    selectedSubtitle = nil
    subtitles = SubtitleTimeline()
    nextFileID = nil
    streamPath = nil
    mediaTokenExpiry = nil
    lastPersistedPosition = nil
    pendingResumePosition = pendingResumePosition ?? file.position
    currentTime = 0
    duration = file.duration
    actionError = nil

    artwork = nil
    nowPlayingArtwork = nil
    startMonitoring()
    configureRemoteCommands()
    restartPlayback()
    let generation = loadGeneration
    Task { await loadArtwork(for: file, generation: generation) }
  }

  private func restartPlayback() {
    guard let file = currentFile else { return }
    loadTask?.cancel()
    loadGeneration &+= 1
    let generation = loadGeneration
    let audioTrack = selectedAudioIndex
    loadTask = Task { await prepareAndPlay(file: file, audioTrack: audioTrack, generation: generation) }
  }

  private func prepareAndPlay(file: MediaFileInfo, audioTrack: Int?, generation: Int) async {
    guard let store, let session else { return }
    player.pause()
    phase = .loading
    actionError = nil
    do {
      try await configureAudioSession(for: file.mediaType)
      async let tokenRequest = store.mediaToken(for: session)
      var plan = try await store.playbackPlan(fileID: file.id, audioTrack: audioTrack, for: session)
      let mediaToken = try await tokenRequest

      var path: String
      switch PlaybackPlanner.decide(plan) {
      case .play(let ready):
        path = ready
      case .failure(let failure):
        throw failure
      case .prepare(let reason):
        var progress = try await store.prepare(
          fileID: file.id, audioTrack: audioTrack, for: session)
        phase = .preparing(progress, reason)
        path = ""
        polling: while !Task.isCancelled, generation == loadGeneration {
          if progress.state == .failed {
            throw PlaybackFailure.preparationFailed(progress.error ?? reason)
          }
          try await Task.sleep(for: .seconds(1))
          plan = try await store.playbackPlan(
            fileID: file.id, audioTrack: audioTrack, for: session)
          switch PlaybackPlanner.decide(plan) {
          case .play(let ready):
            path = ready
            break polling
          case .failure(let failure):
            throw failure
          case .prepare(let updated):
            progress = plan.preparation ?? progress
            phase = .preparing(progress, updated)
          }
        }
        guard !path.isEmpty else { return }
      }

      guard !Task.isCancelled, generation == loadGeneration else { return }
      streamPath = path
      mediaTokenExpiry = PlaybackPlanner.expiry(of: mediaToken, now: now())
      let source = try PlaybackPlanner.authorizedMediaURL(
        path: path,
        relativeTo: session.credential.serverURL,
        token: mediaToken.token,
        parameter: mediaToken.parameter
      )
      player.replaceCurrentItem(with: AVPlayerItem(url: source))
      player.defaultRate = playbackRate
      let resume = pendingResumePosition ?? file.position
      pendingResumePosition = nil
      if sala.ativa {
        phase = .ready
        sala.alinhar()
      } else {
        if let resume, resume > 5, file.finished != true {
          _ = await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        phase = .ready
        player.playImmediately(atRate: playbackRate)
      }
      Task { await loadAncillaryData(for: file.id, generation: generation) }

      while !Task.isCancelled, generation == loadGeneration {
        try await Task.sleep(for: .seconds(10))
        await persistProgress()
        await renewMediaTokenIfNeeded()
      }
    } catch is CancellationError {
      return
    } catch {
      if case .signedOut = store.phase { return }
      guard generation == loadGeneration else { return }
      phase = .failed(error.localizedDescription)
    }
  }

  private func loadAncillaryData(for fileID: Int, generation: Int) async {
    guard let store, let session else { return }
    async let tracksRequest = try? store.mediaTracks(fileID: fileID, for: session)
    async let nextRequest = try? store.nextEpisode(fileID: fileID, for: session)
    let loadedTracks = await tracksRequest
    let loadedNext = await nextRequest
    guard generation == loadGeneration else { return }
    tracks = loadedTracks ?? MediaTracks(audio: [], subtitles: [])
    nextFileID = loadedNext ?? nil
  }

  /// A capa já foi baixada pela grade; a chave é a mesma de
  /// `AuthenticatedArtwork` para isto ser um acerto de cache, não um download
  /// novo. A dica do ponto de chamada importa: faixas vindas da tela de artista
  /// não trazem `poster` próprio.
  private func loadArtwork(for file: MediaFileInfo, generation: Int) async {
    guard let store, let session else { return }
    guard let path = file.poster ?? file.thumb ?? artworkPath, !path.isEmpty else { return }
    let key = "\(session.credential.serverURL.absoluteString)|\(path)|600"
    let image = await ArtworkCache.shared.image(for: key, maximumPixelSize: 600) {
      try await store.imageData(path: path, for: session)
    }
    guard generation == loadGeneration, let image else { return }
    artwork = image
    // Construído uma vez por item: `updateNowPlayingInfo` roda a cada segundo e
    // recriar isto ali faria a tela de bloqueio piscar.
    //
    // O bloco precisa ser `@Sendable`: o MediaPlayer o chama numa fila de fundo,
    // e uma closure nascida aqui dentro herdaria isolamento de main actor — o
    // que derruba o app na checagem de executor assim que a tela de bloqueio
    // pede a imagem.
    nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    updateNowPlayingInfo()
  }

  private func loadSelectedSubtitle() async {
    subtitles = SubtitleTimeline()
    guard let store, let session,
      let track = selectedSubtitle,
      let path = track.url
    else { return }
    do {
      let source = try await store.subtitleText(path: path, for: session)
      guard selectedSubtitle?.index == track.index else { return }
      subtitles = SubtitleTimeline(WebVTTParser.parse(source))
    } catch {
      guard selectedSubtitle?.index == track.index else { return }
      actionError = "Não foi possível carregar a legenda."
      selectedSubtitle = nil
    }
  }

  /// O token de mídia vence antes de muitos filmes terminarem. Sem renovar, o
  /// AVPlayer pede os próximos trechos com token morto e a reprodução trava.
  private func renewMediaTokenIfNeeded() async {
    guard case .ready = phase,
      let store, let session,
      let path = streamPath,
      let expiry = mediaTokenExpiry,
      PlaybackPlanner.needsRenewal(expiry: expiry, now: now())
    else { return }

    do {
      let token = try await store.mediaToken(for: session)
      let source = try PlaybackPlanner.authorizedMediaURL(
        path: path,
        relativeTo: session.credential.serverURL,
        token: token.token,
        parameter: token.parameter
      )
      let position = player.currentTime()
      let wasPlaying = isPlaying
      player.replaceCurrentItem(with: AVPlayerItem(url: source))
      player.defaultRate = playbackRate
      _ = await player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
      if wasPlaying { player.playImmediately(atRate: playbackRate) }
      mediaTokenExpiry = PlaybackPlanner.expiry(of: token, now: now())
    } catch {
      // A margem de renovação deixa espaço para a próxima volta tentar de novo.
    }
  }

  // MARK: - Observação

  private func observePlayer() {
    // Pausar/retomar não gera tique de tempo; sem isto o botão e a tela de
    // bloqueio ficariam mostrando o estado anterior.
    statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.syncPlaybackState()
        self.updateNowPlayingInfo()
        self.sala.estadoDoPlayerMudou(self.player.timeControlStatus)
      }
    }

    endOfItemObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let finished = notification.object as? AVPlayerItem
      MainActor.assumeIsolated {
        guard let self, let finished, finished === self.player.currentItem else { return }
        Task { await self.playbackEnded() }
      }
    }
  }

  private func startMonitoring() {
    guard monitorTask == nil else { return }
    monitorTask = Task { await monitorPlayer() }
  }

  /// O AVPlayer avisa quando o tempo anda; antes isto era um laço acordando a
  /// cada 250 ms mesmo com o vídeo pausado.
  private func monitorPlayer() async {
    let (ticks, continuation) = AsyncStream<Void>.makeStream()
    let observer = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
      queue: .main
    ) { _ in continuation.yield(()) }
    defer {
      continuation.finish()
      player.removeTimeObserver(observer)
    }

    var lastNowPlayingSecond = -1
    for await _ in ticks {
      syncPlaybackState(fineGrained: timeResolution == .fine)
      let second = Int(currentTime)
      if second != lastNowPlayingSecond {
        lastNowPlayingSecond = second
        updateNowPlayingInfo()
      }
    }
  }

  private func syncPlaybackState(fineGrained: Bool = true) {
    let time = player.currentTime().seconds
    if time.isFinite {
      let bounded = max(time, 0)
      if fineGrained || Int(bounded) != Int(currentTime) { currentTime = bounded }
    }
    let itemDuration = player.currentItem?.duration.seconds ?? 0
    let fallback = currentFile?.duration ?? 0
    let resolved = itemDuration.isFinite && itemDuration > 0 ? itemDuration : fallback
    if duration != resolved { duration = resolved }
    let playing = player.timeControlStatus == .playing
    if isPlaying != playing { isPlaying = playing }
  }

  private func playbackEnded() async {
    currentTime = duration
    await persistProgress(position: duration)
    if sala.ativa {
      if let nextFileID { sala.usuarioPediuProximo(nextFileID) }
      return
    }
    if hasNextItem {
      await playNext()
    } else if let store, let session {
      await store.refreshHomeAfterPlayback(for: session)
    }
  }

  // MARK: - Progresso

  func persistProgress(position: Double? = nil) async {
    guard case .ready = phase, let store, let session, let file = currentFile else { return }
    let position = position ?? player.currentTime().seconds
    let itemDuration = player.currentItem?.duration.seconds ?? 0
    let resolved = itemDuration.isFinite && itemDuration > 0 ? itemDuration : file.duration
    guard
      ProgressCheckpoint.shouldPersist(
        position: position, duration: resolved, lastPersisted: lastPersistedPosition)
    else { return }
    lastPersistedPosition = position
    await store.saveProgress(
      fileID: file.id, position: position, duration: resolved, for: session)
  }

  // MARK: - Sessão de áudio e tela de bloqueio

  private func configureAudioSession(for mediaType: MediaType) async throws {
    let isVideo = mediaType == .video
    try await Task.detached(priority: .userInitiated) {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: isVideo ? .moviePlayback : .default)
      try audioSession.setActive(true)
    }.value
  }

  /// Sem estes observadores, uma ligação encerrava a reprodução para sempre: o
  /// sistema desativa a sessão e ninguém a reativa. A decisão de pausar ou
  /// retomar mora em `InterruptionPolicy`, que é testável sem simulador.
  private func observeAudioSession() {
    let center = NotificationCenter.default

    let interruption = center.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] note in
      let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
      let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
      MainActor.assumeIsolated {
        guard let self, let rawType,
          let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }
        switch type {
        case .began:
          self.handle(.interruption(.began))
        case .ended:
          let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
          self.handle(.interruption(.ended(shouldResume: options.contains(.shouldResume))))
        @unknown default:
          break
        }
      }
    }

    let route = center.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] note in
      let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
      MainActor.assumeIsolated {
        guard let self else { return }
        let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason ?? 0)
        let change: AudioRouteChange =
          switch reason {
          case .oldDeviceUnavailable: .outputDisconnected
          case .newDeviceAvailable: .outputConnected
          default: .other
          }
        self.handle(.routeChanged(change))
      }
    }

    let reset = center.addObserver(
      forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.handle(.mediaServicesReset) }
    }

    sessionObservers = [interruption, route, reset]
  }

  private func handle(_ event: AudioSessionEvent) {
    guard hasItem else { return }
    if case .interruption(.began) = event { wasPlayingBeforeInterruption = isPlaying }

    switch InterruptionPolicy.command(for: event, wasPlaying: wasPlayingBeforeInterruption) {
    case .none:
      break
    case .pause:
      player.pause()
    case .resume:
      wasPlayingBeforeInterruption = false
      guard let file = currentFile else { return }
      Task {
        try? await configureAudioSession(for: file.mediaType)
        player.playImmediately(atRate: playbackRate)
      }
    case .reload:
      restartPlayback()
    }
  }

  private func deactivateAudioSession() async {
    await Task.detached(priority: .utility) {
      try? AVAudioSession.sharedInstance().setActive(
        false, options: .notifyOthersOnDeactivation)
    }.value
  }

  private func configureRemoteCommands() {
    remoteCommands.activate(
      play: { [weak self] in self?.play() },
      pause: { [weak self] in self?.pause() },
      skip: { [weak self] in self?.seek(by: $0) },
      seek: { [weak self] in self?.seek(to: $0) }
    )
  }

  private func updateNowPlayingInfo() {
    guard hasItem else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: episodeLabel,
      MPMediaItemPropertyAlbumTitle: currentTitle,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(playbackRate),
    ]
    if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
  }
}

extension MediaFileInfo {
  /// Semente da fila antes do primeiro item; nunca é reproduzida.
  fileprivate static let placeholder = MediaFileInfo(
    id: -1, relPath: "", name: "", ext: "", mediaType: .video, size: 0, duration: 0,
    width: nil, height: nil, videoCodec: nil, audioCodec: nil, track: nil, thumb: nil,
    position: nil, finished: nil, season: nil, episode: nil, episodeName: nil,
    capturedAt: nil, titleID: nil, titleName: nil, titleKind: nil, poster: nil
  )
}

@MainActor
private final class RemoteCommandController {
  private var isActive = false
  private var playAction: (() -> Void)?
  private var pauseAction: (() -> Void)?
  private var skipAction: ((Double) -> Void)?
  private var seekAction: ((Double) -> Void)?
  private var commandTokens: [(command: MPRemoteCommand, token: Any)] = []

  func activate(
    play: @escaping () -> Void,
    pause: @escaping () -> Void,
    skip: @escaping (Double) -> Void,
    seek: @escaping (Double) -> Void
  ) {
    playAction = play
    pauseAction = pause
    skipAction = skip
    seekAction = seek
    guard !isActive else { return }
    isActive = true

    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = true
    commands.pauseCommand.isEnabled = true
    commands.skipForwardCommand.isEnabled = true
    commands.skipBackwardCommand.isEnabled = true
    commands.changePlaybackPositionCommand.isEnabled = true
    commands.skipForwardCommand.preferredIntervals = [10]
    commands.skipBackwardCommand.preferredIntervals = [10]

    commandTokens = [
      (
        commands.playCommand,
        commands.playCommand.addTarget { [weak self] _ in
          self?.playAction?()
          return .success
        }
      ),
      (
        commands.pauseCommand,
        commands.pauseCommand.addTarget { [weak self] _ in
          self?.pauseAction?()
          return .success
        }
      ),
      (
        commands.skipForwardCommand,
        commands.skipForwardCommand.addTarget { [weak self] event in
          let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
          self?.skipAction?(interval)
          return .success
        }
      ),
      (
        commands.skipBackwardCommand,
        commands.skipBackwardCommand.addTarget { [weak self] event in
          let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
          self?.skipAction?(-interval)
          return .success
        }
      ),
      (
        commands.changePlaybackPositionCommand,
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
          guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
            return .commandFailed
          }
          self?.seekAction?(position)
          return .success
        }
      ),
    ]
  }

  func deactivate() {
    guard isActive else { return }
    for entry in commandTokens { entry.command.removeTarget(entry.token) }
    commandTokens = []

    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = false
    commands.pauseCommand.isEnabled = false
    commands.skipForwardCommand.isEnabled = false
    commands.skipBackwardCommand.isEnabled = false
    commands.changePlaybackPositionCommand.isEnabled = false
    playAction = nil
    pauseAction = nil
    skipAction = nil
    seekAction = nil
    isActive = false
  }
}
