"""Print a text-only summary that is safe to paste into chat (no audio, no names)."""
from __future__ import annotations

import csv
from collections import Counter

from .common import AUDIO, is_included, read_manifest


def main(args) -> None:
    rows = read_manifest()
    if not rows:
        raise SystemExit("No manifest yet. Run `av fetch` first.")
    inc = [r for r in rows if is_included(r)]
    hours = sum(float(r["duration_s"] or 0) for r in inc) / 3600
    years = Counter((r["recorded_at"] or "????")[:4] for r in inc)
    print(f"Videos: {len(rows)} in album, {len(inc)} included, {hours:.2f} h of included footage")
    print("By year:", ", ".join(f"{y}: {n}" for y, n in sorted(years.items())))
    print("Audio formats:", dict(Counter(
        f"{r['audio_codec']}/{r['sample_rate']}Hz/{r['channels']}ch" for r in inc)))

    report = AUDIO / "extract_report.csv"
    if report.exists():
        with report.open(newline="") as f:
            ex = list(csv.DictReader(f))
        ok = [r for r in ex if r.get("status") == "ok" or r.get("status", "").startswith("skipped")]
        print(f"Extracted: {len(ok)}/{len(inc)}; errors: {sum(r['status'].startswith('error') for r in ex)}")
        print("Mix choices:", dict(Counter(r.get("mix") or "?" for r in ok)))
        clip = [float(r["clipped_pct"]) for r in ok if r.get("clipped_pct")]
        if clip:
            print(f"Clipping: {sum(c > 0.1 for c in clip)} files above 0.1% clipped samples")
