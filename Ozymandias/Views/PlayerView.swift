import AVKit
import Combine
import MediaPlayer
import SwiftUI

struct PlayerView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var currentFile: MediaFileInfo
  @State private var currentTitle: String
  @State private var playbackQueue: [MediaFileInfo]
  @State private var queueIndex: Int
  @State private var player = AVPlayer()
  @State private var phase: PlayerPhase = .loading
  @State private var tracks = MediaTracks(audio: [], subtitles: [])
  @State private var selectedAudioIndex: Int?
  @State private var selectedSubtitle: MediaTrack?
  @State private var subtitles = SubtitleTimeline()
  @State private var nextFileID: Int?
  @State private var streamPath: String?
  @State private var mediaTokenExpiry: Date?
  @State private var currentTime = 0.0
  @State private var duration = 0.0
  @State private var isPlaying = false
  @State private var controlsVisible = true
  @State private var playbackRate: Float = 1
  @State private var pendingResumePosition: Double?
  @State private var actionError: String?
  @State private var pictureInPictureCommand = 0
  @State private var isPictureInPictureActive = false
  @State private var remoteCommands = RemoteCommandController()

  init(
    file: MediaFileInfo,
    title: String,
    queue: [MediaFileInfo] = [],
    store: SessionStore,
    session: AuthenticatedSession
  ) {
    self.store = store
    self.session = session
    _currentFile = State(initialValue: file)
    _currentTitle = State(initialValue: title)
    let normalizedQueue = queue.isEmpty ? [file] : queue
    _playbackQueue = State(initialValue: normalizedQueue)
    _queueIndex = State(initialValue: normalizedQueue.firstIndex(where: { $0.id == file.id }) ?? 0)
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      switch phase {
      case .loading:
        playerStatus(icon: "play.rectangle", title: "Preparando reprodução", message: nil)
      case .preparing(let progress, let reason):
        preparationView(progress: progress, reason: reason)
      case .ready:
        playerContent
      case .failed(let message):
        playerStatus(
          icon: "exclamationmark.triangle.fill",
          title: "Não foi possível reproduzir",
          message: message
        )
      }

      if phase != .ready { topBar }
    }
    .preferredColorScheme(.dark)
    .statusBarHidden()
    .task(id: playbackRequest) {
      await prepareAndPlay(file: currentFile, audioTrack: selectedAudioIndex)
    }
    .task(id: subtitleRequest) { await loadSelectedSubtitle() }
    .task { await monitorPlayer() }
    .onAppear { configureRemoteCommands() }
    .onReceive(player.publisher(for: \.timeControlStatus)) { _ in
      // Pausar/retomar não gera tique de tempo; sem isto o botão e a tela de
      // bloqueio ficariam mostrando o estado anterior.
      syncPlaybackState()
      updateNowPlayingInfo()
    }
    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) {
      notification in
      guard let item = notification.object as? AVPlayerItem, item === player.currentItem else {
        return
      }
      Task { await playbackEnded() }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { Task { await persistProgress() } }
    }
    .onDisappear {
      player.pause()
      remoteCommands.deactivate()
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      MPNowPlayingInfoCenter.default().playbackState = .stopped
      Task {
        await persistProgress()
        await store.refreshHomeAfterPlayback(for: session)
      }
    }
  }

  private var playerContent: some View {
    ZStack {
      PlayerSurface(
        player: player,
        pictureInPictureCommand: pictureInPictureCommand,
        isPictureInPictureActive: $isPictureInPictureActive
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      Color.clear
        .contentShape(.rect)
        .onTapGesture {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
          }
        }

      if let subtitle = activeSubtitle {
        Text(subtitle)
          .font(.title3.weight(.semibold))
          .multilineTextAlignment(.center)
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(.black.opacity(0.72), in: .rect(cornerRadius: 6))
          .shadow(color: .black, radius: 2)
          .padding(.horizontal, 24)
          .padding(.bottom, controlsVisible ? 132 : 28)
          .frame(maxHeight: .infinity, alignment: .bottom)
          .transition(.opacity)
          .accessibilityIdentifier("activeSubtitle")
      }

      if controlsVisible {
        playerChrome.transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: controlsVisible)
  }

  private var playerChrome: some View {
    ZStack {
      LinearGradient(
        colors: [.black.opacity(0.78), .clear, .black.opacity(0.88)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      VStack(spacing: 0) {
        topBar
        Spacer()
        centerControls
        Spacer()
        bottomControls
      }
    }
  }

  private var topBar: some View {
    HStack(spacing: 12) {
      playerButton("xmark", label: "Fechar player", identifier: "closePlayerButton") {
        dismiss()
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(currentTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text(episodeLabel).font(.caption).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
      }
      Spacer()

      AirPlayRoutePicker()
        .frame(width: 44, height: 44)
        .accessibilityLabel("AirPlay")
        .accessibilityIdentifier("airPlayButton")

      Button {
        pictureInPictureCommand += 1
      } label: {
        Image(systemName: isPictureInPictureActive ? "pip.exit" : "pip.enter")
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 44, height: 44)
          .background(.black.opacity(0.55), in: .circle)
      }
      .disabled(!AVPictureInPictureController.isPictureInPictureSupported())
      .accessibilityLabel(
        isPictureInPictureActive ? "Encerrar Picture in Picture" : "Iniciar Picture in Picture"
      )
      .accessibilityIdentifier("pictureInPictureButton")

      if !tracks.audio.isEmpty || !tracks.subtitles.isEmpty { trackMenu }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 14)
    .padding(.top, 8)
  }

  private var centerControls: some View {
    HStack(spacing: 42) {
      playerButton("gobackward.10", label: "Voltar 10 segundos") { seek(by: -10) }

      Button(action: togglePlayback) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 30, weight: .semibold))
          .frame(width: 68, height: 68)
          .background(.black.opacity(0.55), in: .circle)
      }
      .accessibilityLabel(isPlaying ? "Pausar" : "Reproduzir")
      .accessibilityIdentifier("playPauseButton")

      playerButton("goforward.10", label: "Avançar 10 segundos") { seek(by: 10) }
    }
    .foregroundStyle(.white)
  }

  private var bottomControls: some View {
    VStack(spacing: 10) {
      Slider(
        value: Binding(
          get: { min(currentTime, max(duration, 1)) },
          set: { seek(to: $0) }
        ),
        in: 0...max(duration, 1)
      )
      .tint(.ozAccent)
      .accessibilityLabel("Posição da reprodução")
      .accessibilityValue("\(timeLabel(currentTime)) de \(timeLabel(duration))")

      HStack(spacing: 14) {
        Text(timeLabel(currentTime))
        Text("−\(timeLabel(max(duration - currentTime, 0)))")
          .foregroundStyle(.white.opacity(0.65))
        Spacer()

        speedMenu

        if hasNextItem {
          Button {
            Task { await playNext() }
          } label: {
            Label("Próximo", systemImage: "forward.end.fill")
          }
          .accessibilityIdentifier("nextEpisodeButton")
        }
      }
      .font(.caption.monospacedDigit())

      if let actionError {
        Text(actionError)
          .font(.caption)
          .foregroundStyle(Color.ozDanger)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 18)
    .padding(.bottom, 14)
  }

  private var trackMenu: some View {
    Menu {
      if !tracks.audio.isEmpty {
        Section("Áudio") {
          Button {
            changeAudio(to: nil)
          } label: {
            menuLabel("Automático", selected: selectedAudioIndex == nil)
          }
          ForEach(tracks.audio) { track in
            Button {
              changeAudio(to: track.index)
            } label: {
              menuLabel(track.label, selected: selectedAudioIndex == track.index)
            }
          }
        }
      }

      if !tracks.subtitles.isEmpty {
        Section("Legendas") {
          Button {
            selectedSubtitle = nil
          } label: {
            menuLabel("Desativadas", selected: selectedSubtitle == nil)
          }
          ForEach(tracks.subtitles) { track in
            Button {
              selectedSubtitle = track
            } label: {
              menuLabel(subtitleLabel(track), selected: selectedSubtitle?.index == track.index)
            }
            .disabled(track.url == nil)
          }
        }
      }
    } label: {
      Image(systemName: "captions.bubble")
        .font(.system(size: 17, weight: .semibold))
        .frame(width: 44, height: 44)
        .background(.black.opacity(0.55), in: .circle)
    }
    .accessibilityLabel("Áudio e legendas")
    .accessibilityIdentifier("trackMenuButton")
  }

  private var speedMenu: some View {
    Menu {
      ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in
        Button {
          playbackRate = Float(speed)
          player.defaultRate = playbackRate
          if isPlaying { player.rate = playbackRate }
        } label: {
          menuLabel(
            "\(speed.formatted(.number.precision(.fractionLength(0...2))))×",
            selected: playbackRate == Float(speed)
          )
        }
      }
    } label: {
      Text("\(Double(playbackRate).formatted(.number.precision(.fractionLength(0...2))))×")
        .font(.caption.weight(.semibold).monospacedDigit())
        .frame(minWidth: 42, minHeight: 36)
        .background(.white.opacity(0.14), in: .capsule)
    }
    .accessibilityLabel("Velocidade")
    .accessibilityIdentifier("playbackSpeedButton")
  }

  private func preparationView(progress: PreparationProgress, reason: String) -> some View {
    VStack(spacing: 18) {
      ProgressView(value: Double(progress.percentage), total: 100)
        .progressViewStyle(.linear)
        .tint(.ozAccent)
        .frame(maxWidth: 320)
      Text("Preparando para este iPhone").font(.title3.weight(.semibold))
      Text("\(progress.percentage)%")
        .font(.title2.monospacedDigit().weight(.bold))
        .foregroundStyle(Color.ozAccent)
      Text(preparationMessage(progress, reason: reason))
        .font(.caption)
        .foregroundStyle(.white.opacity(0.66))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
    }
    .foregroundStyle(.white)
    .padding(24)
  }

  private func playerStatus(icon: String, title: String, message: String?) -> some View {
    VStack(spacing: 16) {
      if phase == .loading {
        ProgressView().controlSize(.large).tint(.ozAccent)
      } else {
        Image(systemName: icon).font(.largeTitle).foregroundStyle(Color.ozDanger)
      }
      Text(title).font(.title3.weight(.semibold))
      if let message {
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.68))
          .multilineTextAlignment(.center)
      }
    }
    .foregroundStyle(.white)
    .padding(24)
  }

  private func prepareAndPlay(file: MediaFileInfo, audioTrack: Int?) async {
    player.pause()
    phase = .loading
    actionError = nil
    do {
      try await configureAudioSession(for: file.mediaType)
      async let tokenRequest = store.mediaToken(for: session)
      var plan = try await store.playbackPlan(
        fileID: file.id, audioTrack: audioTrack, for: session)
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
        polling: while !Task.isCancelled {
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

      guard !Task.isCancelled, currentFile.id == file.id, selectedAudioIndex == audioTrack else {
        return
      }
      streamPath = path
      mediaTokenExpiry = PlaybackPlanner.expiry(of: mediaToken, now: .now)
      let source = try PlaybackPlanner.authorizedMediaURL(
        path: path,
        relativeTo: session.credential.serverURL,
        token: mediaToken.token,
        parameter: mediaToken.parameter
      )
      player.replaceCurrentItem(with: AVPlayerItem(url: source))
      player.allowsExternalPlayback = true
      player.usesExternalPlaybackWhileExternalScreenIsActive = true
      player.defaultRate = playbackRate
      let resume = pendingResumePosition ?? file.position
      pendingResumePosition = nil
      if let resume, resume > 5, file.finished != true {
        _ = await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
      }
      phase = .ready
      player.playImmediately(atRate: playbackRate)
      Task { await loadAncillaryData(for: file.id) }

      while !Task.isCancelled {
        try await Task.sleep(for: .seconds(10))
        await persistProgress()
        await renewMediaTokenIfNeeded()
      }
    } catch is CancellationError {
      return
    } catch {
      if case .signedOut = store.phase { return }
      phase = .failed(error.localizedDescription)
    }
  }

  private func loadAncillaryData(for fileID: Int) async {
    async let tracksRequest = try? store.mediaTracks(fileID: fileID, for: session)
    async let nextRequest = try? store.nextEpisode(fileID: fileID, for: session)
    let loadedTracks = await tracksRequest
    let loadedNext = await nextRequest
    guard currentFile.id == fileID else { return }
    tracks = loadedTracks ?? MediaTracks(audio: [], subtitles: [])
    nextFileID = loadedNext ?? nil
  }

  private func loadSelectedSubtitle() async {
    subtitles = SubtitleTimeline()
    guard let track = selectedSubtitle, let path = track.url else { return }
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
      // Com os controles ocultos e sem legenda ninguém lê o tempo fracionado:
      // a 4 Hz o SwiftUI reavaliaria a tela inteira do player à toa.
      syncPlaybackState(fineGrained: controlsVisible || !subtitles.isEmpty)
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
    let resolved = itemDuration.isFinite && itemDuration > 0 ? itemDuration : currentFile.duration
    if duration != resolved { duration = resolved }
    let playing = player.timeControlStatus == .playing
    if isPlaying != playing { isPlaying = playing }
  }

  private func playbackEnded() async {
    currentTime = duration
    await persistProgress(position: duration)
    if hasNextItem { await playNext() }
  }

  private func playNext() async {
    actionError = nil
    await persistProgress()
    if playbackQueue.indices.contains(queueIndex + 1) {
      queueIndex += 1
      switchTo(playbackQueue[queueIndex])
      return
    }
    guard let nextFileID else { return }
    do {
      let next = try await store.playbackFile(id: nextFileID, for: session)
      currentTitle = next.titleName ?? currentTitle
      switchTo(next)
    } catch {
      actionError = error.localizedDescription
    }
  }

  private func switchTo(_ next: MediaFileInfo) {
    player.pause()
    tracks = MediaTracks(audio: [], subtitles: [])
    selectedAudioIndex = nil
    selectedSubtitle = nil
    subtitles = SubtitleTimeline()
    nextFileID = nil
    streamPath = nil
    mediaTokenExpiry = nil
    pendingResumePosition = next.position
    currentFile = next
    controlsVisible = true
  }

  private var hasNextItem: Bool {
    playbackQueue.indices.contains(queueIndex + 1) || nextFileID != nil
  }

  private func changeAudio(to index: Int?) {
    guard selectedAudioIndex != index else { return }
    Task {
      await persistProgress()
      pendingResumePosition = currentTime
      selectedAudioIndex = index
    }
  }

  private func togglePlayback() {
    if isPlaying { player.pause() } else { player.playImmediately(atRate: playbackRate) }
  }

  private func seek(by delta: Double) { seek(to: currentTime + delta) }

  private func seek(to target: Double) {
    let bounded = min(max(target, 0), max(duration, 0))
    currentTime = bounded
    Task {
      _ = await player.seek(
        to: CMTime(seconds: bounded, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }
  }

  /// O token de mídia vence antes de muitos filmes terminarem. Sem renovar, o
  /// AVPlayer pede os próximos trechos com token morto e a reprodução trava.
  private func renewMediaTokenIfNeeded() async {
    guard case .ready = phase,
      let path = streamPath,
      let expiry = mediaTokenExpiry,
      PlaybackPlanner.needsRenewal(expiry: expiry, now: .now)
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
      mediaTokenExpiry = PlaybackPlanner.expiry(of: token, now: .now)
    } catch {
      // A margem de renovação deixa espaço para a próxima volta tentar de novo.
    }
  }

  private func persistProgress(position: Double? = nil) async {
    guard case .ready = phase else { return }
    let position = position ?? player.currentTime().seconds
    let itemDuration = player.currentItem?.duration.seconds ?? 0
    let duration = itemDuration.isFinite && itemDuration > 0 ? itemDuration : currentFile.duration
    await store.saveProgress(
      fileID: currentFile.id, position: position, duration: duration, for: session)
  }

  private func playerButton(
    _ symbol: String,
    label: String,
    identifier: String? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .bold))
        .frame(width: 44, height: 44)
        .background(.black.opacity(0.55), in: .circle)
    }
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier ?? label)
  }

  private func menuLabel(_ label: String, selected: Bool) -> some View {
    Label(label, systemImage: selected ? "checkmark" : "circle.dashed")
  }

  private var playbackRequest: PlaybackRequest {
    PlaybackRequest(fileID: currentFile.id, audioIndex: selectedAudioIndex)
  }

  private var subtitleRequest: SubtitleRequest {
    SubtitleRequest(fileID: currentFile.id, trackIndex: selectedSubtitle?.index)
  }

  private var activeSubtitle: String? {
    subtitles.text(at: currentTime)
  }

  /// Faixas que o servidor lista mas não sabe entregar vinham só apagadas, sem
  /// dizer por quê — o motivo já chega no payload.
  private func subtitleLabel(_ track: MediaTrack) -> String {
    guard track.url == nil else { return track.label }
    return "\(track.label) — \(track.unavailableReason ?? "indisponível neste formato")"
  }

  private var episodeLabel: String {
    if let season = currentFile.season, let episode = currentFile.episode, season > 0 || episode > 0
    {
      let name = currentFile.episodeName.map { " · \($0)" } ?? ""
      return "T\(season) · E\(episode)\(name)"
    }
    return currentFile.name
  }

  private func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let remaining = total % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remaining) }
    return String(format: "%d:%02d", minutes, remaining)
  }

  private func preparationMessage(_ progress: PreparationProgress, reason: String) -> String {
    if progress.remainingSeconds > 0 {
      return "\(reason) · cerca de \(max(progress.remainingSeconds / 60, 1)) min restantes"
    }
    return reason
  }

  private func configureAudioSession(for mediaType: MediaType) async throws {
    let isVideo = mediaType == .video
    try await Task.detached(priority: .userInitiated) {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        .playback,
        mode: isVideo ? .moviePlayback : .default
      )
      try audioSession.setActive(true)
    }.value
  }

  private func configureRemoteCommands() {
    remoteCommands.activate(
      play: { player.playImmediately(atRate: playbackRate) },
      pause: { player.pause() },
      skip: { seek(by: $0) },
      seek: { seek(to: $0) }
    )
  }

  private func updateNowPlayingInfo() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: episodeLabel,
      MPMediaItemPropertyAlbumTitle: currentTitle,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(playbackRate),
    ]
    MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
  }
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

