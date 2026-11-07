// CINEMANA BUILD CANDIDATE: setup UI, no Apple account data handling.
#if !os(tvOS)
private struct CinemanaAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cinemana.pairingMode") private var pairingMode = "auto"
    @AppStorage("cinemana.language") private var language = "ar"
    @AppStorage("cinemana.autoStartLocalVPN") private var autoStartLocalVPN = false
    @AppStorage("cinemana.checkOnOpen") private var checkOnOpen = true
    @State private var apple: String = "Not checked"
    @State private var anisette: String = "Not checked"
    @State private var tunnel: String = "Not checked"
    @State private var message: String = ""
    @State private var busy = false
    @State private var errorText = ""
    @State private var confirmReset = false

    private func tr(_ english: String, _ arabic: String) -> String {
        language == "ar" ? arabic : english
    }
    private var remoteExists: Bool {
        PairingFileManager.shared.hasPairingFile(for: .rppairing)
    }
    private var lockdownExists: Bool {
        PairingFileManager.shared.hasPairingFile(for: .lockdown)
    }
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(tr("Cinemana SideStore", "Cinemana SideStore"))
                        .font(.title2).bold()
                    Text(tr("Installation health, pairing and connectivity in one place.",
                            "فحص التجهيز والربط والاتصال بمكان واحد."))
                        .foregroundColor(.secondary)
                }
                Section(header: Text(tr("Pairing", "الربط"))) {
                    Label(tr("Remote pairing", "Remote Pairing"), systemImage:
                          remoteExists ? "checkmark.circle.fill" : "exclamationmark.circle")
                    Label(tr("Lockdown pairing", "Lockdown Pairing"), systemImage:
                          lockdownExists ? "checkmark.circle.fill" : "circle.dashed")
                    Picker(tr("Selection", "اختيار الربط"), selection: $pairingMode) {
                        Text(tr("Automatic", "تلقائي")).tag("auto")
                        Text(tr("Manual", "يدوي")).tag("manual")
                    }
                    .pickerStyle(.segmented)
                    Text(tr("Automatic prefers Remote Pairing on iOS 26.4+ when available. Existing files stay untouched.",
                            "التلقائي يفضل Remote Pairing على iOS 26.4 وفوك إذا الملف موجود. ما يحذف أي ملف."))
                        .font(.caption).foregroundColor(.secondary)
                    SwiftUI.Button(tr("Use Remote Pairing now", "اختار Remote Pairing هسه")) {
                        PairingFileManager.shared.preferredProtocol = .rppairing
                        pairingMode = "manual"
                        message = tr("Preference saved. Restart SideStore for an active session.",
                                     "انحفظ الاختيار. أعد تشغيل SideStore للاتصال الحالي.")
                    }
                    .disabled(!remoteExists)
                    Link(tr("Pairing instructions", "شرح الربط"),
                         destination: URL(string:"https://docs.sidestore.io/docs/advanced/pairing-file")!)
                }
                Section(header: Text(tr("Connectivity", "الاتصال"))) {
                    HStack { Text("Apple"); Spacer(); Text(apple).foregroundColor(.secondary) }
                    HStack { Text("Anisette"); Spacer(); Text(anisette).foregroundColor(.secondary) }
                    HStack { Text(tr("Local tunnel", "النفق المحلي")); Spacer(); Text(tunnel).foregroundColor(.secondary) }
                    SwiftUI.Button(tr("Check all connections", "افحص كل الاتصالات")) {
                        Task { await runChecks() }
                    }
                    .disabled(busy)
                    Toggle(tr("Auto-request LocalDevVPN on tunnel failure", "اطلب LocalDevVPN تلقائياً بعد فشل النفق"),
                           isOn: $autoStartLocalVPN)
                    Toggle(tr("Check on launch", "افحص عند الفتح"), isOn: $checkOnOpen)
                    SwiftUI.Button(tr("Connect LocalDevVPN", "شغّل LocalDevVPN")) {
                        requestLocalVPN()
                    }
                    Link(tr("Get LocalDevVPN", "نزّل LocalDevVPN"),
                         destination: URL(string:"https://apps.apple.com/app/localdevvpn/id6755608044")!)
                    Text(tr("LocalDevVPN is not an internet VPN. It cannot resolve every ISP or Apple authentication problem.",
                            "LocalDevVPN مو VPN إنترنت وما يصلح كل مشاكل مزود الخدمة أو تسجيل Apple."))
                        .font(.caption).foregroundColor(.secondary)
                }
                Section(header: Text(tr("Error assistance", "مساعدة بالأخطاء"))) {
                    TextField(tr("Paste an error code", "الصق رمز الخطأ"), text: $errorText)
                        .textInputAutocapitalization(.never)
                    SwiftUI.Button(tr("Analyze", "شخّص")) { analyze() }
                }
                Section(header: Text(tr("Customize", "التخصيص"))) {
                    Picker(tr("Language", "اللغة"), selection: $language) {
                        Text("العربية").tag("ar")
                        Text("English").tag("en")
                    }
                }
                Section(header: Text("Cinemana")) {
                    Label(tr("The Cinemana IPA will be added when ready.", "نسخة Cinemana للأيفون تنضاف من تجهز."),
                          systemImage: "film")
                    Text(tr("This beta does not contain Cinemana or any Apple account credentials.",
                            "هذا الاختبار ما بي Cinemana ولا معلومات حساب Apple."))
                        .font(.caption).foregroundColor(.secondary)
                }
                if !message.isEmpty {
                    Section { Text(message).font(.footnote) }
                }
            }
            .navigationTitle("Cinemana Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    SwiftUI.Button(tr("Done", "تم")) { dismiss() }
                }
            }
            .task { if checkOnOpen { await runChecks() } }
        }
        .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
    }

    private func probe(_ urlString: String) async -> String {
        guard let url = URL(string:urlString) else { return "Invalid URL" }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let response = response as? HTTPURLResponse {
                return (200..<400).contains(response.statusCode) ? "Reachable" : "HTTP \(response.statusCode)"
            }
            return "Unexpected response"
        } catch { return "Unreachable" }
    }

    @MainActor
    private func runChecks() async {
        if busy { return }
        busy = true
        defer { busy = false }
        async let appleResult = probe("https://www.apple.com/library/test/success.html")
        async let anisetteResult = probe("https://ani.sidestore.io")
        let local = await isMinimuxerReady()
        apple = await appleResult
        anisette = await anisetteResult
        switch local {
        case .success(let ready):
            tunnel = ready ? "Ready" : "Not ready"
        case .failure(let error):
            tunnel = "Unavailable"
            if autoStartLocalVPN {
                switch error {
                case .noVPN(_), .invalidVPN(_):
                    if remoteExists || lockdownExists { requestLocalVPN() }
                default: break
                }
            }
        }
    }
    @MainActor
    private func requestLocalVPN() {
        guard let link = URL(string:"localdevvpn://enable"),
              UIApplication.shared.canOpenURL(link) else {
            message = tr("Install and authorize LocalDevVPN first.", "نصّب LocalDevVPN ووافق على الصلاحيات أولاً.")
            return
        }
        UIApplication.shared.open(link)
    }
    private func analyze() {
        let text = errorText.lowercased()
        if text.contains("80045") || text.contains("anisette") {
            message = tr("Check Apple and Anisette connectivity, then review SideStore's Anisette server settings. No universal sign-in fix exists.",
                         "افحص اتصال Apple وAnisette وراجع إعدادات خادم Anisette. ماكو حل مضمون لكل مشاكل التسجيل.")
        } else if text.contains("1016") || text.contains("unlocked recently") {
            message = tr("Unlock the iPhone and retry. Avoid unnecessary pairing resets.",
                         "افتح قفل الآيفون وجرب مرة ثانية. لا تمسح ملف الربط بدون سبب.")
        } else if text.contains("invalidvpn") || text.contains("brokenpipe") {
            message = tr("Check LocalDevVPN and prefer Remote Pairing when available on newer iOS.",
                         "افحص LocalDevVPN وفضّل Remote Pairing بالإصدارات الحديثة إذا موجود.")
        } else if text.contains("pairing") {
            message = tr("Regenerate the appropriate pairing file using iLoader or idevice_pair.",
                         "ولّد ملف ربط مناسب بواسطة iLoader أو idevice_pair.")
        } else {
            message = tr("No specific diagnosis. Check official SideStore troubleshooting.",
                         "ماكو تشخيص محدد. راجع دليل SideStore الرسمي.")
        }
    }
}
#endif
