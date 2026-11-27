"""Step 0: copy the original videos from an Immich album onto the NAS and
build manifest.csv. Runs entirely on the server; nothing leaves the LAN.

Re-running is safe: files already downloaded (SHA-1 matches Immich's checksum)
are skipped, and your edits to the manifest's include/notes columns are kept.
"""
from __future__ import annotations

import base64
import hashlib
import os
import re
import sys
from pathlib import Path

import requests

from .common import RAW, USER_FIELDS, audio_info, read_manifest, write_manifest


class Immich:
    def __init__(self, url: str, key: str):
        self.base = url.rstrip("/")
        if not self.base.endswith("/api"):
            self.base += "/api"
        self.s = requests.Session()
        self.s.headers.update({"x-api-key": key, "Accept": "application/json"})

    def get(self, path: str, **params):
        r = self.s.get(self.base + path, params=params, timeout=60)
        r.raise_for_status()
        return r.json()

    def post(self, path: str, body: dict):
        r = self.s.post(self.base + path, json=body, timeout=60)
        r.raise_for_status()
        return r.json()

    def find_album(self, name_or_id: str) -> dict:
        albums = self.get("/albums") + self.get("/albums", shared="true")
        for a in albums:
            if a["id"] == name_or_id or a.get("albumName", "").strip() == name_or_id.strip():
                return a
        names = sorted({a.get("albumName", "") for a in albums})
        sys.exit(f"Album '{name_or_id}' not found. Albums visible to this key: {names}")

    def album_assets(self, album_id: str) -> list[dict]:
        album = self.get(f"/albums/{album_id}")
        assets = album.get("assets") or []
        if not assets and album.get("assetCount"):
            # Newer Immich versions may omit assets here; page through search.
            page, assets = 1, []
            while page:
                res = self.post("/search/metadata",
                                {"albumIds": [album_id], "page": page, "size": 500})
                assets += res["assets"]["items"]
                page = res["assets"].get("nextPage")
                page = int(page) if page else None
        return assets

    def download(self, asset_id: str, dest: Path) -> str:
        """Stream the original file to dest; return its base64 SHA-1."""
        h = hashlib.sha1()
        part = dest.with_name(dest.name + ".part")
        with self.s.get(f"{self.base}/assets/{asset_id}/original",
                        stream=True, timeout=600) as r:
            r.raise_for_status()
            with part.open("wb") as f:
                for chunk in r.iter_content(1 << 20):
                    f.write(chunk)
                    h.update(chunk)
        part.replace(dest)
        return base64.b64encode(h.digest()).decode()


def sha1_b64(path: Path) -> str:
    h = hashlib.sha1()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return base64.b64encode(h.digest()).decode()


def dest_name(asset: dict) -> str:
    when = (asset.get("localDateTime") or asset.get("fileCreatedAt") or "")[:19]
    when = re.sub(r"[^0-9]", "", when)  # 20190704153000
    stamp = f"{when[:8]}_{when[8:14]}" if len(when) >= 14 else "nodate"
    ext = Path(asset.get("originalFileName", "")).suffix.lower() or ".mp4"
    return f"{stamp}_{asset['id'][:8]}{ext}"


def main(args) -> None:
    url, key = os.environ.get("IMMICH_URL"), os.environ.get("IMMICH_API_KEY")
    album_name = args.album or os.environ.get("IMMICH_ALBUM")
    if not (url and key and album_name):
        sys.exit("Set IMMICH_URL, IMMICH_API_KEY and IMMICH_ALBUM in the stack's .env")

    im = Immich(url, key)
    album = im.find_album(album_name)
    assets = [a for a in im.album_assets(album["id"]) if a.get("type") == "VIDEO"]
    print(f"Album '{album['albumName']}': {len(assets)} videos")

    RAW.mkdir(parents=True, exist_ok=True)
    old = {r["asset_id"]: r for r in read_manifest()}
    rows = []
    for i, a in enumerate(assets, 1):
        dest = RAW / dest_name(a)
        label = f"[{i}/{len(assets)}] {a.get('originalFileName')} -> {dest.name}"
        if dest.exists() and (args.no_verify or sha1_b64(dest) == a.get("checksum")):
            print(f"{label}: already here")
        else:
            if dest.exists():
                dest.chmod(0o644)
            print(f"{label}: downloading")
            got = im.download(a["id"], dest)
            if a.get("checksum") and got != a["checksum"]:
                print(f"  WARNING: checksum mismatch for {dest.name}")
        dest.chmod(0o444)  # originals are read-only from here on

        row = {"asset_id": a["id"], "file": dest.name,
               "original_name": a.get("originalFileName", ""),
               "recorded_at": (a.get("localDateTime") or a.get("fileCreatedAt") or "")[:19],
               "include": "yes", "notes": ""}
        row.update(audio_info(dest))
        if not row["audio_codec"]:
            row["include"], row["notes"] = "no", "no audio track"
        for k in USER_FIELDS:
            if a["id"] in old and old[a["id"]].get(k, "") != "":
                row[k] = old[a["id"]][k]
        rows.append(row)

    gone = set(old) - {a["id"] for a in assets}
    if gone:
        print(f"Note: {len(gone)} video(s) were removed from the album; dropped from manifest "
              "(their files in 00_raw_videos were left alone).")
    write_manifest(rows)
    total = sum(float(r["duration_s"] or 0) for r in rows) / 3600
    print(f"Manifest written: {len(rows)} videos, {total:.1f} h total. "
          "Set include=no for any you want to skip.")
