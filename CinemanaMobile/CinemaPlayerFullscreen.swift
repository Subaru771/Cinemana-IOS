import SwiftUI
import AVFoundation
import AVKit
import UIKit
import Combine
import UniformTypeIdentifiers

private let cinemaAccent = Color(red: 1.00, green: 0.18, blue: 0.25)

/// Shared header mark, without a second square around the emblem.
/// Keep iOS visible in both compact and expanded navigation headers.
struct CinemanaLogo: View {
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 5 : 9) {
            CinemanaGlyph()
                .frame(width: compact ? 34 : 51, height: compact ? 34 : 51)
            Text("CINEMANA")
                .font(.system(size: compact ? 13 : 22, weight: .black, design: .rounded))
                .tracking(compact ? 0.6 : 1.2)
                .foregroundStyle(.white)
            Text("iOS")
                .font(.system(size: compact ? 10 : 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.15, blue: 0.23))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cinemana iOS")
    }
}

/// Only AVPlayerLayer renders pixels. No Apple video-player interface is presented.
final class CinemanaRenderView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var renderLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct CinemanaVideoCanvas: UIViewRepresentable {
    let player: AVPlayer?
    var fillScreen: Bool
    var onLayer: ((AVPlayerLayer) -> Void)? = nil

    func makeUIView(context: Context) -> CinemanaRenderView {
        let view = CinemanaRenderView()
        view.backgroundColor = .black
        view.renderLayer.videoGravity = .resizeAspect
        let callback = onLayer
        DispatchQueue.main.async { callback?(view.renderLayer) }
        return view
    }

    func updateUIView(_ uiView: CinemanaRenderView, context: Context) {
        if uiView.renderLayer.player !== player {
            uiView.renderLayer.player = player
        }
        uiView.renderLayer.videoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
    }
}

struct CinemanaAirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(red: 1.00, green: 0.18, blue: 0.25, alpha: 1)
        picker.prioritizesVideoDevices = true
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Brightness / volume indicator shown while swiping.
struct LevelHUD: Equatable {
    let symbol: String
    let level: Float
}

/// Draws external (SRT/VTT) subtitles. It owns its own clock so the main player view does not
/// re-render every tenth of a second.
struct SubtitleOverlay: View {
    @ObservedObject var controller: SubtitleController
    let player: AVPlayer?
    let scale: Double
    let lift: CGFloat
    @AppStorage("cinemana-sub-background") private var captionBackdrop = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { _ in
            VStack {
                Spacer()
                if let text = currentText() {
                    Text(text)
                        .font(.system(size: 21 * scale, weight: .semibold))
                        .environment(\.layoutDirection, text.unicodeScalars.contains(where: {
                            (0x0600...0x08FF).contains(Int($0.value))
                        }) ? .rightToLeft : .leftToRight)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black, radius: 2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(captionBackdrop ? 0.65 : 0), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 44)
                }
            }
            .padding(.bottom, lift)
        }
        .allowsHitTesting(false)
    }

    private func currentText() -> String? {
        guard controller.selected != nil, let player else { return nil }
        let time = player.currentTime().seconds - controller.offset
        guard time.isFinite else { return nil }
        return controller.cue(at: time)?.text
    }
}

