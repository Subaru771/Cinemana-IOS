import SwiftUI

/// Show only downloadable resolutions provided by this video's actual sources.
/// Season batches automatically choose the best available per episode.
struct DownloadQualityMenu: View {
    private let videos: [Video]
    private let compact: Bool
    private let title: String
    @ObservedObject private var center = DownloadCenter.shared
    @State private var qualities: [Int] = []
    @State private var unknownQuality = false
    @State private var loaded = false

    init(video: Video, compact: Bool = false, title: String = "Download options") {
        self.videos = [video]
        self.compact = compact
        self.title = title
    }

    init(videos: [Video], compact: Bool = false, title: String = "Download season") {
        self.videos = videos
        self.compact = compact
        self.title = title
    }

    private var isSeason: Bool { videos.count > 1 }
    private var requestID: String { videos.map(\.id).joined(separator: "|") }

    var body: some View {
        Menu {
            if isSeason {
                Button("Best available") {
                    center.enqueue(videos, preferredQuality: Int.max)
                }
            } else if !loaded {
                Text("Checking qualities…")
            } else {
                ForEach(qualities, id: \.self) { quality in
                    Button("\(quality)p") {
                        center.enqueue(videos, preferredQuality: quality)
                    }
                }
                if unknownQuality {
                    Button("Best available") {
                        center.enqueue(videos, preferredQuality: Int.max)
                    }
                }
                if qualities.isEmpty && !unknownQuality {
                    Text("No downloadable qualities")
                }
            }
        } label: {
            if compact {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.title3)
                    .frame(minWidth: 40, minHeight: 40)
                    .accessibilityLabel(LocalizedStringKey(title))
            } else {
                Label(LocalizedStringKey(title), systemImage: "arrow.down.to.line")
            }
        }
        .task(id: requestID) {
            guard !isSeason, let video = videos.first else { return }
            loaded = false
            qualities = []
            unknownQuality = false
            do {
                let sources = DownloadPolicy.supported(
                    try await CinemanaAPI.shared.streams(video.id, preferComplete: true))
                var resolutions = Set(sources.map(\.quality).filter { $0 > 0 })
                var unlabelled = false
                for stream in sources where stream.quality == 0 {
                    if stream.url.pathExtension.lowercased() == "m3u8" {
                        let heights = await HLSQuality.availableHeights(at: stream.url)
                        resolutions.formUnion(heights)
                        if heights.isEmpty { unlabelled = true }
                    } else {
                        unlabelled = true
                    }
                }
                guard !Task.isCancelled else { return }
                qualities = resolutions.sorted(by: >)
                unknownQuality = unlabelled
            } catch {
                guard !Task.isCancelled else { return }
                qualities = []
                unknownQuality = false
            }
            loaded = true
        }
    }
}
