import SwiftUI

struct ArtistsView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @State private var state: Loadable<[ArtistCard]> = .idle
  @State private var query = ""

  private let columns = [GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 18, alignment: .top)]

  var body: some View {
    Group {
      switch state {
      case .idle, .loading:
        LoadingContent(label: "Carregando artistas…")
      case .failed(let message):
        ContentErrorView(message: message) { Task { await load() } }
      case .loaded(let artists):
        content(artists)
      }
    }
    .background(Color.ozBackground)
    .navigationTitle("Artistas")
    .searchable(text: $query, prompt: "Buscar artista")
    .task { await load() }
  }

  private func content(_ artists: [ArtistCard]) -> some View {
    let visible = filtered(artists)
    return ScrollView {
      if artists.isEmpty {
        ContentUnavailableView(
          "Nenhum artista",
          systemImage: "music.mic",
          description: Text("Os artistas aparecem a partir das tags dos arquivos de música.")
        )
        .padding(.top, 60)
      } else if visible.isEmpty {
        ContentUnavailableView.search(text: query).padding(.top, 60)
      } else {
        LazyVGrid(columns: columns, spacing: 24) {
          ForEach(visible) { artist in
            NavigationLink {
              ArtistDetailView(name: artist.name, store: store, session: session)
            } label: {
              VStack(spacing: 10) {
                AuthenticatedArtwork(
                  path: artist.poster,
                  name: artist.name,
                  store: store,
                  session: session,
                  maximumPixelSize: 500
                )
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.circle)
                .overlay { Circle().stroke(Color.ozLine) }

                Text(artist.name)
                  .font(.subheadline.weight(.semibold))
                  .lineLimit(1)
                Text("\(artist.albums) álbuns · \(artist.tracks) faixas")
                  .font(.caption2)
                  .foregroundStyle(Color.ozMuted)
                  .lineLimit(1)
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("artist-\(artist.name)")
          }
        }
        .padding(16)
        .accessibilityIdentifier("artistsLoaded")
      }
    }
    .refreshable { await load() }
  }

  private func filtered(_ artists: [ArtistCard]) -> [ArtistCard] {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return artists }
    return artists.filter { $0.name.localizedStandardContains(clean) }
  }

  private func load() async {
    state.beginLoading()
    do {
      state = try await .loaded(store.artists(for: session))
    } catch {
      if case .signedOut = store.phase { return }
      state = .failed(error.localizedDescription)
    }
  }
}

private struct QueueSelection: Identifiable {
  let file: MediaFileInfo
  let queue: [MediaFileInfo]
  let artist: String
  var id: Int { file.id }
}

struct ArtistDetailView: View {
  let name: String
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @State private var state: Loadable<ArtistDetail> = .idle
  @State private var selection: QueueSelection?

  private let albumColumns = [GridItem(.adaptive(minimum: 108, maximum: 160), spacing: 16, alignment: .top)]

  var body: some View {
    Group {
      switch state {
      case .idle, .loading:
        LoadingContent(label: "Carregando discografia…")
      case .failed(let message):
        ContentErrorView(message: message) { Task { await load() } }
      case .loaded(let artist):
        artistContent(artist)
      }
    }
    .background(Color.ozBackground)
    .navigationTitle(name)
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .fullScreenCover(item: $selection) { selection in
      PlayerView(
        file: selection.file,
        title: selection.artist,
        queue: selection.queue,
        store: store,
        session: session
      )
    }
  }

  private func artistContent(_ artist: ArtistDetail) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 14) {
          Text(artist.name)
            .font(.largeTitle.bold())
            .accessibilityIdentifier("artistDetailName")
          Text(summary(artist))
            .font(.subheadline)
            .foregroundStyle(Color.ozMuted)

          if !artist.tracks.isEmpty {
            HStack(spacing: 12) {
              Button {
                play(artist.tracks, from: 0, artist: artist.name)
              } label: {
                Label("Tocar tudo", systemImage: "play.fill").frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("playAllButton")

              Button {
                play(artist.tracks.shuffled(), from: 0, artist: artist.name)
              } label: {
                Label("Aleatório", systemImage: "shuffle").frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .accessibilityIdentifier("shuffleButton")
            }
            .controlSize(.large)
          }
        }
        .padding(.horizontal, 16)

        if !artist.albums.isEmpty {
          VStack(alignment: .leading, spacing: 14) {
            Text("Discografia").font(.headline).padding(.horizontal, 16)
            LazyVGrid(columns: albumColumns, spacing: 20) {
              ForEach(artist.albums) { album in
                PosterTile(title: album, store: store, session: session)
              }
            }
            .padding(.horizontal, 16)
          }
        }

        if !artist.tracks.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Todas as faixas").font(.headline).padding(.horizontal, 16)
            VStack(spacing: 0) {
              ForEach(Array(artist.tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                  play(artist.tracks, from: index, artist: artist.name)
                } label: {
                  HStack(spacing: 12) {
                    Image(systemName: "music.note")
                      .foregroundStyle(Color.ozAccent)
                      .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                      Text(track.name).font(.subheadline).lineLimit(1)
                      if let number = track.track, number > 0 {
                        Text("Faixa \(number)").font(.caption2).foregroundStyle(Color.ozMuted)
                      }
                    }
                    Spacer()
                    Text(duration(track.duration))
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(Color.ozMuted)
                  }
                  .padding(.horizontal, 14)
                  .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("artistTrack-\(track.id)")
                if track.id != artist.tracks.last?.id {
                  Divider().overlay(Color.ozLine).padding(.leading, 54)
                }
              }
            }
            .ozyCard()
            .padding(.horizontal, 16)
          }
        }
      }
      .padding(.vertical, 20)
    }
    .refreshable { await load() }
  }

  private func play(_ queue: [MediaFileInfo], from index: Int, artist: String) {
    guard queue.indices.contains(index) else { return }
    selection = QueueSelection(file: queue[index], queue: queue, artist: artist)
  }

  private func load() async {
    state.beginLoading()
    do {
      state = try await .loaded(store.artist(name: name, for: session))
    } catch {
      if case .signedOut = store.phase { return }
      state = .failed(error.localizedDescription)
    }
  }

  private func summary(_ artist: ArtistDetail) -> String {
    "\(artist.albums.count) álbuns · \(artist.tracks.count) faixas · \(duration(artist.duration))"
  }

  private func duration(_ seconds: Double) -> String {
    let total = max(Int(seconds), 0)
    if total >= 3_600 { return "\(total / 3_600)h \((total % 3_600) / 60)m" }
    return "\(total / 60):\(String(format: "%02d", total % 60))"
  }
}
