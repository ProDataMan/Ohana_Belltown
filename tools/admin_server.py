#!/usr/bin/env python3
"""Admin server to edit `database/menu.json` and upload images.

- GET /api/menu -> returns local `database/menu.json`
- POST /api/save-menu -> accepts JSON body and writes to disk or commits to GitHub (if GITHUB_TOKEN provided)
- POST /api/upload-image -> multipart upload; saves locally and optionally commits to gh-pages branch via GitHub API

Configuration via env:
- GITHUB_TOKEN: (optional) PAT with repo permissions to commit files to the repo on branch `gh-pages`.
- REPO_OWNER, REPO_NAME: optional, default to ProDataMan/Ohana_Belltown from repo context
- BRANCH: branch to commit to; default `gh-pages`

Run:
    python3 tools/admin_server.py

"""
import os
import base64
import json
from pathlib import Path
from flask import Flask, jsonify, request, send_from_directory
import requests

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / 'database' / 'menu.json'
PUBLIC_UPLOADS = ROOT / 'frontend' / 'public' / 'uploads'
PUBLIC_UPLOADS.mkdir(parents=True, exist_ok=True)

GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN')
REPO_OWNER = os.environ.get('REPO_OWNER', 'ProDataMan')
REPO_NAME = os.environ.get('REPO_NAME', 'Ohana_Belltown')
BRANCH = os.environ.get('BRANCH', 'gh-pages')

app = Flask(__name__, static_folder=str(ROOT / 'frontend' / 'admin'))


def github_put_file(path: str, content_bytes: bytes, message: str):
    """Create or update a file in the repo at `path` on branch BRANCH using GITHUB_TOKEN."""
    if not GITHUB_TOKEN:
        raise RuntimeError('GITHUB_TOKEN not set')
    api = f'https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/contents/{path}'
    headers = {'Authorization': f'token {GITHUB_TOKEN}', 'Accept': 'application/vnd.github.v3+json'}
    # check if file exists to get sha
    r = requests.get(api + f'?ref={BRANCH}', headers=headers)
    if r.status_code == 200:
        sha = r.json().get('sha')
    else:
        sha = None
    payload = {
        'message': message,
        'content': base64.b64encode(content_bytes).decode('ascii'),
        'branch': BRANCH
    }
    if sha:
        payload['sha'] = sha
    r = requests.put(api, headers=headers, json=payload)
    r.raise_for_status()
    return r.json()


@app.route('/')
def admin_ui():
    return app.send_static_file('index.html')


@app.route('/api/menu', methods=['GET'])
def get_menu():
    with DB_PATH.open() as f:
        return jsonify(json.load(f))


@app.route('/api/save-menu', methods=['POST'])
def save_menu():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid JSON'}), 400
    # write locally
    with DB_PATH.open('w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    # if token provided, commit to gh-pages branch path
    if GITHUB_TOKEN:
        # commit to same path under repo: database/menu.json
        try:
            # commit canonical menu.json (useful for API-backed sites)
            github_put_file('database/menu.json', json.dumps(data, ensure_ascii=False, indent=2).encode('utf-8'), 'Update menu via admin UI')
            # also commit a copy under docs so Pages using /docs can read it
            github_put_file('docs/database/menu.json', json.dumps(data, ensure_ascii=False, indent=2).encode('utf-8'), 'Update menu (docs) via admin UI')
        except Exception as e:
            return jsonify({'warning': 'Saved locally but failed to commit to GitHub', 'error': str(e)}), 202
    return jsonify({'ok': True})


@app.route('/api/upload-image', methods=['POST'])
def upload_image():
    if 'file' not in request.files:
        return jsonify({'error': 'no file part'}), 400
    f = request.files['file']
    filename = request.form.get('filename') or f.filename
    # save locally under frontend/public/uploads
    relpath = Path('frontend') / 'public' / 'uploads' / filename
    local_path = PUBLIC_UPLOADS / filename
    f.save(str(local_path))
    # commit to gh-pages branch under relpath
    if GITHUB_TOKEN:
        try:
            with open(local_path, 'rb') as fh:
                # commit the uploaded file into the repo at frontend/public/uploads/<filename>
                github_put_file(str(relpath), fh.read(), f'Upload image {filename} via admin UI')
        except Exception as e:
            return jsonify({'warning': 'Saved locally but failed to commit to GitHub', 'error': str(e)}), 202
    return jsonify({'ok': True, 'path': f'/uploads/{filename}'})


@app.route('/uploads/<path:filename>')
def serve_upload(filename):
    return send_from_directory(str(PUBLIC_UPLOADS), filename)


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8001)
    args = parser.parse_args()
    print('GITHUB_TOKEN set' if GITHUB_TOKEN else 'GITHUB_TOKEN not set; server will only write locally')
    app.run(host=args.host, port=args.port)
