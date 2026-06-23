#!/usr/bin/env python3
import json
from pathlib import Path

p = Path(__file__).resolve().parents[1] / 'database' / 'menu.json'
print('Loading', p)
with p.open() as f:
    data = json.load(f)

cats = data.get('categories', [])
for i, c in enumerate(cats):
    cid = c.get('id','')
    name = c.get('name','')
    if cid.startswith('yosh-s') or 'Yosh' in name and 'Teriyaki' in name:
        print('Found teriyaki category at index', i)
        # preserve any existing spicy-beef item if present
        existing_items = {it.get('id'): it for it in c.get('items', [])}
        new_ids = [
            ('tofu-teriyaki','Tofu Teriyaki'),
            ('chicken-teriyaki','Chicken Teriyaki'),
            ('spicy-chicken-teriyaki','Spicy Chicken Teriyaki'),
            ('beef-teriyaki','Beef Teriyaki'),
            ('salmon-teriyaki','Salmon Teriyaki'),
            ('spicy-beef-teriyaki','Spicy Beef Teriyaki')
        ]
        new_items = []
        for nid, nname in new_ids:
            if nid in existing_items:
                new_items.append(existing_items[nid])
            elif nid == 'spicy-beef-teriyaki' and 'spicy-beef-teriyaki' in existing_items:
                new_items.append(existing_items[nid])
            else:
                new_items.append({
                    'id': nid,
                    'name': nname,
                    'description': None,
                    'price': None,
                    'image': None,
                    'tags': [],
                    'available': True,
                    'featured': False
                })
        c['id'] = 'yosh-teriyaki'
        c['name'] = "Yosh's Teriyaki (comes with miso soup, rice & broccoli)"
        c['items'] = new_items
        break

with p.open('w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print('Wrote', p)
