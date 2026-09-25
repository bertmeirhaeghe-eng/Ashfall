#!/usr/bin/env python3
"""Collects every user-visible English string in the game (GDScript literals and
data/rules.json names) and checks data/lang/<lang>.json for missing entries.

  python3 tools/lang/extract_strings.py            # report missing Dutch strings
  python3 tools/lang/extract_strings.py --list F   # write the missing ones to F as {id: english}

Strings are the English text itself; the translation file maps English -> Dutch.
"""
import glob, json, re, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
# lines whose strings never reach the player
SKIP_LINE = re.compile(r'^\s*#|print\(|printerr\(|push_warning|push_error|load\(|\.name = |get_node|has_meta|set_meta|get_meta|'
                       r'add_theme_|theme_override|begins_with\("--|get_environment|ClassDB|\.call\(|\.set\(|connect\(|'
                       r'AudioServer|bus = |get_bus_index|Input\.|is_action')
# string literals that are identifiers, file names, formats without words ...
def is_text(s):
    if not re.search(r'[A-Za-z]{2}', s):
        return False
    if s.startswith(('res://', 'user://', '@', '#', 'spk_', 'ack_', '%s|')):
        return False
    if re.fullmatch(r'[a-z0-9_./]+', s):          # ids, keys, paths
        return False
    if re.fullmatch(r'[a-z_]+%d', s) or re.fullmatch(r'[a-zA-Z0-9_.-]+', s) and '-' in s:  # tags, file names
        return False
    if re.fullmatch(r'[A-Za-z]+_[A-Za-z0-9_]+', s):  # node / bus names
        return False
    if '.amdl' in s:
        return False
    if s.startswith('[color') and re.fullmatch(r'(\[[^\]]*\]|%[sd]|[\s:/()-])*', s):
        return False
    return True

NOT_UI = {"GeometryInstance3D", "MeshInstance3D", "AMDL", "PanelContainer", "Button", "Label", "RichTextLabel", "ProgressBar",
          "English", "Nederlands", "Player", "--langcheck", "Hollerdorf", "Weissbach", "Lenz", "MCV", "Voice", "Music", "Sfx", "Master", "Map", "World", "Fx", "Camera", "Input", "HUD", "Mission", "Sun",
          "Weather", "Kokoro", "PiperTTS", "TextToSpeech", "Harden", "Kokoro TTS", "ASHFALL"}

def unescape(s):
    return s.encode('utf-8').decode('unicode_escape').encode('latin-1').decode('utf-8')

def collect():
    out = {}
    for f in sorted(glob.glob(os.path.join(ROOT, 'scripts', '**', '*.gd'), recursive=True)):
        rel = os.path.relpath(f, ROOT)
        if '/dev/' in rel:
            continue
        src = open(f, encoding='utf-8').read()
        # multi-line """ strings (help text)
        for m in re.finditer(r'"""(.*?)"""', src, re.S):
            out.setdefault(m.group(1), rel)
        src = re.sub(r'""".*?"""', '""', src, flags=re.S)
        for line in src.split('\n'):
            if SKIP_LINE.search(line):
                continue
            for m in LIT.finditer(line):
                s = unescape(m.group(1))
                if is_text(s) and s not in NOT_UI:
                    out.setdefault(s, rel)
    rules = json.load(open(os.path.join(ROOT, 'data', 'rules.json'), encoding='utf-8'))
    for sect in ('units', 'structures'):
        for d in rules.get(sect, {}).values():
            if 'name' in d:
                out.setdefault(d['name'], 'data/rules.json')
            if 'desc' in d:
                out.setdefault(d['desc'], 'data/rules.json')
    for s in ["primary", "secondary", "bonus", "Primary", "Secondary", "Bonus", "Infantry", "Light", "Heavy",
              "Structure", "Rookie", "Veteran", "Elite", "ground", "air", "ground and air"]:
        out.setdefault(s, 'computed')
    return out

def main():
    lang = 'nl'
    strings = collect()
    path = os.path.join(ROOT, 'data', 'lang', lang + '.json')
    table = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
    missing = [s for s in strings if s not in table]
    unused = [s for s in table if not s.startswith('@') and s not in strings]
    if '--list' in sys.argv:
        dst = sys.argv[sys.argv.index('--list') + 1]
        json.dump({str(i): {"en": s, "from": strings[s]} for i, s in enumerate(missing)}, open(dst, 'w', encoding='utf-8'),
                  ensure_ascii=False, indent=1)
    print("%d strings, %d translated, %d missing, %d not found in code (may be runtime-built)" %
          (len(strings), len(strings) - len(missing), len(missing), len(unused)))
    if '--verbose' in sys.argv:
        for s in missing:
            print("  missing [%s] %s" % (strings[s], s[:100]))
    return 0 if not missing else 1

if __name__ == '__main__':
    sys.exit(main())
