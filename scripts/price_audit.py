#!/usr/bin/env python3
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / 'database' / 'menu.json'
OUT = ROOT / 'docs' / 'price_audit.md'

with DB.open() as f:
    data = json.load(f)

lines = ["# Price audit\n","This report lists every menu item and its current price. Items with missing prices are flagged.\n\n"]
count_missing = 0
count_missing_yoshi = 0
for cat in data.get('categories', []):
    lines.append(f"## {cat.get('name')}\n\n")
    for it in cat.get('items', []):
        pid = it.get('id')
        name = it.get('name')
        price = it.get('price')
        yoshi = it.get('yoshi_price')
        if price is None:
            lines.append(f"- **MISSING**: `{pid}` — {name}\n")
            count_missing += 1
        else:
            try:
                p = float(price)
                lines.append(f"- `{pid}` — {name} — ${p:.2f}")
            except Exception:
                lines.append(f"- **INVALID**: `{pid}` — {name} — value: {price}")
        if yoshi is None:
            lines.append("  - Yoshi price: **MISSING**\n")
            count_missing_yoshi += 1
        else:
            try:
                yp = float(yoshi)
                lines.append(f"  - Yoshi price: ${yp:.2f}\n")
            except Exception:
                lines.append(f"  - Yoshi price: **INVALID** ({yoshi})\n")

lines.append(f"\nTotal items with missing primary prices: {count_missing}\n")
lines.append(f"Total items with missing Yoshi prices: {count_missing_yoshi}\n")

OUT.parent.mkdir(parents=True, exist_ok=True)
with OUT.open('w') as f:
    f.writelines(lines)
print('Wrote', OUT)
