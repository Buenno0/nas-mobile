import SwiftUI
import UIKit

struct HomeView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @State private var heroScrollOffset: CGFloat = 0

  var body: some View {
    Group {
      switch store.homeState {
      case .idle, .loading:
        LoadingContent(label: "Carregando seu acervo…")
      case .failed(let message):
        ContentErrorView(message: message) {
          Task { await store.loadHome(for: session, force: true) }
        }
      case .loaded(let content):
        if content.hero == nil && content.continueItems.isEmpty && content.rows.isEmpty {
          EmptyLibraryView()
        } else {
          home(content)
        }
      }
    }
    .background(Color.ozBackground)
    // O banner precisa chegar ao topo; a barra de navegação daria um degrau.
    .toolbar(.hidden, for: .navigationBar)
    .task { await store.loadHome(for: session) }
    .accessibilityIdentifier("homeScreen")
  }

  private func home(_ content: HomeResponse) -> some View {
    GeometryReader { proxy in
      homeScroll(content, containerWidth: proxy.size.width)
    }
    // Medir já incluindo a faixa da status bar: é ela que o banner ocupa.
    .ignoresSafeArea(edges: .top)
  }

  private func homeScroll(_ content: HomeResponse, containerWidth: CGFloat) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 30) {
        if let hero = content.hero {
          TitleHeroBanner(
            title: hero,
            containerWidth: containerWidth,
            scrollOffset: heroScrollOffset,
            store: store,
            session: session
          )
        }

        if !content.continueItems.isEmpty {
          ContinueShelf(
            title: "Continuar assistindo", items: content.continueItems,
            store: store, session: session)
        }

        ForEach(content.rows) { row in
          PosterShelf(title: row.title, items: row.items, store: store, session: session)
        }

        if let forgotten = content.forgotten, !forgotten.isEmpty {
          ContinueShelf(title: "Esquecidos", items: forgotten, store: store, session: session)
        }
      }
      .padding(.bottom, 16)
    }
    .heroScrollOffset($heroScrollOffset)
    .refreshable { await store.loadHome(for: session, force: true) }
    .accessibilityIdentifier("homeLoaded")
  }
}

