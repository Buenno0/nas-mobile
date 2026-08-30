import SwiftUI

struct ServerSettingsView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @State private var state: Loadable<ServerSettings> = .idle
  @State private var apiKey = ""
  @State private var language = "pt-BR"
  @State private var scanInterval = ""
  @State private var isSaving = false
  @State private var saveError: String?
  @State private var showingRemoveKeyConfirmation = false

  var body: some View {
    Group {
      switch state {
      case .idle, .loading:
        LoadingContent(label: "Carregando configurações…")
      case .failed(let message):
        ContentErrorView(message: message) { Task { await load() } }
      case .loaded(let settings):
        settingsForm(settings)
      }
    }
    .background(Color.ozBackground)
    .navigationTitle("Configurações")
    .confirmationDialog(
      "Remover integração com o TMDB?",
      isPresented: $showingRemoveKeyConfirmation,
      titleVisibility: .visible
    ) {
      Button("Remover chave", role: .destructive) { Task { await removeTMDBKey() } }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text(
        "Capas, sinopses e identificação manual deixarão de funcionar até uma nova chave ser configurada."
      )
    }
    .task { await load() }
  }

  private func settingsForm(_ settings: ServerSettings) -> some View {
    Form {
      Section("Servidor") {
        statusRow("Porta", value: String(settings.port), icon: "network")
        statusRow(
          "FFmpeg",
          value: settings.ffmpegAvailable ? "Disponível" : "Indisponível",
          icon: settings.ffmpegAvailable ? "checkmark.circle.fill" : "xmark.circle.fill",
          color: settings.ffmpegAvailable ? .ozOkay : .ozDanger
        )
        statusRow(
          "Conexão",
          value: settings.tunnelName.map { "Túnel · \($0)" } ?? "Rede local",
          icon: settings.tunnelName == nil ? "wifi" : "point.3.connected.trianglepath.dotted"
        )
      }

      Section {
        statusRow(
          "TMDB",
          value: settings.tmdbConfigured ? "Configurado" : "Não configurado",
          icon: settings.tmdbConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
          color: settings.tmdbConfigured ? .ozOkay : .ozWarning
        )
        .accessibilityIdentifier("settingsLoaded")

        if session.user.isAdmin {
          SecureField(
            settings.tmdbConfigured ? "Nova chave (opcional)" : "Chave da API do TMDB",
            text: $apiKey
          )
          .textContentType(.password)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("tmdbKeyField")

          Picker("Idioma dos metadados", selection: $language) {
            Text("Português (Brasil)").tag("pt-BR")
            Text("Inglês").tag("en-US")
            Text("Espanhol").tag("es-ES")
          }

          if settings.tmdbConfigured {
            Button("Remover chave do TMDB", role: .destructive) {
              showingRemoveKeyConfirmation = true
            }
          }
        } else {
          statusRow("Idioma", value: settings.tmdbLanguage, icon: "globe")
        }
      } header: {
        Text("Metadados")
      } footer: {
        if session.user.isAdmin {
          Text("Uma chave já configurada nunca é enviada de volta pelo servidor.")
        }
      }

      Section {
        if session.user.isAdmin {
          Picker("Frequência", selection: $scanInterval) {
            Text("Somente manual").tag("")
            Text("A cada 15 minutos").tag("15m")
            Text("A cada 30 minutos").tag("30m")
            Text("A cada hora").tag("1h")
            Text("A cada 6 horas").tag("6h")
            Text("Uma vez por dia").tag("24h")
          }
        } else {
          statusRow(
            "Frequência",
            value: settings.scanInterval.isEmpty ? "Somente manual" : settings.scanInterval,
            icon: "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
          )
        }
      } header: {
        Text("Varredura automática")
      }

      if session.user.isAdmin {
        Section {
          if let saveError {
            Label(saveError, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(Color.ozDanger)
          }
          Button {
            Task { await save() }
          } label: {
            HStack {
              if isSaving { ProgressView() }
              Text(isSaving ? "Salvando…" : "Salvar configurações")
                .frame(maxWidth: .infinity)
            }
          }
          .disabled(isSaving)
          .accessibilityIdentifier("saveSettingsButton")
        }
      } else {
        Section {
          Label(
            "Somente administradores podem alterar estas configurações.",
            systemImage: "lock.fill"
          )
          .foregroundStyle(Color.ozMuted)
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func statusRow(
    _ title: String,
    value: String,
    icon: String,
    color: Color = .ozAccent
  ) -> some View {
    LabeledContent {
      Text(value).foregroundStyle(Color.ozMuted)
    } label: {
      Label(title, systemImage: icon).foregroundStyle(color)
    }
  }

  private func load() async {
    state.beginLoading()
    do {
      let settings = try await store.settings(for: session)
      language = settings.tmdbLanguage
      scanInterval = settings.scanInterval
      state = .loaded(settings)
    } catch {
      if case .signedOut = store.phase { return }
      state = .failed(error.localizedDescription)
    }
  }

  private func save() async {
    guard !isSaving else { return }
    isSaving = true
    saveError = nil
    do {
      let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      let updated = try await store.updateSettings(
        SettingsUpdateRequest(
          tmdbKey: trimmedKey.isEmpty ? nil : trimmedKey,
          tmdbLanguage: language,
          scanInterval: scanInterval
        ),
        for: session
      )
      apiKey = ""
      withAnimation(.snappy) { state = .loaded(updated) }
    } catch {
      saveError = error.localizedDescription
    }
    isSaving = false
  }

  private func removeTMDBKey() async {
    guard !isSaving else { return }
    isSaving = true
    saveError = nil
    do {
      let updated = try await store.updateSettings(
        SettingsUpdateRequest(tmdbKey: "", tmdbLanguage: nil, scanInterval: nil),
        for: session
      )
      withAnimation(.snappy) { state = .loaded(updated) }
    } catch {
      saveError = error.localizedDescription
    }
    isSaving = false
  }
}

struct MatchCorrectionView: View {
  @Environment(\.dismiss) private var dismiss
  let detail: TitleDetail
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  let onApplied: () -> Void
  @State private var query: String
  @State private var year: String
  @State private var results: [MatchCandidate] = []
  @State private var isSearching = false
  @State private var applyingID: Int?
  @State private var errorMessage: String?

  init(
    detail: TitleDetail,
    store: SessionStore,
    session: AuthenticatedSession,
    onApplied: @escaping () -> Void
  ) {
    self.detail = detail
    self.store = store
    self.session = session
    self.onApplied = onApplied
    _query = State(initialValue: detail.name)
    _year = State(initialValue: detail.year.map(String.init) ?? "")
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField("Ano (opcional)", text: $year)
            .keyboardType(.numberPad)
            .accessibilityIdentifier("matchYearField")

          Button {
            Task { await search() }
          } label: {
            HStack {
              if isSearching { ProgressView() }
              Text(isSearching ? "Buscando…" : "Buscar no TMDB")
                .frame(maxWidth: .infinity)
            }
          }
          .disabled(isSearching || cleanQuery.isEmpty)
          .accessibilityIdentifier("matchSearchButton")
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(Color.ozDanger)
          }
        }

        Section("Resultados") {
          if isSearching && results.isEmpty {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
          } else if results.isEmpty {
            ContentUnavailableView(
              "Nenhum resultado",
              systemImage: "magnifyingglass",
              description: Text("Tente outro nome ou remova o ano.")
            )
          } else {
            ForEach(results) { candidate in
              candidateRow(candidate)
            }
          }
        }
      }
      .navigationTitle("Corrigir identificação")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: "Nome do filme ou série")
      .onSubmit(of: .search) { Task { await search() } }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancelar") { dismiss() }
        }
      }
      .task { await search() }
    }
  }

  private func candidateRow(_ candidate: MatchCandidate) -> some View {
    HStack(alignment: .top, spacing: 12) {
      candidatePoster(candidate)

      VStack(alignment: .leading, spacing: 6) {
        Text(candidate.name).font(.headline).lineLimit(2)
        HStack(spacing: 8) {
          if let year = candidate.year { Text(String(year)) }
          if let rating = candidate.rating, rating > 0 {
            Text("★ \(rating.formatted(.number.precision(.fractionLength(1))))")
          }
        }
        .font(.caption)
        .foregroundStyle(Color.ozMuted)

        if let overview = candidate.overview, !overview.isEmpty {
          Text(overview)
            .font(.caption)
            .foregroundStyle(Color.ozMuted)
            .lineLimit(3)
        }

        Button {
          Task { await apply(candidate) }
        } label: {
          HStack {
            if applyingID == candidate.id { ProgressView().controlSize(.small) }
            Text(applyingID == candidate.id ? "Aplicando…" : "Usar este resultado")
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(applyingID != nil)
        .accessibilityIdentifier("applyMatch-\(candidate.id)")
      }
    }
    .padding(.vertical, 6)
  }

  @ViewBuilder
  private func candidatePoster(_ candidate: MatchCandidate) -> some View {
    if let poster = candidate.poster, let url = URL(string: poster) {
      AsyncImage(url: url) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else if phase.error != nil {
          posterPlaceholder
        } else {
          ProgressView()
        }
      }
      .frame(width: 72, height: 108)
      .background(Color.ozSurface)
      .clipShape(.rect(cornerRadius: 9))
    } else {
      posterPlaceholder
    }
  }

  private var posterPlaceholder: some View {
    Image(systemName: "film")
      .font(.title2)
      .foregroundStyle(Color.ozMuted)
      .frame(width: 72, height: 108)
      .background(Color.ozSurface)
      .clipShape(.rect(cornerRadius: 9))
  }

  private var cleanQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func search() async {
    guard !isSearching, !cleanQuery.isEmpty else { return }
    isSearching = true
    errorMessage = nil
    do {
      results = try await store.matchCandidates(
        titleID: detail.id,
        query: cleanQuery,
        year: Int(year),
        for: session
      )
    } catch {
      if case .signedOut = store.phase { return }
      errorMessage = error.localizedDescription
    }
    isSearching = false
  }

  private func apply(_ candidate: MatchCandidate) async {
    guard applyingID == nil else { return }
    applyingID = candidate.id
    errorMessage = nil
    do {
      try await store.applyMatch(titleID: detail.id, tmdbID: candidate.tmdbID, for: session)
      onApplied()
      dismiss()
    } catch {
      if case .signedOut = store.phase { return }
      errorMessage = error.localizedDescription
      applyingID = nil
    }
  }
}
