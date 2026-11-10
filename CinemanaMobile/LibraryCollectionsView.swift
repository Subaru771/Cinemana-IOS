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
                                            Text(video.title).font(.subheadline.weight(.semibold))
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

/// Each season already supports batch download. This adds choose-episodes selection.
struct EpisodeBatchDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloader = DownloadCenter.shared
    let videos: [Video]
    @State private var selected: Set<String>
    @State private var quality = 720

    init(videos: [Video]) {
        self.videos = videos
        _selected = State(initialValue: Set(videos.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Select all") { selected = Set(videos.map(\.id)) }
                        Spacer()
                        Button("Clear") { selected = [] }
                    }
                    ForEach(videos) { video in
                        Button {
                            if selected.contains(video.id) { selected.remove(video.id) }
                            else { selected.insert(video.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(video.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(video.id) ? Color.red : Color.gray)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("S\(video.season) E\(video.episode)").font(.caption.weight(.bold))
                                    Text(video.title).lineLimit(2)
                                }
                                Spacer()
                                if downloader.entry(for: video.id)?.status == .ready {
                                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                                }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                } header: { Text("Choose episodes (\(selected.count))") }
                Section("Quality") {
                    Picker("Quality", selection: $quality) {
                        ForEach([480, 720, 1080, 2160], id: \.self) { value in
                            Text("Up to \(value)p").tag(value)
                        }
                    }.pickerStyle(.segmented)
                    if let free = downloader.freeBytes {
                        Label("\(ByteFormat.string(free)) available on this device", systemImage: "internaldrive")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Download episodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Queue \(selected.count)") {
                        downloader.enqueue(videos.filter { selected.contains($0.id) }, preferredQuality: quality)
                        dismiss()
                    }.disabled(selected.isEmpty)
                }
            }
        }
    }
}