struct CatalogView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @State private var query = ""
  @State private var selectedLibrary: Int?
  @State private var selectedKind: TitleKind?
  @State private var sort: CatalogSort = .recent

  private let columns = [GridItem(.adaptive(minimum: 108, maximum: 170), spacing: 16, alignment: .top)]

  var body: some View {
    Group {
      switch store.catalogState {
      case .idle, .loading:
        LoadingContent(label: "Carregando o acervo…")
      case .failed(let message):
        ContentErrorView(message: message) {
          Task { await store.loadCatalog(for: session, query: catalogQuery, force: true) }
        }
      case .loaded(let content):
        catalog(content)
      }
    }
    .background(Color.ozBackground)
    .navigationTitle("Acervo")
    .searchable(text: $query, prompt: "Buscar no acervo")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("Ordenar", selection: $sort) {
            ForEach(CatalogSort.allCases, id: \.self) { option in
              Text(option.label).tag(option)
            }
          }
        } label: {
          Label("Ordenar", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("catalogSortButton")
      }
    }
    .task(id: catalogQuery) {
      if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
      guard !Task.isCancelled else { return }
      await store.loadCatalog(for: session, query: catalogQuery)
    }
    .onChange(of: selectedLibrary) { _, _ in
      // Trocar de biblioteca pode esconder a fila de tipos; um filtro invisível
      // deixaria o acervo vazio sem nenhum botão para desfazer.
      guard let kind = selectedKind,
        let libraries = store.catalogState.value?.libraries.filter(\.enabled),
        !availableKinds(in: libraries).contains(kind)
      else { return }
      selectedKind = nil
    }
    .accessibilityIdentifier("catalogScreen")
  }

  private func catalog(_ content: CatalogContent) -> some View {
    let libraries = content.libraries.filter(\.enabled)
    let kinds = availableKinds(in: libraries)

    return ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Com uma única biblioteca, "Tudo" e o nome dela dão o mesmo resultado:
        // a fila inteira vira ruído e ecoa a fila de tipos logo abaixo.
        if libraries.count > 1 {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              FilterChip(title: "Tudo", selected: selectedLibrary == nil) {
                selectedLibrary = nil
              }
              ForEach(libraries) { library in
                FilterChip(title: library.name, selected: selectedLibrary == library.id) {
                  selectedLibrary = library.id
                }
              }
            }
            .padding(.horizontal, 16)
          }
          .scrollIndicators(.hidden)
        }

        // Só os tipos que existem no acervo: oferecer "Série" onde só há filmes
        // leva a uma busca garantidamente vazia.
        if kinds.count > 1 {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              FilterChip(title: "Todos os tipos", selected: selectedKind == nil) {
                selectedKind = nil
              }
              ForEach(kinds, id: \.self) { kind in
                FilterChip(title: kindLabel(kind), selected: selectedKind == kind) {
                  selectedKind = kind
                }
              }
            }
            .padding(.horizontal, 16)
          }
          .scrollIndicators(.hidden)
        }

        Text(
          "\(content.items.count) de \(content.total) \(content.total == 1 ? "título" : "títulos") · \(sort.label.lowercased())"
        )
        .font(.caption)
        .foregroundStyle(Color.ozMuted)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("catalogLoaded")

        if content.items.isEmpty {
          if query.isEmpty {
            ContentUnavailableView("Nenhum título", systemImage: "rectangle.stack")
              .frame(maxWidth: .infinity)
              .padding(.top, 44)
          } else {
            ContentUnavailableView.search(text: query)
              .frame(maxWidth: .infinity)
              .padding(.top, 44)
          }
        } else {
          LazyVGrid(columns: columns, spacing: 22) {
            ForEach(content.items) { title in
              PosterTile(title: title, store: store, session: session)
                .onAppear {
                  // A grade é lazy: a última célula só aparece quando o usuário
                  // chega ao fim, e é aí que a próxima página é pedida.
                  guard title.id == content.items.last?.id else { return }
                  Task { await store.loadMoreCatalog(for: session, query: catalogQuery) }
                }
            }
          }
          .padding(.horizontal, 16)

          pagingFooter(content)
        }
      }
      .padding(.vertical, 12)
    }
    .refreshable {
      await store.loadCatalog(for: session, query: catalogQuery, force: true)
    }
  }

  @ViewBuilder
  private func pagingFooter(_ content: CatalogContent) -> some View {
    if let message = store.catalogPageError {
      VStack(spacing: 10) {
        Text(message)
          .font(.caption)
          .foregroundStyle(Color.ozDanger)
          .multilineTextAlignment(.center)
        Button("Tentar novamente") {
          Task { await store.loadMoreCatalog(for: session, query: catalogQuery) }
        }
        .buttonStyle(.bordered)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
      .accessibilityIdentifier("catalogPageError")
    } else if store.isLoadingMoreCatalog {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityIdentifier("catalogLoadingMore")
    } else if content.canLoadMore {
      Button("Carregar mais") {
        Task { await store.loadMoreCatalog(for: session, query: catalogQuery) }
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
      .accessibilityIdentifier("catalogLoadMoreButton")
    }
  }

  /// Os tipos presentes nas bibliotecas visíveis, na ordem em que o servidor as
  /// devolve. Se o servidor usar um `kind` que o app não conhece, cai de volta
  /// para a lista completa em vez de sumir com o filtro.
  private func availableKinds(in libraries: [MediaLibrary]) -> [TitleKind] {
    let scoped = selectedLibrary.map { id in libraries.filter { $0.id == id } } ?? libraries
    var kinds: [TitleKind] = []
    for library in scoped {
      guard let kind = TitleKind(rawValue: library.kind), !kinds.contains(kind) else { continue }
      kinds.append(kind)
    }
    return kinds.isEmpty ? [.movie, .tv, .album, .photos] : kinds
  }

  private var catalogQuery: CatalogQuery {
    CatalogQuery(
      libraryID: selectedLibrary,
      kind: selectedKind,
      text: query,
      sort: sort
    )
  }
}

/// Banner da Home: arte sangrando até o topo, metadados e título por cima, e
/// as ações numa fila de vidro dimensionada pelo conteúdo.
private struct TitleHeroBanner: View {
  let title: TitleCard
  let containerWidth: CGFloat
  let scrollOffset: CGFloat
  @Bindable var store: SessionStore
  let session: AuthenticatedSession

  @State private var selectedFile: MediaFileInfo?
  @State private var isStartingPlayback = false
  @State private var playbackError: String?

  var body: some View {
    HeroBanner(containerWidth: containerWidth, scrollOffset: scrollOffset) {
      AuthenticatedArtwork(
        path: title.backdrop ?? title.poster,
        name: title.name,
        store: store,
        session: session,
        maximumPixelSize: 1400
      )
    } content: {
      VStack(alignment: .leading, spacing: 0) {
        NavigationLink {
          TitleDetailView(titleID: title.id, store: store, session: session)
        } label: {
          VStack(alignment: .leading, spacing: 7) {
            HeroMetadataLine(parts: metadataParts)
            HeroTitle(text: title.name)
              .accessibilityIdentifier("homeHero")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)

        if let playbackError {
          Text(playbackError)
            .font(.caption)
            .foregroundStyle(Color.ozDanger)
            .padding(.top, 10)
            .transition(.opacity)
        }

        HeroActionRow {
          HeroPlayButton(title: "Assistir", isBusy: isStartingPlayback) {
            Task { await startPlayback() }
          }
          .accessibilityIdentifier("heroPlayButton")

          NavigationLink {
            TitleDetailView(titleID: title.id, store: store, session: session)
          } label: {
            HeroIconLabel(systemImage: "info")
          }
          .heroIconButtonStyle()
          .accessibilityLabel("Detalhes")
          .accessibilityIdentifier("heroDetailsButton")

          Spacer(minLength: 0)
        }
        .padding(.top, 18)
      }
      .animation(.snappy(duration: 0.25), value: playbackError)
      .animation(.snappy(duration: 0.25), value: isStartingPlayback)
    }
    .fullScreenCover(item: $selectedFile) { file in
      PlayerView(file: file, title: title.name, store: store, session: session)
    }
  }

  /// `FILME · 2026 · 2 h 17 min`, como a Apple faz — em vez de uma pílula.
  private var metadataParts: [String] {
    var parts = [kindLabel(title.kind).uppercased()]
    if let year = title.year { parts.append(String(year)) }
    if let duration = title.duration, duration > 0 {
      parts.append(heroDurationLabel(duration))
    }
    if let rating = title.rating, rating > 0 {
      parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))")
    }
    return parts
  }

  private func startPlayback() async {
    guard !isStartingPlayback else { return }
    isStartingPlayback = true
    playbackError = nil
    defer { isStartingPlayback = false }
    do {
      let detail = try await store.title(id: title.id, for: session)
      guard let file = detail.preferredPlayableFile else {
        playbackError = "Este título ainda não tem arquivo para reproduzir."
        return
      }
      selectedFile = file
    } catch {
      if case .signedOut = store.phase { return }
      playbackError = error.localizedDescription
    }
  }
}

