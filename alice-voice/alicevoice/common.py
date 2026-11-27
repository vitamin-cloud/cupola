"""Shared paths, manifest handling and ffprobe helpers."""
from __future__ import annotations

import csv
import json
import os
import subprocess
from pathlib import Path

DATA = Path(os.environ.get("ALICE_DATA", "/data"))
RAW = DATA / "00_raw_videos"
AUDIO = DATA / "01_audio"
MANIFEST = DATA / "manifest.csv"

MANIFEST_FIELDS = [
    "asset_id", "file", "original_name", "recorded_at", "duration_s",
    "audio_codec", "sample_rate", "channels", "include", "notes",
]
# Columns the user edits by hand; preserved when the manifest is rebuilt.
USER_FIELDS = ("include", "notes")


def read_manifest() -> list[dict]:
    if not MANIFEST.exists():
        return []
    with MANIFEST.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_manifest(rows: list[dict]) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    tmp = MANIFEST.with_suffix(".csv.tmp")
    with tmp.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=MANIFEST_FIELDS, extrasaction="ignore")
        w.writeheader()
        for r in sorted(rows, key=lambda r: (r.get("recorded_at", ""), r["file"])):
            w.writerow(r)
    tmp.replace(MANIFEST)


def is_included(row: dict) -> bool:
    return row.get("include", "yes").strip().lower() not in ("no", "n", "0", "false", "")


def ffprobe(path: Path) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-print_format", "json",
         "-show_format", "-show_streams", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)


def audio_info(path: Path) -> dict:
    """Duration and first audio stream's codec/rate/channels ('' if no audio)."""
    probe = ffprobe(path)
    info = {"duration_s": "", "audio_codec": "", "sample_rate": "", "channels": ""}
    dur = probe.get("format", {}).get("duration")
    if dur:
        info["duration_s"] = f"{float(dur):.1f}"
    for s in probe.get("streams", []):
        if s.get("codec_type") == "audio":
            info.update(audio_codec=s.get("codec_name", ""),
                        sample_rate=s.get("sample_rate", ""),
                        channels=str(s.get("channels", "")))
            break
    return info
