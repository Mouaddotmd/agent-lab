#!/usr/bin/env python3
"""Checks one live chat run in Agent Lab Native (ported from Mavis's tools/check-chat-run.py).

1. defaults write dev.agentlab.native agentLabScrollLog -bool YES   (then reopen the app; the log empties at launch)
2. Send an agent a task that uses tools.
3. python3 native/tools/check-chat-run.py

Reads ~/Library/Caches/Agent Lab/scroll-log.txt and the newest conversation in the engine's data folder, and flags:
ghost frames, snaps (the view jumped without the glide), lurches (a glide step over 12 pt; your send's quick glide is
exempt), a send with no glide, content shrinking while
the agent works (only the finished swap may shrink it), and reports left open.
"""
import glob, json, os, re

log = os.path.expanduser('~/Library/Caches/Agent Lab/scroll-log.txt')
data = os.environ.get('AGENT_LAB_DATA', os.path.expanduser('~/Library/Application Support/Agent Lab'))
rows = []
for line in open(log):
    m = re.match(r'([\d.]+) y=([\d.-]+) h=([\d.]+).*?following=(\d) touching=(\d)\s*(.*)', line)
    if m: rows.append((float(m[1]), float(m[2]), float(m[3]), int(m[4]), int(m[5]), m[6].strip()))
issues = []
ghosts = []
for i, r in enumerate(rows):
    if r[5].startswith('HELD'):
        back = float(re.search(r'HELD back ([\d.]+)', r[5])[1])
        before = [q for q in rows[:i] if not q[5]]
        if before and before[-1][1] >= r[1] + back - 0.5: ghosts.append((r[0], back))
held = sum(1 for r in rows if r[5].startswith('HELD'))
print(f"stray moves put back before drawing: {held - len(ghosts)}")
if ghosts: issues.append(f"ghost frames (moved view drawn before put back): {ghosts}")
prev = None; snaps = []; shrinks = []; steps = []
for r in rows:
    if r[5].startswith('FOLLOW'):
        steps.append(float(re.search(r'move=([\d.]+)', r[5])[1])); prev = None; continue
    if r[5]: continue
    if prev and r[1] - prev[1] > 12 and not prev[5] and not r[4]: snaps.append((r[0], round(r[1] - prev[1], 1), round(r[2] - prev[2], 1)))
    if prev and r[2] < prev[2] - 1: shrinks.append((r[0], round(r[2] - prev[2], 1)))
    prev = r
if snaps: issues.append(f"snaps (view jumped without the glide): {snaps[:5]}")
jumps = [s for s, r in zip(steps, [r for r in rows if r[5].startswith('FOLLOW')]) if 'JUMP' not in r[5] and 'SEND' not in r[5]]
big = max(jumps) if jumps else 0
if big > 12: issues.append(f"largest glide step {big:.1f} pt (lurch)")

files = sorted(glob.glob(os.path.join(data, 'messages', '*.json')), key=os.path.getmtime)
if files:
    msgs = json.load(open(files[-1]))
    you = [m for m in msgs if m['role'] == 'user']
    turn = you[-1]['id'] if you else None
    mine = [m for m in msgs if m.get('turn') == turn]
    raw = '\n\n'.join(m['text'] for m in mine if m['role'] == 'assistant')
    tools = [m for m in mine if m['role'] == 'tool']
    plan = re.search(r'⟦\s*plan\s*:([^⟧]*)⟧', raw); dones = re.findall(r'⟦\s*done\s*:\s*(\d+)', raw)
    print(f"turn {str(turn)[:12]} steps={len(tools)} unfinished={sum(1 for t in tools if not t.get('done'))} plan={'yes (' + str(len(plan[1].split('|'))) + ')' if plan else 'no'} ticks={dones}")
    print(f"opening: {raw.split('⟦')[0].strip().splitlines()[0][:90] if raw.strip() else ''!r}")
    if '⟦report' in raw and '⟦/report⟧' not in raw: issues.append("report left open (the card still shows as finished)")
sends = [r for r in rows if r[5].startswith('FOLLOW') and 'SEND' in r[5]]
if any(r[5].startswith('SENT') for r in rows) and not sends: issues.append('a send with no send glide')
print(f"send glide frames={len(sends)}  glide steps={len(steps)} largest={big:.1f}  shrinks={shrinks} (the last one is the finished swap)")
if len(shrinks) > 1: issues.append(f"content shrank while working: {shrinks[:-1]}")
print("ISSUES:" if issues else "no issues", *issues, sep="\n  ")
