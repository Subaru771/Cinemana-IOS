import SwiftUI

/// An ordinary episode browser: choose a season, tap an episode to play.
/// No multi-select or checkbox state anywhere in the viewing flow.
struct SeriesEpisodeBrowser: View {
    let episodes: [Video]
    @Binding var season: Int
    let loading: Bool
    let error: String?
    let parentPoster: URL?
    let onPlay: (Video) -> Void
    let onRetry: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @AppStorage(MatureContentFilter.preferenceKey) private var hideMatureContent = false
    @AppStorage(MatureContentFilter.strictPreferenceKey) private var strictFilter = true

    private var shown: [Video] {
        episodes
    }
    private var seasons: [Int] { Array(Set(shown.map(\.season))).sorted() }
    private var currentSeason: [Video] {
        shown.filter { $0.season == season }.sorted { ($0.episode, $0.id) < ($1.episode, $1.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Episodes").font(.title2.bold())
                Spacer(minLength: 8)
                if seasons.count > 1 {
                    Menu {
                        ForEach(seasons, id: \.self) { item in
                            Button("Season \(item)") { season = item }
                        }
                    } label: {
                        Label("Season \(season)", systemImage: "chevron.down.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .accessibilityLabel("Choose season")
                } else if let only = seasons.first {
                    Text("Season \(only)").font(.subheadline).foregroundStyle(.secondary)
                }
                if !currentSeason.isEmpty {
                    DownloadQualityMenu(videos: currentSeason, compact: true,
                                        title: "Download season \(season)")
                        .accessibilityLabel("Download entire season")
                }
            }
            if loading {
                HStack { ProgressView(); Text("Loading episodes…") }
                    .foregroundStyle(.secondary)
            } else if episodes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Episodes couldn't be loaded", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error ?? "The provider did not return a playable episode list.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(action: onRetry) {
                        Label("Retry loading episodes", systemImage: "arrow.clockwise")
                    }.buttonStyle(.bordered)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            } else if currentSeason.isEmpty {
                Text("No episodes were returned for this season.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                    ForEach(currentSeason) { ep in
                        episodeCard(ep)
                    }
                }
            }
        }.padding(.top, 10)
        .onChange(of: shown.map(\.season)) { _ in
            if let first = seasons.first, !seasons.contains(season) { season = first }
        }
    }

    private func episodeCard(_ episode: Video) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button { onPlay(episode) } label: {
                HStack(spacing: 12) {
                    RemotePoster(url: episode.poster ?? parentPoster)
                        .frame(width: 92, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Episode \(episode.episode)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.red)
                        Text(episode.title).font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary).lineLimit(2)
                        if library.isWatched(episode.id) {
                            Text("Watched").font(.caption2).foregroundStyle(.green)
                        } else if let progress = library.playback(for: episode.id) {
                            ProgressView(value: progress.fraction).tint(.red)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.red)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            DownloadAction(video: episode)
                .frame(width: 44)
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(library.isWatched(episode.id) ? "Mark unwatched" : "Mark watched") {
                library.markWatched(episode, watched: !library.isWatched(episode.id))
            }
        }
    }
}