private struct PosterShelf: View {
  let title: String
  let items: [TitleCard]
  @Bindable var store: SessionStore
  let session: AuthenticatedSession

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.headline).padding(.horizontal, 16)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 14) {
          ForEach(items) { item in
            PosterTile(title: item, store: store, session: session)
              .frame(width: 128)
          }
        }
        .padding(.horizontal, 16)
      }
      .scrollIndicators(.hidden)
    }
  }
}

private struct ContinueShelf: View {
  let title: String
  let items: [ContinueItem]
  @Bindable var store: SessionStore
  let session: AuthenticatedSession

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.headline).padding(.horizontal, 16)
      ScrollView(.horizontal) {
        LazyHStack(spacing: 14) {
          ForEach(items) { item in
            NavigationLink {
              TitleDetailView(titleID: item.titleID, store: store, session: session)
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                ZStack {
                  AuthenticatedArtwork(
                    path: item.backdrop ?? item.poster,
                    name: item.titleName,
                    store: store,
                    session: session,
                    maximumPixelSize: 600
                  )
                  Image(systemName: "play.fill")
                    .foregroundStyle(.white)
                    .padding(13)
                    .background(.black.opacity(0.58), in: .circle)
                }
                .frame(width: 220, height: 124)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                  GeometryReader { proxy in
                    Color.ozAccent
                      .frame(width: proxy.size.width * progress(item), height: 4)
                      .frame(maxHeight: .infinity, alignment: .bottom)
                  }
                }
                Text(item.titleName).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(item.label ?? remaining(item))
                  .font(.caption)
                  .foregroundStyle(Color.ozMuted)
              }
              .frame(width: 220, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 16)
      }
      .scrollIndicators(.hidden)
    }
  }

  private func progress(_ item: ContinueItem) -> Double {
    guard item.duration > 0 else { return 0 }
    return min(max(item.position / item.duration, 0), 1)
  }

  private func remaining(_ item: ContinueItem) -> String {
    let minutes = max(Int((item.duration - item.position) / 60), 0)
    return "faltam \(minutes) min"
  }
}