/// The full-screen cover presents this view immediately, even while the stream URL is loading.
struct CinemaPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var downloads = DownloadCenter.shared
    @StateObject private var session = PlaybackSession()
    @StateObject private var subtitles = SubtitleController()
    @StateObject private var pip = PictureInPictureController()

    @AppStorage("cinemana-speed") private var savedSpeed = 1.0
    @AppStorage("cinemana-auto-landscape") private var autoLandscape = true
    @AppStorage("cinemana-sub-scale") private var subtitleScale = 1.0
    @AppStorage("cinemana-sub-background") private var captionBackdrop = true
    @AppStorage(MatureContentFilter.preferenceKey) private var skipMatureScenes = false
    @AppStorage("cinemana-lookup-community-intro") private var useCommunityIntro = false

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var blockedByFilter: Bool { false } // Never block a title; scene skipping is time-coded.

    @State private var current: Video
    @State private var showsControls = true
    @State private var isScrubbing = false
    @State private var seekPreview = 0.0
    @State private var seekInFlight = false
    @State private var seekRequestID = 0
    @State private var bufferedUntil = 0.0
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var playing = false
    @State private var waiting = false
    @State private var cropVideo = false
    @State private var locked = false
    @State private var hideTask: Task<Void, Never>?
    @State private var captions: [AVMediaSelectionOption] = []
    @State private var audioTracks: [AVMediaSelectionOption] = []
    @State private var captionGroup: AVMediaSelectionGroup?
    @State private var audioGroup: AVMediaSelectionGroup?
    @State private var selectedCaption: AVMediaSelectionOption?
    @State private var selectedAudio: AVMediaSelectionOption?
    @State private var upNext: Video?
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var hud: LevelHUD?
    @State private var hudTask: Task<Void, Never>?
    @State private var dragBase: Float?
    @State private var flash: String?
    @State private var flashTask: Task<Void, Never>?
    @State private var appliedPlayer: ObjectIdentifier?
    @State private var originalBrightness: CGFloat = 0.5
    @State private var stalledSince: Date?
    @State private var watchedPlayerID: ObjectIdentifier?
    @State private var showDiagnostics = false
    @State private var importingSubtitles = false
    @State private var showEpisodePicker = false
    @State private var matureSceneRanges: [SceneSkipRange] = []
    @State private var providerIntroEnd: Double?
    @State private var introSegment: VerifiedIntroSegment?
    @State private var externalMarkers: [ExternalSceneMarker] = []
    @State private var providerMatureRanges: [SceneSkipRange] = []
    @State private var metadataIMDbID: String?
    @State private var introLookupKey: String?
    @State private var introLookupStatus = "Intro timing not yet checked"
    @State private var sceneMarkersLoaded = false
    @State private var introSkipUsed = false
    @State private var alreadySkippedScenes = Set<String>()


    private let playlist: [Video]
    private let seriesIMDbID: String?

    init(video: Video, playlist: [Video] = [], imdbID: String? = nil) {
        _current = State(initialValue: video)
        self.playlist = playlist
        self.seriesIMDbID = imdbID
    }

    private var speed: Float { Float(savedSpeed) }
    private var timeLimit: Double { max(1, duration) }
    private var isDownloaded: Bool { downloads.localURL(for: current.id) != nil }
    private var nextEpisode: Video? {
        PlaybackPlanner.nextEpisode(after: current, in: playlist)
    }
    private var subtitleLift: CGFloat { showsControls && !locked ? 150 : 46 }

    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                CinemanaVideoCanvas(player: session.player, fillScreen: cropVideo,
                                    onLayer: { pip.attach($0) })
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                gestureLayer(height: geometry.size.height)

                SubtitleOverlay(controller: subtitles, player: session.player,
                                scale: subtitleScale, lift: subtitleLift)
                    .animation(.easeOut(duration: 0.18), value: subtitleLift)

                VolumeHost().frame(width: 1, height: 1).allowsHitTesting(false)

                stateOverlays

                if showsControls {
                    if locked { lockedOverlay } else { controlOverlay.transition(.opacity) }
                }

                if let next = upNext { upNextCard(next) }
                if let hud { hudView(hud) }
                if let flash { flashView(flash) }
                skipMarkersOverlay

            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(.black)
        .ignoresSafeArea()
        .statusBarHidden(!isPad)
        .persistentSystemOverlays(isPad ? .automatic : .hidden)
        .defersSystemGestures(on: isPad ? [] : .all)
        .preferredColorScheme(.dark)
        .task(id: current.id) {
            await startPlayback()
            await loadSkipMarkers()
        }
        .onAppear { prepareScreen() }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            updateProgress()
        }
        .onChange(of: session.selected?.id) { _ in
            Task { await loadTracks() }
        }
        .onChange(of: playing) { _ in refreshNowPlaying() }
        .onChange(of: duration > 0) { ready in
            refreshNowPlaying()
            if ready { Task { await loadCommunityIntroIfAllowed() } }
        }
        .onChange(of: useCommunityIntro) { allowed in
            introLookupKey = nil
            if allowed { Task { await loadCommunityIntroIfAllowed() } }
            else {
                introSegment = nil
                externalMarkers.removeAll { $0.kind != "mature" }
                introLookupStatus = "Community intro/recap/credits lookup is off"
            }
        }
        .onChange(of: skipMatureScenes) { enabled in
            introLookupKey = nil
            if enabled { Task { await loadCommunityIntroIfAllowed() } }
            else { matureSceneRanges = providerMatureRanges }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { session.save(library: library) }
        }
        .sheet(isPresented: $showEpisodePicker) {
            NavigationStack {
                List {
                    ForEach(playlist) { episode in
                        Button {
                            showEpisodePicker = false
                            play(episode)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: episode.id == current.id ? "play.circle.fill" : "play.circle")
                                    .foregroundStyle(cinemaAccent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Season \(episode.season) · Episode \(episode.episode)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(episode.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if library.isWatched(episode.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Episodes")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showEpisodePicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onDisappear { teardown() }
        .fileImporter(isPresented: $importingSubtitles,
                      allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText,
                                            UTType(filenameExtension: "vtt") ?? .plainText]) { result in
            switch result {
            case .success(let url): Task { await subtitles.importFile(url) }
            case .failure(let error): flashMessage("Import failed: \(error.localizedDescription)")
            }
        }
        .alert("Playback diagnostics", isPresented: $showDiagnostics) {
            Button("Copy report") { UIPasteboard.general.string = diagnosticsReport }
            Button("Close", role: .cancel) { }
        } message: {
            Text(diagnosticsReport)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { note in
            if let item = note.object as? AVPlayerItem {
                session.failed(item: item, library: library,
                    reason: (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            if let item = note.object as? AVPlayerItem, session.player?.currentItem === item {
                playing = false
                library.markWatched(current, watched: true)
                showControls()
                if let next = nextEpisode { beginUpNext(next) }
            }
        }
    }

    // MARK: Lifecycle

    private func startPlayback() async {
        guard !blockedByFilter else { session.player?.pause(); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* Playback may still work with the previous audio session. */ }
        let id = current.id
        Task { await subtitles.load(for: id) }
        await session.load(video: current, library: library)
        if session.player != nil { showControls() }
        refreshNowPlaying()
    }

    private func prepareScreen() {
        originalBrightness = UIScreen.main.brightness
        UIApplication.shared.isIdleTimerDisabled = true
        if autoLandscape && !isPad { PlayerOrientation.request(.landscape) }
        let sessionRef = session
        NowPlayingBridge.shared.activate(
            player: { sessionRef.player },
            next: { [self] in
                guard let next = nextEpisode else { return false }
                DispatchQueue.main.async { play(next) }
                return true
            }
        )
    }

    private func teardown() {
        hideTask?.cancel()
        countdownTask?.cancel()
        hudTask?.cancel()
        flashTask?.cancel()
        session.close(library: library)
        subtitles.reset()
        pip.stop()
        NowPlayingBridge.shared.deactivate()
        UIApplication.shared.isIdleTimerDisabled = false
        UIScreen.main.brightness = originalBrightness
        if autoLandscape && !isPad { PlayerOrientation.request(.portrait) }
    }

    // MARK: Gestures

    private func gestureLayer(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            tapZone(rightSide: false, height: height)
            tapZone(rightSide: true, height: height)
        }
        .ignoresSafeArea()
    }

    private func tapZone(rightSide: Bool, height: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !locked, session.player != nil else { return }
                skip(rightSide ? 10 : -10)
            }
            .onTapGesture { toggleControls() }
            .gesture(levelDrag(rightSide: rightSide, height: height))
    }

    /// Left half changes brightness, right half changes volume.
    private func levelDrag(rightSide: Bool, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard !locked else { return }
                if dragBase == nil {
                    // Ignore mostly-horizontal drags so they cannot change the levels.
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    dragBase = rightSide ? SystemVolume.current : Float(UIScreen.main.brightness)
                }
                guard let base = dragBase else { return }
                let delta = Float(-value.translation.height / (height * 0.75))
                let level = min(1, max(0, base + delta))
                if rightSide {
                    SystemVolume.set(level)
                    showHUD(LevelHUD(symbol: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", level: level))
                } else {
                    UIScreen.main.brightness = CGFloat(level)
                    showHUD(LevelHUD(symbol: "sun.max.fill", level: level))
                }
            }
            .onEnded { _ in
                dragBase = nil
                hudTask?.cancel()
                hudTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.8))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) { hud = nil }
                }
            }
    }

    private func showHUD(_ value: LevelHUD) {
        hudTask?.cancel()
        hud = value
    }

    private func flashMessage(_ text: String) {
        flashTask?.cancel()
        flash = text
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { flash = nil }
        }
    }

    private func skip(_ delta: Double) {
        seek(to: livePosition() + delta)
        flashMessage(delta > 0 ? "+\(Int(delta))s" : "−\(Int(-delta))s")
    }


    /// Buttons appear only inside a verified segment window. No arbitrary seek.
    @ViewBuilder
    private var skipMarkersOverlay: some View {
        if session.player != nil && !locked {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Spacer()
                    if let destination = externalSceneButtonDestination() {
                            Button(destination.label) {
                                introSkipUsed = true
                                seek(to: destination.time)
                                flashMessage("Skipped \(destination.label.lowercased()) · \(destination.source)")
                            }
                            .buttonStyle(.borderedProminent).tint(cinemaAccent)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, showsControls ? 200 : 58)
            }
        }
    }

    /// The ordering prevents overlapping metadata sources from offering two buttons.
    private func externalSceneButtonDestination() -> (label: String, time: Double, source: String)? {
        for kind in ["recap", "intro", "outro", "preview"] {
            if let segment = externalMarkers.first(where: { $0.kind == kind }),
               let position = segment.destination(at: currentTime, duration: duration) {
                let label = ["recap": "Skip Recap", "intro": "Skip Intro",
                             "outro": "Skip Credits", "preview": "Skip Preview"][kind] ?? "Skip"
                return (label, position, segment.source)
            }
        }
        if let position = CommunitySkipTimes.skipDestination(current: currentTime,
                                                              duration: duration, segment: introSegment)
            ?? SceneSkipPlanner.introDestination(current: currentTime, duration: duration,
                                                  marker: providerIntroEnd)?.time {
            return ("Skip Intro", position, "provider")
        }
        return nil
    }

    @MainActor
    private func loadSkipMarkers() async {
        matureSceneRanges = []
        providerMatureRanges = []
        externalMarkers = []
        providerIntroEnd = nil
        metadataIMDbID = nil
        introSegment = nil
        externalMarkers = []
        providerMatureRanges = []
        introLookupKey = nil
        alreadySkippedScenes = []
        sceneMarkersLoaded = false
        let id = current.id
        let marks = await CinemanaAPI.shared.playbackSkipMarkers(id)
        guard !Task.isCancelled && current.id == id else { return }
        matureSceneRanges = marks.scenes
        providerMatureRanges = marks.scenes
        providerIntroEnd = marks.introEnd
        metadataIMDbID = marks.imdbID
        sceneMarkersLoaded = true
        await loadCommunityIntroIfAllowed()
    }

    @MainActor
    private func loadCommunityIntroIfAllowed() async {
        guard useCommunityIntro || skipMatureScenes else {
            introLookupStatus = "External lookups disabled"
            return
        }
        guard duration > 60 else { return }
        guard let imdbID = seriesIMDbID ?? current.imdbID ?? metadataIMDbID else {
            introLookupStatus = "No IMDb identifier; community scene times unavailable"
            return
        }
        let videoID = current.id
        let selectedDuration = duration
        let key = "\(videoID)|\(imdbID)|\(Int(selectedDuration.rounded()))|\(useCommunityIntro)|\(skipMatureScenes)"
        guard introLookupKey != key else { return }
        introLookupKey = key
        introLookupStatus = "Checking scene timestamps…"
        let segments = await ExternalSceneService.shared.markers(
            imdbID: imdbID, season: current.episode > 0 ? current.season : 0,
            episode: current.episode, duration: selectedDuration,
            includeCommunity: useCommunityIntro, includeMature: skipMatureScenes)
        guard videoID == current.id, introLookupKey == key else { return }
        externalMarkers = segments
        let communityScenes = segments.filter { $0.kind == "mature" }.map {
            SceneSkipRange(start: $0.start, end: $0.end, category: $0.category)
        }
        matureSceneRanges = providerMatureRanges + communityScenes
        let count = segments.filter { $0.kind != "mature" }.count
        introLookupStatus = count > 0 ? "\(count) timed intro/recap/credits marks available" :
            "No precise community skip times for this version"
    }

    // MARK: Overlays

    @ViewBuilder
    private var stateOverlays: some View {
        if session.loading && session.player == nil {
            loadingState
        } else if let problem = session.error, session.player == nil {
            errorState(problem)
        }
        if waiting && session.player != nil && !session.loading {
            ProgressView().tint(cinemaAccent).scaleEffect(1.4)
                .allowsHitTesting(false)
        }
    }

    private var lockedOverlay: some View {
        VStack {
            HStack {
                Button {
                    locked = false
                    showControls()
                } label: {
                    Label("Unlock", systemImage: "lock.open.fill")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(cinemaAccent)
                Spacer()
            }.padding(24)
            Spacer()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 19) {
            CinemanaLogo()
            ProgressView().tint(cinemaAccent).scaleEffect(1.4)
            Text("Preparing playback…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Button("Close") { closePlayer() }.tint(cinemaAccent)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 15) {
            Image(systemName: "play.slash.fill").font(.system(size: 42))
                .foregroundStyle(cinemaAccent)
            Text("Couldn't play this video").font(.title3.weight(.bold))
            Text(message).font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            Button("Try again") { Task { await session.load(video: current, library: library) } }
                .buttonStyle(.borderedProminent).tint(cinemaAccent)
            Button("Close player") { closePlayer() }.tint(.white)
        }
        .padding(26)
        .frame(maxWidth: 450)
    }

    private func hudView(_ value: LevelHUD) -> some View {
        VStack(spacing: 10) {
            Image(systemName: value.symbol).font(.title3)
            ProgressView(value: Double(value.level)).tint(cinemaAccent).frame(width: 120)
        }
        .padding(16)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func flashView(_ text: String) -> some View {
        Text(text)
            .font(.title2.weight(.heavy))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(.black.opacity(0.6), in: Capsule())
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private func upNextCard(_ next: Video) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text("UP NEXT").font(.caption.weight(.heavy)).foregroundStyle(cinemaAccent)
                    Text(next.title).font(.headline).lineLimit(2)
                    Text("Season \(next.season) · Episode \(next.episode)")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 12) {
                        Button { play(next) } label: {
                            Label("Play now (\(countdown))", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(cinemaAccent)
                        .foregroundStyle(.black)
                        Button("Cancel") { cancelUpNext() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                    }
                }
                .padding(16)
                .frame(maxWidth: 340, alignment: .leading)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(24)
        }
        .foregroundStyle(.white)
    }

    // MARK: Controls

    private var controlOverlay: some View {
        VStack(spacing: 0) {
            topBar
                .frame(maxWidth: isPad ? 1100 : .infinity)
            Spacer(minLength: 10)
            if session.player != nil { centerControls }
            Spacer(minLength: 10)
            bottomBar
                .frame(maxWidth: isPad ? 960 : .infinity)
        }
        .foregroundStyle(.white)
        .background {
            LinearGradient(colors: [.black.opacity(0.72), .clear, .black.opacity(0.86)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack(spacing: isPad ? 16 : 8) {
            overlayButton("chevron.down", label: "Close player") { closePlayer() }
            VStack(alignment: .leading, spacing: 3) {
                Text(current.title)
                    .font((isPad ? Font.title3 : Font.subheadline).weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    if current.episode > 0 {
                        Text("S\(current.season) · E\(current.episode)")
                    }
                    Text(isDownloaded ? "OFFLINE" : (session.selected?.label ?? "AUTO"))
                    if savedSpeed != 1 { Text("\(savedSpeed.formatted())×") }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(cinemaAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if pip.possible {
                overlayButton("pip.enter", label: "Picture in Picture") { pip.toggle() }
            }
            CinemanaAirPlayButton().frame(width: 36, height: 36)
            optionsMenu
        }
        .padding(.horizontal, isPad ? 28 : 14)
        .padding(.top, isPad ? 18 : 25)
    }

    private var centerControls: some View {
        HStack(spacing: isPad ? 56 : 27) {
            overlayButton("gobackward.10", label: "Back 10 seconds", size: 29) {
                seek(to: livePosition() - 10)
            }
            Button {
                togglePlayback()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: isPad ? 86 : 70, height: isPad ? 86 : 70)
                    .background(cinemaAccent, in: Circle())
            }
            .accessibilityLabel(playing ? "Pause" : "Play")
            overlayButton("goforward.30", label: "Forward 30 seconds", size: 29) {
                seek(to: livePosition() + 30)
            }
        }
        .tint(.white)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = session.notice {
                Label(notice, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.yellow)
                    .lineLimit(2)
            }
            if session.player != nil { timeline }
            actionRow
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 40)
    }

    private var timeline: some View {
        VStack(spacing: 6) {
            if isScrubbing || seekInFlight {
                Text("Seek to \(formatTime(seekPreview))")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(cinemaAccent)
                    .frame(maxWidth: .infinity)
            }
            GeometryReader { geometry in
                ZStack {
                    Capsule().fill(.white.opacity(0.17))
                        .frame(height: 3)
                    Capsule().fill(cinemaAccent.opacity(0.35))
                        .frame(width: max(0, geometry.size.width * min(1, bufferedUntil / timeLimit)), height: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Slider(value: $seekPreview, in: 0...timeLimit,
                           onEditingChanged: { editing in
                        isScrubbing = editing
                        if editing {
                            hideTask?.cancel()
                        } else {
                            // Keep the preview locked to the chosen time until AVPlayer
                            // confirms the seek, rather than snapping back to stale time.
                            seek(to: seekPreview)
                        }
                    })
                    .tint(cinemaAccent)
                    .disabled(duration <= 0)
                    .accessibilityLabel("Video timeline")
                }
            }
            .frame(height: 30)
            HStack {
                Text(formatTime(isScrubbing ? seekPreview : currentTime))
                Spacer()
                Text(duration > 0
                     ? "-\(formatTime(max(0, duration - (isScrubbing ? seekPreview : currentTime))))"
                     : "LIVE")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var actionRow: some View {
        HStack(spacing: isPad ? 24 : 12) {
            if !playlist.isEmpty {
                Button { showEpisodePicker = true } label: {
                    Label("Episodes", systemImage: "list.bullet.rectangle")
                }
            }
            if let next = nextEpisode {
                Button { play(next) } label: {
                    Label("Next", systemImage: "forward.end.fill")
                }
            }
            Spacer(minLength: 4)
            downloadStatus
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.plain)
        .tint(.white)
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if let entry = downloads.entry(for: current.id), entry.isActive {
            HStack(spacing: 8) {
                ProgressView(value: entry.progress).frame(width: 42)
                Text(entry.status == .paused ? "Paused" : "\(Int(entry.progress * 100))%")
            }
        } else if !isDownloaded {
            DownloadQualityMenu(video: current)
        } else {
            Label("Downloaded", systemImage: "checkmark.circle.fill")
        }
    }

    private var optionsMenu: some View {
        Menu {
            Section("Scene filtering") {
                Toggle("Skip timed mature scenes", isOn: $skipMatureScenes)
                if sceneMarkersLoaded && matureSceneRanges.isEmpty {
                    Label("Unavailable: this video has no mature-scene timestamps", systemImage: "exclamationmark.triangle")
                } else if sceneMarkersLoaded {
                    Text("\(matureSceneRanges.count) timed scene(s) ready to skip")
                } else {
                    Text("Checking available scene timestamps…")
                }
                Text("Provider timestamps and applicable MovieHavenDB movie data (CC BY 4.0) may be used. TV-series mature-scene coverage is currently limited. No automatic video scanning.")
            }
            Section("Accurate intro skipping") {
                Toggle("Use community intro timings", isOn: $useCommunityIntro)
                Text(introLookupStatus)
                Text("Checks SkipDB (ODbL 1.0) and IntroDB for intro, recap, credits, and previews. Requests only IMDb ID, episode and duration. Different video cuts may not align; no guessed skips.")
            }
            Section("Playback") {
                speedMenu
                if !isDownloaded && !session.streams.isEmpty { qualityMenu }
                audioMenu
                Button(cropVideo ? "Fit original aspect ratio" : "Fill screen (crop edges)") {
                    cropVideo.toggle()
                }
            }
            Section("Captions & chapters") {
                subtitleMenu
            }
            Section("More") {
                Button { locked = true; showControls() } label: {
                    Label("Lock controls", systemImage: "lock")
                }
                Button { library.markWatched(current, watched: !library.isWatched(current.id)) } label: {
                    Label(library.isWatched(current.id) ? "Unmark watched" : "Mark watched",
                          systemImage: "checkmark.circle")
                }
                Button {
                    showDiagnostics = true
                    showControls()
                } label: {
                    Label("Playback diagnostics", systemImage: "waveform.path.ecg")
                }
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Player settings, including maturity filter")
    }

    private var speedMenu: some View {
        Menu("Playback speed") {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                Button {
                    setSpeed(value)
                } label: {
                    if abs(savedSpeed - value) < 0.01 {
                        Label("\(value.formatted())×", systemImage: "checkmark")
                    } else {
                        Text("\(value.formatted())×")
                    }
                }
            }
        }
    }

    private var qualityMenu: some View {
        Menu("Video quality") {
            ForEach(session.streams) { stream in
                Button {
                    let position = livePosition()
                    session.select(stream, video: current, library: library)
                    // Session retains the last playing position during the switch.
                    currentTime = position
                    showControls()
                } label: {
                    if stream.id == session.selected?.id {
                        Label(stream.label, systemImage: "checkmark")
                    } else {
                        Text(stream.label)
                    }
                }
            }
        }
    }

    private var subtitleMenu: some View {
        Menu("Subtitles") {
            Button {
                chooseCaption(nil)
            } label: {
                if subtitles.selected == nil && selectedCaption == nil {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }
            Button { importingSubtitles = true } label: {
                Label("Import SRT / VTT from Files", systemImage: "doc.badge.plus")
            }
            if !subtitles.available.isEmpty {
                Menu("Provider subtitles") {
                    ForEach(subtitles.available) { item in
                        Button {
                            chooseExternal(item)
                        } label: {
                            if subtitles.selected?.id == item.id {
                                Label(item.name, systemImage: "checkmark")
                            } else {
                                Text(item.name)
                            }
                        }
                    }
                }
            }
            if !captions.isEmpty {
                Menu("Built-in subtitles") {
                    ForEach(captions.indices, id: \.self) { index in
                        Button(captions[index].displayName) { chooseCaption(captions[index]) }
                    }
                }
            }
            if subtitles.selected != nil {
                Toggle("Subtitle background", isOn: $captionBackdrop)
                Menu("Subtitle timing") {
                    Button("Show 0.5 s earlier") { subtitles.adjustOffset(by: -0.5); showControls() }
                    Button("Show 0.5 s later") { subtitles.adjustOffset(by: 0.5); showControls() }
                    Button("Reset (\(subtitles.offset.formatted()) s)") {
                        subtitles.adjustOffset(by: -subtitles.offset)
                        showControls()
                    }
                }
                Menu("Subtitle size") {
                    ForEach([("Small", 0.8), ("Medium", 1.0), ("Large", 1.3), ("Extra large", 1.6)], id: \.0) { entry in
                        Button {
                            subtitleScale = entry.1
                        } label: {
                            if abs(subtitleScale - entry.1) < 0.01 {
                                Label(entry.0, systemImage: "checkmark")
                            } else {
                                Text(entry.0)
                            }
                        }
                    }
                }
            }
            if subtitles.available.isEmpty && captions.isEmpty {
                Text(subtitles.loading ? "Looking for subtitles…" : "No subtitles available")
            }
            if let failure = subtitles.failure { Text(failure) }
        }
    }

    private var audioMenu: some View {
        Menu("Audio track") {
            if audioTracks.isEmpty { Text("Default audio") }
            ForEach(audioTracks.indices, id: \.self) { index in
                Button(audioTracks[index].displayName) { chooseAudio(audioTracks[index]) }
            }
        }
    }

    private func overlayButton(_ symbol: String, label: String, size: CGFloat = 21,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    // MARK: Playback actions

    private func livePosition() -> Double {
        let value = session.player?.currentTime().seconds ?? currentTime
        return value.isFinite ? value : currentTime
    }

    private func togglePlayback() {
        guard let player = session.player else { return }
        if playing { player.pause() }
        else {
            if duration > 0, livePosition() >= duration - 0.5 { seek(to: 0) }
            player.defaultRate = speed
            player.play()
        }
        playing.toggle()
        showControls()
    }

    private func setSpeed(_ value: Double) {
        savedSpeed = value
        session.player?.defaultRate = Float(value)
        if playing { session.player?.rate = Float(value) }
        showControls()
    }

    private func updateProgress() {
        guard let player = session.player else {
            stalledSince = nil
            watchedPlayerID = nil
            return
        }
        let playerID = ObjectIdentifier(player)
        if watchedPlayerID != playerID {
            watchedPlayerID = playerID
            stalledSince = nil
            // Invalidate completion callbacks from a previous video/quality.
            seekRequestID &+= 1
            seekInFlight = false
            bufferedUntil = 0
        }
        if player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
           player.currentItem?.status == .readyToPlay, scenePhase == .active {
            if let start = stalledSince {
                if Date().timeIntervalSince(start) > 14 {
                    stalledSince = nil
                    session.recoverFromStall(library: library)
                }
            } else {
                stalledSince = Date()
            }
        } else {
            stalledSince = nil
        }
        let time = player.currentTime().seconds
        if time.isFinite && time >= 0 && !isScrubbing && !seekInFlight {
            currentTime = time
            seekPreview = time
        }
        let length = player.currentItem?.duration.seconds ?? 0
        duration = length.isFinite && length > 0 ? length : 0
        if skipMatureScenes && !seekInFlight && !isScrubbing,
           let scene = SceneSkipPlanner.active(matureSceneRanges, at: currentTime, duration: duration),
           !alreadySkippedScenes.contains(scene.identifier) {
            alreadySkippedScenes.insert(scene.identifier)
            seek(to: scene.end)
            flashMessage("Skipped a marked mature scene")
        }
        if let lastRange = player.currentItem?.loadedTimeRanges.last?.timeRangeValue {
            let end = CMTimeGetSeconds(CMTimeRangeGetEnd(lastRange))
            if end.isFinite { bufferedUntil = max(0, end) }
        }
        let nowPlaying = player.rate > 0
        if nowPlaying && appliedPlayer != ObjectIdentifier(player) {
            // Re-apply the remembered speed to every new player instance (quality change, next episode).
            appliedPlayer = ObjectIdentifier(player)
            player.defaultRate = speed
            if speed != 1 { player.rate = speed }
        }
        if nowPlaying != playing {
            playing = nowPlaying
            if nowPlaying { scheduleAutoHide() }
            else { hideTask?.cancel(); showsControls = true }
        }
        waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    private func seek(to value: Double) {
        guard let targetPlayer = session.player, value.isFinite, duration > 0 else { return }
        let bounded = max(0, min(value, duration))
        seekRequestID &+= 1
        let requestID = seekRequestID
        seekInFlight = true
        isScrubbing = false
        currentTime = bounded
        seekPreview = bounded
        // Repeated taps / new slider drags replace old seek requests.
        targetPlayer.currentItem?.cancelPendingSeeks()
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        targetPlayer.seek(to: CMTime(seconds: bounded, preferredTimescale: 600),
                          toleranceBefore: tolerance, toleranceAfter: tolerance) { completed in
            Task { @MainActor in
                guard seekRequestID == requestID, session.player === targetPlayer else { return }
                seekInFlight = false
                let actual = targetPlayer.currentTime().seconds
                if actual.isFinite && actual >= 0 {
                    currentTime = actual
                    seekPreview = actual
                }
                if completed { session.save(library: library) }
                refreshNowPlaying()
            }
        }
        // Malformed streams sometimes never deliver a seek completion.
        // Unlock the timeline without treating the seek as successful.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, seekRequestID == requestID, seekInFlight else { return }
            seekInFlight = false
        }
        if upNext != nil { cancelUpNext() }
        showControls()
    }

    private func refreshNowPlaying() {
        guard session.player != nil else { return }
        NowPlayingBridge.shared.update(video: current, position: livePosition(),
                                       duration: duration,
                                       rate: playing ? (session.player?.rate ?? 1) : 0)
    }

    // MARK: Episodes

    private func play(_ next: Video) {
        cancelUpNext()
        session.player?.pause()
        playing = false
        currentTime = 0
        seekPreview = 0
        duration = 0
        seekInFlight = false
        seekRequestID &+= 1
        captions = []
        audioTracks = []
        selectedCaption = nil
        selectedAudio = nil
        matureSceneRanges = []
        providerIntroEnd = nil
        metadataIMDbID = nil
        introSegment = nil
        externalMarkers = []
        providerMatureRanges = []
        introLookupKey = nil
        sceneMarkersLoaded = false
        alreadySkippedScenes = []
        introSkipUsed = false
        current = next
        showControls()
    }

    private func beginUpNext(_ next: Video) {
        guard upNext == nil else { return }
        upNext = next
        countdown = 8
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                countdown -= 1
            }
            if !Task.isCancelled, upNext?.id == next.id { play(next) }
        }
    }

    private func cancelUpNext() {
        countdownTask?.cancel()
        countdownTask = nil
        upNext = nil
    }

    // MARK: Chrome visibility

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.16)) { showsControls.toggle() }
        if showsControls { scheduleAutoHide() }
        else { hideTask?.cancel() }
    }

    private func showControls() {
        withAnimation(.easeOut(duration: 0.16)) { showsControls = true }
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard playing && !isScrubbing else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { showsControls = false }
        }
    }

    private var diagnosticsReport: String {
        var lines = [
            "Title: \(current.title)",
            "Source: \(isDownloaded ? "Offline" : (session.selected?.label ?? "Unknown"))",
            "Player state: \(waiting ? "Buffering" : (playing ? "Playing" : "Paused"))",
            "Recoveries: \(session.recoveryCount)",
            "Network: \(session.player?.isExternalPlaybackActive == true ? "External playback" : "On device")",
            "Position: \(formatTime(currentTime)) / \(formatTime(duration))"
        ]
        if let reason = session.lastRecoveryReason { lines.append("Last recovery: \(reason)") }
        if let event = session.player?.currentItem?.accessLog()?.events.last {
            lines.append("Observed bitrate: \(Int(max(0, event.observedBitrate / 1000))) kb/s")
            lines.append("Stream stalls: \(event.numberOfStalls)")
            lines.append("Dropped frames: \(event.numberOfDroppedVideoFrames)")
        }
        if let error = session.error { lines.append("Error: \(error)") }
        return lines.joined(separator: "\n")
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let x = Int(seconds)
        if x >= 3600 { return String(format: "%d:%02d:%02d", x / 3600, (x % 3600) / 60, x % 60) }
        return String(format: "%d:%02d", x / 60, x % 60)
    }

    private func closePlayer() {
        hideTask?.cancel()
        session.close(library: library)
        dismiss()
    }

    // MARK: Tracks

    private func loadTracks() async {
        captions = []
        audioTracks = []
        guard let item = session.player?.currentItem else { return }
        // The AVAsset async APIs avoid blocking the rendering/UI thread.
        let asset = item.asset
        let caption = try? await asset.loadMediaSelectionGroup(for: .legible)
        let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
        guard session.player?.currentItem === item else { return }
        captionGroup = caption
        audioGroup = audible
        captions = caption?.options ?? []
        audioTracks = audible?.options ?? []
    }

    /// Selects a built-in subtitle (or turns every subtitle off when `option` is nil).
    private func chooseCaption(_ option: AVMediaSelectionOption?) {
        if let group = captionGroup {
            session.player?.currentItem?.select(option, in: group)
        }
        selectedCaption = option
        Task { await subtitles.select(nil) }
        showControls()
    }

    private func chooseExternal(_ subtitle: Subtitle) {
        if let group = captionGroup {
            session.player?.currentItem?.select(nil, in: group)
        }
        selectedCaption = nil
        Task { await subtitles.select(subtitle) }
        showControls()
    }

    private func chooseAudio(_ option: AVMediaSelectionOption) {
        if let group = audioGroup {
            session.player?.currentItem?.select(option, in: group)
        }
        selectedAudio = option
        showControls()
    }
}
