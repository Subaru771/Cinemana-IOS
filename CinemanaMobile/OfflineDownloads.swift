import Foundation
import AVFoundation
import Combine
import UIKit

/// Local, sandboxed download manager. Only provider-supplied, directly downloadable streams
/// are accepted. The manager never bypasses DRM or a provider's network authorization.
final class DownloadCenter: NSObject, ObservableObject, URLSessionDownloadDelegate, AVAssetDownloadDelegate {
    static let shared = DownloadCenter()
    private static let fileID = "app.cinemana.mobile.ios.background-media-v1"
    private static let hlsID = "app.cinemana.mobile.ios.background-hls-v1"

    @Published private(set) var items: [OfflineEntry] = []
    private let fm = FileManager.default
    private let root: URL
    private var fileSession: URLSession!
    private var hlsSession: AVAssetDownloadURLSession!
    private var completionHandlers: [String: () -> Void] = [:]
    private var hlsDestinations: [String: URL] = [:]

    private override init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CinemanaOffline", isDirectory: true)
        super.init()
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([OfflineEntry].self, from: data) {
            items = saved
        }
        let files = URLSessionConfiguration.background(withIdentifier: Self.fileID)
        files.sessionSendsLaunchEvents = true
        files.isDiscretionary = false
        fileSession = URLSession(configuration: files, delegate: self, delegateQueue: .main)
        let hls = URLSessionConfiguration.background(withIdentifier: Self.hlsID)
        hls.sessionSendsLaunchEvents = true
        hls.isDiscretionary = false
        hlsSession = AVAssetDownloadURLSession(configuration: hls, assetDownloadDelegate: self, delegateQueue: .main)
        restoreTasks()
    }

    private var indexURL: URL { root.appendingPathComponent("downloads.json") }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
    }

    private func change(_ id: String, _ mutation: (inout OfflineEntry) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutation(&items[index])
        items[index].updatedAt = Date()
        persist()
    }

    func entry(for id: String) -> OfflineEntry? { items.first { $0.id == id } }

    func localURL(for id: String) -> URL? {
        guard let item = entry(for: id), item.status == .ready, let path = item.localPath else { return nil }
        let url = URL(fileURLWithPath: path)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    @MainActor
    func begin(_ video: Video) async {
        if localURL(for: video.id) != nil || entry(for: video.id)?.isActive == true { return }
        items.removeAll { $0.id == video.id }
        items.insert(OfflineEntry(video: video, status: .preparing, format: nil, progress: 0,
                                  localPath: nil, bytesReceived: 0, bytesExpected: 0,
                                  message: nil, updatedAt: Date()), at: 0)
        persist()
        do {
            let available = DownloadPolicy.supported(try await CinemanaAPI.shared.streams(video.id))
            guard !Task.isCancelled, entry(for: video.id)?.status == .preparing else { return }
            let configured = UserDefaults.standard.integer(forKey: "cinemana-max-download-quality")
            guard let stream = PlaybackPlanner.preferred(from: available,
                    maximumQuality: configured > 0 ? configured : 1080),
                  let format = DownloadPolicy.format(for: stream.url) else {
                fail(video.id, "The provider has no downloadable MP4 or HLS source for this title.")
                return
            }
            change(video.id) { $0.status = .downloading; $0.format = format }
            switch format {
            case .file:
                let task = fileSession.downloadTask(with: stream.url)
                task.taskDescription = video.id
                task.resume()
            case .hls:
                let asset = AVURLAsset(url: stream.url)
                guard let task = hlsSession.makeAssetDownloadTask(
                    asset: asset, assetTitle: video.title, assetArtworkData: nil, options: nil
                ) else {
                    fail(video.id, "This HLS stream cannot be downloaded.")
                    return
                }
                task.taskDescription = video.id
                task.resume()
            }
        } catch {
            if entry(for: video.id)?.status == .preparing { fail(video.id, error.localizedDescription) }
        }
    }

    func cancel(_ id: String) {
        fileSession.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        }
        hlsSession.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        }
        change(id) { $0.status = .cancelled; $0.message = "Cancelled" }
    }

    func remove(_ id: String) {
        cancel(id)
        if let item = entry(for: id), let path = item.localPath {
            let url = URL(fileURLWithPath: path)
            if item.format == .hls ||
                (item.format == .file && url.deletingLastPathComponent() == root) {
                try? fm.removeItem(at: url)
            }
        }
        items.removeAll { $0.id == id }
        persist()
    }

    private func fail(_ id: String, _ message: String) {
        change(id) { $0.status = .failed; $0.message = message }
    }

    private func restoreTasks() {
        fileSession.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async { self?.reconcile(tasks, format: .file) }
        }
        hlsSession.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async { self?.reconcile(tasks, format: .hls) }
        }
    }

    private func reconcile(_ tasks: [URLSessionTask], format: OfflineEntry.Format) {
        let active = Set(tasks.compactMap(\.taskDescription))
        for item in items where item.isActive && item.format == format && !active.contains(item.id) {
            guard Date().timeIntervalSince(item.updatedAt) > 900 else { continue }
            fail(item.id, "Download interrupted. Tap Retry to start again.")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        change(id) {
            $0.bytesReceived = totalBytesWritten
            $0.bytesExpected = totalBytesExpectedToWrite
            if totalBytesExpectedToWrite > 0 {
                $0.progress = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription,
              entry(for: id)?.status == .downloading else { return }
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode,
           !(200...299).contains(status) {
            fail(id, "Download rejected: HTTP \(status)")
            return
        }
        if let mime = downloadTask.response?.mimeType?.lowercased(),
           mime.contains("html") || mime.contains("json") || mime.contains("text/plain") {
            fail(id, "Server returned a document, not a video.")
            return
        }
        let ext = downloadTask.originalRequest?.url?.pathExtension.lowercased() ?? "mp4"
        let destination = root.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try fm.moveItem(at: location, to: destination)
            change(id) { $0.status = .ready; $0.localPath = destination.path; $0.progress = 1; $0.message = nil }
        } catch { fail(id, error.localizedDescription) }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    willDownloadTo location: URL) {
        guard let id = assetDownloadTask.taskDescription else { return }
        hlsDestinations[id] = location
        change(id) { $0.localPath = location.path }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange, totalTimeRangesLoaded: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected.isFinite && expected > 0 else { return }
        let loaded = totalTimeRangesLoaded.reduce(0) { $0 + max(0, $1.timeRangeValue.duration.seconds) }
        change(id) { $0.progress = min(0.99, max(0, loaded / expected)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let entry = entry(for: id) else { return }
        if entry.status == .cancelled { return }
        if let error { fail(id, error.localizedDescription); return }
        if entry.format == .hls {
            if let path = entry.localPath ?? hlsDestinations[id]?.path,
               fm.fileExists(atPath: path) {
                change(id) { $0.status = .ready; $0.progress = 1; $0.localPath = path; $0.message = nil }
            } else { fail(id, "HLS package was not saved.") }
        } else if entry.status != .ready {
            fail(id, "Download finished without a playable file.")
        }
    }

    func registerCompletion(_ identifier: String, handler: @escaping () -> Void) {
        completionHandlers[identifier] = handler
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        let handler = completionHandlers.removeValue(forKey: identifier)
        handler?()
    }
}
