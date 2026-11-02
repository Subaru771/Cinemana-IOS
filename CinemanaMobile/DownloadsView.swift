import SwiftUI

/// Offline library with live progress and explicit retry/cancel/delete actions.
struct DownloadsView: View {
    @ObservedObject private var center = DownloadCenter.shared
    @State private var watch: Video?

    var body: some View {
        NavigationStack {
            Group {
                if center.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.to.line.compact")
                            .font(.system(size: 54))
                            .foregroundStyle(.mint)
                        Text("Your downloads").font(.title2.bold())
                        Text("Choose Download from a movie or episode. Supported videos will appear here for offline playback.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text("Availability depends on the video provider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(center.items) { entry in
                            HStack(alignment: .center, spacing: 12) {
                                AsyncImage(url: entry.video.poster) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "film")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .frame(width: 60, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 7) {
                                    Text(entry.video.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                    Text(statusDescription(entry))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if entry.isActive {
                                        ProgressView(value: entry.progress)
                                            .tint(.mint)
                                        Text("\(Int(entry.progress * 100))%")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let message = entry.message, entry.status == .failed {
                                        Text(message)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .lineLimit(3)
                                    }
                                    HStack(spacing: 16) {
                                        if entry.status == .ready &&
                                            center.localURL(for: entry.id) != nil {
                                            Button {
                                                watch = entry.video
                                            } label: {
                                                Label("Play", systemImage: "play.fill")
                                            }
                                        }
                                        if entry.status == .preparing || entry.status == .downloading {
                                            Button("Cancel") { center.cancel(entry.id) }
                                        }
                                        if entry.status == .failed || entry.status == .cancelled {
                                            Button("Retry") {
                                                Task { await center.begin(entry.video) }
                                            }
                                        }
                                        Button("Delete", role: .destructive) { center.remove(entry.id) }
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Downloads")
            .background(Color.black)
            .fullScreenCover(item: $watch) { video in
                VideoPlaybackView(video: video)
            }
        }
    }

    private func statusDescription(_ entry: OfflineEntry) -> String {
        switch entry.status {
        case .preparing: return "Preparing download"
        case .downloading: return "Downloading"
        case .ready: return center.localURL(for: entry.id) == nil ? "File unavailable" : "Ready to watch offline"
        case .failed: return "Download failed"
        case .cancelled: return "Cancelled"
        }
    }
}
