import SwiftUI
import WebKit
import AVKit
import UIKit

// Independent CEE edition. All browsing remains on CEE's own site/session.
// No Cinemana/Shabakaty catalog or stream endpoints are used here.
private enum CEETheme {
    static let red = Color(red: 0.95, green: 0.15, blue: 0.21)
    static let background = Color(red: 0.055, green: 0.014, blue: 0.022)
    static let surface = Color(red: 0.14, green: 0.065, blue: 0.078)
}
private enum CEEAddress {
    static let primary = URL(string: "https://cee.buzz/home")!
    static let mirror = URL(string: "https://cee.buzz.iraq.soft31.com/2")!
    static func isMedia(_ url: URL) -> Bool {
        ["mp4", "m4v", "mov", "m3u8"].contains(url.pathExtension.lowercased())
    }
    static func canDownload(_ url: URL) -> Bool {
        ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) &&
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}

private struct CEEPoster: Codable, Identifiable, Equatable {
    let title: String
    let link: URL
    let poster: URL?
    var id: String { link.absoluteString }
}
private struct CEEStream: Identifiable {
    let url: URL
    let id = UUID()
}

private final class CEEBookmarks: ObservableObject {
    @Published private(set) var saved: [CEEPoster] = []
    init() {
        if let data = UserDefaults.standard.data(forKey: "cee-ios-bookmarks"),
           let decoded = try? JSONDecoder().decode([CEEPoster].self, from: data) {
            saved = decoded
        }
    }
    func contains(_ item: CEEPoster) -> Bool { saved.contains(where: { $0.id == item.id }) }
    func toggle(_ item: CEEPoster) {
        if contains(item) { saved.removeAll(where: { $0.id == item.id }) }
        else { saved.insert(item, at: 0) }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "cee-ios-bookmarks")
        }
    }
}

