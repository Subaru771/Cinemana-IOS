#!/usr/bin/env python3
"""Check static English/Arabic public pages and local navigation at CI time."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import re

ROOT = Path(__file__).resolve().parents[1] / "landing"
PAIRS = ("index", "livecontainer", "privacy")


class Inspect(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.language = None
        self.direction = None
        self.links = []
        self.alternates = {}
        self.current = False
        self.titles = 0

    def handle_starttag(self, tag, attrs):
        attr = dict(attrs)
        if tag == "html":
            self.language = attr.get("lang")
            self.direction = attr.get("dir")
        if tag in ("a", "link") and attr.get("href"):
            self.links.append(attr["href"])
        if tag == "link" and attr.get("rel") == "alternate":
            self.alternates[attr.get("hreflang", "")] = attr.get("href")
        if attr.get("aria-current") == "page":
            self.current = True
        if tag == "title":
            self.titles += 1


def validate():
    issues = []
    for pair in PAIRS:
        en = f"{pair}.html"
        ar = f"{pair}-ar.html"
        for filename, lang in ((en, "en"), (ar, "ar")):
            path = ROOT / filename
            if not path.is_file():
                issues.append(f"Missing {path}")
                continue
            content = path.read_text(encoding="utf-8")
            parser = Inspect()
            parser.feed(content)
            if parser.language != lang:
                issues.append(f"{filename}: expected html lang={lang}, got {parser.language}")
            if lang == "ar" and parser.direction != "rtl":
                issues.append(f"{filename}: missing RTL direction")
            if not parser.current:
                issues.append(f"{filename}: no current language indicator")
            if parser.titles != 1:
                issues.append(f"{filename}: expected exactly one page title")
            if parser.alternates.get("en") != en or parser.alternates.get("ar") != ar:
                issues.append(f"{filename}: invalid bilingual alternate links")
            target = ar if lang == "en" else en
            if target not in parser.links:
                issues.append(f"{filename}: missing counterpart language switch to {target}")
            if lang == "ar" and len(re.findall(r"[\u0600-\u06ff]", content)) < 120:
                issues.append(f"{filename}: Arabic translation missing or incomplete")
            for href in parser.links:
                parsed = urlsplit(href)
                if parsed.scheme or parsed.netloc or href.startswith("#") or not parsed.path:
                    continue
                resolved = (path.parent / parsed.path).resolve()
                if not resolved.is_relative_to(ROOT.resolve()) or not resolved.is_file():
                    issues.append(f"{filename}: broken internal link {href}")
    if issues:
        raise SystemExit("Landing locale checks failed:\n" + "\n".join(issues))
    print(f"Landing locale checks passed: {len(PAIRS) * 2} pages, RTL, language switches and local links.")


if __name__ == "__main__":
    validate()
