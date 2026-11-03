from pathlib import Path
import shutil, json, hashlib
root=Path(__file__).resolve().parents[1]
art=root/'Branding/CinemanaApprovedSplash.jpg'
assert hashlib.sha256(art.read_bytes()).hexdigest()=='235a1f6086048f118c4066646e0cf36aa20f3d687566cbcc601235ee54084896'
asset=root/'CinemanaMobile/Assets.xcassets/CinemanaSplash.imageset'
asset.mkdir(parents=True,exist_ok=True)
shutil.copyfile(art,asset/'CinemanaSplash.jpg')
(asset/'Contents.json').write_text(json.dumps({'images':[{'filename':'CinemanaSplash.jpg','idiom':'universal'}],'info':{'author':'xcode','version':1}}))
p=root/'CinemanaMobile/CinemanaBrand.swift'
s=p.read_text()
a=s.index('/// Launch branding uses')
b=s.index('\n}',s.index('struct CinemanaSplashView: View {',a))+2
v='''/// Approved Cinemana Hub-style splash, full-bleed, no square tile.
struct CinemanaSplashView: View {
    var body: some View {
        GeometryReader { geo in
            Image("CinemanaSplash").resizable().interpolation(.high)
                .scaledToFill().frame(width: geo.size.width, height: geo.size.height)
                .clipped().accessibilityHidden(true)
        }
        .background(Color.black).ignoresSafeArea().preferredColorScheme(.dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cinemana iOS is opening")
    }
}'''
p.write_text(s[:a]+v+s[b:])
p=root/'project.yml'
s=p.read_text().replace("CFBundleShortVersionString: '1.6.11'","CFBundleShortVersionString: '1.6.12'").replace("CFBundleVersion: '19'","CFBundleVersion: '20'")
p.write_text(s)
p=root/'scripts/validate_branding.py'
s=p.read_text().replace("""assert 'Image("CinemanaWordmark")' in brand
assert 'CinemanaGlyph()' in brand""","""assert 'Image("CinemanaSplash")' in brand""")
p.write_text(s)
print('Approved v1.6.12 splash installed; player code preserved')