struct PosterTile: View {
  let title: TitleCard
  @Bindable var store: SessionStore
  let session: AuthenticatedSession

  var body: some View {
    NavigationLink {
      TitleDetailView(titleID: title.id, store: store, session: session)
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        AuthenticatedArtwork(path: title.poster, name: title.name, store: store, session: session)
          .aspectRatio(2 / 3, contentMode: .fit)
          .clipShape(.rect(cornerRadius: 12))
          .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.ozLine) }
        // Reserva as duas linhas mesmo com título curto: sem isso a célula de
        // uma linha fica mais baixa e o ano desalinha em relação à vizinha.
        Text(title.name)
          .font(.subheadline.weight(.medium))
          .lineLimit(2, reservesSpace: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(title.year.map(String.init) ?? kindLabel(title.kind))
          .font(.caption)
          .foregroundStyle(Color.ozMuted)
      }
      .accessibilityElement(children: .combine)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("titleCard-\(title.id)")
  }
}

/// Detalhe do título: o mesmo banner da Home — arte sangrando até o topo, ficha
/// e ações por cima dela — e abaixo as etiquetas, a sinopse e os arquivos.
struct TitleDetailView: View {
  let titleID: Int
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @State private var state: Loadable<TitleDetail> = .idle
  @State private var favorite = false
  @State private var isChangingFavorite = false
  @State private var actionError: String?
  @State private var selectedFile: MediaFileInfo?
  @State private var showingCollections = false
  @State private var matchDetail: TitleDetail?
  @State private var heroScrollOffset: CGFloat = 0
  @State private var overviewExpanded = false

  var body: some View {
    Group {
      switch state {
      case .idle, .loading:
        LoadingContent(label: "Carregando detalhes…")
      case .failed(let message):
        ContentErrorView(message: message) { Task { await load(force: true) } }
      case .loaded(let detail):
        detailContent(detail)
      }
    }
    .background(Color.ozBackground)
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .fullScreenCover(item: $selectedFile) { file in
      PlayerView(file: file, title: loadedTitle, store: store, session: session)
    }
    .sheet(isPresented: $showingCollections) {
      CollectionMembershipView(titleID: titleID, store: store, session: session)
    }
    .sheet(item: $matchDetail) { detail in
      MatchCorrectionView(detail: detail, store: store, session: session) {
        Task { await load(force: true) }
      }
    }
    .accessibilityIdentifier("titleDetailScreen")
  }

