#!/usr/bin/env python3
"""Patch pinned upstream iLoader v2.4.1 into Cinemana Loader 1.1.1."""
import json
import hashlib
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
UPSTREAM = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "upstream"

def replace_once(path, old, new):
    file = UPSTREAM / path
    s = file.read_text(encoding="utf-8")
    if s.count(old) != 1:
        raise RuntimeError(f"Unexpected upstream layout in {path}: {old[:60]!r} count={s.count(old)}")
    file.write_text(s.replace(old, new, 1), encoding="utf-8")

def main():
    assert (UPSTREAM / "src/App.tsx").is_file()
    assert (UPSTREAM / "src-tauri/src/lib.rs").is_file()
    package = json.loads((UPSTREAM / "package.json").read_text())
    if package.get("version") != "2.4.1":
        raise RuntimeError("Only validated against iLoader v2.4.1")
    expected = {
        "Cinemana-SideStore-V0.10-TEST.ipa": "b0e6d58f93d034362af87053a0f359ae0ba1d043477ff6929674a559641c3f59",
        "Cinemana-iOS-v2.1.1-beta.1-Unsigned.ipa": "42348c3d7571a4b202a73993106327440abfc457741e530fab3cba32926f6a00",
    }
    for name, expected_hash in expected.items():
        data=(ROOT/"assets"/name).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected_hash:
            raise RuntimeError(f"Missing or incorrect bundled IPA: {name}")
    dest=UPSTREAM/"src-tauri"/"cinemana-assets"
    dest.mkdir(exist_ok=True)
    for name in expected:
        shutil.copyfile(ROOT/"assets"/name, dest/name)
    shutil.copyfile(ROOT/"src"/"cinemana_install.rs",UPSTREAM/"src-tauri"/"src"/"cinemana_install.rs")
    shutil.copyfile(ROOT/"src"/"CinemanaApp.tsx",UPSTREAM/"src"/"App.tsx")
    shutil.copyfile(ROOT/"src"/"cinemana.css",UPSTREAM/"src"/"cinemana.css")
    (UPSTREAM/"src"/"cinemana").mkdir(exist_ok=True)
    for f in (ROOT/"src"/"cinemana").glob("*.ts"):
        shutil.copyfile(f,UPSTREAM/"src"/"cinemana"/f.name)

    replace_once("src-tauri/src/lib.rs", "mod operation;", "mod operation;\nmod cinemana_install;")
    replace_once("src-tauri/src/lib.rs", "use tauri::Manager;", "use crate::cinemana_install::cinemana_install_operation;\nuse tauri::Manager;")
    replace_once("src-tauri/src/lib.rs", "            has_stored_rppairing,", "            has_stored_rppairing,\n            cinemana_install_operation,")
    replace_once("src-tauri/src/lib.rs", "        .plugin(tauri_plugin_updater::Builder::new().build())", "        // Do not use updater signed by upstream iLoader.")
    replace_once("src-tauri/Cargo.toml", 'serde_json = "1"', 'serde_json = "1"\nsha2 = "0.10"')

    confpath=UPSTREAM/"src-tauri/tauri.conf.json"
    conf=json.loads(confpath.read_text())
    conf["productName"]="Cinemana Loader"
    conf["version"]="1.1.1"
    conf["identifier"]="app.cinemana.loader"
    conf["build"]["beforeDevCommand"]="npm run dev"
    conf["build"]["beforeBuildCommand"]="npm run build"
    for window in conf["app"]["windows"]:
        window.update({"title":"Cinemana Loader","width":550,"height":680,"minWidth":460,"minHeight":570})
    conf.get("plugins",{}).pop("updater",None)
    conf["bundle"]["targets"]=["nsis"]
    conf["bundle"]["createUpdaterArtifacts"]=False
    conf["bundle"].setdefault("windows",{})["webviewInstallMode"]={"type":"downloadBootstrapper","silent":True}
    confpath.write_text(json.dumps(conf,indent=2)+"\n")
    package["name"]="cinemana-loader"
    package["version"]="1.1.1"
    # Prevent npm from resolving newer incompatible plugin minor versions.
    exact = {
        "@tauri-apps/api": "2.11.1",
        "@tauri-apps/plugin-dialog": "2.7.3",
        "@tauri-apps/plugin-opener": "2.5.5",
        "@tauri-apps/plugin-process": "2.3.1",
        "@tauri-apps/plugin-store": "2.4.5",
        "@tauri-apps/plugin-updater": "2.12.0",
    }
    for name, version in exact.items():
        package["dependencies"][name] = version
    package["devDependencies"]["@tauri-apps/cli"] = "2.11.5"
    (UPSTREAM/"package.json").write_text(json.dumps(package,indent=2)+"\n")
    print("Patched Cinemana Loader 1.1.1")
if __name__=="__main__":
    main()
