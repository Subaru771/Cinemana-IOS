import SwiftUI
import UIKit

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
                    HStack(spacing: 12) {
                        Button(action: onRetry) {
                            Label("Retry loading episodes", systemImage: "arrow.clockwise")
                        }.buttonStyle(.bordered)
                        if let error, !error.isEmpty {
                            Button {
                                UIPasteboard.general.string = error
                            } label: {
                                Label("Copy diagnostics", systemImage: "doc.on.doc")
                            }.buttonStyle(.bordered)
                        }
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            } else if currentSeason.isEmpty {
                Text("No episodes were returned for this season.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], spacing: 12) {
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
            EpisodeDownloadControl(video: episode)
                .frame(width: 40, height: 40)
        }
        .padding(10)
        .frame(minHeight: 86)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(library.isWatched(episode.id) ? "Mark unwatched" : "Mark watched") {
                library.markWatched(episode, watched: !library.isWatched(episode.id))
            }
        }
    }
}

/// Compact, fixed-size download control for one episode.
/// Never embed the full-width DownloadAction row inside a 40-point column:
/// its text labels and spacers can expand a grid card to hundreds of points.
private struct EpisodeDownloadControl: View {
    let video: Video
    @ObservedObject private var downloads = DownloadCenter.shared

    var body: some View {
        Group {
            if let entry = downloads.entry(for: video.id),
               entry.status == .ready, downloads.localURL(for: video.id) != nil {
                Menu {
                    Button("Remove offline copy", role: .destructive) { downloads.remove(video.id) }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
                .accessibilityLabel("Episode downloaded")
            } else if let entry = downloads.entry(for: video.id), entry.isActive {
                Menu {
                    if entry.status == .paused {
                        Button("Resume download", systemImage: "play.fill") { downloads.resume(video.id) }
                    } else {
                        Button("Pause download", systemImage: "pause.fill") { downloads.pause(video.id) }
                    }
                    Button("Cancel download", role: .destructive) { downloads.cancel(video.id) }
                } label: {
                    Image(systemName: entry.status == .paused ? "pause.circle" : "arrow.down.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
                .accessibilityLabel("Manage episode download")
            } else {
                DownloadQualityMenu(video: video, compact: true,
                                    title: "Download episode \(video.episode)")
                    .buttonStyle(.plain)
            }
        }
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }
}
