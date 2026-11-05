import SwiftUI
import AVKit
import UIKit

private let mint = Color(red: 1.00, green: 0.18, blue: 0.25)
private let ink = Color(red: 0.052, green: 0.013, blue: 0.018)
private let tile = Color(red: 0.13, green: 0.06, blue: 0.075)

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
    @StateObject private var startup = CinemanaStartupState()
    @StateObject private var classifier = MatureClassifier()
    @State private var showBrandSplash = true
    @State private var showHubWelcome = false
    @AppStorage("cinemana-hub-promo-hidden") private var hideHubWelcome = false
    @AppStorage("cinemana-hub-promo-seen") private var hasSeenHubWelcome = false
    @AppStorage("cinemana-app-language") private var appLanguage = "system"

    init() {
        // The default image cache is tiny, so posters reloaded while scrolling flicker.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 300 * 1024 * 1024)
    }

    private var selectedLocale: Locale {
        Locale(identifier: appLanguage == "system" ? Locale.current.identifier : appLanguage)
    }

    private var isRightToLeft: Bool {
        appLanguage == "ar" || (appLanguage == "system" &&
                               Locale.current.languageCode == "ar")
    }

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
            .environmentObject(startup)
            .environmentObject(classifier)
            .environment(\.locale, selectedLocale)
            .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
            // Rebuild static navigation and tab labels as soon as language changes.
            .id(appLanguage)
            .overlay {
                if showBrandSplash {
                    CinemanaSplashView()
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                guard showBrandSplash else { return }
                // Never block the opening screen on catalog or provider availability.
                // The app loads in parallel under a brief, non-interactive reveal.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.15)) { showBrandSplash = false }
                // Let the short transition complete before presenting Cinema Hub.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                if !hideHubWelcome && !hasSeenHubWelcome {
                    hasSeenHubWelcome = true
                    showHubWelcome = true
                }
            }
            .sheet(isPresented: $showHubWelcome) {
                CinemaHubWelcomeView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
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
    @EnvironmentObject private var startup: CinemanaStartupState
    @EnvironmentObject private var classifier: MatureClassifier
    @AppStorage("cinemana-home-featured") private var showFeatured = true
    @AppStorage("cinemana-home-for-you") private var showForYou = true
    @AppStorage("cinemana-home-trending") private var showTrending = true
    @AppStorage("cinemana-home-new") private var showNew = true
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    @AppStorage(MatureContentFilter.strictPreferenceKey) private var strictMatureContent = true

    private var visibleRows: [CatalogRow] {
        MatureContentFilter.visibleRows(rows, hideMature: hideMatureContent, strict: strictMatureContent)
    }
    private var recommendations: [Video] {
        let all = visibleRows.flatMap(\.videos)
        guard !library.snapshot.favorites.isEmpty || !library.snapshot.recent.isEmpty else { return [] }
        return library.recommendations(from: all)
    }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if isLoading && rows.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            if kind == nil {
                                CinemanaLogo(compact: false)
                                    .padding(.bottom, 8)
                            }
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
                    if visibleRows.isEmpty && !isLoading && error == nil {
                        EmptyStateView(symbol: "film.stack", title: "Nothing to show yet",
                                       message: hideMatureContent && !rows.isEmpty
                                       ? "The content filter is hiding these titles. Review Settings → Content filter."
                                       : "Refresh the catalog or check your connection.")
                    }
                    if (kind != nil || showFeatured), let hero = visibleRows.first?.videos.first {
                        NavigationLink(value: hero) {
                            FeaturedPoster(video: hero)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                    if kind == nil && showForYou && !recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles").foregroundStyle(mint)
                                Text("For You").font(.title3.weight(.bold))
                                Spacer()
                            }.padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(recommendations) { video in
                                        NavigationLink(value: video) { PosterCard(video: video) }
                                            .buttonStyle(.plain)
                                    }
                                }.padding(.horizontal, 16)
                            }
                        }
                    }
                    ForEach(visibleRows.filter { row in
                        let name = row.title.lowercased()
                        if kind == nil && !showTrending && name.hasPrefix("trending") { return false }
                        if kind == nil && !showNew && name.hasPrefix("new ") { return false }
                        return true
                    }) { row in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(LocalizedStringKey(row.title))
                                .font(.title3.weight(.bold))
                                .padding(.horizontal, 16)
                            if isPad {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 20) {
                                    ForEach(row.videos) { video in
                                        NavigationLink(value: video) { PosterCard(video: video, width: 168) }
                                            .buttonStyle(.plain)
                                    }
                                }.padding(.horizontal, 16)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(alignment: .top, spacing: 12) {
                                        ForEach(row.videos) { video in
                                            NavigationLink(value: video) { PosterCard(video: video) }
                                                .buttonStyle(.plain)
                                        }
                                    }.padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .background(ink)
            .navigationTitle(LocalizedStringKey(title))
            .toolbar {
                if kind == nil {
                    ToolbarItem(placement: .principal) {
                        CinemanaLogo(compact: true)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            AboutView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .navigationDestination(for: Video.self) { selected in
                MovieDetailView(video: selected, seriesContext: kind == 2 ||
                    (kind == nil && rows.contains { row in
                        row.title.hasSuffix("Series") && row.videos.contains(where: { $0.id == selected.id })
                    }))
            }
            .refreshable { await refresh() }
            .onChange(of: hideMatureContent) { enabled in
                if enabled { classifier.start(rows.flatMap(\.videos)) }
            }
            .task(id: kind) {
                // Saved rows appear instantly; anything older than a few minutes is
                // refreshed quietly in the background.
                if rows.isEmpty, let cached = await CatalogCache.shared.readEntry(kind: kind) {
                    rows = cached.rows.sorted { $0.sortKey < $1.sortKey }
                    isLoading = false
                    classifier.start(cached.rows.flatMap(\.videos))
                    if kind == nil { startup.finishInitialCatalogLoad() }
                    if Date().timeIntervalSince(cached.savedAt) < 15 * 60 { return }
                }
                await refresh()
            }
        }
    }

    @MainActor
    private func merge(_ row: CatalogRow) {
        var updated = rows
        if let index = updated.firstIndex(where: { $0.title == row.title }) { updated[index] = row }
        else { updated.append(row) }
        rows = updated.sorted { $0.sortKey < $1.sortKey }
    }

    @MainActor
    private func refresh() async {
        isLoading = rows.isEmpty
        defer {
            isLoading = false
            if kind == nil { startup.finishInitialCatalogLoad() }
        }
        var fresh: [String: CatalogRow] = [:]
        do {
            // Rows are shown one by one as they arrive.
            for try await row in CinemanaAPI.shared.catalogStream(kind) {
                guard !Task.isCancelled else { return }
                if hideMatureContent { await classifier.prepare(row.videos) }
                fresh[row.title] = row
                merge(row)
                error = nil
                isLoading = false
            }
            guard !Task.isCancelled, !fresh.isEmpty else { return }
            let ordered = fresh.values.sorted { $0.sortKey < $1.sortKey }
            rows = ordered
            await CatalogCache.shared.save(ordered, kind: kind)
        } catch {
            if !Task.isCancelled && rows.isEmpty { self.error = error.localizedDescription }
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
    let maxPixel: CGFloat
    @State private var image: UIImage?

    init(url: URL?, maxPixel: CGFloat = 480) {
        self.url = url
        self.maxPixel = maxPixel
        // A memory hit shows immediately, so recycled rows never flash a placeholder.
        _image = State(initialValue: url.flatMap { PosterImageCache.shared.image(for: $0) })
    }

    var body: some View {
        ZStack {
            Rectangle().fill(
                LinearGradient(colors: [tile, ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            ).overlay {
                Image(systemName: "film.stack")
                    .font(.system(size: 29, weight: .ultraLight))
                    .foregroundStyle(mint.opacity(0.55))
            }
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    @MainActor
    private func load() async {
        guard let url else { image = nil; return }
        if let hit = PosterImageCache.shared.image(for: url) { image = hit; return }
        guard let loaded = await PosterImageCache.shared.load(url, maxPixel: maxPixel),
              !Task.isCancelled else { return }
        image = loaded
    }
}

struct FeaturedPoster: View {
    let video: Video
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemotePoster(url: video.backdrop ?? video.poster, maxPixel: 1100)
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
    @EnvironmentObject private var classifier: MatureClassifier
    let video: Video
    @State private var detail: Video?
    @State private var episodes: [Video] = []
    @State private var related: [Video] = []
    @State private var watch: Video?
    @State private var selectedSeason = 1
    @State private var synopsisExpanded = false
    @State private var loadingEpisodes = false
    @State private var episodeError: String?
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    @AppStorage(MatureContentFilter.strictPreferenceKey) private var strictMatureContent = true
    var seriesContext = false

    /// A title with no type from the provider is treated as a series once episodes are found.
    private var isSeries: Bool {
        seriesContext || (video.isSeries && video.episode == 0) ||
        (detail.map { $0.isSeries && $0.episode == 0 } ?? false) ||
        (video.kind.isEmpty && !episodes.isEmpty)
    }
    private var visibleRelated: [Video] { MatureContentFilter.visible(related, hideMature: hideMatureContent, strict: strictMatureContent) }
    private var playTarget: Video? {
        if isSeries {
            let permitted = MatureContentFilter.visible(episodes, hideMature: hideMatureContent,
                                                         strict: strictMatureContent)
            guard !permitted.isEmpty else { return nil }
            if let resumed = library.snapshot.recent.first(where: { record in
                permitted.contains(where: { $0.id == record.id }) && record.fraction < 0.95
            }) { return permitted.first { $0.id == resumed.id } }
            return ViewingPlanner.nextUnwatched(episodes: permitted,
                       watched: Set(library.extras.watched.keys)) ?? permitted.first
        }
        return PlaybackPlanner.playTarget(for: video, episodes: episodes, recent: library.snapshot.recent)
    }

    var body: some View {
        Group {
            if !MatureContentFilter.allows(detail ?? video, hideMature: hideMatureContent, strict: strictMatureContent) {
                ContentFilteredView()
            } else {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
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
                    if let target = playTarget { DownloadAction(video: target) }
                    HStack(spacing: 12) {
                        Button {
                            library.markWatched(video, watched: !library.isWatched(video.id))
                        } label: {
                            Label(library.isWatched(video.id) ? "Watched" : "Mark watched",
                                  systemImage: library.isWatched(video.id) ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                        .buttonStyle(.bordered)
                        if !library.extras.collections.isEmpty {
                            Menu {
                                ForEach(library.extras.collections) { collection in
                                    Button {
                                        library.toggle(video, in: collection.id)
                                    } label: {
                                        Label(collection.name, systemImage:
                                              library.inCollection(video.id, collection: collection)
                                              ? "checkmark.circle.fill" : "plus.circle")
                                    }
                                }
                            } label: { Label("Collections", systemImage: "folder") }
                            .buttonStyle(.bordered)
                        }
                    }
                    .font(.footnote)
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
                        SeriesEpisodeBrowser(
                            episodes: episodes,
                            season: $selectedSeason,
                            loading: loadingEpisodes,
                            error: episodeError,
                            parentPoster: (detail ?? video).poster,
                            onPlay: { watch = $0 },
                            onRetry: { Task { await reloadEpisodes() } }
                        )
                    }
                    if !visibleRelated.isEmpty {
                        Text("More like this").font(.title2.weight(.bold)).padding(.top, 10)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(visibleRelated) { item in
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
        .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 1000 : .infinity)
        .frame(maxWidth: .infinity)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Video.self) { MovieDetailView(video: $0) }
        .fullScreenCover(item: $watch) { CinemaPlayerScreen(video: $0, playlist: episodes) }
        .task(id: video.id) {
            // Restore the reliable details-first flow. Never launch playback from
            // a poster tap: Play/Resume and episode row buttons own that action.
            detail = video
            synopsisExpanded = false
            related = []
            episodes = []
            episodeError = nil
            loadingEpisodes = isSeries
            selectedSeason = 1
            let probeEpisodes = isSeries || video.kind.isEmpty
            // Load metadata and episode list concurrently. Neither an unrelated
            // recommendation request nor a slow provider response blocks Play.
            await withTaskGroup(of: DetailLoadResult.self) { group in
                group.addTask { .detail(await CinemanaAPI.shared.detail(video)) }
                group.addTask { .related(await CinemanaAPI.shared.related(video.id)) }
                if probeEpisodes {
                    group.addTask {
                        do { return .episodes(.ready(try await CinemanaAPI.shared.episodesDetailed(video.id))) }
                        catch { return .episodes(.failed(error.localizedDescription)) }
                    }
                }
                for await result in group {
                    guard !Task.isCancelled else { group.cancelAll(); break }
                    switch result {
                    case .detail(let value):
                        // Never let unrelated/partial provider metadata change
                        // the selected movie into a series or disable its Play.
                        if value.id == video.id &&
                           (value.kind.isEmpty || value.kind == video.kind) {
                            detail = value
                            if MatureContentFilter.metadataSaysMature(value) || MatureContentFilter.hasVerifiedSafeRating(value) {
                                MatureVerdictStore.shared.record(value.id, mature: MatureContentFilter.metadataSaysMature(value))
                            }
                        }
                    case .episodes(.ready(let list)):
                        episodes = list
                        episodeError = nil
                        selectedSeason = list.first?.season ?? 1
                        loadingEpisodes = false
                    case .episodes(.failed(let message)):
                        episodeError = message
                        loadingEpisodes = false
                    case .related(let list):
                        related = list
                        classifier.start(list)
                    }
                }
            }
            loadingEpisodes = false
        }
            } // visible detail
        } // filter gate
    }

    @MainActor
    private func reloadEpisodes() async {
        guard !loadingEpisodes else { return }
        loadingEpisodes = true
        episodeError = nil
        defer { loadingEpisodes = false }
        do {
            let list = try await CinemanaAPI.shared.episodesDetailed(video.id)
            if !Task.isCancelled {
                episodes = list
                selectedSeason = list.first?.season ?? 1
            }
        } catch {
            if !Task.isCancelled { episodeError = error.localizedDescription }
        }
    }
}

private enum EpisodeLoadOutcome: Sendable {
    case ready([Video])
    case failed(String)
}

private enum DetailLoadResult: Sendable {
    case detail(Video)
    case episodes(EpisodeLoadOutcome)
    case related([Video])
}

struct SearchCatalogView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var classifier: MatureClassifier
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    @AppStorage(MatureContentFilter.strictPreferenceKey) private var strictMatureContent = true
    @State private var onlyUnwatched = false
    @State private var savedOnly = false
    @State private var minimumYear = 0
    @State private var query = ""
    @State private var results: [Video] = []
    @State private var options = SearchOptions()
    @State private var loading = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    private var genres: [String] {
        Array(Set(MatureContentFilter.visible(results, hideMature: hideMatureContent, strict: strictMatureContent).flatMap(\.genres))).sorted()
    }
    private var filtered: [Video] {
        options.apply(results).filter { video in
            (minimumYear == 0 || (Int(video.year) ?? 0) >= minimumYear) &&
            (!onlyUnwatched || !library.isWatched(video.id)) &&
            (!savedOnly || library.isSaved(video)) && MatureContentFilter.allows(video, hideMature: hideMatureContent, strict: strictMatureContent)
        }
    }

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
                        Menu {
                            ForEach([0, 2010, 2020, 2024, 2025, 2026], id: \.self) { year in
                                Button(year == 0 ? "Any year" : "From \(year)") { minimumYear = year }
                            }
                        } label: { FilterLabel(text: minimumYear == 0 ? "Year" : "\(minimumYear)+", active: minimumYear > 0) }
                        Button { onlyUnwatched.toggle() } label: {
                            FilterLabel(text: "Unwatched", active: onlyUnwatched)
                        }
                        Button { savedOnly.toggle() } label: {
                            FilterLabel(text: "My List", active: savedOnly)
                        }
                        Button("Clear") {
                            options = SearchOptions(); onlyUnwatched = false; savedOnly = false; minimumYear = 0
                        }.font(.caption)
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
            if hideMatureContent { await classifier.prepare(found, timeout: 3) }
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

struct DownloadAction: View {
    let video: Video
    @ObservedObject private var center = DownloadCenter.shared

    var body: some View {
        let entry = center.entry(for: video.id)
        HStack(spacing: 10) { content(entry) }
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func content(_ entry: OfflineEntry?) -> some View {
        if let entry, entry.status == .ready, center.localURL(for: video.id) != nil {
            Label("Available offline", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Spacer(minLength: 4)
            Button(role: .destructive) { center.remove(video.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete download")
        } else if let entry, entry.isActive {
            activeRow(entry)
        } else {
            DownloadQualityMenu(video: video,
                                title: entry?.status == .failed ? "Retry with quality" : "Download options")
                .buttonStyle(.bordered)
            if let entry, entry.status == .failed, let message = entry.message {
                Text(message).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func activeRow(_ entry: OfflineEntry) -> some View {
        if entry.status == .queued || entry.status == .preparing {
            ProgressView().controlSize(.small)
            Text(entry.status == .preparing ? "Preparing…" : (entry.message ?? "Waiting in queue"))
                .font(.caption)
        } else {
            ProgressView(value: entry.progress).tint(.green).frame(maxWidth: 140)
            Text(progressText(entry)).font(.caption)
        }
        Spacer(minLength: 4)
        if entry.status == .downloading {
            Button { center.pause(video.id) } label: { Image(systemName: "pause.fill") }
                .buttonStyle(.bordered)
                .accessibilityLabel("Pause download")
        }
        if entry.status == .paused {
            Button { center.resume(video.id) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.bordered)
                .accessibilityLabel("Resume download")
        }
        Button("Cancel") { center.cancel(video.id) }.buttonStyle(.bordered)
    }

    private func progressText(_ entry: OfflineEntry) -> String {
        let percent = "\(Int(entry.progress * 100))%"
        if entry.status == .paused { return "Paused · \(percent)" }
        if let rate = center.rates[video.id], rate > 0 {
            return "\(percent) · \(ByteFormat.string(Int64(rate)))/s"
        }
        return percent
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
    private var stallRestarted = false
    @Published private(set) var recoveryCount = 0
    @Published private(set) var lastRecoveryReason: String?
    private var video: Video?

    func load(video: Video, library: LibraryStore) async {
        close(library: library)
        self.video = video
        self.loading = true
        self.error = nil
        self.notice = nil
        stallRestarted = false
        recoveryCount = 0
        lastRecoveryReason = nil
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
            guard let preferred = PlaybackPlanner.adaptivePreferred(from: found) else {
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
        stallRestarted = false
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
        // Limit needless forward prebuffering on slow links while keeping enough
        // data for stable playback. The player still follows iOS buffering policy.
        item.preferredForwardBufferDuration = 2
        let next = AVPlayer(playerItem: item)
        next.automaticallyWaitsToMinimizeStalling = true
        // Honor iOS AirPlay routing, including external video displays.
        next.allowsExternalPlayback = true
        player = next
        let resumePoint = resume
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item, weak next] in
                guard let self, let item, let next, self.player === next else { return }
                switch item.status {
                case .readyToPlay:
                    if resumePoint.isFinite && resumePoint > 10 {
                        let seekTo = CMTime(seconds: resumePoint, preferredTimescale: 600)
                        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
                        // Start immediately when AVPlayer becomes ready. A failed
                        // resume seek must never leave the player paused forever.
                        next.play()
                        next.seek(to: seekTo, toleranceBefore: tolerance,
                                  toleranceAfter: tolerance) { [weak self, weak next] _ in
                            Task { @MainActor [weak self, weak next] in
                                guard let self, let next, self.player === next else { return }
                                next.play()
                            }
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

    /// Called only for a ready-to-play item that has been stalled long enough.
    /// Bound recovery attempts; never loop indefinitely or treat a 403 as a retryable stall.
    func recoverFromStall(library: LibraryStore) {
        guard let video, let current = selected, let item = player?.currentItem,
              item.status == .readyToPlay else { return }
        if let fallback = PlaybackPlanner.fallback(from: streams, failed: current, tried: attempted) {
            attempted.insert(fallback.id)
            recoveryCount += 1
            lastRecoveryReason = "Slow stream: switched from \(current.label) to \(fallback.label)"
            start(fallback, video: video, library: library)
            notice = "Buffering too long. Trying \(fallback.label)…"
        } else if !stallRestarted {
            stallRestarted = true
            recoveryCount += 1
            lastRecoveryReason = "Reconnected \(current.label) once"
            start(current, video: video, library: library)
            notice = "Reconnecting stalled video…"
        } else {
            failed(item: item, library: library, reason: "Video stalled repeatedly. Check your connection.")
        }
    }

    func failed(item: AVPlayerItem, library: LibraryStore, reason: String?) {
        guard player?.currentItem === item, let failedStream = selected, let video else { return }
        if let fallback = PlaybackPlanner.fallback(from: streams, failed: failedStream, tried: attempted) {
            attempted.insert(fallback.id)
            notice = "\(failedStream.label) unavailable. Trying \(fallback.label)…"
            start(fallback, video: video, library: library)
        } else {
            Task { await CinemanaAPI.shared.invalidateStreams(video.id) }
            save(library: library)
            detachPlayer()
            selected = nil
            error = "Playback failed on the available sources. \(PlaybackPlanner.explainFailure(reason))"
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
        stallRestarted = false
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

struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        Capsule().fill(.white.opacity(0.18))
            .overlay {
                Capsule().fill(mint)
                    .scaleEffect(x: max(0.001, min(1, fraction)), y: 1, anchor: .leading)
            }
            .clipShape(Capsule())
    }
}

private enum LibraryTab: String, CaseIterable, Identifiable {
    case continueWatching = "Continue Watching"
    case favorites = "Favorites"
    var id: String { rawValue }
}

/// One tab for everything the viewer is coming back to: Continue Watching and Favorites.
struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var classifier: MatureClassifier
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    @AppStorage(MatureContentFilter.strictPreferenceKey) private var strictMatureContent = true
    private var visibleRecent: [PlaybackRecord] {
        library.snapshot.recent.filter { MatureContentFilter.allows($0.video, hideMature: hideMatureContent, strict: strictMatureContent) }
    }
    private var visibleFavorites: [Video] {
        MatureContentFilter.visible(library.snapshot.favorites, hideMature: hideMatureContent, strict: strictMatureContent)
    }
    @State private var section: LibraryTab = .continueWatching

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Picker("", selection: $section) {
                        ForEach(LibraryTab.allCases) { tab in
                            Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    NavigationLink { CollectionsView() } label: {
                        Label("Collections", systemImage: "folder.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    NavigationLink { DownloadsView() } label: {                        Label("Downloads", systemImage: "arrow.down.to.line.compact")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    switch section {
                    case .continueWatching: continueWatching
                    case .favorites: favorites
                    }
                }
                .padding(16)
            }
            .background(ink)
            .navigationTitle("My List")
            .task(id: hideMatureContent) {
                if hideMatureContent {
                    classifier.start(library.snapshot.favorites + library.snapshot.recent.map(\.video))
                }
            }
            .toolbar { NavigationLink { AboutView() } label: { Image(systemName: "gearshape") } }
            .navigationDestination(for: Video.self) { MovieDetailView(video: $0) }
        }
    }

    @ViewBuilder
    private var continueWatching: some View {
        if visibleRecent.isEmpty {
            emptyState(symbol: "play.circle", title: "Nothing to continue yet",
                       message: "Titles you start watching will appear here so you can pick up where you left off.")
        } else {
            ForEach(visibleRecent) { item in
                HStack(spacing: 12) {
                    NavigationLink(value: item.video) {
                        HStack(spacing: 12) {
                            RemotePoster(url: item.video.poster)
                                .frame(width: 72, height: 105)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.video.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                ProgressBar(fraction: item.fraction).frame(height: 4)
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
    }

    @ViewBuilder
    private var favorites: some View {
        if visibleFavorites.isEmpty {
            emptyState(symbol: "bookmark.circle", title: "Your list is empty",
                       message: "Save a movie or series to find it here later.")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 20) {
                ForEach(visibleFavorites) { item in
                    NavigationLink(value: item) { PosterCard(video: item) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func emptyState(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 48)).foregroundStyle(mint)
            Text(title).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct AboutView: View {
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    @AppStorage(MatureContentFilter.strictPreferenceKey) private var strictMatureContent = true
    @AppStorage("cinemana-auto-landscape") private var autoLandscape = true
    @AppStorage("cinemana-app-language") private var appLanguage = "system"
    @AppStorage("cinemana-hub-promo-hidden") private var hideHubWelcome = false
    @AppStorage("cinemana-hub-promo-seen") private var hasSeenHubWelcome = false
    @State private var confirmHistory = false
    @State private var confirmWatchlist = false
    @State private var cacheCleared = false
    @State private var eraseAll = false
    @State private var exportURL: URL?
    @AppStorage("cinemana-home-featured") private var showFeatured = true
    @AppStorage("cinemana-home-for-you") private var showForYou = true
    @AppStorage("cinemana-home-trending") private var showTrending = true
    @AppStorage("cinemana-home-new") private var showNew = true

    var body: some View {
        Form {
            Section("Language") {
                Picker("App Language", selection: $appLanguage) {
                    Text("Follow iPhone Language").tag("system")
                    Text("English").tag("en")
                    Text("العربية").tag("ar")
                }
                .pickerStyle(.menu)
            }
            Section("Cinemana iOS") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Offline videos", value: "\(DownloadCenter.shared.items.filter { $0.status == .ready }.count)")
                LabeledContent("Saved titles", value: "\(library.snapshot.favorites.count)")
                LabeledContent("Continue Watching", value: "\(library.snapshot.recent.count)")
            }
            Section("Home screen") {
                Toggle("Featured title", isOn: $showFeatured)
                Toggle("For You recommendations", isOn: $showForYou)
                Toggle("Trending sections", isOn: $showTrending)
                Toggle("Recently added sections", isOn: $showNew)
            }
            Section("Content filter") {
                Toggle("Hide Mature Content", isOn: $hideMatureContent)
                if hideMatureContent {
                    Toggle("Strict: also hide unrated titles", isOn: $strictMatureContent)
                    Text("Strict filtering hides any title without a verified safe age rating. Most unrated titles may disappear. This filters titles, not scenes inside a video.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Privacy and data") {
                Toggle("Remember viewing history", isOn: Binding(
                    get: { library.extras.saveHistory },
                    set: { library.setSaveHistory($0) }))
                Button("Prepare personal data export") {
                    if let data = library.exportData() {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("cinemana-personal-export.json")
                        do { try data.write(to: url, options: .atomic); exportURL = url }
                        catch { exportURL = nil }
                    }
                }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share personal data export", systemImage: "square.and.arrow.up") }
                }
                Button("Erase all personal viewing data", role: .destructive) { eraseAll = true }
            }
            Section("Local storage") {
                Button("Clear cached catalog") {
                    Task {
                        await CatalogCache.shared.clear()
                        MatureVerdictStore.shared.clear()
                        cacheCleared = true
                    }
                }
                if cacheCleared {
                    Label("Cache cleared", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Clear Continue Watching", role: .destructive) { confirmHistory = true }
                Button("Clear My List", role: .destructive) { confirmWatchlist = true }
            }
            Section("Offline downloads") {
                NavigationLink { DownloadsView() } label: {
                    Label("Manage downloads", systemImage: "arrow.down.to.line.compact")
                }
            }
            Section("Player") {
                Toggle("Rotate to landscape when playing", isOn: $autoLandscape)
            }
            Section("Connection") {
                NavigationLink { ConnectionDiagnosticsView() } label: {
                    Label("Network diagnostics", systemImage: "network")
                }
            }
            Section("Cinema Hub") {
                Link(destination: URL(string: "https://t.me/CinemanaHub")!) {
                    Label("Cinema Hub on Telegram", systemImage: "paperplane.fill")
                }
                Button("Show welcome popup next launch") {
                    hideHubWelcome = false
                    hasSeenHubWelcome = false
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Remove all Continue Watching progress?", isPresented: $confirmHistory) {
            Button("Clear playback progress", role: .destructive) { library.clearHistory() }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Erase all viewing history, collections and skip markers?", isPresented: $eraseAll) {
            Button("Erase viewing data", role: .destructive) { library.clearPersonalData() }
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
            Text(LocalizedStringKey(title)).font(.headline)
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
