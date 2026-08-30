import SwiftUI

struct CollectionsView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @State private var state: Loadable<[MediaCollection]> = .idle
  @State private var showingCreate = false
  @State private var newName = ""
  @State private var isCreating = false
  @State private var actionError: String?

  var body: some View {
    Group {
      switch state {
      case .idle, .loading:
        LoadingContent(label: "Carregando coleções…")
      case .failed(let message):
        ContentErrorView(message: message) { Task { await load(force: true) } }
      case .loaded(let collections):
        collectionList(collections)
      }
    }
    .background(Color.ozBackground)
    .navigationTitle("Coleções")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          newName = ""
          showingCreate = true
        } label: {
          Label("Nova coleção", systemImage: "plus")
        }
        .accessibilityIdentifier("createCollectionButton")
      }
    }
    .alert("Nova coleção", isPresented: $showingCreate) {
      TextField("Nome", text: $newName)
      Button("Cancelar", role: .cancel) {}
      Button("Criar") { Task { await createCollection() } }
        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    } message: {
      Text("Crie uma lista para organizar filmes, séries, álbuns ou fotos.")
    }
    .task { await load() }
  }

  @ViewBuilder
  private func collectionList(_ collections: [MediaCollection]) -> some View {
    VStack(spacing: 0) {
      if let actionError {
        Label(actionError, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(Color.ozDanger)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(Color.ozDanger.opacity(0.12), in: .rect(cornerRadius: 10))
          .padding(.horizontal, 16)
          .padding(.top, 10)
          .accessibilityIdentifier("collectionsError")
      }
      collectionBody(collections)
    }
  }

  @ViewBuilder
  private func collectionBody(_ collections: [MediaCollection]) -> some View {
    if collections.isEmpty {
      ContentUnavailableView {
        Label("Nenhuma coleção", systemImage: "rectangle.stack")
      } description: {
        Text("Monte listas para organizar o que quiser rever depois.")
      } actions: {
        Button("Criar coleção") { showingCreate = true }
          .buttonStyle(.borderedProminent)
      }
      .accessibilityIdentifier("collectionsLoaded")
    } else {
      List(collections) { collection in
        NavigationLink {
          CollectionDetailView(collection: collection, store: store, session: session) {
            Task { await load(force: true) }
          }
        } label: {
          HStack(spacing: 14) {
            AuthenticatedArtwork(
              path: collection.poster,
              name: collection.name,
              store: store,
              session: session,
              maximumPixelSize: 200
            )
            .frame(width: 58, height: 76)
            .clipShape(.rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 5) {
              Text(collection.name).font(.headline)
              Text(
                "\(collection.itemCount) \(collection.itemCount == 1 ? "título" : "títulos")"
              )
              .font(.caption)
              .foregroundStyle(Color.ozMuted)
            }
          }
          .padding(.vertical, 4)
        }
        .accessibilityIdentifier("collection-\(collection.id)")
      }
      .listStyle(.plain)
      .refreshable { await load(force: true) }
      .accessibilityIdentifier("collectionsLoaded")
    }
  }

  private func load(force: Bool = false) async {
    guard force || state == .idle else { return }
    state.beginLoading()
    do {
      state = try await .loaded(store.collections(for: session))
    } catch {
      if case .signedOut = store.phase { return }
      state = .failed(error.localizedDescription)
    }
  }

  private func createCollection() async {
    guard !isCreating else { return }
    isCreating = true
    actionError = nil
    do {
      _ = try await store.createCollection(name: newName, for: session)
      await load(force: true)
    } catch {
      actionError = error.localizedDescription
    }
    isCreating = false
  }
}

private struct CollectionDetailView: View {
  let collection: MediaCollection
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  let didChange: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var state: Loadable<CollectionContent> = .idle
  @State private var showingRename = false
  @State private var showingDelete = false
  @State private var renameName = ""
  @State private var actionError: String?

  private let columns = [GridItem(.adaptive(minimum: 108, maximum: 170), spacing: 16, alignment: .top)]

