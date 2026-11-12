import SwiftUI
import Foundation
import CryptoKit
import UIKit

// Noncommercial adaptation of SideInstaller by FrizzleM.
// All pairing, signing and installation are handled by its local engine.
@MainActor
struct CinemanaSetupView: View {
    @Environment(Engine.self) private var engine
    @Environment(\.openURL) private var openURL
    @AppStorage("cinemanaArabic") private var arabic = false
    @AppStorage("cinemanaIncludeSideStore") private var includeSideStore = false
    private enum Phase: Equatable { case idle, sideStore, download, cinemana, done, failed }
    @State private var phase: Phase = .idle
    @State private var message = ""
    @AppStorage("cinemanaSideStoreCompletedAccount") private var completedAccount = ""
    @State private var showSettings = false
    @State private var continueAfterAccount = false
    @State private var currentFlowIncludesSideStore = false
    @State private var runningAccountKey = ""

    private var accountKey: String {
        let email = engine.appleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return "" }
        return SHA256.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private var accountReady: Bool { !accountKey.isEmpty && !engine.applePassword.isEmpty }
    private var sideStoreReady: Bool {
        !accountKey.isEmpty && completedAccount == accountKey &&
        UIApplication.shared.canOpenURL(URL(string: "sidestore://")!)
    }

