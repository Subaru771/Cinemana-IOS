import SwiftUI
import Foundation
import UIKit

/// Non-invasive diagnostic: checks the published catalog endpoint only.
/// It does not route around ISP policies, test arbitrary third-party hosts,
/// or send user/device information to any new service.
struct ConnectionDiagnosticsView: View {
    @State private var checking = false
    @State private var result = "Run the connection test to check catalog access."
    @State private var lastChecked: Date?
    @State private var succeeded: Bool?

    private let catalogURL = URL(string:
        "https://cinemana.shabakaty.com/api/android/video/videoKind/1/categoryNb/0/langNb/0/sortParam/views_desc/itemsPerPage/20/searchTextValue/-/pageNumber/0"
    )!

    var body: some View {
        Form {
            Section("Catalog server") {
                Label(succeeded == nil ? "Not checked" : (succeeded == true ? "Reachable" : "Unavailable"),
                      systemImage: succeeded == nil ? "questionmark.circle" : (succeeded == true ? "checkmark.circle" : "exclamationmark.triangle"))
                    .foregroundStyle(succeeded == false ? Color.orange : Color.primary)
                Text(result).font(.footnote).textSelection(.enabled)
                if let lastChecked {
                    Text(lastChecked.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { await run() }
                } label: {
                    if checking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Checking…")
                        }
                    } else {
                        Label("Check connection", systemImage: "network")
                    }
                }
                .disabled(checking)
                Button("Copy result") { UIPasteboard.general.string = result }
                    .disabled(lastChecked == nil)
            }
            Section("Media streaming") {
                Text("Media streams may use different servers. A successful catalog test does not guarantee playback.")
                Text("For a video-specific report, open the video player, then Player settings → Playback diagnostics.")
            }
            Section {
                Text("This check tests the catalog only, not video playback or ISP authorization for every media server.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Network diagnostics")
    }

    @MainActor
    private func run() async {
        guard !checking else { return }
        checking = true
        defer { checking = false; lastChecked = Date() }
        let start = Date()
        var request = URLRequest(url: catalogURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                succeeded = false
                result = "The catalog did not return a valid HTTP response."
                return
            }
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            switch http.statusCode {
            case 200..<300:
                guard (try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])) != nil else {
                    succeeded = false
                    result = "Catalog responded in \(elapsed) ms, but did not return usable JSON."
                    return
                }
                succeeded = true
                result = "Catalog reachable. HTTP \(http.statusCode), \(elapsed) ms. Other video servers may still be restricted."
            case 401:
                succeeded = false
                result = "Catalog requires provider authorization (HTTP 401)."
            case 403, 451:
                succeeded = false
                result = "Provider denied this network/request (HTTP \(http.statusCode))."
            default:
                succeeded = false
                result = "Catalog HTTP \(http.statusCode) after \(elapsed) ms."
            }
        } catch let error as URLError {
            succeeded = false
            switch error.code {
            case .timedOut: result = "Catalog request timed out after 12 seconds."
            case .cannotFindHost, .dnsLookupFailed: result = "Cannot resolve the catalog server (DNS issue)."
            case .notConnectedToInternet: result = "Device is offline."
            default: result = "Catalog connection failed: \(error.localizedDescription)"
            }
        } catch {
            succeeded = false
            result = "Catalog connection failed: \(error.localizedDescription)"
        }
    }
}