private final class PlayerLayerView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }

  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct PlayerSurface: UIViewRepresentable {
  let player: AVPlayer
  let pictureInPictureCommand: Int
  @Binding var isPictureInPictureActive: Bool

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeUIView(context: Context) -> PlayerLayerView {
    let view = PlayerLayerView()
    view.backgroundColor = .black
    view.playerLayer.videoGravity = .resizeAspect
    view.playerLayer.player = player
    context.coordinator.configure(for: view.playerLayer)
    return view
  }

  func updateUIView(_ view: PlayerLayerView, context: Context) {
    context.coordinator.parent = self
    if view.playerLayer.player !== player { view.playerLayer.player = player }
    context.coordinator.configure(for: view.playerLayer)
    context.coordinator.handle(command: pictureInPictureCommand)
  }

  static func dismantleUIView(_ view: PlayerLayerView, coordinator: Coordinator) {
    coordinator.stop()
    view.playerLayer.player = nil
  }

  @MainActor final class Coordinator: NSObject, @MainActor AVPictureInPictureControllerDelegate {
    var parent: PlayerSurface
    private var controller: AVPictureInPictureController?
    private weak var configuredLayer: AVPlayerLayer?
    private var lastCommand = 0

    init(parent: PlayerSurface) {
      self.parent = parent
    }

    func configure(for layer: AVPlayerLayer) {
      guard configuredLayer !== layer else { return }
      configuredLayer = layer
      guard AVPictureInPictureController.isPictureInPictureSupported(),
        let controller = AVPictureInPictureController(playerLayer: layer)
      else { return }
      controller.delegate = self
      controller.canStartPictureInPictureAutomaticallyFromInline = true
      self.controller = controller
    }

    func handle(command: Int) {
      guard command != lastCommand else { return }
      lastCommand = command
      guard let controller else { return }
      if controller.isPictureInPictureActive {
        controller.stopPictureInPicture()
      } else if controller.isPictureInPicturePossible {
        controller.startPictureInPicture()
      }
    }

    func stop() {
      if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
      controller = nil
    }

    @MainActor func pictureInPictureControllerDidStartPictureInPicture(
      _ pictureInPictureController: AVPictureInPictureController
    ) {
      parent.isPictureInPictureActive = true
    }

    @MainActor func pictureInPictureControllerDidStopPictureInPicture(
      _ pictureInPictureController: AVPictureInPictureController
    ) {
      parent.isPictureInPictureActive = false
    }

    @MainActor func pictureInPictureController(
      _ pictureInPictureController: AVPictureInPictureController,
      failedToStartPictureInPictureWithError error: any Error
    ) {
      parent.isPictureInPictureActive = false
    }
  }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.prioritizesVideoDevices = true
    picker.activeTintColor = UIColor(Color.ozAccent)
    picker.tintColor = .white
    return picker
  }

  func updateUIView(_ view: AVRoutePickerView, context: Context) {
    view.activeTintColor = UIColor(Color.ozAccent)
    view.tintColor = .white
  }
}

private struct PlaybackRequest: Equatable {
  let fileID: Int
  let audioIndex: Int?
}

private struct SubtitleRequest: Equatable {
  let fileID: Int
  let trackIndex: Int?
}

private enum PlayerPhase: Equatable {
  case loading
  case preparing(PreparationProgress, String)
  case ready
  case failed(String)
}
