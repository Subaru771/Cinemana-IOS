import SwiftUI
import WebKit
import AVKit

/// CEE's website is the provider. Never call Cinemana/Shabakaty endpoints.
/// This bridge exposes only titles actually found in its live DOM.
@MainActor final class CEESite: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = CEESite()
    @Published private(set) var titles: [Video] = []
    @Published var loading = false
    @Published var error: String?
    @Published var pageTitle = "CEE"
    let browser: WKWebView
    private(set) var isStarted = false
    private var cards: [Int: URL] = [:]

    override private init() {
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .default()
        settings.allowsInlineMediaPlayback = true
        settings.mediaTypesRequiringUserActionForPlayback = []
        browser = WKWebView(frame: .zero, configuration: settings)
        super.init()
        browser.navigationDelegate = self
        browser.uiDelegate = self
        browser.allowsBackForwardNavigationGestures = true
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        openHome()
    }

    func openHome() {
        guard let url = URL(string: "https://cee.buzz/home") else { return }
        loading = true
        browser.load(URLRequest(url: url))
    }

    func scan() {
        let js = #"""
        (function () {
          const results = [], seen = new Set();
          // Rebuild markers on each scan: site is frequently re-rendered by React.
          document.querySelectorAll('[data-cee-ios-index]').forEach(e => e.removeAttribute('data-cee-ios-index'));
          function add(el, img) {
            if (!el || !img || results.length >= 180) return;
            const src = img.currentSrc || img.src || img.getAttribute('data-src') || '';
            if (!/^https?:\/\//i.test(src)) return;
            const title = (el.getAttribute('aria-label') || el.getAttribute('title') || img.alt || el.innerText || '').replace(/\s+/g,' ').trim().slice(0,140);
            if (title.length < 2 || /^(image|poster|cover|movie|film)$/i.test(title)) return;
            const href = el.href || el.getAttribute('href') || '';
            let link = ''; try { link = href ? new URL(href, document.baseURI).href : ''; } catch(e) {}
            const key = title.toLowerCase() + '|' + src;
            if (seen.has(key)) return;
            seen.add(key);
            const index = results.length;
            el.setAttribute('data-cee-ios-index', String(index));
            results.push({title, image:src, link, index});
          }
          for (const img of document.querySelectorAll('img')) {
            let el = img.closest('a[href],button,[role="button"],[onclick],.poster,.card') || img.parentElement;
            for (let p=img.parentElement, depth=0;p && depth<4; p=p.parentElement,depth++) {
              if (p.onclick || window.getComputedStyle(p).cursor === 'pointer') {el=p;break;}
            }
            add(el,img);
          }
          window.__ceeOpenCard = function(i) {
            const e = document.querySelector('[data-cee-ios-index="'+ Number(i) +'"]');
            if (!e) return false;
            e.scrollIntoView({block:'center',behavior:'instant'}); e.click(); return true;
          };
          return JSON.stringify(results);
        })();
        """#
        browser.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self, let string = result as? String,
                  let data = string.data(using: .utf8),
                  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            var list: [Video] = []
            var links: [Int: URL] = [:]
            for item in items {
                guard let title = item["title"] as? String,
                      let poster = item["image"] as? String,
                      let idx = item["index"] as? Int else { continue }
                let link = item["link"] as? String ?? ""
                let json: [String: Any] = [
                    "nb": "cee:\(idx):\(title)",
                    "title": title,
                    "imgMediumThumbObjUrl": poster,
                    "imgObjUrl": poster,
                    "videoKind": "1"
                ]
                if let video = Video(json: json) { list.append(video) }
                if let url = URL(string: link), ["https","http"].contains(url.scheme ?? "") {links[idx]=url}
            }
            if !list.isEmpty {
                self.titles = list
                self.cards = links
                self.error = nil
            }
        }
    }

    func open(_ video: Video) {
        start()
        guard video.id.hasPrefix("cee:") else { return }
        let components = video.id.split(separator: ":")
        guard components.count >= 2, let index = Int(components[1]) else { return }
        if let url = cards[index] {
            browser.load(URLRequest(url: url))
        } else {
            browser.evaluateJavaScript("window.__ceeOpenCard && window.__ceeOpenCard(\(index))") { _, _ in }
        }
    }

    func awaitTitles() async throws -> [Video] {
        start()
        if !titles.isEmpty { return titles }
        // Deliberately bounded; never invent empty titles or use a different provider.
        for _ in 0..<22 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(500))
            if !titles.isEmpty { return titles }
            if error != nil { break }
        }
        throw NSError(domain: "CEE", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "CEE is not showing discoverable titles. Open its website to browse."])
    }

    func search(_ query: String) async -> [Video] {
        let all = (try? await awaitTitles()) ?? titles
        return all.filter { $0.title.localizedStandardContains(query) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        pageTitle = webView.title ?? "CEE"
        scan()
        // Reactive sites may mount posters after the navigation finishes.
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            scan()
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError err: Error) {
        loading = false; error = err.localizedDescription
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError err: Error) {
        loading = false; error = err.localizedDescription
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { browser.load(URLRequest(url: url)) }
        return nil
    }

    nonisolated static func catalogStream(_ kind: Int?) -> AsyncThrowingStream<CatalogRow, Error> {
        AsyncThrowingStream { continuation in
            let job = Task { @MainActor in
                do {
                    let titles = try await CEESite.shared.awaitTitles()
                    let label = kind == 2 ? "Series" : "Movies"
                    // The website doesn't reveal title type reliably. Don't fabricate a series classification.
                    if kind != 2 {
                        continuation.yield(CatalogRow(title:"Trending \(label)", videos:Array(titles.prefix(40))))
                        if titles.count > 40 {
                            continuation.yield(CatalogRow(title:"New \(label)", videos:Array(titles.dropFirst(40).prefix(40))))
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing:error) }
            }
            continuation.onTermination = { _ in job.cancel() }
        }
    }
}

struct CEESharedBrowser: UIViewRepresentable {
    @ObservedObject var site: CEESite
    func makeUIView(context: Context) -> WKWebView { site.browser }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct CEEWebsiteView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var site = CEESite.shared
    var startVideo: Video?
    @State private var firstAppear = true
    var body: some View {
        NavigationStack {
            CEESharedBrowser(site: site)
                .background(Color(red:0.052,green:0.013,blue:0.018))
                .ignoresSafeArea(edges:.bottom)
                .navigationTitle(site.pageTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        Button { if site.browser.canGoBack { site.browser.goBack() } } label: { Image(systemName:"chevron.left") }
                        Button { site.openHome() } label: { Image(systemName:"house") }
                        Button { site.browser.reload() } label: { Image(systemName:"arrow.clockwise") }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if firstAppear {
                firstAppear=false
                if let startVideo { site.open(startVideo) }
                else { site.start() }
            }
        }
    }
}

/// Native detail layout uses the original Cinemana artwork component and controls.
/// CEE website retains its own playback, DRM and server selection.
struct CEEVideoDetail: View {
    let video: Video
    @EnvironmentObject private var library: LibraryStore
    @State private var showPlayer=false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                RemotePoster(url:video.backdrop ?? video.poster)
                    .frame(height:240).clipped()
                VStack(alignment:.leading,spacing:15) {
                    Text(video.title).font(.largeTitle.weight(.bold))
                    HStack(spacing:12) {
                        Button {showPlayer=true} label: {
                            Label("Play on CEE",systemImage:"play.fill")
                                .frame(maxWidth:.infinity).padding(7)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red:1,green:0.18,blue:0.25))
                        Button {library.toggle(video)} label: {
                            Image(systemName:library.isSaved(video) ? "bookmark.fill":"bookmark")
                                .frame(width:50,height:40)
                        }.buttonStyle(.bordered)
                    }
                    Text("Playback is provided by CEE. Stream quality, available subtitles and episode selection depend on the website.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.horizontal,16)
            }
        }
        .background(Color(red:0.052,green:0.013,blue:0.018))
        .navigationTitle(video.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented:$showPlayer) { CEEWebsiteView(startVideo:video) }
    }
}

/// Switch destinations without changing any of the original Cinemana navigation,
/// poster cards, saved list, or tab structure.
struct CEEDestination: View {
    let video: Video
    var seriesContext: Bool = false
    @ViewBuilder var body: some View {
        if video.id.hasPrefix("cee:") {
            CEEVideoDetail(video: video)
        } else {
            MovieDetailView(video: video, seriesContext: seriesContext)
        }
    }
}
