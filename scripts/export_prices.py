#!/usr/bin/env python3
import csv
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / 'database' / 'menu.json'
OUT = ROOT / 'database' / 'menu_prices.csv'

data = json.loads(DB.read_text(encoding='utf-8'))
with OUT.open('w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(['id','category','name','price','yoshi_price'])
    for cat in data.get('categories',[]):
        for it in cat.get('items',[]):
            w.writerow([
                it.get('id',''),
                cat.get('id',''),
                it.get('name',''),
                '' if it.get('price') is None else it.get('price'),
                '' if it.get('yoshi_price') is None else it.get('yoshi_price')
            ])
print('Wrote', OUT)
