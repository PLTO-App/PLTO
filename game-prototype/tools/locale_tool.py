"""Keeps locale/strings.csv (the game's texts, one column per language) in order.
  python3 -I locale_tool.py <game_dir> add <file.py with dict S...>   adds or updates keys from Python dicts (Hebrew column)
  python3 -I locale_tool.py <game_dir> check                          lists keys used in code and content that have no text
The CSV is the source of truth; this script only writes it with proper quoting so commas in Hebrew stay safe."""
import csv, json, os, re, sys

game = sys.argv[1]; cmd = sys.argv[2]
path = os.path.join(game, 'locale', 'strings.csv')

def read():
    rows = {}; order = []; langs = ['he']
    if os.path.exists(path):
        with open(path, newline='', encoding='utf-8') as f:
            r = csv.reader(f); head = next(r); langs = head[1:]
            for row in r:
                if not row: continue
                rows[row[0]] = dict(zip(langs, row[1:])); order.append(row[0])
    return rows, order, langs

def write(rows, order, langs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL, lineterminator='\n')
        w.writerow(['keys'] + langs)
        for k in order: w.writerow([k] + [rows[k].get(l, '') for l in langs])

if cmd == 'add':
    rows, order, langs = read()
    for src in sys.argv[3:]:
        ns = {}; exec(open(src, encoding='utf-8').read(), ns)
        for name, d in ns.items():
            if not isinstance(d, dict) or name.startswith('__'): continue
            for k, v in d.items():
                if k not in rows: rows[k] = {}; order.append(k)
                rows[k]['he'] = v
    write(rows, order, langs); print('keys', len(order))
elif cmd == 'check':
    rows, order, langs = read()
    used = set()
    key_re = re.compile(r'"((?:day|biz|cap|ing|prod|mk|upg|sup|partner|svc|staff|role|wx|npc|goal|insp|err|coach|week|ev|ui|hint|tut|scene|sign|set|ach|bank|tab|plan|sum|town|people|dlg|today|orders|fin|bld|act|start|setup|track|fmt)\.[a-z0-9_.]+)"')
    for root, _, files in os.walk(game):
        if '/.godot' in root or '/tools' in root: continue
        for fn in files:
            if fn.endswith(('.gd', '.json')):
                for m in key_re.finditer(open(os.path.join(root, fn), encoding='utf-8').read()): used.add(m.group(1))
    missing = sorted(k for k in used if k not in rows or not rows[k].get('he'))
    print('used', len(used), 'defined', len(rows), 'missing', len(missing))
    for k in missing: print('  MISSING', k)
    sys.exit(1 if missing else 0)
