"""Builds assets/programs/min_max_canonical.json, the only program file the app reads, from the
12-week extraction kept for reference in docs/program/min_max_phase2_12weeks.json.

The owner runs one fixed weekly template. Week 5 is canonical: the week-5 RIR per set, and no
intensity techniques (those are added by hand in the logger). Everything else (sets, rep ranges,
warm-ups, rest, supersets, substitutions, notes, videos) is identical in all 12 weeks; the extractor
asserts that. Re-run after re-extracting:

    python3 tool/program/canonical_week.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/program/min_max_phase2_12weeks.json"
OUT = ROOT / "assets/programs/min_max_canonical.json"
CANONICAL_WEEK = "5"


def main():
    j = json.loads(SRC.read_text())
    program = {k: v for k, v in j["program"].items() if k != "weeks"}
    program["canonical_week"] = int(CANONICAL_WEEK)
    method = {k: v for k, v in j["method"].items() if k != "blocks"}
    days = []
    for d in j["days"]:
        slots = []
        for s in d["slots"]:
            w = s["weeks"][CANONICAL_WEEK]
            assert w["technique"] is None, (s["slot_id"], "week 5 has no techniques")
            slot = {k: v for k, v in s.items() if k not in ("weeks", "source_pages")}
            slot["rir"] = w["rir"]
            assert len(slot["rir"]) == s["working_sets"], s["slot_id"]
            slots.append(slot)
        days.append({**{k: v for k, v in d.items() if k != "slots"}, "slots": slots})
    out = {"schema_version": 2, "program": program, "method": method, "days": days, "videos_source": j.get("videos_source")}
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {OUT.relative_to(ROOT)}: {sum(len(d['slots']) for d in days)} slots, week {CANONICAL_WEEK}")


if __name__ == "__main__":
    main()