    private func t(_ en: String, _ ar: String) -> String { arabic ? ar : en }
    private var busy: Bool { [.sideStore, .download, .cinemana].contains(phase) }

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.075, blue: 0.055).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Label("CINEMANA", systemImage: "play.rectangle.fill")
                            .font(.headline.bold()).tracking(2)
                        Spacer()
                        Button(arabic ? "English" : "عربي") { arabic.toggle() }
                            .buttonStyle(.bordered)
                    }
                    .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("IPHONE INSTALLER", "التثبيت من الآيفون"))
                            .font(.caption.bold()).tracking(2).foregroundStyle(.mint)
                        Text(t("Install Cinemana", "ثبّت سينمانا"))
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                        Text(t("One action to download, verify, sign and install. We guide you through Apple’s required approvals.",
                               "بخطوة واحدة: تنزيل وفحص وتوقيع وتثبيت سينمانا، مع إرشادك لتأكيدات Apple المطلوبة."))
                            .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    }
                    .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 15) {
                        if includeSideStore {
                            step(1, "SideStore", phase == .sideStore,
                                 sideStoreReady || phase == .download || phase == .cinemana || phase == .done)
                            Divider().overlay(.white.opacity(0.2))
                        }
                        step(includeSideStore ? 2 : 1, "Cinemana",
                             phase == .download || phase == .cinemana, phase == .done)
                    }
                    .padding(20)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    if busy {
                        if phase == .download { ProgressView().tint(.mint) }
                        else { ProgressView(value: max(0.05, engine.overallProgress)).tint(.mint) }
                        Text(t("Follow Apple Account, VPN and pairing prompts if shown.",
                               "اتبع تعليمات حساب Apple والـ VPN والاقتران إن ظهرت."))
                            .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                    if !message.isEmpty {
                        Text(message).font(.subheadline)
                            .foregroundStyle(phase == .failed ? .orange : .green)
                    }
                    Toggle(isOn: $includeSideStore) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Also install SideStore", "ثبّت SideStore أيضًا"))
                                .font(.subheadline.weight(.semibold))
                            Text(t("Optional: helps manage self-refresh; requires extra setup.",
                                   "اختياري للتجديد الذاتي، لكنه يحتاج خطوات إضافية."))
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .tint(.mint)
                    .disabled(busy || engine.isRunning)
                    Button { beginSetup() } label: {
                        Label(phase == .done && currentFlowIncludesSideStore
                                ? t("Open SideStore to finish", "افتح SideStore للإكمال")
                                : includeSideStore
                                    ? t("Set up SideStore + Cinemana", "إعداد SideStore وسينمانا")
                                    : t("Install Cinemana", "تثبيت سينمانا"),
                              systemImage: "arrow.down.app.fill")
                            .frame(maxWidth: .infinity).padding(14).font(.headline)
                    }
                    .buttonStyle(.borderedProminent).tint(.mint)
                    .disabled(busy || engine.isRunning)
                    Button(t("Account and settings", "الحساب والإعدادات")) { showSettings = true }
                        .buttonStyle(.borderless).disabled(busy || engine.isRunning)
                    Button {
                        openURL(URL(string: "https://apps.apple.com/app/id6755608044")!)
                    } label: {
                        Label("LocalDevVPN", systemImage: "network.badge.shield.half.filled")
                    }
                    .buttonStyle(.borderless).foregroundStyle(.mint)
                    Text(t("iOS 27+ can self-pair. Earlier supported iOS versions need a pairing file from a computer. The first installation of this installer requires a valid signature; it cannot install itself. Apple Account, Developer Mode and pairing approvals remain manual. Free-account signatures usually expire after 7 days.",
                           "يمكن الإقران على iOS 27+ من نفس الهاتف. الإصدارات الأقدم المدعومة تحتاج ملف اقتران من كمبيوتر. أداة التثبيت نفسها تحتاج توقيعًا صالحًا ولا يمكنها تثبيت نفسها. تأكيدات Apple ونمط المطور والاقتران يدوية. ينتهي التوقيع المجاني عادةً خلال ٧ أيام."))
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    if includeSideStore {
                        Text(t("After setup, open SideStore and refresh it once. Do not assume renewal is automatic without testing.",
                               "بعد الإعداد افتح SideStore وجدّده مرة واحدة. التجديد التلقائي يحتاج اختبارًا."))
                            .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                    Text("SideInstaller by FrizzleM · noncommercial source adaptation")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            guard continueAfterAccount else { return }
            continueAfterAccount = false
            if accountReady { beginSetup() }
            else { message = t("Add your Apple Account to continue.", "أضف حساب Apple للمتابعة.") }
        }) { SettingsView() }
        .onChange(of: engine.isRunning) { was, running in
            if was && !running { onRunCompleted() }
        }
    }

    private func step(_ number: Int, _ name: String, _ active: Bool, _ completed: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: completed ? "checkmark.circle.fill" :
                  active ? "arrow.down.circle.fill" : "circle")
                .foregroundStyle(completed ? .green : active ? .mint : .gray)
            Text("\(number). \(name)").font(.headline).foregroundStyle(.white)
            Spacer()
        }
    }

    private func beginSetup() {
        guard !busy && !engine.isRunning else { return }
        if phase == .done && currentFlowIncludesSideStore {
            openURL(URL(string: "sidestore://")!)
            return
        }

        // Let the upstream one-click engine handle the VPN, pairing,
        // 2FA, signing and installation; never attempt to approve Apple prompts.
        engine.refreshNetworkStatus()
        guard engine.osSupported else {
            fail(t("This iOS version is not supported by the signing engine.",
                   "هذا الإصدار من iOS غير مدعوم من أداة التوقيع."))
            return
        }
        guard engine.canSelfPair || engine.hasPairingFile else {
            fail(t("This iOS version needs a pairing file created on a computer. iOS 27+ can pair on-device.",
                   "هذا الإصدار يحتاج ملف اقتران من كمبيوتر. iOS 27+ يقدر يقترن من نفس الهاتف."))
            return
        }
        if engine.needsFreshPairing && !engine.wifiConnected {
            fail(t("Connect Wi-Fi to create a pairing file, then tap Install again.",
                   "شغّل Wi-Fi لإنشاء ملف الاقتران، ثم حاول التثبيت مجددًا."))
            return
        }
        if engine.needsFreshPairing && Engine.developerModeIsOn == false {
            fail(t("Enable Developer Mode in iPhone Settings → Privacy & Security, restart if requested, then return here.",
                   "فعّل نمط المطور من إعدادات الآيفون ← الخصوصية والأمان، وأعد التشغيل إذا طُلب منك."))
            return
        }
        guard engine.vpnConnected || engine.localDevVPNInstalled else {
            fail(t("Install LocalDevVPN using the link below, then return here.",
                   "ثبّت LocalDevVPN من الرابط أدناه ثم ارجع هنا."))
            return
        }
        guard accountReady else {
            continueAfterAccount = true
            showSettings = true
            return
        }
        // The engine can open LocalDevVPN automatically when a tunnel is needed.
        engine.autoStartVPN = true
        currentFlowIncludesSideStore = includeSideStore
        if includeSideStore && !sideStoreReady { startBoth() }
        else { installCinemanaOnly() }
    }

    private func startBoth() {
        guard !busy && !engine.isRunning else { return }
        runningAccountKey = accountKey
        phase = .sideStore; message = ""
        engine.installSource = .sideStore
        engine.releaseChannel = .stable
        engine.runOneClick()
        checkStart(.sideStore)
    }

    private func installCinemanaOnly() {
        guard !busy && !engine.isRunning else { return }
        runningAccountKey = accountKey
        phase = .download; message = ""
        Task { await downloadAndInstall() }
    }

    // SideInstaller may perform a short asynchronous network probe first.
    private func checkStart(_ expected: Phase) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if phase == expected && !engine.isRunning {
                fail(engine.lastError ?? t("Open the Install tab to complete account, pairing and VPN setup.",
                                          "افتح تبويب Install لإكمال إعداد الحساب والاقتران والـ VPN."))
            }
        }
    }

    private func onRunCompleted() {
        guard runningAccountKey == accountKey else {
            fail(t("Account changed. Start setup again.", "تغيّر الحساب. ابدأ الإعداد مجدداً."))
            return
        }
        switch phase {
        case .sideStore:
            guard engine.finished else {
                fail(engine.lastError ?? "SideStore installation failed.")
                return
            }
            completedAccount = accountKey
            phase = .download
            Task { await downloadAndInstall() }
        case .cinemana:
            guard engine.finished else {
                fail(engine.lastError ?? "Cinemana installation failed.")
                return
            }
            phase = .done
            message = currentFlowIncludesSideStore
                ? t("Both apps installed. Open SideStore and refresh it once. Renew signatures before seven days.",
                    "تم تثبيت التطبيقين. افتح SideStore وجدّده مرة واحدة. جدّد التوقيع قبل سبعة أيام.")
                : t("Cinemana installed. Keep this installer signed and renew Cinemana before seven days.",
                    "تم تثبيت سينمانا. حافظ على توقيع أداة التثبيت وجدّد سينمانا قبل سبعة أيام.")
        default:
            break
        }
    }

    private func fail(_ detail: String) { phase = .failed; message = detail }

    private struct Catalog: Decodable {
        let version: String
        let downloadURL: String
        let sha256: String
        let size: Int
        let signing: String
    }
    private enum SetupError: LocalizedError {
        case problem(String)
        var errorDescription: String? {
            if case .problem(let text) = self { return text }
            return nil
        }
    }

    private func downloadAndInstall() async {
        do {
            let catalogURL = URL(string:
                "https://raw.githubusercontent.com/Subaru771/Cinemana-IOS/main/landing/release.json")!
            let (catalogData, catalogResponse) = try await URLSession.shared.data(from: catalogURL)
            guard (catalogResponse as? HTTPURLResponse)?.statusCode == 200,
                  catalogData.count < 20_000 else {
                throw SetupError.problem("Cannot load Cinemana release catalog.")
            }
            let catalog = try JSONDecoder().decode(Catalog.self, from: catalogData)
            guard catalog.signing == "unsigned", catalog.size > 0, catalog.size < 150_000_000,
                  catalog.sha256.count == 64,
                  let url = URL(string: catalog.downloadURL),
                  url.scheme == "https", url.host?.lowercased() == "github.com",
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.hasPrefix("/Subaru771/Cinemana-IOS/releases/download/"),
                  url.path.lowercased().hasSuffix(".ipa") else {
                throw SetupError.problem("Cinemana release catalog is invalid.")
            }

            let (downloadedFile, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw SetupError.problem(code == 404 ?
                    "The Cinemana download is not available. Its release may still be private or a draft." :
                    "Cinemana IPA download failed (HTTP \(code)).")
            }
            let contents = try Data(contentsOf: downloadedFile, options: .mappedIfSafe)
            guard contents.count == catalog.size else {
                throw SetupError.problem("Cinemana IPA size mismatch.")
            }
            let digest = SHA256.hash(data: contents)
                .map { String(format: "%02x", $0) }.joined()
            guard digest == catalog.sha256.lowercased() else {
                throw SetupError.problem("Cinemana IPA SHA-256 mismatch.")
            }
            let temporaryFolder = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporaryFolder) }
            let importedFile = temporaryFolder.appendingPathComponent("Cinemana.ipa")
            try contents.write(to: importedFile, options: .atomic)

            engine.installSource = .custom
            await engine.importCustomIPA(from: importedFile)
            guard engine.lastError == nil, engine.customIPAName != nil else {
                throw SetupError.problem(engine.lastError ?? "Cinemana import failed.")
            }
            phase = .cinemana
            engine.runOneClick()
            checkStart(.cinemana)
        } catch {
            fail(t("Cinemana installation failed: ", "فشل تثبيت سينمانا: ")
                 + error.localizedDescription)
        }
    }
}