  var body: some View {
    Group {
      switch state {
      case .idle, .loading:
        LoadingContent(label: "Abrindo coleção…")
      case .failed(let message):
        ContentErrorView(message: message) { Task { await load(force: true) } }
      case .loaded(let content):
        detail(content)
      }
    }
    .background(Color.ozBackground)
    .navigationTitle(currentName)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button {
            renameName = currentName
            showingRename = true
          } label: {
            Label("Renomear", systemImage: "pencil")
          }
          Button(role: .destructive) {
            showingDelete = true
          } label: {
            Label("Apagar coleção", systemImage: "trash")
          }
        } label: {
          Label("Opções", systemImage: "ellipsis.circle")
        }
      }
    }
    .alert("Renomear coleção", isPresented: $showingRename) {
      TextField("Nome", text: $renameName)
      Button("Cancelar", role: .cancel) {}
      Button("Salvar") { Task { await rename() } }
        .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .confirmationDialog(
      "Apagar \(currentName)?",
      isPresented: $showingDelete,
      titleVisibility: .visible
    ) {
      Button("Apagar coleção", role: .destructive) { Task { await delete() } }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("Os títulos não serão apagados do servidor.")
    }
    .task { await load() }
  }

  private func detail(_ content: CollectionContent) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(
          "\(content.items.count) \(content.items.count == 1 ? "título" : "títulos")"
        )
        .font(.caption)
        .foregroundStyle(Color.ozMuted)

        if let actionError {
          Label(actionError, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(Color.ozDanger)
        }

        if content.items.isEmpty {
          ContentUnavailableView(
            "Coleção vazia",
            systemImage: "rectangle.stack.badge.plus",
            description: Text("Adicione títulos pelo botão Coleções na tela de detalhes.")
          )
          .frame(maxWidth: .infinity)
          .padding(.top, 50)
        } else {
          LazyVGrid(columns: columns, spacing: 22) {
            ForEach(content.items) { title in
              PosterTile(title: title, store: store, session: session)
                .contextMenu {
                  Button(role: .destructive) {
                    Task { await remove(titleID: title.id) }
                  } label: {
                    Label("Remover da coleção", systemImage: "minus.circle")
                  }
                }
                .accessibilityAction(named: "Remover da coleção") {
                  Task { await remove(titleID: title.id) }
                }
            }
          }
        }
      }
      .padding(16)
    }
    .refreshable { await load(force: true) }
  }

  private var currentName: String {
    if case .loaded(let content) = state { return content.collection.name }
    return collection.name
  }

  private func load(force: Bool = false) async {
    guard force || state == .idle else { return }
    state.beginLoading()
    do {
      state = try await .loaded(store.collection(id: collection.id, for: session))
    } catch {
      if case .signedOut = store.phase { return }
      state = .failed(error.localizedDescription)
    }
  }

  private func rename() async {
    do {
      try await store.renameCollection(id: collection.id, name: renameName, for: session)
      didChange()
      await load(force: true)
    } catch {
      actionError = error.localizedDescription
    }
  }

  private func delete() async {
    do {
      try await store.deleteCollection(id: collection.id, for: session)
      didChange()
      dismiss()
    } catch {
      actionError = error.localizedDescription
    }
  }

  private func remove(titleID: Int) async {
    do {
      try await store.setCollectionMembership(
        collectionID: collection.id,
        titleID: titleID,
        included: false,
        for: session
      )
      didChange()
      await load(force: true)
    } catch {
      actionError = error.localizedDescription
    }
  }
}

struct CollectionMembershipView: View {
  let titleID: Int
  @Bindable var store: SessionStore
  let session: AuthenticatedSession
  @Environment(\.dismiss) private var dismiss
  @State private var state: Loadable<MembershipContent> = .idle
  @State private var changingIDs: Set<Int> = []
  @State private var actionError: String?

  var body: some View {
    NavigationStack {
      Group {
        switch state {
        case .idle, .loading:
          LoadingContent(label: "Carregando coleções…")
        case .failed(let message):
          ContentErrorView(message: message) { Task { await load() } }
        case .loaded(let content):
          membershipList(content)
        }
      }
      .background(Color.ozBackground)
      .navigationTitle("Coleções")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Concluir") { dismiss() }
        }
      }
    }
    .task { await load() }
  }

  private func membershipList(_ content: MembershipContent) -> some View {
    List {
      if let actionError {
        Label(actionError, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(Color.ozDanger)
      }
      if content.collections.isEmpty {
        ContentUnavailableView(
          "Nenhuma coleção",
          systemImage: "rectangle.stack",
          description: Text("Crie uma coleção na aba Coleções primeiro.")
        )
      } else {
        ForEach(content.collections) { collection in
          Button {
            Task { await toggle(collection, content: content) }
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(collection.name).foregroundStyle(Color.primary)
                Text("\(collection.itemCount) títulos")
                  .font(.caption)
                  .foregroundStyle(Color.ozMuted)
              }
              Spacer()
              if changingIDs.contains(collection.id) {
                ProgressView().controlSize(.small)
              } else if content.selectedIDs.contains(collection.id) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ozAccent)
              } else {
                Image(systemName: "circle").foregroundStyle(Color.ozMuted)
              }
            }
          }
          .disabled(changingIDs.contains(collection.id))
          .accessibilityIdentifier("membership-\(collection.id)")
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  private func load() async {
    state.beginLoading()
    do {
      async let collections = store.collections(for: session)
      async let selected = store.collectionIDs(titleID: titleID, for: session)
      state = try await .loaded(
        MembershipContent(collections: collections, selectedIDs: Set(selected)))
    } catch {
      if case .signedOut = store.phase { return }
      state = .failed(error.localizedDescription)
    }
  }

  private func toggle(_ collection: MediaCollection, content: MembershipContent) async {
    let included = !content.selectedIDs.contains(collection.id)
    changingIDs.insert(collection.id)
    actionError = nil
    do {
      try await store.setCollectionMembership(
        collectionID: collection.id,
        titleID: titleID,
        included: included,
        for: session
      )
      var selected = content.selectedIDs
      if included { selected.insert(collection.id) } else { selected.remove(collection.id) }
      state = .loaded(MembershipContent(collections: content.collections, selectedIDs: selected))
    } catch {
      actionError = error.localizedDescription
    }
    changingIDs.remove(collection.id)
  }
}

private struct MembershipContent: Equatable, Sendable {
  let collections: [MediaCollection]
  let selectedIDs: Set<Int>
}
