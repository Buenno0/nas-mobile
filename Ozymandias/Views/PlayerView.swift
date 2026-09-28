import AVKit
import SwiftUI

/// Só a moldura. Toda a reprodução — fila, token de mídia, progresso, tela de
/// bloqueio — vive no `PlaybackController`, que sobrevive a esta tela: fechar o
/// player não pode parar a música.
struct PlayerView: View {
  let playback: PlaybackController

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var controlsVisible = true
  @State private var pictureInPictureCommand = 0
  @State private var isPictureInPictureActive = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      switch playback.phase {
      case .idle, .loading:
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

      if playback.phase != .ready { topBar }
    }
    .preferredColorScheme(.dark)
    .statusBarHidden()
    .onAppear { syncTimeResolution() }
    .onChange(of: controlsVisible) { _, _ in syncTimeResolution() }
    .onChange(of: playback.subtitles) { _, _ in syncTimeResolution() }
  }

  /// Sem controles à mostra e sem legenda ninguém lê o tempo fracionado — e a
  /// 4 Hz o SwiftUI reavaliaria tudo o que observa o controlador, que agora é o
  /// app inteiro.
  private func syncTimeResolution() {
    playback.timeResolution =
      controlsVisible || !playback.subtitles.isEmpty ? .fine : .coarse
  }

  private var playerContent: some View {
    ZStack {
      PlayerSurface(
        player: playback.player,
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

      if let subtitle = playback.activeSubtitle {
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

      if playback.sala.ativa {
        SalaOverlay(sala: playback.sala, controlesVisiveis: controlsVisible)
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
      // Fechar devolve a tela, não encerra a reprodução: quem encerra é o "x"
      // do mini player.
      playerButton("chevron.down", label: "Fechar player", identifier: "closePlayerButton") {
        playback.dismissFullScreen()
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(playback.currentTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text(playback.episodeLabel).font(.caption).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
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

      if !playback.tracks.audio.isEmpty || !playback.tracks.subtitles.isEmpty { trackMenu }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 14)
    .padding(.top, 8)
  }

  private var centerControls: some View {
    HStack(spacing: 42) {
      playerButton("gobackward.10", label: "Voltar 10 segundos") { playback.seek(by: -10) }

      Button(action: playback.togglePlayback) {
        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 30, weight: .semibold))
          .frame(width: 68, height: 68)
          .background(.black.opacity(0.55), in: .circle)
      }
      .accessibilityLabel(playback.isPlaying ? "Pausar" : "Reproduzir")
      .accessibilityIdentifier("playPauseButton")

      playerButton("goforward.10", label: "Avançar 10 segundos") { playback.seek(by: 10) }
    }
    .foregroundStyle(.white)
  }

  private var bottomControls: some View {
    VStack(spacing: 10) {
      Slider(
        value: Binding(
          get: { min(playback.currentTime, max(playback.duration, 1)) },
          set: { playback.seek(to: $0) }
        ),
        in: 0...max(playback.duration, 1)
      )
      .tint(.ozAccent)
      .accessibilityLabel("Posição da reprodução")
      .accessibilityValue(
        "\(timeLabel(playback.currentTime)) de \(timeLabel(playback.duration))")

      HStack(spacing: 14) {
        Text(timeLabel(playback.currentTime))
        Text("−\(timeLabel(max(playback.duration - playback.currentTime, 0)))")
          .foregroundStyle(.white.opacity(0.65))
        Spacer()

        // Na sala, a velocidade é a da sala (e o ajuste fino mexe nela).
        if !playback.sala.ativa { speedMenu }

        if !playback.sala.ativa, playback.currentFile?.mediaType == .video,
          let contexto = playback.contexto, let fileID = playback.currentFile?.id
        {
          Button {
            Task {
              await playback.sala.criar(
                fileID: fileID, store: contexto.store, session: contexto.session)
            }
          } label: {
            Label("Assistir junto", systemImage: "person.2.fill")
          }
          .accessibilityIdentifier("watchTogetherButton")
        }

        if playback.hasNextItem {
          Button {
            Task { await playback.playNext() }
          } label: {
            Label("Próximo", systemImage: "forward.end.fill")
          }
          .accessibilityIdentifier("nextEpisodeButton")
        }
      }
      .font(.caption.monospacedDigit())

      if let actionError = playback.actionError {
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
      if !playback.tracks.audio.isEmpty {
        Section("Áudio") {
          Button {
            playback.selectAudio(nil)
          } label: {
            menuLabel(automaticAudioLabel, selected: playback.selectedAudioIndex == nil)
          }
          ForEach(playback.tracks.audio) { track in
            Button {
              playback.selectAudio(track.index)
            } label: {
              menuLabel(
                PlaybackPlanner.audioTrackLabel(for: track),
                selected: playback.selectedAudioIndex == track.index
              )
            }
          }
        }
      }

      if !playback.tracks.subtitles.isEmpty {
        Section("Legendas") {
          Button {
            playback.selectSubtitle(nil)
          } label: {
            menuLabel("Desativadas", selected: playback.selectedSubtitle == nil)
          }
          ForEach(playback.tracks.subtitles) { track in
            Button {
              playback.selectSubtitle(track)
            } label: {
              menuLabel(
                subtitleLabel(track), selected: playback.selectedSubtitle?.index == track.index)
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

  /// "Automático" sozinho não diz nada; dizer qual faixa o servidor entregou
  /// evita a dúvida de estar no áudio dublado ou original.
  private var automaticAudioLabel: String {
    guard playback.selectedAudioIndex == nil,
      let resolved = PlaybackPlanner.preferredAudioTrack(in: playback.tracks.audio)
    else { return "Automático" }
    return "Automático · \(resolved.label)"
  }

  private var speedMenu: some View {
    Menu {
      ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in
        Button {
          playback.playbackRate = Float(speed)
        } label: {
          menuLabel(
            "\(speed.formatted(.number.precision(.fractionLength(0...2))))×",
            selected: playback.playbackRate == Float(speed)
          )
        }
      }
    } label: {
      Text("\(Double(playback.playbackRate).formatted(.number.precision(.fractionLength(0...2))))×")
        .font(.caption.weight(.semibold).monospacedDigit())
        .frame(minWidth: 42, minHeight: 36)
        .background(.white.opacity(0.14), in: .capsule)
    }
    .accessibilityLabel("Velocidade")
    .accessibilityIdentifier("playbackSpeedButton")
  }

  private func preparationView(progress: PreparationProgress, reason: String) -> some View {
    let naNuvem = PlaybackPlanner.isCloudPreparation(progress)
    return VStack(spacing: 18) {
      if naNuvem {
        // O worker não informa porcentagem: a barra só respira.
        CloudPreparationBar().frame(maxWidth: 320)
        Text("Preparando na nuvem").font(.title3.weight(.semibold))
      } else {
        ProgressView(value: Double(progress.percentage), total: 100)
          .progressViewStyle(.linear)
          .tint(.ozAccent)
          .frame(maxWidth: 320)
        Text("Preparando para este iPhone").font(.title3.weight(.semibold))
        Text("\(progress.percentage)%")
          .font(.title2.monospacedDigit().weight(.bold))
          .foregroundStyle(Color.ozAccent)
      }
      Text(naNuvem ? "\(reason)\nO worker avisa quando terminar; a versão preparada fica pronta para todos os aparelhos." : preparationMessage(progress, reason: reason))
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
      if playback.phase == .loading || playback.phase == .idle {
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

  /// Faixas que o servidor lista mas não sabe entregar vinham só apagadas, sem
  /// dizer por quê — o motivo já chega no payload.
  private func subtitleLabel(_ track: MediaTrack) -> String {
    guard track.url == nil else { return track.label }
    return "\(track.label) — \(track.unavailableReason ?? "indisponível neste formato")"
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

  // Desanexar a camada não para o áudio: o `AVPlayer` continua tocando sem ela.
  // Fechar a tela cheia num vídeo, portanto, segue em áudio — o vídeo só volta
  // ao reabrir o player.
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

/// Barra do preparo feito pelo worker: sem porcentagem, só respira, como o
/// painel "Preparando na nuvem" do web.
private struct CloudPreparationBar: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var aceso = false

  var body: some View {
    Capsule()
      .fill(Color.ozAccent)
      .frame(height: 6)
      .opacity(reduceMotion ? 1 : (aceso ? 1 : 0.45))
      .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: aceso)
      .onAppear { aceso = true }
      .accessibilityLabel("Preparando na nuvem")
  }
}