  private func detailContent(_ detail: TitleDetail) -> some View {
    GeometryReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 22) {
          hero(detail, containerWidth: proxy.size.width)
          if let actionError { errorBanner(actionError) }
          facts(detail)
          overviewSection(detail)
          mediaSection(detail)
        }
        .padding(.bottom, 32)
        .animation(.snappy(duration: 0.25), value: actionError)
      }
      .heroScrollOffset($heroScrollOffset)
      .refreshable { await load(force: true) }
      .scrollIndicators(.hidden)
    }
    // O banner precisa começar na status bar; sem isso a barra de navegação
    // deixa um degrau preto em cima da arte.
    .ignoresSafeArea(edges: .top)
    // O nome já aparece grande no banner: repetir na barra é ruído.
    .toolbar(removing: .title)
  }

  // MARK: - Banner

  private func hero(_ detail: TitleDetail, containerWidth: CGFloat) -> some View {
    HeroBanner(containerWidth: containerWidth, scrollOffset: heroScrollOffset) {
      AuthenticatedArtwork(
        path: detail.backdropURL ?? detail.posterURL,
        name: detail.name,
        store: store,
        session: session,
        maximumPixelSize: 1400
      )
    } content: {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 7) {
          HeroMetadataLine(parts: metadataParts(detail))
          HeroTitle(text: detail.name)
            .accessibilityIdentifier("titleDetailName")
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let resume = detail.preferredPlayableFile.flatMap(resumeProgress) {
          resumeBar(fraction: resume.fraction, label: resume.label)
            .padding(.top, 14)
        }

        HeroActionRow {
          if let playable = detail.preferredPlayableFile {
            HeroPlayButton(title: playLabel(playable)) {
              selectedFile = playable
            }
            .accessibilityIdentifier("primaryPlayButton")
          }

          Button {
            Task { await toggleFavorite(detail) }
          } label: {
            HeroIconLabel(systemImage: favorite ? "heart.fill" : "heart")
          }
          .heroIconButtonStyle()
          .disabled(isChangingFavorite)
          .accessibilityLabel(favorite ? "Nos favoritos" : "Favoritar")
          .accessibilityIdentifier("favoriteButton")

          Button {
            showingCollections = true
          } label: {
            HeroIconLabel(systemImage: "rectangle.stack.badge.plus")
          }
          .heroIconButtonStyle()
          .accessibilityLabel("Coleções")
          .accessibilityIdentifier("titleCollectionsButton")

          Button {
            matchDetail = detail
          } label: {
            HeroIconLabel(systemImage: "sparkles.rectangle.stack")
          }
          .heroIconButtonStyle()
          .accessibilityLabel("Corrigir identificação")
          .accessibilityIdentifier("correctMatchButton")

          Spacer(minLength: 0)
        }
        .padding(.top, 18)
      }
      .animation(.snappy(duration: 0.25), value: favorite)
    }
  }

  /// Barra fina de retomada: onde o filme parou, com o tempo que falta.
  private func resumeBar(fraction: Double, label: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.26))
          Capsule().fill(.white).frame(width: max(proxy.size.width * fraction, 6))
        }
      }
      .frame(height: 4)
      Text(label)
        .font(.caption)
        .foregroundStyle(.white.opacity(0.78))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
  }

  // MARK: - Ações

  private func errorBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "exclamationmark.triangle.fill")
      Text(message).font(.caption)
      Spacer(minLength: 0)
    }
    .foregroundStyle(Color.ozDanger)
    .padding(12)
    .background(Color.ozDanger.opacity(0.12), in: .rect(cornerRadius: 12))
    .padding(.horizontal, 16)
    .transition(.opacity)
  }

  // MARK: - Ficha e sinopse

  @ViewBuilder
  private func facts(_ detail: TitleDetail) -> some View {
    let chips = factChips(detail)
    if !chips.isEmpty {
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(chips, id: \.self) { MetaChip(text: $0) }
        }
        .padding(.horizontal, 16)
      }
      .scrollIndicators(.hidden)
    }
  }

  @ViewBuilder
  private func overviewSection(_ detail: TitleDetail) -> some View {
    if let overview = detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
      !overview.isEmpty
    {
      VStack(alignment: .leading, spacing: 10) {
        sectionHeader("Sinopse")
        VStack(alignment: .leading, spacing: 8) {
          Text(overview)
            .font(.subheadline)
            .lineSpacing(3)
            .foregroundStyle(Color.ozMuted)
            .lineLimit(overviewExpanded ? nil : 4)
            .fixedSize(horizontal: false, vertical: true)

          // Sinopse curta cabe inteira; o botão só entra quando há corte.
          if overview.count > 200 {
            Button(overviewExpanded ? "Mostrar menos" : "Mostrar mais") {
              withAnimation(.snappy(duration: 0.25)) { overviewExpanded.toggle() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.ozAccent)
            .accessibilityIdentifier("overviewToggle")
          }
        }
        .padding(.horizontal, 16)
      }
    }
  }

  private func sectionHeader(_ title: String, detail: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(title).font(.title3.weight(.semibold))
      if let detail {
        Text(detail).font(.caption).foregroundStyle(Color.ozMuted)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
  }

  // MARK: - Arquivos

  @ViewBuilder
  private func mediaSection(_ detail: TitleDetail) -> some View {
    if let seasons = detail.seasons, !seasons.isEmpty {
      VStack(alignment: .leading, spacing: 14) {
        sectionHeader("Episódios", detail: episodeCountLabel(seasons))
        ForEach(seasons) { season in
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Text(season.number == 0 ? "Especiais" : "Temporada \(season.number)")
                .font(.subheadline.weight(.semibold))
              Spacer(minLength: 8)
              Text("\(season.episodes.count) ep.")
                .font(.caption)
                .foregroundStyle(Color.ozMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider().overlay(Color.ozLine)
            ForEach(season.episodes) { episode in
              MediaFileRow(
                file: episode,
                kind: detail.kind,
                action: { selectedFile = episode },
                setWatched: { watched in
                  Task { await changeWatched(watched, file: episode) }
                }
              )
              if episode.id != season.episodes.last?.id {
                Divider().overlay(Color.ozLine).padding(.leading, 60)
              }
            }
          }
          .background(Color.ozSurface, in: .rect(cornerRadius: 16))
          .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.ozLine) }
          .padding(.horizontal, 16)
        }
      }
    } else if detail.files.isEmpty {
      ContentUnavailableView("Nenhum arquivo", systemImage: "doc")
    } else {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader(
          sectionTitle(detail.kind),
          detail: detail.files.count > 1 ? "\(detail.files.count)" : nil
        )
        VStack(spacing: 0) {
          ForEach(detail.files) { file in
            MediaFileRow(
              file: file,
              kind: detail.kind,
              action: { if file.mediaType != .photo { selectedFile = file } },
              setWatched: { watched in
                Task { await changeWatched(watched, file: file) }
              }
            )
            if file.id != detail.files.last?.id {
              Divider().overlay(Color.ozLine).padding(.leading, 60)
            }
          }
        }
        .background(Color.ozSurface, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.ozLine) }
        .padding(.horizontal, 16)
      }
    }
  }

  // MARK: - Dados

  private func load(force: Bool = false) async {
    guard force || state == .idle else { return }
    state.beginLoading()
    do {
      let detail = try await store.title(id: titleID, for: session, force: force)
      favorite = detail.favorite
      state = .loaded(detail)
    } catch {
      if case .signedOut = store.phase { return }
      state = .failed(error.localizedDescription)
    }
  }

  private func toggleFavorite(_ detail: TitleDetail) async {
    guard !isChangingFavorite else { return }
    isChangingFavorite = true
    actionError = nil
    let next = !favorite
    do {
      try await store.setFavorite(next, titleID: detail.id, for: session)
      withAnimation(.snappy) { favorite = next }
    } catch {
      if case .signedOut = store.phase { return }
      actionError = error.localizedDescription
    }
    isChangingFavorite = false
  }

  private func changeWatched(_ watched: Bool, file: MediaFileInfo) async {
    actionError = nil
    do {
      try await store.setWatched(watched, file: file, for: session)
      await load(force: true)
    } catch {
      if case .signedOut = store.phase { return }
      actionError = error.localizedDescription
    }
  }

  // MARK: - Texto

  /// `FILME · 2026 · 2 h 17 min · ★ 7,9`, no mesmo formato da Home.
  private func metadataParts(_ detail: TitleDetail) -> [String] {
    var parts = [kindLabel(detail.kind).uppercased()]
    if let year = detail.year { parts.append(String(year)) }
    if let artist = detail.artist, !artist.isEmpty { parts.append(artist) }
    if let seasons = detail.seasons, !seasons.isEmpty {
      parts.append(
        seasons.count == 1 ? episodeCountLabel(seasons) : "\(seasons.count) temporadas")
    } else if let runtime = runtimeLabel(detail) {
      parts.append(runtime)
    }
    if let rating = detail.rating, rating > 0 {
      parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))")
    }
    return parts
  }

  /// Etiquetas da ficha: biblioteca primeiro, depois os gêneros que vierem do
  /// servidor separados por vírgula ou barra.
  private func factChips(_ detail: TitleDetail) -> [String] {
    var chips: [String] = []
    var seen = Set<String>()
    let candidates =
      [detail.library, qualityLabel(detail) ?? ""]
      + (detail.genres ?? "")
      .split(whereSeparator: { $0 == "," || $0 == "|" || $0 == ";" })
      .map { String($0) }
    for candidate in candidates {
      let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
      chips.append(text)
    }
    return chips
  }

  private func runtimeLabel(_ detail: TitleDetail) -> String? {
    guard detail.seasons == nil, detail.files.count == 1,
      let file = detail.files.first, file.duration > 0
    else { return nil }
    return heroDurationLabel(file.duration)
  }

  private func qualityLabel(_ detail: TitleDetail) -> String? {
    guard let file = detail.preferredPlayableFile, file.mediaType == .video,
      let height = file.height, height > 0
    else { return nil }
    if height >= 2000 { return "4K" }
    if height >= 1400 { return "1440p" }
    if height >= 1000 { return "1080p" }
    if height >= 700 { return "720p" }
    return "\(height)p"
  }

  private func episodeCountLabel(_ seasons: [MediaSeason]) -> String {
    let total = seasons.reduce(0) { $0 + $1.episodes.count }
    return total == 1 ? "1 episódio" : "\(total) episódios"
  }

  private func resumeProgress(_ file: MediaFileInfo) -> (fraction: Double, label: String)? {
    guard file.finished != true, let position = file.position, position > 5, file.duration > 0
    else { return nil }
    let fraction = min(max(position / file.duration, 0), 1)
    let remaining = max(Int((file.duration - position) / 60), 1)
    return (fraction, "Faltam \(remaining) min · \(Int(fraction * 100))% assistido")
  }

  private func sectionTitle(_ kind: TitleKind) -> String {
    switch kind {
    case .album: "Faixas"
    case .photos: "Fotos"
    default: "Arquivos"
    }
  }

  private var loadedTitle: String {
    if case .loaded(let detail) = state { return detail.name }
    return "Ozymandias"
  }

  private func playLabel(_ file: MediaFileInfo) -> String {
    if let position = file.position, position > 5, file.finished != true {
      return "Continuar"
    }
    return file.mediaType == .audio ? "Tocar" : "Assistir"
  }
}

