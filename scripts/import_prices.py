#!/usr/bin/env python3
import csv
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / 'database' / 'menu.json'
INFILE = ROOT / 'database' / 'menu_prices.csv'

data = json.loads(DB.read_text(encoding='utf-8'))
# load CSV into dict
updates = {}
with INFILE.open(encoding='utf-8') as f:
    r = csv.DictReader(f)
    for row in r:
        pid = row.get('id')
        price = row.get('price','').strip()
        yoshi = row.get('yoshi_price','').strip()
        val = None
        yval = None
        if price != '':
            try:
                val = float(price)
            except Exception:
                val = None
        if yoshi != '':
            try:
                yval = float(yoshi)
            except Exception:
                yval = None
        updates[pid] = (val, yval)

# apply updates
changed = 0
for cat in data.get('categories',[]):
    for it in cat.get('items',[]):
        pid = it.get('id')
        if pid in updates:
            val, yval = updates[pid]
            it['price'] = val
            it['yoshi_price'] = yval
            changed += 1

DB.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding='utf-8')
print('Applied', changed, 'price updates to', DB)
