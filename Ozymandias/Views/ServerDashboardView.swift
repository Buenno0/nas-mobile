import SwiftUI

struct ServerDashboardView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @State private var scanState: Loadable<ScanStatus> = .idle
  @State private var metricsState: Loadable<MetricsSnapshot> = .idle
  @State private var isStartingWork = false
  @State private var showingMetadataOptions = false
  @State private var actionError: String?
  @State private var scanIsLive = false
  @State private var metricsAreLive = false

  private let metricColumns = [GridItem(.adaptive(minimum: 145), spacing: 12)]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 22) {
        scanSection

        if session.user.isAdmin {
          adminActions
          metricsSection
        } else {
          Label(
            "Métricas e ações de manutenção estão disponíveis para administradores.",
            systemImage: "lock.fill"
          )
          .font(.subheadline)
          .foregroundStyle(Color.ozMuted)
          .padding(16)
          .ozyCard()
        }
      }
      .padding(16)
    }
    .background(Color.ozBackground)
    .navigationTitle("Servidor")
    .refreshable { await refresh(silent: true) }
    .confirmationDialog(
      "Atualizar metadados",
      isPresented: $showingMetadataOptions,
      titleVisibility: .visible
    ) {
      Button("Apenas títulos pendentes") { Task { await startMetadata(all: false) } }
      Button("Refazer todos os títulos") { Task { await startMetadata(all: true) } }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("Refazer tudo pode demorar bastante em acervos grandes.")
    }
    .task { await refresh(silent: false) }
    .task { await listenForScanEvents() }
    .task {
      if session.user.isAdmin { await listenForMetricEvents() }
    }
  }

  @ViewBuilder
  private var scanSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Acervo", systemImage: "externaldrive.fill.badge.magnifyingglass")
          .font(.headline)
        Spacer()
        liveIndicator(connected: scanIsLive)
          .accessibilityIdentifier("scanLiveIndicator")
      }

      switch scanState {
      case .idle, .loading:
        HStack {
          ProgressView()
          Text("Consultando o servidor…")
        }
        .foregroundStyle(Color.ozMuted)
        .padding(16)
        .ozyCard()
      case .failed(let message):
        ContentErrorView(message: message) { Task { await refresh(silent: false) } }
      case .loaded(let status):
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Label(
              status.running ? scanStage(status.stage) : "Servidor disponível",
              systemImage: status.running
                ? "arrow.trianglehead.2.clockwise.rotate.90" : "checkmark.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(status.running ? Color.ozAccent : Color.ozOkay)
            Spacer()
            if status.running { ProgressView().controlSize(.small) }
          }

          if status.running {
            if let current = status.current, let total = status.total, total > 0 {
              ProgressView(value: Double(current), total: Double(total))
                .tint(.ozAccent)
              Text("\(current) de \(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.ozMuted)
            }
            if let library = status.library, !library.isEmpty {
              serverDetail("Biblioteca", value: library)
            }
            if let file = status.file, !file.isEmpty {
              Text(file)
                .font(.caption)
                .foregroundStyle(Color.ozMuted)
                .lineLimit(2)
            }
          } else {
            if let lastRun = status.lastRun {
              serverDetail("Última atualização", value: formatDate(lastRun))
            }
            if let stats = status.lastStats, !stats.isEmpty {
              Text(stats).font(.caption).foregroundStyle(Color.ozMuted)
            }
          }

          if let error = status.lastError, !error.isEmpty {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(Color.ozDanger)
          }
        }
        .padding(16)
        .ozyCard()
        .accessibilityIdentifier("serverDashboardLoaded")
      }
    }
  }

  private var adminActions: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Manutenção").font(.headline)

      if let actionError {
        Label(actionError, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(Color.ozDanger)
      }

      // Dimensionados pelo conteúdo e em uma linha só. Com
      // `.frame(maxWidth: .infinity)` viravam meias-larguras e "Escanear agora"
      // quebrava em duas linhas dentro da cápsula.
      HStack(spacing: 10) {
        Button {
          Task { await startScan() }
        } label: {
          Label("Escanear", systemImage: "arrow.clockwise")
            .lineLimit(1)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isStartingWork || currentScanRunning)
        .accessibilityIdentifier("startScanButton")

        Button {
          showingMetadataOptions = true
        } label: {
          Label("Metadados", systemImage: "sparkles")
            .lineLimit(1)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .disabled(isStartingWork || currentScanRunning)
        .accessibilityIdentifier("refreshMetadataButton")

        Spacer(minLength: 0)
      }
      .buttonBorderShape(.capsule)
      .controlSize(.large)
    }
  }

  @ViewBuilder
  private var metricsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Métricas").font(.headline)
        Spacer()
        liveIndicator(connected: metricsAreLive)
      }

      switch metricsState {
      case .idle, .loading:
        HStack {
          ProgressView()
          Text("Carregando métricas…")
        }
        .foregroundStyle(Color.ozMuted)
      case .failed(let message):
        Label(message, systemImage: "chart.xyaxis.line")
          .font(.caption)
          .foregroundStyle(Color.ozDanger)
      case .loaded(let metrics):
        LazyVGrid(columns: metricColumns, spacing: 12) {
          metricCard(
            "Disco livre",
            value: formatBytes(metrics.freeDiskBytes),
            detail: "de \(formatBytes(metrics.totalDiskBytes))",
            icon: "internaldrive"
          )
          metricCard(
            "Cache",
            value: formatBytes(metrics.usedCacheBytes),
            detail: "limite \(formatBytes(metrics.cacheLimitBytes))",
            icon: "shippingbox"
          )
          metricCard(
            "CPU",
            value: metrics.process.cpuPercent.formatted(.number.precision(.fractionLength(1)))
              + "%",
            detail:
              "\(metrics.process.cpuCores.formatted(.number.precision(.fractionLength(1)))) núcleos",
            icon: "cpu"
          )
          metricCard(
            "Memória",
            value: formatBytes(Int64(metrics.process.heapBytes)),
            detail: "\(metrics.process.goroutines) tarefas",
            icon: "memorychip"
          )
          metricCard(
            "Requisições",
            value: metrics.traffic.total.formatted(),
            detail: "\(metrics.traffic.errors) erros",
            icon: "network"
          )
          metricCard(
            "Ativo há",
            value: uptime(metrics.uptimeSeconds),
            detail: metrics.mode == "tunnel" ? "túnel" : "rede local",
            icon: "clock"
          )
        }

        if !metrics.traffic.routes.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            Text("Rotas mais usadas")
              .font(.subheadline.weight(.semibold))
              .padding(14)
            Divider().overlay(Color.ozLine)
            ForEach(metrics.traffic.routes.prefix(5)) { route in
              HStack {
                Text(route.route).font(.caption).lineLimit(1)
                Spacer()
                Text("\(route.total) · p95 \(Int(route.p95MS)) ms")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(Color.ozMuted)
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
            }
          }
          .ozyCard()
        }
      }
    }
  }

  private func refresh(silent: Bool) async {
    if !silent {
      scanState = .loading
      if session.user.isAdmin { metricsState = .loading }
    }
    do {
      async let scan = store.scanStatus(for: session)
      if session.user.isAdmin {
        async let metrics = store.metrics(for: session)
        let values = try await (scan, metrics)
        scanState = .loaded(values.0)
        metricsState = .loaded(values.1)
      } else {
        scanState = try await .loaded(scan)
      }
    } catch {
      if case .signedOut = store.phase { return }
      if !silent || scanState == .loading { scanState = .failed(error.localizedDescription) }
      if session.user.isAdmin && (!silent || metricsState == .loading) {
        metricsState = .failed(error.localizedDescription)
      }
    }
  }

  private func listenForScanEvents() async {
    var retry = 1
    while !Task.isCancelled {
      do {
        let events = try store.scanEvents(for: session)
        for try await status in events {
          guard !Task.isCancelled else { return }
          scanIsLive = true
          retry = 1
          withAnimation(.smooth) { scanState = .loaded(status) }
        }
      } catch {
        scanIsLive = false
        if await store.handleEventStreamError(error) { return }
        if let status = try? await store.scanStatus(for: session) {
          scanState = .loaded(status)
        }
      }
      guard !Task.isCancelled else { return }
      scanIsLive = false
      try? await Task.sleep(for: .seconds(retry))
      retry = min(retry * 2, 8)
    }
  }

  private func listenForMetricEvents() async {
    var retry = 1
    while !Task.isCancelled {
      do {
        let events = try store.metricEvents(for: session)
        for try await metrics in events {
          guard !Task.isCancelled else { return }
          metricsAreLive = true
          retry = 1
          withAnimation(.smooth) { metricsState = .loaded(metrics) }
        }
      } catch {
        metricsAreLive = false
        if await store.handleEventStreamError(error) { return }
        if let metrics = try? await store.metrics(for: session) {
          metricsState = .loaded(metrics)
        }
      }
      guard !Task.isCancelled else { return }
      metricsAreLive = false
      try? await Task.sleep(for: .seconds(retry))
      retry = min(retry * 2, 8)
    }
  }

  private func startScan() async {
    await runAction { try await store.startScan(for: session) }
  }

  private func startMetadata(all: Bool) async {
    await runAction { try await store.refreshMetadata(all: all, for: session) }
  }

  private func runAction(_ action: () async throws -> Void) async {
    guard !isStartingWork else { return }
    isStartingWork = true
    actionError = nil
    do {
      try await action()
      store.invalidateContent()
      await refresh(silent: true)
    } catch {
      actionError = error.localizedDescription
    }
    isStartingWork = false
  }

  private var currentScanRunning: Bool {
    if case .loaded(let status) = scanState { return status.running }
    return false
  }

  private func metricCard(
    _ title: String,
    value: String,
    detail: String,
    icon: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.ozMuted)
      Text(value).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
      Text(detail).font(.caption2).foregroundStyle(Color.ozMuted).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .ozyCard()
  }

  private func serverDetail(_ label: String, value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(Color.ozMuted)
      Spacer()
      Text(value).lineLimit(1)
    }
    .font(.caption)
  }

  private func scanStage(_ stage: String?) -> String {
    stage == "metadados" ? "Atualizando metadados" : "Escaneando arquivos"
  }

  private func formatDate(_ value: String) -> String {
    guard let date = ISO8601.date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .shortened)
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
  }

  private func uptime(_ seconds: Int64) -> String {
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    if days > 0 { return "\(days)d \(hours)h" }
    let minutes = (seconds % 3_600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
  }

  private func liveIndicator(connected: Bool) -> some View {
    Label(
      connected ? "Ao vivo" : "Conectando",
      systemImage: connected ? "dot.radiowaves.left.and.right" : "ellipsis"
    )
    .font(.caption2.weight(.semibold))
    .foregroundStyle(connected ? Color.ozOkay : Color.ozMuted)
    .contentTransition(.symbolEffect(.replace))
  }
}
