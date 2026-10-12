"""Builds assets/programs/min_max_phase2.json from your own copy of
"The Min-Max Program Phase 2 5x" PDF (never committed; see .gitignore `private/`).

Usage (needs `pip install pdfplumber`):
    python tool/program/extract_min_max.py "/path/to/The Min-Max Program Phase 2 5x.pdf"

Table cells are rebuilt from word coordinates (column x-ranges, row bands anchored on the
"Working Sets" column). The method pages (warm-up protocol, RIR rules, techniques, progression,
rest, supersets) are transcribed by hand below because they're prose, not tables.
"""
import json
import re
import sys

import pdfplumber

COLS = [('exercise', 180, 325), ('technique', 325, 490), ('warmup', 490, 590), ('working', 590, 690),
        ('reps', 690, 775), ('rir1', 1350, 1450), ('rir2', 1450, 1545), ('rir3', 1545, 1640),
        ('rest', 1640, 1745), ('sub1', 1745, 1888), ('sub2', 1888, 2032), ('notes', 2032, 2700)]
DAYS = ['upper', 'lower', 'push', 'pull', 'arms']
FIRST_TABLE_PAGE = 26  # 1-based; weeks 1..12 x 5 days follow in order


def extract_rows(pdf):
    pages = []
    for i in range(60):
        p = pdf.pages[FIRST_TABLE_PAGE - 1 + i]
        ws = p.extract_words()
        text = p.extract_text() or ''
        week = int(re.search(r'WEEK\s+(\d+)', text).group(1))
        anchors = sorted({round(w['top']) for w in ws
                          if 590 <= w['x0'] < 690 and w['top'] > 220 and re.fullmatch(r'[\d\-–]+', w['text'])})
        rows = []
        for k, a in enumerate(anchors):
            lo = (anchors[k - 1] + a) / 2 if k else a - 70
            hi = (a + anchors[k + 1]) / 2 if k + 1 < len(anchors) else a + 70
            row = {}
            for name, x0, x1 in COLS:
                cell = sorted([w for w in ws if x0 <= w['x0'] < x1 and lo <= w['top'] < hi],
                              key=lambda w: (round(w['top'] / 4), w['x0']))
                row[name] = re.sub(r'\(Set \d\)', '', re.sub(r'\s+', ' ', ' '.join(w['text'] for w in cell))).strip()
            rows.append(row)
        pages.append({'page': FIRST_TABLE_PAGE + i, 'week': week, 'day': DAYS[i % 5], 'rows': rows})
    return pages


def rng(s):
    s = s.strip()
    m = re.fullmatch(r'(\d+)\s*[-–]\s*(\d+)', s)
    if m:
        return int(m.group(1)), int(m.group(2))
    m = re.fullmatch(r'(\d+)', s)
    if m:
        return int(m.group(1)), int(m.group(1))
    raise ValueError(s)


def reps(s):
    per_side = 'per leg' in s or 'per side' in s or 'per arm' in s
    lo, hi = rng(s.replace('per leg', '').replace('per side', '').replace('per arm', ''))
    return {'min': lo, 'max': hi, 'per_side': per_side, 'text': s}


def rest(s):
    if s in ('-', ''):
        return None
    m = re.fullmatch(r'(\d+)\s*[-–]\s*(\d+)\s*(min|sec)', s)
    mult = 60 if m.group(3) == 'min' else 1
    return {'min_s': int(m.group(1)) * mult, 'max_s': int(m.group(2)) * mult, 'text': s}


def rir(s):
    return None if s in ('-', '') else int(s)


TECHNIQUES = {
    '-': None,
    'Myo-reps': 'myo_reps',
    'Two Drop Sets (~25% per)': 'drop_sets_2x25',
    'Weighted Static Hold (30 sec)': 'weighted_static_hold_30s',
}

# Exercises where the PDF says RIR 0 means "no rep left, but don't attempt and fail the last rep".
NO_FAILED_REP = {'Hack Squat', 'Smith Machine Bench Press'}


