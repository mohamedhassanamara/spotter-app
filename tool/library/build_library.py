"""Builds assets/library_sources.json: free sources merged into the exercise library.

    python3 tool/library/build_library.py <wger_exerciseinfo.json>

wger_exerciseinfo.json is every result of https://wger.de/api/v2/exerciseinfo/ (public, no key).
Sources, in precedence order (the first keeps the canonical entry and its id):
  1. free-exercise-db (assets/exercises.json + extra_exercises.json): existing ids never change
  2. wger (CC-BY-SA 3.0/4.0, CC-BY 4.0, CC0; licence and author kept per exercise and image)
  3. ExerciseDB V1 free data (assets/exercisedb_v1.json; GIFs, non-commercial personal use)
Duplicates are detected by normalised name tokens (equipment words removed) + equipment + primary
muscle group; a duplicate's media is attached to the canonical entry instead of adding a new one.
"""
import html
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
STOP = {"the", "a", "an", "with", "and", "on", "of", "to", "in", "for", "on", "your", "version"}
EQUIP_WORDS = {"barbell", "dumbbell", "dumbbells", "cable", "machine", "lever", "leverage", "smith", "kettlebell",
               "band", "bands", "resistance", "ez", "sz", "bar", "bodyweight", "body", "weight", "weighted", "sled"}
SYN = {"flye": "fly", "flyes": "fly", "pushdown": "pushdown", "press-down": "pushdown", "pressdown": "pushdown",
       "pullup": "pull-up", "chinup": "chin-up", "situp": "sit-up", "pushup": "push-up", "db": "dumbbell", "bb": "barbell"}


def tokens(name):
    n = name.lower().replace("’", "'")
    for a, b in ((r"pull[\s-]?ups?", "pullup"), (r"chin[\s-]?ups?", "chinup"), (r"push[\s-]?ups?", "pushup"), (r"sit[\s-]?ups?", "situp")):
        n = re.sub(a, b, n)
    n = n.replace("-", " ")
    n = re.sub(r"\(.*?\)", " ", n)
    out = []
    for t in re.findall(r"[a-z0-9]+", n):
        t = SYN.get(t, t)
        if t in STOP:
            continue
        if len(t) > 3 and t.endswith("s") and not t.endswith("ss"):
            t = t[:-1]
        out.append(t)
    return out


NOISE = {"medium", "standard", "regular", "basic", "exercise", "conventional", "flat", "normal", "ups", "up"}
# Words that make a different movement: a name with one of these extra is never a duplicate.
DISTINCT = {"incline", "decline", "close", "wide", "narrow", "reverse", "single", "one", "arm", "leg", "seated",
            "standing", "lying", "hammer", "front", "rear", "behind", "overhead", "sumo", "romanian", "stiff", "split",
            "bulgarian", "jump", "isometric", "stretch", "hold", "kneeling", "alternate", "alternating", "concentration",
            "preacher", "spider", "drag", "zottman", "hack", "pause", "deficit", "box", "goblet", "pistol", "neutral",
            "underhand", "upright", "high", "low", "floor", "landmine", "explosive", "jumping", "left", "right"}


def name_key(name):
    toks = [t for t in tokens(name) if t not in EQUIP_WORDS and t not in NOISE]
    if "grip" in toks and not ({"close", "wide", "narrow", "reverse", "neutral", "underhand", "hammer"} & set(toks)):
        toks.remove("grip")
    return " ".join(sorted(set(toks)))


GROUP = {  # dataset muscle -> coarse group for the dedupe key
    "chest": "chest", "lats": "back", "middle back": "back", "lower back": "lowerback", "shoulders": "shoulders",
    "traps": "traps", "biceps": "biceps", "triceps": "triceps", "forearms": "forearms", "abdominals": "abs",
    "quadriceps": "quads", "hamstrings": "hamstrings", "glutes": "glutes", "calves": "calves",
    "abductors": "abductors", "adductors": "adductors", "neck": "neck",
}


def key(name, equipment, primary):
    g = GROUP.get(primary[0], primary[0]) if primary else ""
    return (name_key(name), equipment or "other", g)


def dice(a, b):
    a, b = set(a.split()), set(b.split())
    return 0 if not a or not b else 2 * len(a & b) / (len(a) + len(b))


# --- wger --------------------------------------------------------------------------------------
WGER_MUSCLE = {"Glutes": "glutes", "Shoulders": "shoulders", "Lats": "lats", "Quads": "quadriceps", "Chest": "chest",
               "Abs": "abdominals", "Biceps": "biceps", "Triceps": "triceps", "Trapezius": "traps", "Hamstrings": "hamstrings",
               "Obliquus externus abdominis": "abdominals", "Calves": "calves", "Brachialis": "biceps",
               "Serratus anterior": "chest", "Soleus": "calves"}
WGER_EQUIP = ["Barbell", "SZ-Bar", "Dumbbell", "Cable machine", "Kettlebell", "Resistance band", "Swiss Ball",
              "Pull-up bar", "none (bodyweight exercise)", "Bench", "Incline bench", "Gym mat"]
