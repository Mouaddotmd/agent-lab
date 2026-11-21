#!/usr/bin/env python3
"""System drift check: views must use the MAVIS system (Sources/MavisSystem.swift, Theme.swift, Themes.swift),
not their own numbers. Counts raw colours, sizes, gaps, corners, font sizes and strokes written as literals in each
view file and compares them with tools/systemlint.baseline.json.

  python3 tools/systemlint.py            check: fails if any file has more than its baseline (new files start at 0)
  python3 tools/systemlint.py --update   after moving a file onto the system: lowers the baseline (never raises it)
  python3 tools/systemlint.py --list F   prints every flagged line in file F

The count can only go down. When it reaches 0 for a file, that file follows the system completely.
Spec: docs/mavis-system.md.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, 'Sources')
BASE = os.path.join(HERE, 'systemlint.baseline.json')
# Where values are allowed to be written: the system itself, the theme presets, and generated icon data.
ALLOWED = {'MavisSystem.swift', 'Theme.swift', 'Themes.swift', 'IconData.swift', 'Icons.swift', 'MavisIcons.swift'}

NUM = r'(?<![\w.])(?!0(?:\.0+)?\b)\d+(?:\.\d+)?\b'   # a literal number other than 0
RULES = [
    ('colour', re.compile(r'\b(?:Color|NSColor)\(\s*(?:0x[0-9a-fA-F]+|rgb:|red:|white:|\.sRGB|srgbRed:|calibratedRed:|hue:)')),
    ('padding', re.compile(r'\.padding\([^)\n]*' + NUM)),
    ('frame', re.compile(r'\.frame\([^)\n]*\b(?:width|height|minWidth|minHeight|maxWidth|maxHeight|idealWidth|idealHeight):\s*' + NUM)),
    ('spacing', re.compile(r'\bspacing:\s*' + NUM)),
    ('corner', re.compile(r'(?:cornerRadius:?\s*\(?\s*|\.cornerRadius\(\s*)' + NUM)),
    ('font', re.compile(r'\b(?:size|ofSize):\s*' + NUM)),
    ('stroke', re.compile(r'\blineWidth:\s*' + NUM)),
    ('offset', re.compile(r'\.offset\([^)\n]*' + NUM)),
]

def scan(path):
    hits = []
    with open(path, encoding='utf-8') as f:
        for n, line in enumerate(f, 1):
            code = line.split('//', 1)[0]
            for kind, rx in RULES:
                for _ in rx.finditer(code):
                    hits.append((n, kind, line.rstrip()))
    return hits

def counts():
    out = {}
    for name in sorted(os.listdir(SRC)):
        if name.endswith('.swift') and name not in ALLOWED:
            out[name] = len(scan(os.path.join(SRC, name)))
    return out

def main():
    args = sys.argv[1:]
    if args[:1] == ['--list'] and len(args) > 1:
        for n, kind, line in scan(os.path.join(SRC, args[1])):
            print(f'{args[1]}:{n}  {kind:8} {line.strip()}')
        return 0
    now = counts()
    base = json.load(open(BASE)) if os.path.exists(BASE) else None
    if base is None or args[:1] == ['--update']:
        if base is not None:
            raised = {f: (base.get(f, 0), c) for f, c in now.items() if c > base.get(f, 0)}
            if raised:
                for f, (b, c) in raised.items(): print(f'systemlint: {f} went up ({b} → {c}); fix it, the baseline only goes down')
                return 1
        json.dump(now, open(BASE, 'w'), indent=1, sort_keys=True)
        print(f'systemlint: baseline written, {sum(now.values())} raw values left in {sum(1 for c in now.values() if c)} files')
        return 0
    worse = [(f, base.get(f, 0), c) for f, c in now.items() if c > base.get(f, 0)]
    total, was = sum(now.values()), sum(base.values())
    if worse:
        for f, b, c in worse:
            print(f'systemlint: {f} has {c} raw values (baseline {b}). Use MV.* from Sources/MavisSystem.swift.')
            print(f'            python3 tools/systemlint.py --list {f}')
        return 1
    note = f', down {was - total} — run with --update to lock it in' if total < was else ''
    print(f'systemlint: ok, {total} raw values left{note}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
