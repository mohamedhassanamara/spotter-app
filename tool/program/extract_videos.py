"""Adds Jeff Nippard's demo videos to assets/programs/min_max_phase2.json.

    python3 tool/program/extract_videos.py "/path/to/The Min-Max Program Phase 2 5x.pdf"

The PDF links every exercise name (and every listed substitution) to a YouTube demo through link
annotations; the visible text doesn't contain the URL. For each annotation the words inside its
rectangle are collected; a name wrapped over two lines has two rectangles with the same URL on the
same page, which are joined. Each slot gets "video" and each substitution "substitution_videos[name]",
as {"url", "start_s"} (start_s from a t= parameter, else 0). Only the PDF's own links are used: an
exercise without a link gets no video.
"""
import json
import pathlib
import re
import sys
from urllib.parse import parse_qs, urlparse

import pdfplumber

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROGRAM = ROOT / "assets/programs/min_max_phase2.json"


def norm(s):
    s = s.lower().replace("’", "'").replace("–", "-")
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return " ".join(s.split())


def start_seconds(url):
    q = parse_qs(urlparse(url).query)
    t = (q.get("t") or q.get("start") or ["0"])[0]
    m = re.fullmatch(r"(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?", t)
    if not m:
        return 0
    h, mi, se = (int(x) if x else 0 for x in m.groups())
    return h * 3600 + mi * 60 + se


def links(pdf_path):
    """normalised linked text -> url, over the whole PDF."""
    out = {}
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            hl = [h for h in page.hyperlinks if "youtu" in (h.get("uri") or "")]
            if not hl:
                continue
            words = page.extract_words()
            # Rectangles of one URL that sit on consecutive lines in the same column are one wrapped name.
            groups = []
            by_uri = {}
            for h in hl:
                by_uri.setdefault(h["uri"], []).append(h)
            for uri, rects in by_uri.items():
                rects.sort(key=lambda h: (h["top"], h["x0"]))
                for h in rects:
                    inside = [w["text"] for w in words
                              if h["x0"] - 1 <= (w["x0"] + w["x1"]) / 2 <= h["x1"] + 1 and h["top"] - 1 <= (w["top"] + w["bottom"]) / 2 <= h["bottom"] + 1]
                    text = " ".join(inside)
                    g = groups[-1] if groups and groups[-1][0] == uri else None
                    if g is not None and -6 <= h["top"] - g[2] < 12 and abs(h["x0"] - g[3]) < 60:
                        g[1].append(text)
                        g[2] = h["bottom"]
                    else:
                        groups.append([uri, [text], h["bottom"], h["x0"]])
            for uri, texts, _, _ in groups:
                name = norm(" ".join(texts))
                if name:
                    out.setdefault(name, uri)
    return out


def main():
    found = links(sys.argv[1])
    program = json.loads(PROGRAM.read_text())

    def lookup(name):
        n = norm(name)
        if n in found:
            return found[n]
        # A link rectangle may clip a word at the edge: accept a linked name that contains all of ours.
        cands = [u for k, u in found.items() if set(n.split()) <= set(k.split()) and len(k.split()) <= len(n.split()) + 1]
        return cands[0] if len(set(cands)) == 1 else None

    def video(name):
        u = lookup(name)
        return None if u is None else {"url": u, "start_s": start_seconds(u)}

    report = []
    for day in program["days"]:
        for slot in day["slots"]:
            slot["video"] = video(slot["exercise"])
            slot["substitution_videos"] = {s: video(s) for s in slot["substitutions"]}
            report.append((slot["exercise"], slot["video"] is not None))
            report += [(s, v is not None) for s, v in slot["substitution_videos"].items()]
    program["videos_source"] = "Demo links from the PDF's link annotations (tool/program/extract_videos.py)."
    PROGRAM.write_text(json.dumps(program, indent=1, ensure_ascii=False) + "\n")
    names = dict(report)
    missing = sorted(n for n, ok in names.items() if not ok)
    print(f"{len(found)} linked names in the PDF; {sum(names.values())}/{len(names)} program names have a video")
    for n in missing:
        print("  no video:", n)


main()
