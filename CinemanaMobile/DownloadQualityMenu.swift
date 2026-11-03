import SwiftUI

/// Four explicit resolution ceilings. The selection is stored with each
/// download, and no legacy default / best / network menu items are displayed.
struct DownloadQualityMenu: View {
    private let videos: [Video]
    private let compact: Bool
    private let title: String

    @ObservedObject private var center = DownloadCenter.shared

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

    var body: some View {
        Menu {
            ForEach([480, 720, 1080, 2160], id: \.self) { quality in
                Button {
                    center.enqueue(videos, preferredQuality: quality)
                } label: {
                    Text("Up to \(quality)p")
                }
            }
        } label: {
            if compact {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.title3)
                    .frame(minWidth: 40, minHeight: 40)
                    .accessibilityLabel(title)
            } else {
                Label(title, systemImage: "arrow.down.to.line")
            }
        }
    }
}
