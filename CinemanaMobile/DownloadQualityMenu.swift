import SwiftUI

/// Shared quality and network chooser for an individual video or a full season.
/// The chosen resolution is a ceiling; a lower available source is used if needed.
struct DownloadQualityMenu: View {
    private let videos: [Video]
    private let compact: Bool
    private let title: String

    @ObservedObject private var center = DownloadCenter.shared
    @AppStorage("cinemana-wifi-only") private var wifiOnly = false

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
            Section("Download quality") {
                Button {
                    center.enqueue(videos)
                } label: {
                    Label("Use preferred quality", systemImage: "gearshape")
                }
                Button {
                    center.enqueue(videos, preferredQuality: Int.max)
                } label: {
                    Label("Best available", systemImage: "sparkles.tv")
                }
                ForEach([480, 720, 1080, 2160], id: \.self) { quality in
                    Button {
                        center.enqueue(videos, preferredQuality: quality)
                    } label: {
                        Text("Up to \(quality)p")
                    }
                }
            }
            Divider()
            Toggle(isOn: $wifiOnly) {
                Label("Wi-Fi only", systemImage: "wifi")
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
        .onChange(of: wifiOnly) { _ in center.updateNetworkPolicy() }
    }
}
