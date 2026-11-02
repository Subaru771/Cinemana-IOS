import SwiftUI
import AVKit
import UIKit

private let mint = Color(red: 0.55, green: 0.96, blue: 0.69)
private let ink = Color(red: 0.035, green: 0.065, blue: 0.06)
private let tile = Color(red: 0.09, green: 0.13, blue: 0.12)

final class CinemanaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadCenter.shared.registerCompletion(identifier, handler: completionHandler)
    }
}

@main
struct CinemanaMobileApp: App {
    @UIApplicationDelegateAdaptor(CinemanaAppDelegate.self) private var appDelegate
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
                    if isLoading && rows.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            ProgressView("Loading catalog…").tint(mint)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(0..<4, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(tile).frame(width: 132, height: 195)
                                    }
                                }
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 18)
                    }
                    if let error {
                        ErrorMessage(text: error) { Task { await refresh() } }
                    }
                    if rows.isEmpty && !isLoading && error == nil {
                        EmptyStateView(symbol: "film.stack", title: "Nothing to show yet",
                                       message: "Refresh the catalog or check your connection.")
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
            if !Task.isCancelled { self.error = error.localizedDescription }
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
                Rectangle().fill(
                    LinearGradient(colors: [tile, ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                ).overlay {
                    Image(systemName: "film.stack")
                        .font(.system(size: 29, weight: .ultraLight))
                        .foregroundStyle(mint.opacity(0.55))
                }
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
    @ObservedObject private var downloads = DownloadCenter.shared
    @EnvironmentObject private var library: LibraryStore
    let video: Video
    @State private var detail: Video?
    @State private var episodes: [Video] = []
    @State private var related: [Video] = []
    @State private var watch: Video?
    @State private var selectedSeason = 1
    @State private var synopsisExpanded = false
    @State private var loadingEpisodes = false

    private var isSeries: Bool { (detail ?? video).kind == "2" }
    private var sortedSeasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }
    private var visibleEpisodes: [Video] { episodes.filter { $0.season == selectedSeason } }
    private var playTarget: Video? {
        PlaybackPlanner.playTarget(for: detail ?? video,
                                   episodes: episodes, recent: library.snapshot.recent)
    }

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
                        Button {
                            if let target = playTarget { watch = target }
                        } label: {
                            Label(isSeries ? (playTarget.flatMap { library.playback(for: $0.id) } == nil ? "Play Episode" : "Resume Episode")
                                   : (library.playback(for: video.id) == nil ? "Play" : "Resume"),
                                  systemImage: "play.fill")
                                .frame(maxWidth: .infinity).padding(7)
                        }
                        .disabled(playTarget == nil)
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
                    if let target = playTarget {
                        DownloadAction(video: target)
                    }
                    if !(detail ?? video).overview.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text((detail ?? video).overview)
                                .lineLimit(synopsisExpanded ? nil : 4)
                                .foregroundStyle(.secondary)
                            Button(synopsisExpanded ? "Show less" : "Read more") {
                                withAnimation(.easeInOut(duration: 0.15)) { synopsisExpanded.toggle() }
                            }
                            .font(.footnote.weight(.semibold)).tint(mint)
                        }
                    }
                    if !(detail ?? video).genres.isEmpty {
                        Text((detail ?? video).genres.joined(separator: "  •  "))
                            .font(.footnote).foregroundStyle(mint)
                    }
                    if isSeries {
                        HStack {
                            Text("Episodes").font(.title2.weight(.bold))
                            Spacer()
                            if sortedSeasons.count > 1 {
                                Menu {
                                    ForEach(sortedSeasons, id: \.self) { season in
                                        Button("Season \(season)") { selectedSeason = season }
                                    }
                                } label: {
                                    Label("Season \(selectedSeason)", systemImage: "chevron.down")
                                        .font(.subheadline).foregroundStyle(mint)
                                }
                            }
                        }.padding(.top, 10)
                        if loadingEpisodes {
                            ProgressView("Loading episodes…").tint(mint)
                        } else if episodes.isEmpty {
                            Text("No episodes available on this connection.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Retry episodes") { Task { await reloadEpisodes() } }
                                .buttonStyle(.bordered)
                        }
                        ForEach(visibleEpisodes) { ep in
                            Button { watch = ep } label: {
                                HStack(spacing: 12) {
                                    RemotePoster(url: ep.poster ?? (detail ?? video).poster)
                                        .frame(width: 96, height: 65).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("S\(ep.season) · E\(ep.episode)")
                                            .font(.caption).foregroundStyle(mint)
                                        Text(ep.title).font(.subheadline).lineLimit(2)
                                        if let record = library.playback(for: ep.id) {
                                            ProgressView(value: record.fraction).tint(mint)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill").foregroundStyle(mint)
                                }.padding(.vertical, 5)
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
            detail = video
            synopsisExpanded = false
            related = []
            episodes = []
            loadingEpisodes = video.kind == "2"
            // Each section updates independently as its network request finishes.
            await withTaskGroup(of: DetailLoadResult.self) { group in
                group.addTask { .detail(await CinemanaAPI.shared.detail(video)) }
                group.addTask { .episodes(await CinemanaAPI.shared.episodes(video.id)) }
                group.addTask { .related(await CinemanaAPI.shared.related(video.id)) }
                for await update in group {
                    guard !Task.isCancelled else { break }
                    switch update {
                    case .detail(let value): detail = value
                    case .episodes(let list):
                        episodes = list
                        selectedSeason = list.first?.season ?? 1
                        loadingEpisodes = false
                    case .related(let list): related = list
                    }
                }
            }
            loadingEpisodes = false
        }
    }

    @MainActor
    private func reloadEpisodes() async {
        loadingEpisodes = true
        let list = await CinemanaAPI.shared.episodes(video.id)
        if !Task.isCancelled {
            episodes = list
            selectedSeason = list.first?.season ?? 1
        }
        loadingEpisodes = false
    }
}

private enum DetailLoadResult: Sendable {
    case detail(Video)
    case episodes([Video])
    case related([Video])
}

struct SearchCatalogView: View {
    @State private var query = ""
    @State private var results: [Video] = []
    @State private var options = SearchOptions()
    @State private var loading = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

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
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onSubmit { searchFocused = false }
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
                        Menu {
                            ForEach([0.0, 6.0, 7.0, 8.0, 9.0], id: \.self) { value in
                                Button(value == 0 ? "Any rating" : "★ \(Int(value))+") {
                                    options.minRating = value
                                }
                            }
                        } label: {
                            FilterLabel(text: options.minRating == 0 ? "Rating" : "★ \(Int(options.minRating))+",
                                        active: options.minRating > 0)
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
                if loading { ProgressView("Searching…").tint(mint).padding(.horizontal, 16) }
                if let error { ErrorMessage(text: error) { Task { await search(query) } } }
                if !results.isEmpty {
                    Text("\(filtered.count) of \(results.count) matches")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                ScrollView {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                        EmptyStateView(symbol: "magnifyingglass", title: "Find something to watch",
                                       message: "Search by movie or series title.")
                    } else if !loading && error == nil && filtered.isEmpty {
                        EmptyStateView(symbol: "line.3.horizontal.decrease.circle", title: "No matching titles",
                                       message: results.isEmpty ? "Try another title." : "Try clearing your filters.")
                        if !results.isEmpty {
                            Button("Reset filters") { options = SearchOptions() }
                                .buttonStyle(.bordered).tint(mint)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], alignment: .leading, spacing: 20) {
                            ForEach(filtered) { item in
                                NavigationLink(value: item) { PosterCard(video: item) }.buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(ink)
            .navigationTitle("Search")
            .navigationDestination(for: Video.self) { MovieDetailView(video: $0) }
            .task(id: query) {
                let submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard submitted.count >= 2 else {
                    results = []; error = nil; loading = false; return
                }
                loading = true
                error = nil
                // Cancel stale searches when a new character arrives.
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await search(submitted)
            }
        }
    }

    @MainActor
    private func search(_ submitted: String) async {
        loading = true
        do {
            let found = try await CinemanaAPI.shared.search(submitted)
            guard !Task.isCancelled, submitted == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = found
            error = nil
            loading = false
        } catch {
            guard !Task.isCancelled, submitted == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = []
            self.error = error.localizedDescription
            loading = false
        }
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

struct DownloadAction: View {
    let video: Video
    @ObservedObject private var center = DownloadCenter.shared

    var body: some View {
        HStack(spacing: 10) {
            let entry = center.entry(for: video.id)
            if entry?.status == .ready && center.localURL(for: video.id) != nil {
                Label("Available offline", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if entry?.isActive == true {
                ProgressView(value: entry?.progress ?? 0).tint(.green)
                Text("Downloading \(Int((entry?.progress ?? 0) * 100))%").font(.caption)
                Button("Cancel") { center.cancel(video.id) }.buttonStyle(.bordered)
            } else {
                Button {
                    Task { await center.begin(video) }
                } label: {
                    Label(entry?.status == .failed ? "Retry download" : "Download", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

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

/// The native AVPlayer controls keep seeking, volume, AirPlay, and embedded subtitle
/// selection consistent with iOS. Stream recovery is managed separately from SwiftUI.
struct VideoPlaybackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var session = PlaybackSession()
    let video: Video

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let player = session.player {
                    NativePlayerView(player: player)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                } else if session.loading {
                    ProgressView("Finding a compatible stream…")
                        .tint(mint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ErrorMessage(text: session.error ?? "No compatible stream available") {
                        Task { await session.load(video: video, library: library) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if session.player != nil {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(video.title).font(.title2.weight(.bold)).lineLimit(2)
                        if let selected = session.selected {
                            Label("\(selected.label) quality", systemImage: "checkmark.circle.fill")
                                .font(.subheadline).foregroundStyle(mint)
                        }
                        if let notice = session.notice {
                            Label(notice, systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption).foregroundStyle(.yellow)
                        }
                        HStack(spacing: 22) {
                            if let player = session.player {
                                Button {
                                    let seconds = max(0, player.currentTime().seconds - 10)
                                    player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                                } label: { Label("Back 10s", systemImage: "gobackward.10") }
                                Button {
                                    if player.rate == 0 { player.play() } else { player.pause() }
                                } label: { Label("Play/Pause", systemImage: "playpause.fill") }
                                Button {
                                    let current = player.currentTime().seconds
                                    let duration = player.currentItem?.duration.seconds ?? 0
                                    let target = duration.isFinite && duration > 0 ? min(duration, current + 30) : current + 30
                                    player.seek(to: CMTime(seconds: max(0, target), preferredTimescale: 600))
                                } label: { Label("Forward 30s", systemImage: "goforward.30") }
                                Menu {
                                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                        Button("\(rate.formatted())×") { player.defaultRate = Float(rate); player.rate = Float(rate) }
                                    }
                                } label: { Label("Speed", systemImage: "speedometer") }
                            }
                        }.font(.caption).buttonStyle(.borderless)
                        Text("Tap the video for seeking, AirPlay, and available audio or subtitles.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                Spacer(minLength: 0)
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { session.close(library: library); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(session.streams) { stream in
                            Button { session.select(stream, video: video, library: library) } label: {
                                if session.selected?.id == stream.id {
                                    Label(stream.label, systemImage: "checkmark")
                                } else { Text(stream.label) }
                            }
                        }
                    } label: {
                        Label(session.selected?.label ?? "Quality", systemImage: "gearshape")
                    }
                    .disabled(session.streams.isEmpty)
                }
            }
        }
        .task(id: video.id) { await session.load(video: video, library: library) }
        .onDisappear { session.close(library: library) }
        .onChange(of: scenePhase) { phase in
            if phase != .active { session.save(library: library) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { note in
            if let item = note.object as? AVPlayerItem {
                session.failed(item: item, library: library,
                               reason: (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription)
            }
        }
    }
}

@MainActor
final class PlaybackSession: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var streams: [Stream] = []
    @Published private(set) var selected: Stream?
    @Published private(set) var loading = true
    @Published private(set) var error: String?
    @Published private(set) var notice: String?

    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var attempted = Set<String>()
    private var video: Video?

    func load(video: Video, library: LibraryStore) async {
        close(library: library)
        self.video = video
        self.loading = true
        self.error = nil
        self.notice = nil
        if let local = DownloadCenter.shared.localURL(for: video.id) {
            let stream = Stream(url: local, quality: 0)
            self.streams = [stream]
            start(stream, video: video, library: library)
            self.notice = "Playing downloaded copy"
            return
        }
        do {
            let found = try await CinemanaAPI.shared.streams(video.id)
            guard !Task.isCancelled, self.video?.id == video.id else { return }
            self.streams = found
            guard let preferred = PlaybackPlanner.preferred(from: found) else {
                throw CinemanaAPI.APIError.noStream
            }
            select(preferred, video: video, library: library)
        } catch {
            if !Task.isCancelled {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }

    func select(_ stream: Stream, video: Video, library: LibraryStore) {
        attempted = [stream.id]
        notice = nil
        start(stream, video: video, library: library)
    }

    private func start(_ stream: Stream, video: Video, library: LibraryStore) {
        let current = player?.currentTime().seconds ?? 0
        let resume = current.isFinite && current > 10
            ? current : (library.playback(for: video.id)?.seconds ?? 0)
        save(library: library)
        detachPlayer()
        self.video = video
        self.selected = stream
        self.loading = false
        self.error = nil

        let item = AVPlayerItem(url: stream.url)
        let next = AVPlayer(playerItem: item)
        player = next
        let resumePoint = resume
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item, weak next] in
                guard let self, let item, let next, self.player === next else { return }
                switch item.status {
                case .readyToPlay:
                    if resumePoint.isFinite && resumePoint > 10 {
                        let seekTo = CMTime(seconds: resumePoint, preferredTimescale: 600)
                        next.seek(to: seekTo) { [weak next] completed in
                            if completed { next?.play() }
                        }
                    } else { next.play() }
                case .failed:
                    self.failed(item: item, library: library,
                                reason: item.error?.localizedDescription)
                default: break
                }
            }
        }
        timeObserver = next.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main
        ) { [weak self, weak next] _ in
            Task { @MainActor [weak self, weak next] in
                guard let self, let next, self.player === next else { return }
                self.save(library: library)
            }
        }
    }

    func failed(item: AVPlayerItem, library: LibraryStore, reason: String?) {
        guard player?.currentItem === item, let failedStream = selected, let video else { return }
        if let fallback = PlaybackPlanner.fallback(from: streams, failed: failedStream, tried: attempted) {
            attempted.insert(fallback.id)
            notice = "\(failedStream.label) unavailable. Trying \(fallback.label)…"
            start(fallback, video: video, library: library)
        } else {
            save(library: library)
            detachPlayer()
            selected = nil
            error = "Playback failed on the available sources. \(reason ?? "Check your connection or try again.")"
            notice = nil
        }
    }

    func save(library: LibraryStore) {
        guard let video, let player else { return }
        library.record(video, position: player.currentTime().seconds,
                       duration: player.currentItem?.duration.seconds ?? .nan)
    }

    func close(library: LibraryStore) {
        save(library: library)
        detachPlayer()
        streams = []
        selected = nil
        video = nil
        attempted.removeAll()
        notice = nil
    }

    private func detachPlayer() {
        // Dispose observations before replacing the item so stale errors cannot
        // trigger additional quality changes after the player has been dismissed.
        itemObservation = nil
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
                    NavigationLink { DownloadsView() } label: {
                        Label("Downloads", systemImage: "arrow.down.to.line.compact")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                    }
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
    @EnvironmentObject private var library: LibraryStore
    @State private var confirmHistory = false
    @State private var confirmWatchlist = false
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section("Cinemana iOS") {
                LabeledContent("Version", value: "1.3.0")
                LabeledContent("Player", value: "AVPlayer · Cinema controls")
                LabeledContent("Offline videos", value: "\(DownloadCenter.shared.items.filter { $0.status == .ready }.count)")
                LabeledContent("Saved titles", value: "\(library.snapshot.favorites.count)")
                LabeledContent("Continue Watching", value: "\(library.snapshot.recent.count)")
            }
            Section("Local storage") {
                Button("Clear cached catalog") {
                    Task {
                        await CatalogCache.shared.clear()
                        cacheCleared = true
                    }
                }
                if cacheCleared {
                    Text("Catalog cache cleared. It will refresh the next time you open a catalog.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Clear Continue Watching", role: .destructive) { confirmHistory = true }
                Button("Clear My List", role: .destructive) { confirmWatchlist = true }
                Text("Your list and playback progress stay on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Connection and playback") {
                Text("The content provider may restrict access by ISP or require authorization. Cinemana iOS does not bypass restrictions.")
                Text("Playback supports compatible HLS and progressive files. MPEG-DASH, MKV, and external subtitles are not supported by this native player build.")
            }
            Section("Distribution") {
                Text("Installing on an iPhone requires valid Apple signing. Public distribution requires appropriate content rights.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Remove all Continue Watching progress?", isPresented: $confirmHistory) {
            Button("Clear playback progress", role: .destructive) { library.clearHistory() }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Remove every title from My List?", isPresented: $confirmWatchlist) {
            Button("Clear My List", role: .destructive) { library.clearWatchlist() }
            Button("Cancel", role: .cancel) { }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(mint)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 65)
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
