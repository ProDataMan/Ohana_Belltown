Admin UI

This admin UI is a minimal editor for `database/menu.json` and supports image uploads.

Local run (recommended for testing):

1. Create a virtualenv and install requirements:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. (Optional) Create a GitHub Personal Access Token (PAT) with `repo` scope and export it for commits to `gh-pages`:

```bash
export GITHUB_TOKEN=ghp_...yourtoken...
export REPO_OWNER=ProDataMan
export REPO_NAME=Ohana_Belltown
export BRANCH=gh-pages
```

3. Run the admin server:

```bash
python3 tools/admin_server.py --host 0.0.0.0 --port 8001
```

4. Open `http://localhost:8001/` to edit the menu and upload images. If `GITHUB_TOKEN` is set the server will attempt to commit changes and uploads to the `gh-pages` branch; otherwise it writes locally under `database/menu.json` and `frontend/public/uploads/`.

Publishing to GitHub Pages (manual steps):

- Option 1 (create `gh-pages` branch locally):
	- Build a static preview (copy files you want into a `docs/` folder or create a static site) and push to `gh-pages` branch.
	- In GitHub repo Settings → Pages, select `gh-pages` as source.

- Option 2 (admin server commits directly):
	- Provide a PAT with repo write permissions and set the environment variables as above. The admin server will commit `database/menu.json` and uploaded images to the `gh-pages` branch.

Security note: never commit PATs into the repo. For production, use a backend with a secure secret store or GitHub Actions with repository secrets.