def build(pdf_path):
    pdf = pdfplumber.open(pdf_path)
    pages = extract_rows(pdf)
    days = []
    for d in DAYS:
        week_pages = [p for p in pages if p['day'] == d]
        base = week_pages[0]['rows']
        slots = []
        for idx, r in enumerate(base):
            m = re.match(r'^(S\d):\s*(.+)$', r['exercise'])
            superset, name = (m.group(1), m.group(2)) if m else (None, r['exercise'])
            wmin, wmax = rng(r['warmup'])
            weeks = {}
            for p in week_pages:
                wr = p['rows'][idx]
                assert wr['exercise'] == r['exercise'], (d, idx, p['week'])
                for k in ('warmup', 'working', 'reps', 'rest', 'sub1', 'sub2', 'notes'):
                    assert wr[k] == r[k], (d, idx, p['week'], k)
                sets = int(wr['working'])
                rirs = [rir(wr[f'rir{i}']) for i in (1, 2, 3)][:sets]
                weeks[str(p['week'])] = {'rir': rirs, 'technique': TECHNIQUES[wr['technique']]}
            slots.append({
                'slot_id': f'{d}_{idx + 1:02d}',
                'exercise': name,
                'superset': superset,
                'warmup_sets': {'min': wmin, 'max': wmax},
                'working_sets': int(r['working']),
                'rep_range': reps(r['reps']),
                'rest': rest(r['rest']),
                'substitutions': [s for s in (r['sub1'], r['sub2']) if s not in ('-', '')],
                'notes': r['notes'],
                'rir0_attempt_failure': name not in NO_FAILED_REP,
                'source_pages': [p['page'] for p in week_pages],
                'weeks': weeks,
            })
        days.append({'id': d, 'name': d.capitalize(), 'slots': slots})
    return days