WGER_EQUIP_MAP = {"Barbell": "barbell", "SZ-Bar": "e-z curl bar", "Dumbbell": "dumbbell", "Cable machine": "cable",
                  "Kettlebell": "kettlebells", "Resistance band": "bands", "Swiss Ball": "exercise ball",
                  "Pull-up bar": "body only", "none (bodyweight exercise)": "body only", "Bench": "body only",
                  "Incline bench": "body only", "Gym mat": "body only"}
LICENSES = {1: "CC-BY-SA 3.0", 2: "CC-BY-SA 4.0", 3: "CC0", 4: "CC-BY 4.0", 5: "ODbL"}


def wger_muscle(m):
    return WGER_MUSCLE.get(m.get("name_en") or "", WGER_MUSCLE.get(m.get("name"), None))


def strip_html(s):
    s = re.sub(r"<li>", "\n", s or "")
    s = re.sub(r"</p>|<br\s*/?>", "\n", s)
    s = html.unescape(re.sub(r"<[^>]+>", "", s))
    return [x.strip() for x in s.split("\n") if len(x.strip()) > 2]


def wger_entries(raw):
    out = []
    for e in raw:
        tr = next((t for t in e["translations"] if t["language"] == 2), None)
        if not tr or not tr["name"].strip():
            continue
        prim = [m for m in (wger_muscle(x) for x in e["muscles"]) if m]
        sec = [m for m in (wger_muscle(x) for x in e["muscles_secondary"]) if m and m not in prim]
        eq_names = [q["name"] for q in e["equipment"]]
        eq = next((WGER_EQUIP_MAP[n] for n in WGER_EQUIP if n in eq_names), "body only" if not eq_names else "other")
        low = tr["name"].lower()
        if eq == "body only" and re.search(r"machine|multi ?press|hackenschmi|smith|leg press|leg extension|leg curl|pec deck|butterfly|hack squat", low):
            eq = "machine"
        elif eq == "body only" and re.search(r"cable|pull ?down|pulley", low):
            eq = "cable"
        cat = e["category"]["name"]
        imgs = sorted(e["images"], key=lambda i: not i.get("is_main"))
        out.append({
            "source": "wger",
            "wger_id": e["id"],
            "name": tr["name"].strip(),
            "equipment": eq,
            "primaryMuscles": prim or ([] if cat == "Cardio" else []),
            "secondaryMuscles": sec,
            "category": "cardio" if cat == "Cardio" else "strength",
            "instructions": strip_html(tr.get("description")),
            "images": [i["image"] for i in imgs],
            "credit": {
                "source": "wger.de",
                "license": LICENSES.get(e["license"]["id"], e["license"]["short_name"]),
                "author": e.get("license_author") or "",
                "images": [{"license": LICENSES.get(i["license"], str(i["license"])), "author": i.get("license_author") or ""} for i in imgs],
            },
        })
    return out


# --- ExerciseDB V1 ------------------------------------------------------------------------------
V1_EQUIP = {"bodyweight": "body only", "barbell": "barbell", "dumbbell": "dumbbell", "cable": "cable",
            "leverage machine": "machine", "smith machine": "machine", "sled machine": "machine", "band": "bands",
            "resistance band": "bands", "kettlebell": "kettlebells", "ez barbell": "e-z curl bar", "olympic barbell": "barbell",
            "trap bar": "barbell", "weighted": "body only", "assisted": "machine", "medicine ball": "medicine ball",
            "stability ball": "exercise ball", "rope": "cable", "roller": "foam roll", "wheel roller": "other",
            "bosu ball": "exercise ball", "elliptical machine": "machine", "stationary bike": "machine",
            "stepmill machine": "machine", "skierg machine": "machine", "upper body ergometer": "machine",
            "tire": "other", "hammer": "other"}
V1_MUSCLE = {"pectorals": "chest", "lats": "lats", "upper back": "middle back", "delts": "shoulders", "biceps": "biceps",
             "triceps": "triceps", "forearms": "forearms", "abs": "abdominals", "quads": "quadriceps",
             "hamstrings": "hamstrings", "glutes": "glutes", "calves": "calves", "traps": "traps", "spine": "lower back",
             "serratus anterior": "chest", "abductors": "abductors", "adductors": "adductors", "levator scapulae": "neck",
             "erector spinae": "lower back", "deltoids": "shoulders", "obliques": "abdominals", "rear deltoids": "shoulders",
             "rotator cuff": "shoulders", "brachialis": "biceps", "hip flexors": "quadriceps", "inner thighs": "adductors",
             "lower back": "lower back", "shoulders": "shoulders", "chest": "chest", "back": "middle back"}