private struct MetaChip: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.caption.weight(.medium))
      .foregroundStyle(Color.ozMuted)
      .lineLimit(1)
      .padding(.horizontal, 11)
      .padding(.vertical, 6)
      .background(Color.ozSurface, in: .capsule)
      .overlay { Capsule().stroke(Color.ozLine) }
  }
}

private struct MediaFileRow: View {
  let file: MediaFileInfo
  let kind: TitleKind
  let action: () -> Void
  let setWatched: (Bool) -> Void

  private var isWatched: Bool { file.finished == true }
  private var watchedLabel: String {
    isWatched ? "Marcar como não assistido" : "Marcar como assistido"
  }

  var body: some View {
    Button(action: action) {
      rowContent
    }
    .buttonStyle(.plain)
    .disabled(file.mediaType == .photo)
    .accessibilityIdentifier("playFile-\(file.id)")
    .contextMenu {
      if file.mediaType != .photo {
        Button {
          setWatched(!isWatched)
        } label: {
          Label(watchedLabel, systemImage: isWatched ? "arrow.uturn.backward" : "checkmark.circle")
        }
      }
    }
    .accessibilityAction(named: Text(watchedLabel)) { setWatched(!isWatched) }
  }

  private var rowContent: some View {
    VStack(spacing: 9) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 9).fill(Color.ozAccent.opacity(0.15))
          Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.ozAccent)
        }
        .frame(width: 34, height: 34)

        VStack(alignment: .leading, spacing: 3) {
          // Nome de arquivo de filme costuma ser longo; uma linha só mantém a
          // altura da célula estável e o resto da ficha vem no rótulo de baixo.
          Text(primaryLabel)
            .font(.subheadline.weight(.medium))
            .lineLimit(kind == .tv ? 2 : 1)
            .multilineTextAlignment(.leading)
          Text(secondaryLabel)
            .font(.caption)
            .foregroundStyle(Color.ozMuted)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        if isWatched {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 17))
            .foregroundStyle(Color.ozOkay)
        } else if let fraction = progressFraction {
          Text("\(Int(fraction * 100))%")
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(Color.ozMuted)
        }

        if file.mediaType != .photo {
          Image(systemName: "play.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.ozAccentInk)
            .frame(width: 28, height: 28)
            .background(Color.ozAccent, in: .circle)
        }
      }

      if let fraction = progressFraction {
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.ozLine)
            Capsule().fill(Color.ozAccent).frame(width: max(proxy.size.width * fraction, 5))
          }
        }
        .frame(height: 3)
        .padding(.leading, 46)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .frame(minHeight: 62)
    .contentShape(.rect)
  }

  private var primaryLabel: String {
    if kind == .tv, let episode = file.episode {
      let prefix = "E\(episode)"
      return file.episodeName.map { "\(prefix) · \($0)" } ?? "\(prefix) · \(file.name)"
    }
    return file.name
  }

  private var secondaryLabel: String {
    var parts: [String] = []
    if kind == .album, let track = file.track { parts.append("Faixa \(track)") }
    if file.duration > 0 { parts.append(duration(file.duration)) }
    if let quality { parts.append(quality) }
    if !fileExtension.isEmpty { parts.append(fileExtension) }
    return parts.joined(separator: " · ")
  }

  /// O servidor manda a extensão com ponto; na lista ela vira só a sigla.
  private var fileExtension: String {
    let raw = file.ext.hasPrefix(".") ? String(file.ext.dropFirst()) : file.ext
    return raw.uppercased()
  }

  private var quality: String? {
    guard file.mediaType == .video, let height = file.height, height > 0 else { return nil }
    if height >= 2000 { return "4K" }
    if height >= 1400 { return "1440p" }
    if height >= 1000 { return "1080p" }
    if height >= 700 { return "720p" }
    return "\(height)p"
  }

  private var progressFraction: Double? {
    guard !isWatched, let position = file.position, position > 0, file.duration > 0 else {
      return nil
    }
    return min(max(position / file.duration, 0), 1)
  }

  private var icon: String {
    switch file.mediaType {
    case .video: "play.rectangle"
    case .audio: "music.note"
    case .photo: "photo"
    }
  }

  private func duration(_ seconds: Double) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)min" : "\(minutes) min"
  }
}

