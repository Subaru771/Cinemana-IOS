import Foundation

struct OfflineEntry: Codable, Identifiable {
    enum Status: String, Codable { case preparing, downloading, ready, failed, cancelled }
    enum Format: String, Codable { case file, hls }

    let video: Video
    var status: Status
    var format: Format?
    var progress: Double
    var localPath: String?
    var bytesReceived: Int64
    var bytesExpected: Int64
    var message: String?
    var updatedAt: Date
    var id: String { video.id }
    var isActive: Bool { status == .preparing || status == .downloading }
}

enum DownloadPolicy {
    static func format(for url: URL) -> OfflineEntry.Format? {
        switch url.pathExtension.lowercased() {
        case "m3u8": return .hls
        case "mp4", "m4v", "mov": return .file
        default: return nil
        }
    }
    static func supported(_ streams: [Stream]) -> [Stream] {
        streams.filter { $0.playableOnIOS && format(for: $0.url) != nil }
    }
}
