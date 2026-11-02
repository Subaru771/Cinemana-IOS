import SwiftUI
import AVKit

private let mint = Color(red: 0.55, green: 0.96, blue: 0.69)
private let ink = Color(red: 0.035, green: 0.065, blue: 0.06)
private let tile = Color(red: 0.09, green: 0.13, blue: 0.12)

@main
struct CinemanaMobileApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                CatalogView(kind: nil, title: "Discover")
                    .tabItem { Label("Home", systemImage: "house.fill") }
                CatalogView(kind: 1, title: "Movies")
                    .tabItem { Label("Movies", systemImage: "film") }
                CatalogView(kind: 2, title: "Series")
                    .tabItem { Label("Series", systemImage: "tv") }
                SearchCatalogView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                LibraryView()
                    .tabItem { Label("My List", systemImage: "bookmark.fill") }
            }
            .environmentObject(library)
            .tint(mint)
            .preferredColorScheme(.dark)
        }
    }
}

struct CatalogView: View {
    let kind: Int?
    let title: String
    @State private var rows: [CatalogRow] = []
    @State private var isLoading = true
    @State private var error: String?
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if kind == nil && !library.snapshot.recent.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Continue Watching").font(.title3.weight(.bold)).padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(library.snapshot.recent) { record in
                                        NavigationLink(value: record.video) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                PosterCard(video: record.video, width: 150)
                                                GeometryReader { geo in
                                                    Capsule().fill(.white.opacity(0.18))
                                                        .overlay(alignment: .leading) {
                                                            Capsule().fill(mint).frame(width: geo.size.width * record.fraction)
                                                        }
                                                }.frame(width: 150, height: 4)
                                            }
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.horizontal, 16)
                            }
                        }
                    }
                    if isLoading && rows.isEmpty { ProgressView().padding(30) }
                    if let error {
                        ErrorMessage(text: error) { Task { await refresh() } }
                    }
                    if let hero = rows.first?.videos.first {
                        NavigationLink(value: hero) {
                            FeaturedPoster(video: hero)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(row.title)
                                .font(.title3.weight(.bold))
                                .padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(row.videos) { video in
                                        NavigationLink(value: video) { PosterCard(video: video) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .background(ink)
            .navigationTitle(title)
            .navigationDestination(for: Video.self) { MovieDetailView(video: $0) }
            .refreshable { await refresh() }
            .task(id: kind) {
                if rows.isEmpty, let cached = await CatalogCache.shared.read(kind: kind) {
                    rows = cached
                    isLoading = false
                }
                await refresh()
            }
        }
    }

    @MainActor
    private func refresh() async {
        isLoading = rows.isEmpty
        defer { isLoading = false }
        do {
            let fresh = try await CinemanaAPI.shared.catalog(kind)
            guard !Task.isCancelled else { return }
            rows = fresh
            error = nil
            await CatalogCache.shared.save(fresh, kind: kind)
        } catch {
            if rows.isEmpty && !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

struct PosterCard: View {
    let video: Video
    var width: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemotePoster(url: video.poster)
                .frame(width: width, height: width * 1.46)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(video.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .frame(width: width, alignment: .leading)
            Text([video.year, video.rating.map { String(format: "★ %.1f", $0) } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " • "))
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: width, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
}

struct RemotePoster: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(tile)
                    .overlay { Image(systemName: "film").foregroundStyle(mint.opacity(0.6)) }
            }
        }
        .clipped()
    }
}

struct FeaturedPoster: View {
    let video: Video
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemotePoster(url: video.backdrop ?? video.poster)
            LinearGradient(colors: [.clear, ink.opacity(0.98)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text("FEATURED").font(.caption2.weight(.black)).foregroundStyle(mint)
                Text(video.title).font(.title.weight(.bold)).lineLimit(2)
                Text(video.year).foregroundStyle(.white.opacity(0.75))
            }
            .padding(18)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct MovieDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    let video: Video
    @State private var detail: Video?
    @State private var episodes: [Video] = []
    @State private var related: [Video] = []
    @State private var watch: Video?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemotePoster(url: (detail ?? video).backdrop ?? video.poster)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 14) {
                    Text((detail ?? video).title)
                        .font(.largeTitle.weight(.bold))
                    Text([detail?.year ?? video.year, (detail?.rating ?? video.rating).map { String(format: "★ %.1f", $0) } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: "  •  "))
                        .foregroundStyle(mint)
                    HStack(spacing: 12) {
                        Button { watch = detail ?? video } label: {
                            Label(library.playback(for: video.id) == nil ? "Play" : "Resume", systemImage: "play.fill")
                                .frame(maxWidth: .infinity).padding(7)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(mint).foregroundStyle(ink)
                        Button { library.toggle(detail ?? video) } label: {
                            Image(systemName: library.isSaved(video) ? "bookmark.fill" : "bookmark")
                                .frame(width: 48, height: 40)
                        }
                        .buttonStyle(.bordered)
                        .tint(mint)
                        .accessibilityLabel(library.isSaved(video) ? "Remove from My List" : "Add to My List")
                    }
                    if !(detail ?? video).overview.isEmpty {
                        Text((detail ?? video).overview).foregroundStyle(.secondary)
                    }
                    if !(detail ?? video).genres.isEmpty {
                        Text((detail ?? video).genres.joined(separator: "  •  "))
                            .font(.footnote).foregroundStyle(mint)
                    }
                    if !episodes.isEmpty {
                        Text("Episodes").font(.title2.weight(.bold)).padding(.top, 10)
                        ForEach(episodes) { ep in
                            Button { watch = ep } label: {
                                HStack(spacing: 12) {
                                    RemotePoster(url: ep.poster)
                                        .frame(width: 96, height: 65).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("S\(ep.season) E\(ep.episode)").font(.caption).foregroundStyle(mint)
                                        Text(ep.title).font(.subheadline).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    if !related.isEmpty {
                        Text("More like this").font(.title2.weight(.bold)).padding(.top, 10)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(related) { item in
                                    NavigationLink(value: item) { PosterCard(video: item) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 32)
        }
        .background(ink)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Video.self) { MovieDetailView(video: $0) }
        .fullScreenCover(item: $watch) { VideoPlaybackView(video: $0) }
        .task(id: video.id) {
            async let info = CinemanaAPI.shared.detail(video)
            async let eps = CinemanaAPI.shared.episodes(video.id)
            async let similar = CinemanaAPI.shared.related(video.id)
            detail = await info
            episodes = await eps
            related = await similar
        }
    }
}

struct SearchCatalogView: View {
    @State private var query = ""
    @State private var results: [Video] = []
    @State private var options = SearchOptions()
    @State private var loading = false
    @State private var error: String?

    private var genres: [String] {
        Array(Set(results.flatMap(\.genres))).sorted()
    }
    private var filtered: [Video] { options.apply(results) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search movies and series", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    }
                }
                .padding(12)
                .background(tile)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        Menu {
                            Picker("Type", selection: $options.type) {
                                ForEach(SearchType.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: { FilterLabel(text: options.type.rawValue, active: options.type != .all) }
                        Button { options.recent.toggle() } label: { FilterLabel(text: "2025+", active: options.recent) }
                        Button { options.minRating = options.minRating == 8 ? 0 : 8 } label: {
                            FilterLabel(text: "★ 8+", active: options.minRating == 8)
                        }
                        Menu {
                            Picker("Sort", selection: $options.sort) {
                                ForEach(SearchOrder.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: { FilterLabel(text: options.sort.rawValue, active: options.sort != .relevance) }
                        if !genres.isEmpty {
                            Menu {
                                Button("Any genre") { options.genre = "" }
                                ForEach(genres, id: \.self) { genre in
                                    Button(genre) { options.genre = genre }
                                }
                            } label: { FilterLabel(text: options.genre.isEmpty ? "Genre" : options.genre, active: !options.genre.isEmpty) }
                        }
                        Button("Clear") { options = SearchOptions() }.font(.caption)
                    }
                    .padding(.horizontal, 16)
                }
                if loading { ProgressView().padding(.horizontal, 16) }
                if let error { ErrorMessage(text: error) { Task { await search() } } }
                Text("\(filtered.count) results")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], alignment: .leading, spacing: 20) {
                        ForEach(filtered) { item in
                            NavigationLink(value: item) { PosterCard(video: item) }.buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .background(ink)
            .navigationTitle("Search")
            .navigationDestination(for: Video.self) { MovieDetailView(video: $0) }
            .task(id: query) {
                guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
                    results = []; error = nil; return
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await search()
            }
        }
    }

    @MainActor
    private func search() async {
        loading = true
        defer { loading = false }
        do { results = try await CinemanaAPI.shared.search(query); error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct FilterLabel: View {
    let text: String
    let active: Bool
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(active ? mint.opacity(0.20) : tile)
            .foregroundStyle(active ? mint : .white)
            .clipShape(Capsule())
    }
}

/// Full iOS playback controls, including native scrubbing and AirPlay when available.
struct NativePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

struct VideoPlaybackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var library: LibraryStore
    let video: Video
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var streams: [Stream] = []
    @State private var selected: Stream?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let player {
                    NativePlayerView(player: player)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                } else if loading {
                    ProgressView("Finding a compatible stream…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ErrorMessage(text: error ?? "No compatible stream available") {
                        Task { await load() }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Spacer(minLength: 12)
                if player != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(video.title).font(.title2.weight(.bold))
                        if let selected {
                            Label("Playing \(selected.label)", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(mint)
                        }
                        Text("Use native playback controls to seek, adjust volume, or select AirPlay.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    Spacer(minLength: 12)
                }
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { savePosition(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(streams) { stream in
                            Button { select(stream) } label: {
                                if selected?.id == stream.id {
                                    Label(stream.label, systemImage: "checkmark")
                                } else { Text(stream.label) }
                            }
                        }
                    } label: { Label(selected?.label ?? "Quality", systemImage: "gearshape") }
                        .disabled(streams.isEmpty)
                }
            }
        }
        .task(id: video.id) { await load() }
        .onDisappear { cleanup() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { savePosition() }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let available = try await CinemanaAPI.shared.streams(video.id)
            guard !Task.isCancelled else { return }
            streams = available
            guard let best = streams.first(where: { $0.quality > 0 && $0.quality <= 1080 })
                ?? streams.first else { throw CinemanaAPI.APIError.noStream }
            select(best)
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    @MainActor
    private func select(_ stream: Stream) {
        let previous = player?.currentTime().seconds
        let resume = (previous?.isFinite == true && (previous ?? 0) > 0)
            ? previous! : (library.playback(for: video.id)?.seconds ?? 0)
        savePosition()
        if let token = timeObserver, let player { player.removeTimeObserver(token) }
        timeObserver = nil
        player?.pause()

        let next = AVPlayer(url: stream.url)
        player = next
        selected = stream
        timeObserver = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 600),
                                                    queue: .main) { [weak next] _ in
            Task { @MainActor in
                guard let next else { return }
                let sec = next.currentTime().seconds
                let duration = next.currentItem?.duration.seconds ?? .nan
                library.record(video, position: sec, duration: duration)
            }
        }
        if resume.isFinite && resume > 10 {
            next.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) { finished in
                if finished { next.play() }
            }
        } else {
            next.play()
        }
    }

    @MainActor
    private func savePosition() {
        guard let player else { return }
        library.record(video, position: player.currentTime().seconds,
                       duration: player.currentItem?.duration.seconds ?? .nan)
    }

    @MainActor
    private func cleanup() {
        savePosition()
        if let token = timeObserver, let player { player.removeTimeObserver(token) }
        timeObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if library.snapshot.favorites.isEmpty && library.snapshot.recent.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bookmark.circle")
                                .font(.system(size: 48)).foregroundStyle(mint)
                            Text("Your list is empty").font(.title3.weight(.semibold))
                            Text("Save a movie or series to find it here later.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                    if !library.snapshot.recent.isEmpty {
                        Text("Continue Watching").font(.title2.weight(.bold))
                        ForEach(library.snapshot.recent) { item in
                            HStack(spacing: 12) {
                                NavigationLink(value: item.video) {
                                    HStack(spacing: 12) {
                                        RemotePoster(url: item.video.poster)
                                            .frame(width: 72, height: 105)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(item.video.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                            ProgressView(value: item.fraction).tint(mint)
                                            Text("\(Int(item.fraction * 100))% watched")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }.buttonStyle(.plain)
                                Button { library.removeRecent(item.id) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }.accessibilityLabel("Remove from Continue Watching")
                            }
                        }
                    }
                    if !library.snapshot.favorites.isEmpty {
                        Text("My List").font(.title2.weight(.bold)).padding(.top, 8)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 20) {
                            ForEach(library.snapshot.favorites) { item in
                                NavigationLink(value: item) { PosterCard(video: item) }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(16)
            }
            .background(ink)
            .navigationTitle("My List")
            .toolbar { NavigationLink { AboutView() } label: { Image(systemName: "gearshape") } }
            .navigationDestination(for: Video.self) { MovieDetailView(video: $0) }
        }
    }
}

struct AboutView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Cinemana Mobile") {
                    LabeledContent("Version", value: "iOS 1.1.0")
                    LabeledContent("Player", value: "AVPlayer / HLS / MP4")
                }
                Section("Connection") {
                    Text("The content provider may restrict access by ISP or require authorization. The app does not bypass those restrictions.")
                    Text("Some Android-compatible video formats, including MPEG-DASH, are not supported by the native iOS player.")
                    Text("External subtitle import is not yet available in this build.")
                    Text("The local watchlist and resume positions remain on this device.")
                }
                Section("Distribution") {
                    Text("An Apple signing identity is required for installation on physical iPhones. App Store distribution also requires suitable content rights.")
                }
            }
            .navigationTitle("More")
        }
    }
}

struct ErrorMessage: View {
    let text: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).foregroundStyle(.red)
            Button("Retry", action: retry).buttonStyle(.bordered)
        }
        .padding(16)
    }
}
