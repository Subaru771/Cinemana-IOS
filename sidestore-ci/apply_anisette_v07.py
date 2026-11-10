#!/usr/bin/env python3
"""Independent Cinemana patch against pinned SideStore source."""
from pathlib import Path
import sys
source=Path(sys.argv[1])
path=source/"AltStore/Core/Extensions/UserDefaults+AltStore.swift"
s=path.read_text(encoding="utf-8")
def rep(old,new):
    global s
    if s.count(old)!=1:
        raise RuntimeError("Pinned upstream changed, aborting: "+old[:70])
    s=s.replace(old,new,1)
rep('            #keyPath(UserDefaults.useOnDeviceAnisette): true,',
    '            // CINEMANA_V07: remote Anisette by default, user override retained.\n'
    '            #keyPath(UserDefaults.useOnDeviceAnisette): false,')
rep('        UserDefaults.standard.register(defaults: defaults)',
'''        UserDefaults.standard.register(defaults: defaults)

        // CINEMANA_V07: migrate prior installations just once.
        // Leave all Apple account data, ADI and pairing records untouched.
        let cinemanaAnisetteMigration = "cinemana.remoteAnisetteDefaultV07"
        if !UserDefaults.standard.bool(forKey: cinemanaAnisetteMigration) {
            UserDefaults.standard.useOnDeviceAnisette = false
            UserDefaults.standard.set(true, forKey: cinemanaAnisetteMigration)
        }''')
path.write_text(s,encoding="utf-8")
print("Remote anisette default enabled; user overrides and upstream server failover preserved.")
