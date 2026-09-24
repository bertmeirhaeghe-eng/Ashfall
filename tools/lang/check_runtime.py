#!/usr/bin/env python3
"""Filters the "TEST untranslated:" lines of a --langcheck test run (stdin) down to
strings that really have no translation. Labels look their (already translated)
text up again, so anything built from Dutch table entries is ignored."""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
table = json.load(open(os.path.join(ROOT, 'data', 'lang', 'nl.json'), encoding='utf-8'))
values = [v for k, v in table.items() if not k.startswith('@')]
FMT = re.compile(r'%[-+ 0#]*\d*(?:\.\d+)?[sdif%]')
pats = []
for v in values:
    parts = FMT.split(v)
    if len(parts) > 1:
        rx = '.*?'.join(re.escape(p) for p in parts)
        pats.append(re.compile(rx, re.S))
vals = set(values)
names = {"Ashfall", "Hollerdorf", "Weissbach", "Lenz", "SIBYL", "Kestrel Ruiz", "Tallow", "Dr. Lindqvist", "Lt. Havel"}

SEP = re.compile(r'\s{2,}|\s*//\s*|: |\n|,  |\s+-\s+')
TIME = re.compile(r'[\d:%.,+$()x/ -]*')

def known(s, depth=0):
    s = s.strip()
    if not s or s in vals or s in names or TIME.fullmatch(s) or not re.search(r'[A-Za-z]{2}', s):
        return True
    if any(p.fullmatch(s) for p in pats):
        return True
    if s.upper() == s and any(v.upper() == s for v in vals):   # upper-cased headers
        return True
    if depth > 6:
        return False
    for m in SEP.finditer(s):
        if known(s[:m.start()], depth + 1) and known(s[m.end():], depth + 1):
            return True
    return False

bad = []
for line in sys.stdin:
    if line.startswith('TEST untranslated: '):
        s = line[len('TEST untranslated: '):].rstrip('\n').replace('\\n', '\n')
        s = re.sub(r'\[/?[a-z]+(=[^\]]*)?\]|\[[ x-]\]', '', s)   # bbcode, objective marks
        if not known(s):
            bad.append(s)
for s in sorted(set(bad)):
    print('UNTRANSLATED:', s.replace('\n', '\\n'))
print('%d untranslated strings' % len(bad))
sys.exit(1 if bad else 0)
