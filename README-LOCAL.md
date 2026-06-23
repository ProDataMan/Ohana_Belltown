# Local dev: run backend and preview

From the repo root, create a venv, install backend deps, and start the Flask API:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
python3 backend/app/main.py
```

Then open the preview at `http://localhost:5000/frontend/preview/index.html` or the admin editor at `http://localhost:5000/frontend/admin/index.html` (or serve `frontend` via a simple static server).
