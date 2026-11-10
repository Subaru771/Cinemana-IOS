import SwiftUI

/// Named collections are local-only and built on the existing favorites snapshots.
struct CollectionsView: View {
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    @State private var name = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    TextField("Collection name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { add() }
                    Button("Add", action: add)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if library.extras.collections.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No collections yet").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
            ForEach(library.extras.collections) { collection in
                Section {
                    let matching = library.snapshot.favorites.filter { collection.videoIDs.contains($0.id) && MatureContentFilter.allows($0, hideMature: hideMatureContent) }
                    if matching.isEmpty {
                        Text("Empty")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(matching) { video in
                            HStack {
                                NavigationLink { MovieDetailView(video: video) } label: {
                                    HStack(spacing: 12) {
                                        RemotePoster(url: video.poster).frame(width: 43, height: 63)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        VStack(alignment: .leading) {
                                            Text(video.localizedTitle).font(.subheadline.weight(.semibold))
                                            Text(video.year).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Button { library.toggle(video, in: collection.id) } label: {
                                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove from collection")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(collection.name)
                        Spacer()
                        Text("\(library.snapshot.favorites.filter { collection.videoIDs.contains($0.id) && MatureContentFilter.allows($0, hideMature: hideMatureContent) }.count)")
                    }
                } footer: {
                    Button(role: .destructive) { library.deleteCollection(collection.id) } label: {
                        Label("Delete collection", systemImage: "trash")
                    }.font(.footnote)
                }
            }
        }
        .navigationTitle("Collections")
    }

    private func add() {
        library.addCollection(name)
        name = ""
    }
}
