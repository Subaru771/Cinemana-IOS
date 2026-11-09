from pathlib import Path
import sys

root = Path(sys.argv[1])
api = root / "app/src/main/java/app/cinemanatv/data/ExternalSceneMarkers.kt"
text = api.read_text()
old = '''    fun merge(primary: List<ExternalSceneMarker>, fallback: List<ExternalSceneMarker>): List<ExternalSceneMarker> {
        val kinds = primary.mapTo(mutableSetOf()) { it.kind }
        return (primary + fallback.filter { kinds.add(it.kind) }).sortedBy { it.startMs }
    }'''
new = '''    fun merge(primary: List<ExternalSceneMarker>, fallback: List<ExternalSceneMarker>): List<ExternalSceneMarker> {
        // Preserve every distinct fallback range when the preferred source has none of this kind.
        val primaryKinds = primary.map { it.kind }.toSet()
        return (primary + fallback.filter { it.kind !in primaryKinds })
            .distinctBy { Triple(it.kind, it.startMs, it.endMs) }
            .sortedBy { it.startMs }
    }'''
assert old in text, "Unexpected source revision: aborting build"
api.write_text(text.replace(old, new, 1))
tests = root / "app/src/test/java/app/cinemanatv/data/ExternalSceneMarkersTest.kt"
text = tests.read_text()
needle = "    @Test fun additionalSourcesRequireImdbId() {"
newtest = '''    @Test fun fallbackPreservesMultipleNonOverlappingIntroSegments() {
        val introOne = ExternalSceneMarker("intro", 0, 30000, "TheIntroDB", 0.92)
        val introTwo = ExternalSceneMarker("intro", 120000, 150000, "TheIntroDB", 0.91)
        val credits = ExternalSceneMarker("outro", 2640000, duration, "SkipDB", 0.95)
        val result = ExternalSceneMarkers.merge(listOf(credits), listOf(introOne, introTwo, introOne))
        assertEquals(3, result.size)
        assertEquals(2, result.count { it.kind == "intro" })
        assertEquals(1, result.count { it.kind == "outro" })
    }

'''
assert needle in text, "Unexpected test layout: aborting build"
tests.write_text(text.replace(needle,newtest+needle,1))
print("Applied multi-range skip regression repair and test")
