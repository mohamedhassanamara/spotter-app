"""Writes assets/exercise_muscles.json and assets/strength_standards.json from exercise_data.py.

    python3 tool/standards/build.py

Checks that every exercise with muscles has a standard and vice versa.
"""
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from exercise_data import MUSCLES, STANDARDS  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
MUSCLE_KEYS = {
    "biceps", "triceps", "forearms", "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors",
    "abdominals", "obliques", "front_delt", "middle_delt", "rear_delt", "upper_chest", "lower_chest",
    "lats", "upper_back", "traps", "lower_back",
}

errors = []
for ex, ws in MUSCLES.items():
    for m, w in ws.items():
        if m not in MUSCLE_KEYS:
            errors.append(f"{ex}: unknown muscle {m}")
        if not 0 < w <= 1:
            errors.append(f"{ex}: weight {w} out of range")
    if max(ws.values()) != 1.0:
        errors.append(f"{ex}: needs a prime mover at 1.0")
covered = {}
for name, (kind, per_hand, anchors, ids) in STANDARDS.items():
    if kind not in ("free", "machine", "cable", "bodyweight"):
        errors.append(f"{name}: kind {kind}")
    if list(anchors) != sorted(anchors) or len(set(anchors)) != 5:
        errors.append(f"{name}: anchors must strictly ascend")
    for i in ids:
        if i in covered:
            errors.append(f"{i} in two standards: {covered[i]} and {name}")
        covered[i] = name
for ex in MUSCLES:
    if ex not in covered:
        errors.append(f"{ex}: no standard")
for ex in covered:
    if ex not in MUSCLES:
        errors.append(f"{ex}: standard but no muscles")
if errors:
    sys.exit("\n".join(errors))

muscles = {
    "schema_version": 1,
    "description": "Hand-authored muscle contributions (0-1, 1.0 = prime mover) for every exercise in the "
    "owner's routines and Liftoff history, over the 20 ranking muscles. Exercises not listed derive "
    "theirs from the dataset's primary (1.0) and secondary (0.3) muscles, refined by name keywords "
    "(lib/features/library/domain/muscle_mapping.dart). Source: tool/standards/exercise_data.py.",
    "exercises": {k: MUSCLES[k] for k in sorted(MUSCLES)},
}


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


standards = {
    "schema_version": 3,
    "description": "Strength standards per exercise. anchors = e1RM / bodyweight at the beginner, novice, "
    "intermediate, advanced and elite levels for a male lifter around 100 kg. Machine and cable anchors "
    "are multiplied by machine_strictness. Tier entry points: Iron 0, Bronze = beginner, Silver = novice, "
    "Gold = midpoint novice-intermediate, Platinum = intermediate, Emerald = midpoint intermediate-advanced, "
    "Diamond = advanced, Master = elite, Grandmaster = elite x 1.15, Challenger = elite x 1.30. "
    "kind bodyweight: e1RM includes bodyweight (assisted machines subtract the assistance). "
    "per_hand: per dumbbell or per side. Source: tool/standards/exercise_data.py.",
    "machine_strictness": 1.10,
    "standards": [
        {
            "id": slug(name),
            "name": name,
            "kind": kind,
            "per_hand": per_hand,
            "exercise_ids": ids,
            "anchors": dict(zip(["beginner", "novice", "intermediate", "advanced", "elite"], anchors)),
        }
        for name, (kind, per_hand, anchors, ids) in STANDARDS.items()
    ],
}

(ROOT / "assets/exercise_muscles.json").write_text(json.dumps(muscles, indent=1) + "\n")
(ROOT / "assets/strength_standards.json").write_text(json.dumps(standards, indent=1) + "\n")
print(f"{len(MUSCLES)} exercises, {len(STANDARDS)} standards")