METHOD = {
    'effort': {
        'scale': 'RIR',
        'definition': 'Reps in reserve: how many more reps you could have done. RIR 0 = failure.',
        'rir0_default': 'Attempt the final rep and fail it.',
        'rir0_safety_exception': 'Hack Squat and Smith Machine Bench Press: RIR 0 means no reps left, '
                                 'but do not attempt and fail the final rep (safety).',
        'warmup_sets_effort': 'Light and not fatiguing.',
        'first_set_to_failure': 'Phase 2 takes the FIRST working set to failure on most exercises '
                                '(Phase 1 took the last set to failure).',
    },
    'blocks': [
        {'block': 1, 'weeks': [1, 2, 3, 4, 5, 6], 'intro_week': 1,
         'description': 'Week 1 is an intro week: most sets 1-2 reps shy of failure instead of 0-1. No intensity techniques.'},
        {'block': 2, 'weeks': [7, 8, 9, 10, 11, 12], 'deload_week': 7,
         'description': 'Week 7 is a deload: most sets 1-2 reps shy of failure. Last-set intensity techniques from week 8.'},
    ],
    'warmup': {
        'general': {
            'duration': '5-10 min',
            'items': [
                {'name': 'Light cardio (treadmill, stairmaster, elliptical, bike…)', 'dose': '5-10 minutes', 'optional': False},
                {'name': 'Arm swings', 'dose': '10 reps per side', 'optional': True},
                {'name': 'Arm circles', 'dose': '10 reps per side', 'optional': True},
                {'name': 'Front-to-back leg swings', 'dose': '10 reps per side', 'optional': True},
                {'name': 'Side-to-side leg swings', 'dose': '10 reps per side', 'optional': True},
                {'name': 'Cable external rotation', 'dose': '15 reps per side', 'optional': True},
            ],
            'tip': 'Dynamic stretches can be done during warm-up sets for the first exercise to save time.',
        },
        'exercise_specific': {
            'by_count': {
                '1': [{'pct': 60, 'reps': {'min': 6, 'max': 10}}],
                '2': [{'pct': 50, 'reps': {'min': 6, 'max': 10}}, {'pct': 70, 'reps': {'min': 4, 'max': 6}}],
                '3': [{'pct': 45, 'reps': {'min': 6, 'max': 10}}, {'pct': 65, 'reps': {'min': 4, 'max': 6}},
                      {'pct': 85, 'reps': {'min': 3, 'max': 4}}],
                '4': [{'pct': 45, 'reps': {'min': 6, 'max': 10}}, {'pct': 60, 'reps': {'min': 4, 'max': 6}},
                      {'pct': 75, 'reps': {'min': 3, 'max': 5}}, {'pct': 85, 'reps': {'min': 2, 'max': 4}}],
            },
            'basis': 'Percent of the planned working weight. 1 warm-up set: "or until you feel warm and loose".',
            'rest_between_s': {'min': 0, 'max': 60},
        },
    },
    'techniques': {
        'drop_sets_2x25': {
            'name': 'Two Drop Sets (~25% per)',
            'when': 'After the final working set only',
            'description': 'After reaching failure, reduce the weight by ~25% and go to failure again. Repeat once '
                           'more (3 back-to-back sets in total).',
            'drops': 2, 'drop_pct': 25,
        },
        'myo_reps': {
            'name': 'Myo-reps',
            'when': 'After the final working set only',
            'description': 'After failure, rest 5 seconds and attempt 2 more reps. Repeat (5 s rest → 2 reps) until '
                           'you fail to complete 2 full-ROM reps (usually within 1-3 cycles).',
            'rest_s': 5, 'reps_per_cycle': 2,
        },
        'weighted_static_hold_30s': {
            'name': 'Weighted Static Hold (30 sec)',
            'when': 'After the final working set of Standing Calf Raise (or its substitution)',
            'description': 'After failing, hold the bottom position under full calf tension for 30 seconds.',
            'hold_s': 30,
        },
        'lengthened_partials': {
            'name': 'Lengthened Partials',
            'when': 'After the final working set only',
            'description': 'After reaching failure with full ROM, keep doing partial reps in the stretched position '
                           'until failure.',
            'used_in_this_version': False,
        },
    },
    'progression': {
        'rule': 'Once you can perform all working sets at the top of the rep range, increase the load next session.',
        'fallback': 'If adding weight would drop you below the range, keep the same weight and extend the range '
                    'slightly (e.g. 6-8 → aim for 6-10).',
        'tracking': 'Log load and reps for every working set.',
    },
    'rest': {
        'working_sets': 'As listed per exercise.',
        'warmup_sets_s': {'min': 0, 'max': 60},
        'between_exercises_s': {'min': 60, 'max': 120},
        'faq': 'Timing rest is optional; the priority is feeling recovered without letting the session drag.',
    },
    'supersets': 'Exercises with the same prefix (S1, S2, S3…) are a superset: one set of the first, then one set '
                 'of the second, then rest the listed time (listed on the second exercise) and repeat.',
    'substitutions': 'Every exercise lists two alternatives with a very similar training effect. Prefer the main '
                     'exercise if you can; swap for equipment or preference.',
    'exercise_order': 'Small reorders are fine when the gym is crowded; avoid scrambling the workout.',
    'looping': 'After week 12, loop back to week 1.',
    'four_day_option': 'Run the workouts in order and carry the remaining workout(s) into the next week.',
}


def main():
    pdf_path = sys.argv[1]
    out = {
        'schema_version': 1,
        'program': {
            'id': 'min_max_phase2_5x',
            'name': 'Min-Max Phase 2: Peak Physique (5x/week)',
            'author': 'Jeff Nippard',
            'source': 'Extracted from the owner\'s personal copy of the PDF for personal use. The PDF itself is not in this repository.',
            'weeks': 12,
            'split': ['Upper', 'Lower', 'Push', 'Pull', 'Arms'],
            # Rest-day banners appear after Lower and after Arms in every week's tables.
            'week_layout': ['Upper', 'Lower', 'Rest', 'Push', 'Pull', 'Arms', 'Rest'],
        },
        'method': METHOD,
        'days': build(pdf_path),
    }
    json.dump(out, open('assets/programs/min_max_phase2.json', 'w'), indent=2, ensure_ascii=False)
    print('wrote assets/programs/min_max_phase2.json',
          sum(len(d['slots']) for d in out['days']), 'slots')


if __name__ == '__main__':
    main()
