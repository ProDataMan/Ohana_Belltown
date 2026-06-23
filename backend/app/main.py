from flask import Flask, jsonify, request, send_from_directory
from pathlib import Path
import json
import os

ROOT = Path(__file__).resolve().parents[2]
MENU_FILE = ROOT / "database" / "menu.json"

app = Flask(__name__, static_folder=str(ROOT / "frontend" / "public"))


def read_menu():
    if MENU_FILE.exists():
        return json.loads(MENU_FILE.read_text(encoding="utf-8"))
    return {"restaurant": {}, "categories": []}


def write_menu(data):
    MENU_FILE.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


@app.route("/api/menu", methods=["GET"])
def get_menu():
    return jsonify(read_menu())


@app.route("/api/menu", methods=["POST"])
def save_menu():
    data = request.get_json()
    if not isinstance(data, dict):
        return ("Invalid payload", 400)
    write_menu(data)
    return ("OK", 200)


@app.route("/images/<path:filename>")
def images(filename):
    images_dir = ROOT / "frontend" / "public" / "images"
    return send_from_directory(str(images_dir), filename)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "5000"))
    app.run(host="127.0.0.1", port=port, debug=True)
