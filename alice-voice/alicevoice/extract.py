"""Step 1: extract each included video's audio to a full-quality mono WAV.

- Native sample rate is kept (no resampling), stored as 24-bit PCM.
- Stereo is averaged to mono, unless one channel is dead/far quieter or the
  channels are out of phase (averaging would cancel the voice); then the
  better channel is kept alone.
- Writes 01_audio/<video>.wav plus 01_audio/extract_report.csv.
"""
from __future__ import annotations

import csv
import subprocess
import tempfile
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import numpy as np
import soundfile as sf

from .common import AUDIO, RAW, is_included, read_manifest

BLOCK = 48000 * 30  # 30 s blocks keep memory flat for long videos
REPORT_FIELDS = ["file", "wav", "sample_rate", "src_channels", "mix", "duration_s",
                 "rms_dbfs", "peak_dbfs", "clipped_pct", "silence_pct", "status"]


def db(x: float) -> float:
    return round(20 * np.log10(max(x, 1e-9)), 1)


def channel_stats(path: Path) -> tuple[np.ndarray, float]:
    """Per-channel RMS and inter-channel correlation (first two channels)."""
    ss = None
    cross, n = 0.0, 0
    for blk in sf.blocks(str(path), blocksize=BLOCK, dtype="float32", always_2d=True):
        sq = (blk.astype(np.float64) ** 2).sum(axis=0)
        ss = sq if ss is None else ss + sq
        if blk.shape[1] > 1:
            cross += float((blk[:, 0].astype(np.float64) * blk[:, 1]).sum())
        n += len(blk)
    rms = np.sqrt(ss / max(n, 1))
    corr = cross / (n * rms[0] * rms[1]) if len(rms) > 1 and rms[0] * rms[1] > 0 else 1.0
    return rms, corr


def choose_mix(rms: np.ndarray, corr: float) -> str:
    if len(rms) == 1:
        return "mono"
    a, b = rms[0], rms[1]
    if min(a, b) < 0.1 * max(a, b):  # >20 dB quieter: dead or bad mic
        return "left" if a >= b else "right"
    if corr < -0.3:  # out of phase: averaging would cancel the voice
        return "left" if a >= b else "right"
    return "average"


def extract_one(video: Path, out: Path, overwrite: bool) -> dict:
    row = {"file": video.name, "wav": out.name}
    if out.exists() and not overwrite:
        info = sf.info(str(out))
        return {**row, "sample_rate": info.samplerate, "duration_s": round(info.duration, 1),
                "status": "skipped (exists)"}
    with tempfile.TemporaryDirectory(dir=out.parent) as td:
        tmp = Path(td) / "full.wav"
        # Decode the first audio stream losslessly to float, all channels kept.
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(video),
                        "-map", "0:a:0", "-vn", "-c:a", "pcm_f32le", str(tmp)],
                       check=True)
        info = sf.info(str(tmp))
        rms, corr = channel_stats(tmp)
        mix = choose_mix(rms, corr)

        part = out.with_name(out.stem + ".part.wav")
        peak, ss, clipped, quiet, n = 0.0, 0.0, 0, 0, 0
        win = max(info.samplerate // 50, 1)  # 20 ms windows for silence estimate
        with sf.SoundFile(str(part), "w", samplerate=info.samplerate, channels=1,
                          subtype="PCM_24", format="WAV") as w:
            for blk in sf.blocks(str(tmp), blocksize=BLOCK, dtype="float32", always_2d=True):
                # Clipping is judged on the source channels, before mixing.
                clipped += int((np.abs(blk[:, :2]) >= 0.999).any(axis=1).sum())
                if mix == "average":
                    m = blk[:, :2].mean(axis=1)
                elif mix == "right":
                    m = blk[:, 1]
                else:
                    m = blk[:, 0]
                w.write(m)
                peak = max(peak, float(np.abs(m).max(initial=0)))
                ss += float((m.astype(np.float64) ** 2).sum())
                k = len(m) // win
                if k:
                    frames = m[: k * win].reshape(k, win)
                    quiet += int((np.sqrt((frames ** 2).mean(axis=1)) < 10 ** (-50 / 20)).sum()) * win
                n += len(m)
        part.replace(out)

    return {**row, "sample_rate": info.samplerate, "src_channels": info.channels, "mix": mix,
            "duration_s": round(n / info.samplerate, 1),
            "rms_dbfs": db(np.sqrt(ss / max(n, 1))), "peak_dbfs": db(peak),
            "clipped_pct": round(100 * clipped / max(n, 1), 3),
            "silence_pct": round(100 * quiet / max(n, 1), 1), "status": "ok"}


def main(args) -> None:
    rows = [r for r in read_manifest() if is_included(r)]
    if args.only:
        rows = [r for r in rows if args.only in r["file"]]
    if args.limit:
        rows = rows[: args.limit]
    if not rows:
        raise SystemExit("Nothing to extract. Run `av fetch` first (or check include= in manifest.csv).")
    AUDIO.mkdir(parents=True, exist_ok=True)

    results = []
    with ProcessPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(extract_one, RAW / r["file"], AUDIO / (Path(r["file"]).stem + ".wav"),
                          args.overwrite): r for r in rows}
        for i, f in enumerate(as_completed(futs), 1):
            r = futs[f]
            try:
                res = f.result()
            except Exception as e:  # keep going; report at the end
                res = {"file": r["file"], "status": f"error: {e}"}
            results.append(res)
            print(f"[{i}/{len(rows)}] {res['file']}: {res['status']}"
                  + (f" mix={res.get('mix')} clipped={res.get('clipped_pct')}%"
                     if res["status"] == "ok" else ""))

    report = AUDIO / "extract_report.csv"
    prev = {}
    if report.exists():
        with report.open(newline="") as f:
            prev = {r["file"]: r for r in csv.DictReader(f)}
    for res in results:
        if res["status"] == "ok" or res["file"] not in prev:
            prev[res["file"]] = res
    with report.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=REPORT_FIELDS, extrasaction="ignore")
        w.writeheader()
        for k in sorted(prev):
            w.writerow(prev[k])
    errors = [r for r in results if r["status"].startswith("error")]
    print(f"Done. Report: {report}" + (f"  ({len(errors)} errors)" if errors else ""))
