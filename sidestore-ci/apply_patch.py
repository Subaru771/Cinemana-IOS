#!/usr/bin/env python3
"""Build-only, isolated SideStore fork patch for Cinemana. Pinned upstream revision."""
from pathlib import Path
import sys

root=Path(sys.argv[1])
pair=root/"SideStore/Core/Pairing/PairingFileManager.swift"
settings=root/"AltStore/Settings/SettingsViewController.swift"
plist=root/"AltStore/Info.plist"
def once(text,needle,replacement):
    if text.count(needle)!=1:
        raise RuntimeError(f"Expected unique anchor, found {text.count(needle)}: {needle[:60]}")
    return text.replace(needle,replacement,1)

p=pair.read_text()
old="""    var preferredProtocol: PairingProtocol? {
        get { UserDefaults.standard.preferredPairingProtocol }
        set { UserDefaults.standard.preferredPairingProtocol = newValue }
    }"""
new="""    // CINEMANA: Choose Remote Pairing on iOS 26.4+ only when its file exists.
    // The user may switch to native manual selection; pairing files stay intact.
    var preferredProtocol: PairingProtocol? {
        get {
            let defaults = UserDefaults.standard
            if defaults.string(forKey: "cinemana.pairingMode") != "manual" {
                if #available(iOS 26.4, *), hasPairingFile(for: .rppairing) {
                    return .rppairing
                }
            }
            return defaults.preferredPairingProtocol
        }
        set { UserDefaults.standard.preferredPairingProtocol = newValue }
    }"""
pair.write_text(once(p,old,new))
s=settings.read_text()
old="""    override func viewDidLoad()
    {
        super.viewDidLoad()"""
new="""    override func viewDidLoad()
    {
        super.viewDidLoad()
        #if !os(tvOS)
        let cinemanaButton = UIBarButtonItem(title: "Cinemana", style: .plain,
             target: self, action: #selector(openCinemanaAssistant))
        navigationItem.leftBarButtonItems = (navigationItem.leftBarButtonItems ?? []) + [cinemanaButton]
        #endif"""
s=once(s,old,new)
anchor="    private func handleReleaseChannelSelection(_ channel: String) {"
add="""    #if !os(tvOS)
    @objc private func openCinemanaAssistant() {
        let screen = UIHostingController(rootView: CinemanaAssistantView())
        screen.modalPresentationStyle = .pageSheet
        present(screen, animated: true)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !UserDefaults.standard.bool(forKey: "cinemana.didShowOnboarding") {
            UserDefaults.standard.set(true, forKey: "cinemana.didShowOnboarding")
            openCinemanaAssistant()
        }
    }
    #endif
"""
s=once(s,anchor,add+anchor)
view=Path(__file__).parent.joinpath("CinemanaAssistantView.swift").read_text()
s=s.rstrip()+"\n\n"+view+"\n"
settings.write_text(s)
pi=plist.read_text()
pi=once(pi,"<key>CFBundleName</key>\n\t<string>$(PRODUCT_NAME)</string>",
    "<key>CFBundleDisplayName</key>\n\t<string>Cinemana SideStore</string>\n\t<key>CFBundleName</key>\n\t<string>$(PRODUCT_NAME)</string>")
plist.write_text(pi)
print("Applied Cinemana SideStore setup compatibility patches")
