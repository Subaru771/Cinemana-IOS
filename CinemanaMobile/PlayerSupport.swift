import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer
import UIKit

// MARK: - External subtitles

/// Loads provider subtitle files and exposes the cue for the current playback time.
@MainActor
final class SubtitleController: ObservableObject {
    static let preferenceKey = "cinemana-sub-pref"
    @Published private(set) var available: [Subtitle] = []
    @Published private(set) var selected: Subtitle?
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    /// Positive values delay captions; values are remembered separately for each title.
    @Published private(set) var offset: Double = 0

    private var cues: [SubtitleCue] = []
    private var videoID: String?
    private var imported: Subtitle?

    private static func safeKey(_ id: String) -> String {
        let hash = id.utf8.reduce(UInt64(14695981039346656037)) { (value, byte) in
            (value ^ UInt64(byte)) &* UInt64(1099511628211)
        }
        return String(hash, radix: 16)
    }

    private static func subtitleDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CinemanaSubtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private static func importedURL(_ id: String) -> URL {
        subtitleDirectory().appendingPathComponent("user-\(safeKey(id)).srt")
    }
    private static func cachedURL(_ id: String) -> URL {
        subtitleDirectory().appendingPathComponent("cached-\(safeKey(id)).srt")
    }
    private static func offsetKey(_ id: String) -> String { "cinemana-sub-delay-" + safeKey(id) }

    func load(for id: String) async {
        videoID = id
        available = []
        selected = nil
        failure = nil
        cues = []
        offset = UserDefaults.standard.double(forKey: Self.offsetKey(id))
        imported = nil
        let local = Self.importedURL(id)
        if FileManager.default.fileExists(atPath: local.path) {
            imported = Subtitle(name: "Imported subtitle", url: local)
            available = [imported!]
        } else {
            let cached = Self.cachedURL(id)
            if FileManager.default.fileExists(atPath: cached.path) {
                available = [Subtitle(name: "Saved offline subtitles", url: cached)]
            }
        }
        let preferredLanguage = UserDefaults.standard.string(forKey: "cinemana-subtitle-language") ?? "auto"
        // Off prevents every local and provider subtitle from auto-activating.
        if preferredLanguage != "off", let local = available.first {
            await select(local, remember: false)
        }
        let found = await CinemanaAPI.shared.subtitles(id)
        guard videoID == id else { return }
        available = available + found.filter { subtitle in
            !available.contains(where: { $0.id == subtitle.id })
        }
        guard preferredLanguage != "off" else {
            await select(nil, remember: false)
            return
        }
        if preferredLanguage == "ar" || preferredLanguage == "en" {
            if let match = available.first(where: {
                Self.matchesLanguage($0.name, preferredLanguage)
            }) {
                await select(match, remember: false)
            }
        } else {
            let preferred = UserDefaults.standard.string(forKey: Self.preferenceKey) ?? ""
            if !preferred.isEmpty, let match = available.first(where: { $0.name == preferred }) {
                await select(match, remember: false)
            }
        }
    }

    static func matchesLanguage(_ name: String, _ language: String) -> Bool {
        let text = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if language == "ar" {
            return text.contains("arab") || text.contains("العرب") ||
                text == "ar" || text.hasPrefix("ar-") || text.contains("(ar)")
        }
        if language == "en" {
            return text.contains("english") || text == "en" ||
                text.hasPrefix("en-") || text.contains("(en)")
        }
        return false
    }

    func importFile(_ externalURL: URL) async {
        guard let id = videoID else { return }
        let ext = externalURL.pathExtension.lowercased()
        guard ext == "srt" || ext == "vtt" else {
            failure = "Choose a .srt or .vtt subtitle file."; return
        }
        let scoped = externalURL.startAccessingSecurityScopedResource()
        defer { if scoped { externalURL.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: externalURL)
            guard data.count <= 4_194_304 else { failure = "Subtitle file is too large (4 MB maximum)."; return }
            guard !SubtitleParser.parse(SubtitleParser.decodeText(data)).isEmpty else {
                failure = "This subtitle has no valid timestamps."; return
            }
            let dest = Self.importedURL(id)
            try data.write(to: dest, options: .atomic)
            guard videoID == id else { return }
            let item = Subtitle(name: "Imported subtitle", url: dest)
            imported = item
            available.removeAll { $0.name == item.name }
            available.insert(item, at: 0)
            await select(item)
        } catch { failure = "Unable to import subtitles: \(error.localizedDescription)" }
    }

    func select(_ subtitle: Subtitle?, remember: Bool = true) async {
        if remember { UserDefaults.standard.set(subtitle?.name ?? "", forKey: Self.preferenceKey) }
        failure = nil
        guard let subtitle else { selected = nil; cues = []; return }
        let id = videoID
        loading = true
        defer { loading = false }
        do {
            let data: Data
            if subtitle.url.isFileURL { data = try Data(contentsOf: subtitle.url) }
            else {
                do {
                    let (downloaded, _) = try await URLSession.shared.data(from: subtitle.url)
                    data = downloaded
                    // Store one last-used provider subtitle per movie/episode for offline playback.
                    if let id, downloaded.count <= 4_194_304 {
                        try? downloaded.write(to: Self.cachedURL(id), options: .atomic)
                    }
                } catch {
                    guard let id else { throw error }
                    data = try Data(contentsOf: Self.cachedURL(id))
                }
            }
            guard videoID == id else { return }
            let parsed = SubtitleParser.parse(SubtitleParser.decodeText(data))
            guard !parsed.isEmpty else { selected = nil; cues = []; failure = "Subtitle timestamps are invalid."; return }
            cues = parsed
            selected = subtitle
        } catch {
            guard videoID == id else { return }
            selected = nil; cues = []
            failure = "Subtitles are unavailable offline. Import an SRT/VTT file or reconnect."
        }
    }