private final class CEEBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var posters: [CEEPoster] = []
    @Published var loading = false
    @Published var pageTitle = "CEE"
    @Published var canGoBack = false
    @Published var errorMessage: String?
    @Published var playback: CEEStream?
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    func load(_ url: URL) {
        guard url.scheme == "https" else { return }
        errorMessage = nil
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
    }
    func reload() { webView.reload() }
    func back() { if webView.canGoBack { webView.goBack() } }
    func open(_ poster: CEEPoster) { load(poster.link) }
    func scan() {
        let js = #"""
        (function() {
          const out = [], seen = new Set();
          for (const a of document.querySelectorAll('a[href]')) {
            if (out.length >= 250) break;
            const img = a.querySelector('img');
            if (!img) continue;
            const href = a.href || '';
            if (!/^https?:\/\//i.test(href) || seen.has(href)) continue;
            const src = img.currentSrc || img.src || img.getAttribute('data-src') || '';
            const title = (a.getAttribute('aria-label') || img.alt || a.getAttribute('title') || a.innerText || '').trim().slice(0, 150);
            if (!title || title.length < 2 || !/^https?:\/\//i.test(src)) continue;
            seen.add(href);
            out.push({title: title, link: href, poster: src});
          }
          return JSON.stringify(out);
        })();
        """#
        webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let str = value as? String, let data = str.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([CEEPoster].self, from: data) else { return }
            DispatchQueue.main.async { self?.posters = parsed }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async { self.loading = true; self.errorMessage = nil }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.loading = false
            self.pageTitle = webView.title ?? "CEE"
            self.canGoBack = webView.canGoBack
            self.scan()
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { self.loading = false; self.errorMessage = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { self.loading = false; self.errorMessage = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, CEEAddress.isMedia(url) {
            DispatchQueue.main.async { self.playback = CEEStream(url: url) }
            decisionHandler(.cancel)
            return
        }
        if action.targetFrame == nil, let url = action.request.url {
            webView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { load(url) }
        return nil
    }
}

private struct CEEWebContainer: UIViewRepresentable {
    @ObservedObject var browser: CEEBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private final class CEEDirectDownloads: ObservableObject {
    @Published var message: String?
    func save(_ url: URL) {
        guard CEEAddress.canDownload(url) else { message = "Not a direct downloadable video file"; return }
        message = "Downloading…"
        URLSession.shared.downloadTask(with: url) { [weak self] location, response, error in
            var status = "Download failed"
            if let location {
                let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("CEE Downloads", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let name = response?.suggestedFilename ?? url.lastPathComponent
                    let destination = folder.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: location, to: destination)
                    status = "Saved to CEE Downloads"
                } catch { status = error.localizedDescription }
            } else if let error { status = error.localizedDescription }
            DispatchQueue.main.async { self?.message = status }
        }.resume()
    }
}

private struct CEENativePlayer: View {
    let stream: CEEStream
    let download: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    Spacer()
                    if CEEAddress.canDownload(stream.url) {
                        Button { download(stream.url) } label: { Image(systemName: "arrow.down.circle.fill").font(.title2) }
                    }
                }
                .padding(20)
                Spacer()
            }
            .tint(.white)
        }
        .onAppear { player = AVPlayer(url: stream.url); player?.play() }
        .onDisappear { player?.pause(); player = nil }
    }
}

private enum CEETab: String, CaseIterable, Identifiable {
    case discover, saved, website, settings
    var id: String { rawValue }
    var icon: String {
        switch self { case .discover: return "square.grid.2x2.fill"
        case .saved: return "bookmark.fill"
        case .website: return "globe"
        case .settings: return "gearshape.fill" }
    }
}

struct CinemanaCEEApplication: App {
    var body: some Scene {
        WindowGroup { CEEMainScreen().preferredColorScheme(.dark) }
    }
}

private struct CEEMainScreen: View {
    @StateObject private var browser = CEEBrowser()
    @StateObject private var bookmarks = CEEBookmarks()
    @StateObject private var downloads = CEEDirectDownloads()
    @State private var tab: CEETab = .discover
    @State private var search = ""
    @AppStorage("cee-ios-language") private var language = "system"
    @AppStorage("cee-ios-mirror") private var mirror = false
    @AppStorage("cee-ios-welcome") private var welcomed = false
    @State private var showWelcome = false

    private var arabic: Bool { language == "ar" || (language == "system" && Locale.current.languageCode == "ar") }
    private func word(_ english: String, _ ar: String) -> String { arabic ? ar : english }
    private func name(_ tab: CEETab) -> String {
        switch tab {
        case .discover: return word("Discover", "اكتشف")
        case .saved: return word("Saved", "المحفوظة")
        case .website: return word("Website", "الموقع")
        case .settings: return word("Settings", "الإعدادات")
        }
    }
    private var shown: [CEEPoster] {
        let items = tab == .saved ? bookmarks.saved : browser.posters
        if search.isEmpty { return items }
        return items.filter { $0.title.localizedStandardContains(search) }
    }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 172 : 124), spacing: 12)]
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CEEWebContainer(browser: browser)
                    .opacity(tab == .website ? 1 : 0.002)
                    .allowsHitTesting(tab == .website)
                    .accessibilityHidden(tab != .website)
                if tab != .website {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        switch tab {
                        case .discover, .saved: posterGrid
                        case .settings: settings
                        case .website: EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(CEETheme.background)
                } else {
                    VStack {
                        HStack {
                            Button { browser.back() } label: { Image(systemName: "chevron.left") }
                                .disabled(!browser.canGoBack)
                            Button { browser.load(mirror ? CEEAddress.mirror : CEEAddress.primary) } label: { Image(systemName: "house") }
                            Text(browser.pageTitle).font(.subheadline).lineLimit(1).frame(maxWidth: .infinity)
                            if browser.loading { ProgressView().tint(CEETheme.red) }
                            Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                        }
                        .padding(12)
                        .background(CEETheme.surface)
                        Spacer()
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(CEETab.allCases) { next in
                    Button {
                        tab = next
                        if next == .discover { browser.scan() }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: next.icon).font(.system(size: 19))
                            Text(name(next)).font(.system(size: 11)).lineLimit(1)
                        }
                        .foregroundColor(tab == next ? CEETheme.red : .gray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 53)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 7).background(CEETheme.surface)
        }
        .background(CEETheme.background)
        .tint(CEETheme.red)
        .onAppear {
            if browser.webView.url == nil { browser.load(mirror ? CEEAddress.mirror : CEEAddress.primary) }
            if !welcomed { welcomed = true; showWelcome = true }
        }
        .fullScreenCover(item: $browser.playback) { stream in
            CEENativePlayer(stream: stream, download: { downloads.save($0) })
        }
        .sheet(isPresented: $showWelcome) {
            CEEWelcomeCard(arabic: arabic)
                .presentationDetents([.medium, .large])
        }
        .alert(word("Download", "التنزيل"), isPresented: Binding(
            get: { downloads.message != nil && downloads.message != "Downloading…" },
            set: { if !$0 { downloads.message = nil } }
        )) {
            Button("OK") { downloads.message = nil }
        } message: { Text(downloads.message ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "play.rectangle.fill").foregroundColor(CEETheme.red)
                Text("CINEMANA  |  CEE").font(.system(.title3, design: .rounded, weight: .black))
                Spacer()
                if browser.loading { ProgressView().tint(CEETheme.red) }
                Button { browser.reload(); browser.scan() } label: { Image(systemName: "arrow.clockwise") }
            }
            if tab == .discover || tab == .saved {
                TextField(word("Search loaded titles", "ابحث بالعناوين المحملة"), text: $search)
                    .textInputAutocapitalization(.never)
                    .padding(11)
                    .background(CEETheme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
    }

    private var posterGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                if shown.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tab == .saved ? word("No saved titles", "ماكو عناوين محفوظة") :
                                word("No posters found yet", "ما لكينا بوسترات بعد"))
                            .font(.headline)
                        Text(word("Open CEE Website to browse everything. Native discovery only displays posters that the website exposes with working links.",
                                  "افتح موقع CEE لتصفح المحتوى. واجهة الاكتشاف تعرض فقط الصور والروابط اللي يتيحها الموقع."))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(word("Open website", "افتح الموقع")) { tab = .website }
                            .buttonStyle(.borderedProminent).tint(CEETheme.red)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CEETheme.surface, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    LazyVGrid(columns: columns, spacing: 15) {
                        ForEach(shown) { item in
                            VStack(spacing: 7) {
                                Button {
                                    browser.open(item)
                                    tab = .website
                                } label: {
                                    AsyncImage(url: item.poster) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(CEETheme.surface)
                                            .overlay(Image(systemName: "film").foregroundStyle(.gray))
                                    }
                                    .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 244 : 179)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                HStack(alignment: .top) {
                                    Text(item.title).font(.caption.weight(.medium)).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button { bookmarks.toggle(item) } label: {
                                        Image(systemName: bookmarks.contains(item) ? "bookmark.fill" : "bookmark")
                                            .foregroundColor(CEETheme.red)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                if let error = browser.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
            }
            .padding(16)
        }
        .refreshable { browser.reload() }
    }

    private var settings: some View {
        Form {
            Section(word("Language", "اللغة")) {
                Picker(word("Interface", "الواجهة"), selection: $language) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("العربية").tag("ar")
                }
            }
            Section(word("CEE source", "مصدر CEE")) {
                Toggle(word("Use supplied mirror", "استخدم الرابط البديل"), isOn: $mirror)
                Button(word("Load selected source", "افتح المصدر المختار")) {
                    browser.load(mirror ? CEEAddress.mirror : CEEAddress.primary)
                    tab = .website
                }
            }
            Section(word("Playback & downloads", "التشغيل والتنزيل")) {
                Text(word("Direct MP4/HLS links open in the iOS player. Embedded and protected streams remain on CEE's website.",
                          "روابط MP4 و HLS المباشرة تشتغل بمشغل iOS. بقية الفيديوهات تشتغل داخل موقع CEE."))
                Text(word("Direct-file downloads are stored in this app's Documents folder.",
                          "الملفات المباشرة المحملة تنحفظ داخل مستندات التطبيق."))
            }
            Section { Text("CEE Edition 0.1.0 — separate from original Cinemana iOS").font(.footnote) }
        }
        .scrollContentBackground(.hidden)
        .background(CEETheme.background)
    }
}

private struct CEEWelcomeCard: View {
    let arabic: Bool
    @Environment(\.dismiss) private var dismiss
    private func t(_ en: String, _ ar: String) -> String { arabic ? ar : en }
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "play.rectangle.fill").font(.largeTitle).foregroundColor(CEETheme.red)
                    VStack(alignment: .leading) {
                        Text("CINEMANA  |  CEE").font(.title2.bold())
                        Text(t("iPhone & iPad", "للآيفون والآيباد")).foregroundStyle(.secondary)
                    }
                }
                Text(t("The Cinemana experience, connected to the CEE website.",
                       "واجهة سينمانا متصلة بموقع CEE."))
                    .font(geometry.size.width > 600 ? .title : .title3)
                Text(t("Discover titles, save favorites and watch through CEE. Playback availability depends on the website.",
                       "تصفح العناوين واحفظ المفضلة وتابع عبر CEE. توفر التشغيل يعتمد على الموقع."))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(t("Start browsing", "ابدأ التصفح")) { dismiss() }
                    .buttonStyle(.borderedProminent).tint(CEETheme.red)
                    .frame(maxWidth: .infinity)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CEETheme.background)
        }
        .preferredColorScheme(.dark)
    }
}
