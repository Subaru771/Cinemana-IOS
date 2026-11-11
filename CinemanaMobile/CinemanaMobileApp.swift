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
    @State private var showBrandSplash = true
    @StateObject private var releaseMonitor = CinemanaReleaseMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showTelegramPrompt = false
    @State private var showUpdatePrompt = false
    @AppStorage("cinemana-hub-promo-hidden") private var telegramHidden = false
    @AppStorage("cinemana-update-announced-revision") private var announcedRevision = ""
    @AppStorage("cinemana-app-language") private var appLanguage = "system"

    init() {
        UserDefaults.standard.register(defaults: [
            "cinemana-community-markers": true,
            "cinemana-auto-skip": true,
            "cinemana-next-episode-preload": true,
            "cinemana-background-downloads": true,
            "cinemana-playback-quality-cap": 0,
            "cinemana-subtitle-language": "auto"
        ])
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
            .environmentObject(releaseMonitor)
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
                try? await Task.sleep(for: .milliseconds(560))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) { showBrandSplash = false }
                if !telegramHidden {
                    showTelegramPrompt = true
                }
                await releaseMonitor.refresh()
                announceUpdateIfNeeded()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background { DownloadCenter.shared.setForeground(false) }
                if phase == .active {
                    DownloadCenter.shared.setForeground(true)
                    Task {
                        await releaseMonitor.refresh()
                        announceUpdateIfNeeded()
                    }
                }
            }
            .onChange(of: releaseMonitor.latestRevision) { _ in announceUpdateIfNeeded() }
            .onChange(of: showTelegramPrompt) { showing in
                if !showing { announceUpdateIfNeeded() }
            }
            .overlay {
                if showTelegramPrompt && !showBrandSplash {
                    CinemaHubWelcomeView {
                        showTelegramPrompt = false
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .alert("New update available", isPresented: $showUpdatePrompt) {
                Button("Download IPA") {
                    if let url = releaseMonitor.downloadURL { UIApplication.shared.open(url) }
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text("Download the new IPA and sign it with SideStore.")
            }
            .tint(mint)
            .preferredColorScheme(.dark)
        }
    }

    private func announceUpdateIfNeeded() {
        guard !showBrandSplash, !showTelegramPrompt, !showUpdatePrompt,
              let revision = releaseMonitor.latestRevision,
              releaseMonitor.downloadURL != nil,
              announcedRevision != revision else { return }
        announcedRevision = revision
        showUpdatePrompt = true
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
    @AppStorage("cinemana-home-featured") private var showFeatured = true
    @AppStorage("cinemana-home-for-you") private var showForYou = true
    @AppStorage("cinemana-home-trending") private var showTrending = true
    @AppStorage("cinemana-home-new") private var showNew = true
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false

    private var visibleRows: [CatalogRow] {
        MatureContentFilter.visibleRows(rows, hideMature: hideMatureContent)
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
                                       message: "Refresh the catalog or check your connection.")
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
                        if kind == nil && !showTrending && name.contains("trending") { return false }
                        if kind == nil && !showNew && name.contains("new") { return false }
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
                        row.title.localizedCaseInsensitiveContains("Series") && row.videos.contains(where: { $0.id == selected.id })
                    }))
            }
            .refreshable { await refresh() }
            .task(id: kind) {
                if rows.isEmpty, let cached = await CatalogCache.shared.read(kind: kind) {
                    rows = cached
                    isLoading = false
                    if kind == nil { startup.finishInitialCatalogLoad() }
                }
                // Cached rows appear immediately; avoid automatic API bursts
                // competing with playback and poster decoding on every launch.
                // Pull-to-refresh still fetches the newest catalog on demand.
                if rows.isEmpty { await refresh() }
            }
        }
    }

    @MainActor
    private func refresh() async {
        isLoading = rows.isEmpty
        defer {
            isLoading = false
            if kind == nil { startup.finishInitialCatalogLoad() }
        }
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
            Text(video.localizedTitle)
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
                Text(video.localizedTitle).font(.title.weight(.bold)).lineLimit(2)
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

    @State private var episodeError: String?
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    var seriesContext = false

    private var isSeries: Bool { seriesContext || (video.isSeries && video.episode == 0) }
    private var visibleRelated: [Video] { MatureContentFilter.visible(related, hideMature: hideMatureContent) }
    private var sortedSeasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }
    private var visibleEpisodes: [Video] {
        episodes.filter { $0.season == selectedSeason && MatureContentFilter.allows($0, hideMature: hideMatureContent) }
    }
    private var playTarget: Video? {
        if isSeries && !episodes.isEmpty {
            if let resumed = library.snapshot.recent.first(where: { record in
                episodes.contains(where: { $0.id == record.id }) && record.fraction < 0.95
            }) { return episodes.first { $0.id == resumed.id } }
            return ViewingPlanner.nextUnwatched(episodes: episodes,
                      watched: Set(library.extras.watched.keys)) ?? episodes.first
        }
        if isSeries { return nil } // A series root must never play as if it were an episode.
        return PlaybackPlanner.playTarget(for: video, episodes: episodes, recent: library.snapshot.recent)
    }

    var body: some View {
        Group {
            if !MatureContentFilter.allows(detail ?? video, hideMature: hideMatureContent) {
                ContentFilteredView()
            } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemotePoster(url: (detail ?? video).backdrop ?? video.poster)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 14) {
                    Text((detail ?? video).localizedTitle)
                        .font(.largeTitle.weight(.bold))
                    Text([detail?.year ?? video.year, (detail?.rating ?? video.rating).map { String(format: "★ %.1f", $0) } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: "  •  "))
                        .foregroundStyle(mint)
                    HStack(spacing: 12) {
                        Button {
                            if let target = playTarget { watch = target }
                        } label: {
                            Label(LocalizedStringKey(isSeries ? (playTarget.flatMap { library.playback(for: $0.id) } == nil ? "Play Episode" : "Resume Episode")
                                   : (library.playback(for: video.id) == nil ? "Play" : "Resume")),
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
                        .accessibilityLabel(LocalizedStringKey(library.isSaved(video) ? "Remove from My List" : "Add to My List"))
                    }
                    if let target = playTarget { DownloadAction(video: target) }
                    HStack(spacing: 12) {
                        Button {
                            library.markWatched(video, watched: !library.isWatched(video.id))
                        } label: {
                            Label(LocalizedStringKey(library.isWatched(video.id) ? "Watched" : "Mark watched"),
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
                            Text((detail ?? video).localizedOverview)
                                .lineLimit(synopsisExpanded ? nil : 4)
                                .foregroundStyle(.secondary)
                            Button(CinemanaLocale.text(synopsisExpanded ? "Show less" : "Read more")) {
                                withAnimation(.easeInOut(duration: 0.15)) { synopsisExpanded.toggle() }
                            }
                            .font(.footnote.weight(.semibold)).tint(mint)
                        }
                    }
                    if !(detail ?? video).genres.isEmpty {
                        Text((detail ?? video).genres.map(CinemanaLocale.genre).joined(separator: "  •  "))
                            .font(.footnote).foregroundStyle(mint)
                    }
                    if isSeries {
                        HStack {
                            Text("Episodes").font(.title2.weight(.bold))
                            Spacer()
                            if !visibleEpisodes.isEmpty {

                                DownloadQualityMenu(videos: visibleEpisodes, compact: true,
                                                    title: CinemanaLocale.isArabic ? "تنزيل الموسم \(selectedSeason)" : "Download entire season \(selectedSeason)")
                                    .foregroundStyle(mint)
                            }
                            if sortedSeasons.count > 1 {
                                Menu {
                                    ForEach(sortedSeasons, id: \.self) { season in
                                        Button(CinemanaLocale.season(season)) { selectedSeason = season }
                                    }
                                } label: {
                                    Label(CinemanaLocale.season(selectedSeason), systemImage: "chevron.down")
                                        .font(.subheadline).foregroundStyle(mint)
                                }
                            }
                        }.padding(.top, 10)
                        if loadingEpisodes {
                            ProgressView("Loading episodes…").tint(mint)
                        } else if episodes.isEmpty {
                            Label("Episodes aren't available yet", systemImage: "exclamationmark.triangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(CinemanaLocale.error(episodeError ?? "The provider returned no episodes for this series."))
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { Task { await reloadEpisodes() } } label: {
                                Label("Retry loading episodes", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                        ForEach(visibleEpisodes) { ep in
                            VStack(alignment: .leading, spacing: 2) {
                            Button { watch = ep } label: {
                                HStack(spacing: 12) {
                                    RemotePoster(url: ep.poster ?? (detail ?? video).poster)
                                        .frame(width: 96, height: 65).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(CinemanaLocale.episode(ep.season, ep.episode))
                                            .font(.caption).foregroundStyle(mint)
                                        Text(ep.localizedTitle).font(.subheadline).lineLimit(2)
                                        if library.isWatched(ep.id) {
                                            Label("Watched", systemImage: "checkmark.circle.fill")
                                                .font(.caption2).foregroundStyle(.green)
                                        } else if let record = library.playback(for: ep.id) {
                                            ProgressView(value: record.fraction).tint(mint)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill").foregroundStyle(mint)
                                }.padding(.vertical, 5)
                            }.buttonStyle(.plain)
                            HStack {
                                DownloadAction(video: ep)
                                Spacer()
                                Button {
                                    library.markWatched(ep, watched: !library.isWatched(ep.id))
                                } label: {
                                    Label(LocalizedStringKey(library.isWatched(ep.id) ? "Unmark watched" : "Mark watched"),
                                          systemImage: library.isWatched(ep.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)
                            }
                            }
                        }
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
            // Load metadata and episode list concurrently. Neither an unrelated
            // recommendation request nor a slow provider response blocks Play.
            await withTaskGroup(of: DetailLoadResult.self) { group in
                group.addTask { .detail(await CinemanaAPI.shared.detail(video)) }
                group.addTask { .related(await CinemanaAPI.shared.related(video.id)) }
                if isSeries {
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
                            episodes = episodes.map { $0.inheritingIMDb(value.imdbID ?? video.imdbID) }
                        }
                    case .episodes(.ready(let list)):
                        episodes = list.map { $0.inheritingIMDb((detail ?? video).imdbID) }
                        episodeError = nil
                        selectedSeason = list.first?.season ?? 1
                        loadingEpisodes = false
                    case .episodes(.failed(let message)):
                        episodeError = message
                        loadingEpisodes = false
                    case .related(let list):
                        related = list
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
                episodes = list.map { $0.inheritingIMDb((detail ?? video).imdbID) }
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
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
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
        Array(Set(MatureContentFilter.visible(results, hideMature: hideMatureContent).flatMap(\.genres))).sorted()
    }
    private var filtered: [Video] {
        options.apply(results).filter { video in
            (minimumYear == 0 || (Int(video.year) ?? 0) >= minimumYear) &&
            (!onlyUnwatched || !library.isWatched(video.id)) &&
            (!savedOnly || library.isSaved(video)) && MatureContentFilter.allows(video, hideMature: hideMatureContent)
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
                                ForEach(SearchType.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                            }
                        } label: { FilterLabel(text: options.type.rawValue, active: options.type != .all) }
                        Button { options.recent.toggle() } label: { FilterLabel(text: "2025+", active: options.recent) }
                        Menu {
                            ForEach([0.0, 6.0, 7.0, 8.0, 9.0], id: \.self) { value in
                                Button(value == 0 ? CinemanaLocale.text("Any rating") : "★ \(Int(value))+") {
                                    options.minRating = value
                                }
                            }
                        } label: {
                            FilterLabel(text: options.minRating == 0 ? "Rating" : "★ \(Int(options.minRating))+",
                                        active: options.minRating > 0)
                        }
                        Menu {
                            Picker("Sort", selection: $options.sort) {
                                ForEach(SearchOrder.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                            }
                        } label: { FilterLabel(text: options.sort.rawValue, active: options.sort != .relevance) }
                        if !genres.isEmpty {
                            Menu {
                                Button("Any genre") { options.genre = "" }
                                ForEach(genres, id: \.self) { genre in
                                    Button(CinemanaLocale.genre(genre)) { options.genre = genre }
                                }
                            } label: { FilterLabel(text: options.genre.isEmpty ? "Genre" : CinemanaLocale.genre(options.genre), active: !options.genre.isEmpty) }
                        }
                        Menu {
                            ForEach([0, 2010, 2020, 2024, 2025, 2026], id: \.self) { year in
                                Button(year == 0 ? CinemanaLocale.text("Any year") : (CinemanaLocale.isArabic ? "من \(year)" : "From \(year)")) { minimumYear = year }
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
                ScrollView {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                        EmptyStateView(symbol: "magnifyingglass", title: "Search titles", message: "")
                    } else if !loading && error == nil && filtered.isEmpty {
                        EmptyStateView(symbol: "line.3.horizontal.decrease.circle", title: "No results",
                                       message: results.isEmpty ? "Try another title." : "Clear filters to see more.")
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
        Text(LocalizedStringKey(text))
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
                Text(CinemanaLocale.error(message)).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func activeRow(_ entry: OfflineEntry) -> some View {
        if entry.status == .queued || entry.status == .preparing {
            ProgressView().controlSize(.small)
            Text(CinemanaLocale.isArabic
                 ? (entry.status == .preparing ? "جارٍ التحضير…" : "بانتظار الدور")
                 : (entry.status == .preparing ? "Preparing…" : (entry.message ?? "Waiting in queue")))
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
        if entry.status == .paused { return "\(CinemanaLocale.text("Paused")) · \(percent)" }
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

    func load(video: Video, library: LibraryStore, prefetched: [Stream]? = nil) async {
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
            let found: [Stream]
            if let prefetched, !prefetched.isEmpty {
                found = prefetched
            } else {
                found = try await CinemanaAPI.shared.streams(video.id)
            }
            guard !Task.isCancelled, self.video?.id == video.id else { return }
            self.streams = found
            let cap = UserDefaults.standard.integer(forKey: "cinemana-playback-quality-cap")
            guard let preferred = PlaybackPlanner.globalPreferred(from: found, cap: cap) else {
                throw NSError(domain: "Cinemana", code: 107,
                              userInfo: [NSLocalizedDescriptionKey:
                                "No playable quality is available within the selected limit. Change it in Settings."])
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
        let cap = UserDefaults.standard.integer(forKey: "cinemana-playback-quality-cap")
        if cap > 0 && stream.quality > cap {
            notice = "This quality exceeds the limit in Settings."
            return
        }
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
        let resolutionCap = UserDefaults.standard.integer(forKey: "cinemana-playback-quality-cap")
        if resolutionCap > 0 {
            item.preferredMaximumResolution = CGSize(width: CGFloat(resolutionCap) * 16 / 9,
                                                      height: CGFloat(resolutionCap))
        }
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

    private func cappedStreams() -> [Stream] {
        let cap = UserDefaults.standard.integer(forKey: "cinemana-playback-quality-cap")
        guard cap > 0 else { return streams }
        return streams.filter { $0.quality == 0 || ($0.quality > 0 && $0.quality <= cap) }
    }

    /// Called only for a ready-to-play item that has been stalled long enough.
    /// Bound recovery attempts; never loop indefinitely or treat a 403 as a retryable stall.
    func recoverFromStall(library: LibraryStore) {
        guard let video, let current = selected, let item = player?.currentItem,
              item.status == .readyToPlay else { return }
        if let fallback = PlaybackPlanner.fallback(from: cappedStreams(), failed: current, tried: attempted) {
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
        if let fallback = PlaybackPlanner.fallback(from: cappedStreams(), failed: failedStream, tried: attempted) {
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
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    private var visibleRecent: [PlaybackRecord] {
        library.snapshot.recent.filter { MatureContentFilter.allows($0.video, hideMature: hideMatureContent) }
    }
    private var visibleFavorites: [Video] {
        MatureContentFilter.visible(library.snapshot.favorites, hideMature: hideMatureContent)
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

                    HStack(spacing: 10) {
                        NavigationLink { CollectionsView() } label: {
                            Label("Collections", systemImage: "folder.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                        }
                        NavigationLink { DownloadsView() } label: {
                            Label("Downloads", systemImage: "arrow.down.to.line.compact")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                        }
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
            .toolbar { NavigationLink { AboutView() } label: { Image(systemName: "gearshape") } }
            .navigationDestination(for: Video.self) { MovieDetailView(video: $0) }
        }
    }

    @ViewBuilder
    private var continueWatching: some View {
        if visibleRecent.isEmpty {
            emptyState(symbol: "play.circle", title: "No recent videos")
        } else {
            ForEach(visibleRecent) { item in
                HStack(spacing: 12) {
                    NavigationLink { MovieDetailView(video: item.video) } label: {
                        HStack(spacing: 12) {
                            RemotePoster(url: item.video.poster)
                                .frame(width: 72, height: 105)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.video.localizedTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                                ProgressBar(fraction: item.fraction).frame(height: 4)
                                Text("\(Int(item.fraction * 100))%")
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
            emptyState(symbol: "bookmark.circle", title: "Your list is empty")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 20) {
                ForEach(visibleFavorites) { item in
                    NavigationLink { MovieDetailView(video: item) } label: { PosterCard(video: item) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func emptyState(symbol: String, title: LocalizedStringKey) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 48)).foregroundStyle(mint)
            Text(title).font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct AboutView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var releaseMonitor: CinemanaReleaseMonitor
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    @AppStorage("cinemana-auto-landscape") private var autoLandscape = true
    @AppStorage("cinemana-app-language") private var appLanguage = "system"
    @AppStorage("cinemana-community-markers") private var communityMarkers = true
    @AppStorage("cinemana-auto-skip") private var autoSkip = true
    @AppStorage("cinemana-next-episode-preload") private var preloadNext = true
    @AppStorage("cinemana-background-downloads") private var backgroundDownloads = true
    @AppStorage("cinemana-playback-quality-cap") private var qualityCap = 0
    @AppStorage("cinemana-subtitle-language") private var subtitleLanguage = "auto"
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
                }.pickerStyle(.menu)
            }
            Section("Home screen") {
                Toggle("Featured title", isOn: $showFeatured)
                Toggle("For You recommendations", isOn: $showForYou)
                Toggle("Trending sections", isOn: $showTrending)
                Toggle("Recently added sections", isOn: $showNew)
            }
            Section("Player") {
                Toggle("Rotate to landscape when playing", isOn: $autoLandscape)
                Toggle("Hide Mature Content", isOn: $hideMatureContent)
                Text("Filters tagged titles; does not skip scenes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(CinemanaLocale.isArabic ? "التشغيل الذكي" : "Smart playback") {
                Toggle(CinemanaLocale.isArabic ? "علامات المقدمة والملخص المجتمعية" : "Community intro/recap markers",
                       isOn: $communityMarkers)
                Toggle(CinemanaLocale.isArabic ? "تخطي المقدمة والملخص تلقائياً" : "Automatically skip intro and recap",
                       isOn: $autoSkip)
                    .disabled(!communityMarkers)
                Toggle(CinemanaLocale.isArabic ? "تحميل الحلقة التالية مسبقاً" : "Preload next episode",
                       isOn: $preloadNext)
                Picker(CinemanaLocale.isArabic ? "الحد الأقصى لجودة التشغيل" : "Playback quality limit",
                       selection: $qualityCap) {
                    Text("Auto").tag(0)
                    Text(verbatim: "4K").tag(2160)
                    Text(verbatim: "1080p").tag(1080)
                    Text(verbatim: "720p").tag(720)
                    Text(verbatim: "480p").tag(480)
                }
                Picker(CinemanaLocale.isArabic ? "لغة الترجمة المفضلة" : "Preferred subtitle language",
                       selection: $subtitleLanguage) {
                    Text("Auto").tag("auto")
                    Text("العربية").tag("ar")
                    Text("English").tag("en")
                    Text(CinemanaLocale.isArabic ? "إيقاف" : "Off").tag("off")
                }
                Text(CinemanaLocale.isArabic
                    ? "التخطي يعتمد على توقيتات متوافقة؛ لا يتم التخطي عند غيابها."
                    : "Skip markers must match the stream. Missing timestamps never trigger guessing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Offline downloads") {
                Toggle(CinemanaLocale.isArabic ? "متابعة التنزيل في الخلفية" : "Continue downloads in background",
                       isOn: $backgroundDownloads)
                Text(CinemanaLocale.isArabic
                    ? "يتحكم iOS بمواعيد التنزيل وقد يؤخرها."
                    : "iOS controls background scheduling and may pause transfers.")
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink { DownloadsView() } label: {
                    Label("Manage downloads", systemImage: "arrow.down.to.line.compact")
                }
            }
            Section("Local storage") {
                Button("Clear cached catalog") {
                    Task {
                        await CatalogCache.shared.clear()
                        cacheCleared = true
                    }
                }
                if cacheCleared {
                    Label("Cache cleared", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Clear Continue Watching", role: .destructive) { confirmHistory = true }
                Button("Clear My List", role: .destructive) { confirmWatchlist = true }
            }
            Section("Privacy and data") {
                Toggle("Remember viewing history", isOn: Binding(
                    get: { library.extras.saveHistory },
                    set: { library.setSaveHistory($0) }))
                Button("Export data") {
                    if let data = library.exportData() {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("cinemana-personal-export.json")
                        do { try data.write(to: url, options: .atomic); exportURL = url }
                        catch { exportURL = nil }
                    }
                }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share export", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Erase viewing data", role: .destructive) { eraseAll = true }
            }
            Section("Connection and playback") {
                NavigationLink { ConnectionDiagnosticsView() } label: {
                    Label("Network diagnostics", systemImage: "network")
                }
            }
            Section("Cinemana iOS") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                Button("Check for updates") {
                    Task { await releaseMonitor.refresh() }
                }
                if releaseMonitor.checking {
                    ProgressView("Checking for updates…")
                } else if releaseMonitor.checked {
                    Text(LocalizedStringKey(releaseMonitor.error ? "Couldn't check for updates" :
                         (releaseMonitor.latestRevision == nil ? "Up to date" : "Update available")))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let url = releaseMonitor.downloadURL {
                    Link(destination: url) {
                        Label("Download latest IPA", systemImage: "arrow.down.circle")
                    }
                }
                Link(destination: CinemanaReleaseMonitor.telegramURL) {
                    Label("Cinemana Hub on Telegram", systemImage: "paperplane.fill")
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
            if !message.isEmpty {
                Text(LocalizedStringKey(message)).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
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
            Text(CinemanaLocale.error(text)).foregroundStyle(.red)
            Button("Retry", action: retry).buttonStyle(.bordered)
        }
        .padding(16)
    }
}