struct AuthenticatedArtwork: View {
  let path: String?
  let name: String
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  /// Maior lado em pixels que esta posição precisa; a arte é reduzida no decode.
  var maximumPixelSize: CGFloat = 400
  @State private var image: UIImage?

  var body: some View {
    // `Color.clear` aceita o tamanho proposto e a imagem entra por overlay:
    // `scaledToFill` num ZStack reporta um tamanho de layout MAIOR que o
    // proposto e faz o container inteiro crescer junto.
    Color.clear
      .overlay {
        LinearGradient(
          colors: [Color.ozElevated, Color.ozAccent.opacity(0.48)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
      .overlay {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
        } else {
          Text(initials(name))
            .font(.title2.weight(.bold))
            .foregroundStyle(Color.ozInk.opacity(0.72))
        }
      }
      .clipped()
    .task(id: path) { await loadArtwork() }
    .accessibilityHidden(true)
  }

  private func loadArtwork() async {
    guard let path, !path.isEmpty else {
      image = nil
      return
    }
    let key = "\(session.credential.serverURL.absoluteString)|\(path)|\(Int(maximumPixelSize))"
    let store = store
    let session = session
    image = await ArtworkCache.shared.image(for: key, maximumPixelSize: maximumPixelSize) {
      try await store.imageData(path: path, for: session)
    }
  }

  private func initials(_ value: String) -> String {
    value.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
  }
}

private struct FilterChip: View {
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(title, action: action)
      .font(.caption.weight(.semibold))
      .foregroundStyle(selected ? Color.ozAccentInk : Color.ozInk)
      .padding(.horizontal, 13)
      .frame(minHeight: 36)
      .background(selected ? Color.ozAccent : Color.ozSurface, in: .capsule)
      .overlay { Capsule().stroke(selected ? Color.ozAccent : Color.ozLine) }
  }
}

struct LoadingContent: View {
  let label: String

  var body: some View {
    VStack(spacing: 14) {
      ProgressView().controlSize(.large)
      Text(label).font(.subheadline).foregroundStyle(Color.ozMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct ContentErrorView: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("Não foi possível carregar", systemImage: "wifi.exclamationmark")
    } description: {
      Text(message)
    } actions: {
      Button("Tentar novamente", action: retry).buttonStyle(.borderedProminent)
    }
  }
}

private struct EmptyLibraryView: View {
  var body: some View {
    ContentUnavailableView(
      "Seu acervo está vazio",
      systemImage: "externaldrive",
      description: Text("Adicione uma biblioteca no servidor e execute um scan.")
    )
  }
}

func kindLabel(_ kind: TitleKind) -> String {
  switch kind {
  case .movie: "Filme"
  case .tv: "Série"
  case .album: "Álbum"
  case .photos: "Fotos"
  }
}

/// `2 h 17 min`, `47 min` — o formato que a Apple usa em fichas de mídia.
func heroDurationLabel(_ seconds: Double) -> String {
  let total = max(Int(seconds), 0)
  let hours = total / 3600
  let minutes = (total % 3600) / 60
  if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
  return "\(minutes) min"
}