    func adjustOffset(by delta: Double) {
        offset = max(-30, min(30, ((offset + delta) * 10).rounded() / 10))
        if let id = videoID { UserDefaults.standard.set(offset, forKey: Self.offsetKey(id)) }
    }

    func cue(at time: Double) -> SubtitleCue? { SubtitleParser.cue(at: time, in: cues) }

    func reset() {
        videoID = nil; available = []; selected = nil; cues = []; offset = 0; imported = nil
    }
}

// MARK: - Picture in Picture

final class PictureInPictureController: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var possible = false
    @Published private(set) var active = false
    private var controller: AVPictureInPictureController?
    private var observation: NSKeyValueObservation?

    func attach(_ layer: AVPlayerLayer) {
        guard controller == nil, AVPictureInPictureController.isPictureInPictureSupported(),
              let created = AVPictureInPictureController(playerLayer: layer) else { return }
        created.delegate = self
        created.canStartPictureInPictureAutomaticallyFromInline = true
        controller = created
        observation = created.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] item, _ in
            let value = item.isPictureInPicturePossible
            DispatchQueue.main.async { self?.possible = value }
        }
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive { controller.stopPictureInPicture() }
        else { controller.startPictureInPicture() }
    }

    func stop() {
        if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async { self.active = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async { self.active = false }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - Lock screen / headphone controls

final class NowPlayingBridge {
    static let shared = NowPlayingBridge()
    private var registrations: [(MPRemoteCommand, Any)] = []
    private var artwork: MPMediaItemArtwork?
    private var artworkURL: URL?

    /// `player` is a provider because quality changes replace the underlying AVPlayer.
    func activate(player: @escaping () -> AVPlayer?, next: @escaping () -> Bool) {
        deactivateCommands()
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipBackwardCommand.preferredIntervals = [10]
        add(center.playCommand) { _ in player()?.play(); return .success }
        add(center.pauseCommand) { _ in player()?.pause(); return .success }
        add(center.togglePlayPauseCommand) { _ in
            guard let item = player() else { return .noActionableNowPlayingItem }
            if item.rate > 0 { item.pause() } else { item.play() }
            return .success
        }
        add(center.skipForwardCommand) { _ in Self.jump(player(), by: 30); return .success }
        add(center.skipBackwardCommand) { _ in Self.jump(player(), by: -10); return .success }
        add(center.changePlaybackPositionCommand) { event in
            guard let item = player(),
                  let change = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            item.seek(to: CMTime(seconds: change.positionTime, preferredTimescale: 600))
            return .success
        }
        add(center.nextTrackCommand) { _ in next() ? .success : .noSuchContent }
    }

    func update(video: Video, position: Double, duration: Double, rate: Float) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, position.isFinite ? position : 0),
            MPNowPlayingInfoPropertyPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]
        if duration.isFinite && duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkIfNeeded(video.poster ?? video.backdrop)
    }

    func deactivate() {
        deactivateCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        artwork = nil
        artworkURL = nil
    }

    private func add(_ command: MPRemoteCommand,
                     _ handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        command.isEnabled = true
        // Handlers touch main-actor state (the player), so always run them on the main thread.
        let token = command.addTarget { event in
            if Thread.isMainThread { return handler(event) }
            return DispatchQueue.main.sync { handler(event) }
        }
        registrations.append((command, token))
    }

    private func deactivateCommands() {
        for (command, token) in registrations { command.removeTarget(token) }
        registrations = []
    }

    private static func jump(_ player: AVPlayer?, by seconds: Double) {
        guard let player else { return }
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    private func loadArtworkIfNeeded(_ url: URL?) {
        guard let url, url != artworkURL else { return }
        artworkURL = url
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            let made = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                guard let self, self.artworkURL == url else { return }
                self.artwork = made
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = made
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
}

// MARK: - Orientation, volume

@MainActor
enum PlayerOrientation {
    // UIKit must advertise the requested orientation before iOS 16+ will
    // accept a scene geometry update. The player temporarily narrows the
    // mask; the catalogue gets the default orientations back on dismissal.
    static var supportedMask: UIInterfaceOrientationMask?

    static func request(_ mask: UIInterfaceOrientationMask, onError: ((Error) -> Void)? = nil) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }

        supportedMask = mask
        for window in scene.windows {
            var controller: UIViewController? = window.rootViewController
            while let visible = controller {
                visible.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = visible.presentedViewController
            }
        }
        scene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)) { error in
            DispatchQueue.main.async { onError?(error) }
        }
    }

    static func restoreAfterPlayer() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        request(.portrait)
        Task { @MainActor in
            // Give the fullScreenCover time to finish its dismissal, then
            // restore all normally supported iPhone orientations.
            try? await Task.sleep(for: .milliseconds(700))
            guard supportedMask == .portrait else { return }
            supportedMask = nil
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                for window in scene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }
}

/// Hidden MPVolumeView so a swipe gesture can change the system volume without the system HUD.
struct VolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.alpha = 0.01
        SystemVolume.host = view
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

enum SystemVolume {
    static weak var host: MPVolumeView?

    static var current: Float { AVAudioSession.sharedInstance().outputVolume }

    static func set(_ level: Float) {
        let value = min(1, max(0, level))
        let slider = host?.subviews.compactMap { $0 as? UISlider }.first
        DispatchQueue.main.async { slider?.value = value }
    }
}
