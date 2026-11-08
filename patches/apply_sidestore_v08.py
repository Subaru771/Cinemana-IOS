#!/usr/bin/env python3
"""Apply the opt-in encrypted account handoff to the existing Cinemana SideStore v0.6 fork.

Usage: python3 apply_sidestore_v08.py /path/to/SideStore (after v0.6 patches)
"""
from pathlib import Path
import sys

root=Path(sys.argv[1]); source=Path(__file__).resolve().parent
p=root/'AltStore/Settings/SettingsViewController.swift'
if not p.is_file(): raise SystemExit('SettingsViewController.swift not found')
s=p.read_text(encoding='utf-8')
marker='// CINEMANA_ACCOUNT_HANDOFF_V08'
if marker in s:
    print('Already installed; no source changes')
    exit(0)
if '// CINEMANA_EASY_SETUP_V06' not in s: raise SystemExit('Apply full v0.5 and v0.6 setup first')
if s.count('    @State private var showAdvanced = false') != 1: raise SystemExit('Advanced controls anchor changed')
s=s.replace('    @State private var showAdvanced = false',
 '''    @State private var showAdvanced = false
    @State private var showAccountHandoff = false''',1)
if s.count('                    topCard\n                    nextCard')!=1: raise SystemExit('Main card anchor changed')
s=s.replace('                    topCard\n                    nextCard',
 '''                    topCard
                    if !AuthManager.shared.isAuthenticated {
                        SwiftUI.Button {
                            showAccountHandoff = true
                        } label: {
                            Label(tr("Use the Apple Account already in iLoader", "استخدم حساب Apple الموجود بـ iLoader"),
                                  systemImage: "lock.iphone")
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    nextCard''',1)
needle='            .sheet(isPresented: $showAdvanced) { CinemanaAssistantView() }'
if s.count(needle)!=1: raise SystemExit('Sheet anchor changed')
s=s.replace(needle,'''            .sheet(isPresented: $showAccountHandoff) { CinemanaHandoffView() }
'''+needle,1)
s=s.replace('import SwiftUI','import SwiftUI\nimport CryptoKit\nimport CoreData',1)
s += '\n\n' + (source/'CinemanaHandoff.swift').read_text(encoding='utf-8').strip() + '\n'
p.write_text(s,encoding='utf-8')
print('Cinemana v0.8 account handoff installed, prior SideStore functionality preserved.')