def v1_entries(raw):
    out = []
    for e in raw:
        if e.get("gifAvailable") is False:
            continue
        prim = [V1_MUSCLE[m] for m in e.get("targetMuscles", []) if m in V1_MUSCLE]
        sec = [V1_MUSCLE[m] for m in e.get("secondaryMuscles", []) if m in V1_MUSCLE and V1_MUSCLE[m] not in prim]
        eq = V1_EQUIP.get((e.get("equipments") or ["other"])[0], "other")
        cardio = "cardiovascular system" in e.get("targetMuscles", [])
        out.append({
            "source": "edb_v1",
            "edb_id": e["exerciseId"],
            "name": " ".join(w if w.isupper() else w.capitalize() for w in e["name"].split()),
            "equipment": eq,
            "primaryMuscles": list(dict.fromkeys(prim)),
            "secondaryMuscles": list(dict.fromkeys(sec)),
            "category": "cardio" if cardio else "strength",
            "instructions": [],
            "images": [],
            "gifUrl": e["gifUrl"],
            "credit": {"source": "ExerciseDB V1 (free data)", "license": "non-commercial personal use"},
        })
    return out


def main():
    fedb = json.loads((ROOT / "assets/exercises.json").read_text())
    extra = json.loads((ROOT / "assets/extra_exercises.json").read_text())["exercises"]
    canon = [{"id": e["id"], "name": e["name"], "equipment": e.get("equipment"), "primaryMuscles": e.get("primaryMuscles", [])} for e in fedb + extra]
    by_key = {}
    for c in canon:
        by_key.setdefault(key(c["name"], c["equipment"], c["primaryMuscles"]), c["id"])
    names_by_eq_group = {}
    for c in canon:
        k = key(c["name"], c["equipment"], c["primaryMuscles"])
        names_by_eq_group.setdefault((k[1], k[2]), []).append((k[0], c["id"]))

    by_name_eq = {}
    for c in canon:
        k = key(c["name"], c["equipment"], c["primaryMuscles"])
        by_name_eq.setdefault((k[0], k[1]), c["id"])

    def find(entry):
        k = key(entry["name"], entry["equipment"], entry["primaryMuscles"])
        if k in by_key:
            return by_key[k], 1.0
        # Same name and equipment: the same exercise even when sources list a different primary muscle.
        if (k[0], k[1]) in by_name_eq and k[0]:
            return by_name_eq[(k[0], k[1])], 0.95
        best, score = None, 0
        mine = set(k[0].split())
        for nk, cid in names_by_eq_group.get((k[1], k[2]), []):
            theirs = set(nk.split())
            d = dice(nk, k[0])
            # One name contains the other plus a single word that doesn't change the movement.
            extra = (mine ^ theirs)
            if (mine <= theirs or theirs <= mine) and len(extra) == 1 and not (extra & DISTINCT) and min(len(mine), len(theirs)) >= 2:
                d = max(d, 0.9)
            if d > score:
                best, score = cid, d
        return (best, score) if score >= 0.85 else (None, score)

    attach, added = {}, []
    v1 = json.loads((ROOT / "assets/exercisedb_v1.json").read_text())["exercises"]
    stats = {"wger": [0, 0], "edb_v1": [0, 0]}
    for entry in wger_entries(json.loads(pathlib.Path(sys.argv[1]).read_text())) + v1_entries(v1):
        src = entry["source"]
        if not entry["primaryMuscles"] and entry["category"] != "cardio":
            entry["primaryMuscles"] = []
        cid, score = find(entry)
        if cid is not None:
            a = attach.setdefault(cid, {"images": [], "credits": []})
            if entry["images"]:
                a["images"] += [u for u in entry["images"] if u not in a["images"]]
                a["credits"].append(entry["credit"])
            if src == "edb_v1":
                a.setdefault("edb_v1_id", entry["edb_id"])
            stats[src][0] += 1
            continue
        new_id = f"wger_{entry['wger_id']}" if src == "wger" else f"edbv1_{entry['edb_id']}"
        entry = {"id": new_id, **{k: v for k, v in entry.items() if k not in ("wger_id", "edb_id")}}
        if src == "edb_v1":
            entry["edb_v1_id"] = new_id[len("edbv1_"):]
        added.append(entry)
        k = key(entry["name"], entry["equipment"], entry["primaryMuscles"])
        by_key.setdefault(k, new_id)
        by_name_eq.setdefault((k[0], k[1]), new_id)
        names_by_eq_group.setdefault((k[1], k[2]), []).append((k[0], new_id))
        stats[src][1] += 1

    out = {
        "schema_version": 1,
        "description": "Free sources merged into the library (built by tool/library/build_library.py). 'attach' adds media from "
        "duplicates to an existing exercise (ids unchanged); 'exercises' are new entries. Licences: wger data and images "
        "CC-BY-SA 3.0/4.0, CC-BY 4.0 or CC0 (per item, with author); ExerciseDB V1 free data for non-commercial personal use.",
        "attach": dict(sorted(attach.items())),
        "exercises": sorted(added, key=lambda e: e["name"].lower()),
    }
    (ROOT / "assets/library_sources.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"canonical {len(canon)} · wger dup {stats['wger'][0]} new {stats['wger'][1]} · v1 dup {stats['edb_v1'][0]} new {stats['edb_v1'][1]} "
          f"· attached media to {sum(1 for a in attach.values() if a['images'])} · total {len(canon) + len(added)}")


main()
