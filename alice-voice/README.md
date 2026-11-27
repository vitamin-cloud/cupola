# Alice voice (private, family-only)

Tools to build a clean voice dataset of Alice from pre-surgery home videos,
then (later phases) read storybooks aloud in her voice with IndexTTS2.

**Rules:** all voice data stays on the NAS under `ALICE_DATA`. This repo holds
code only; `.gitignore` blocks audio, video, CSV/JSON outputs and `.env`.

## Status
- Phase 1, step 0 `av fetch`: copies the videos from an Immich album, builds `manifest.csv`. Done.
- Phase 1, step 1 `av extract`: full-quality mono WAV per video. Done.
- Steps 2-7 (voice separation, diarization, Alice matching, transcription and
  clipping, quality scores, review page): next.

## One-time setup (TrueNAS + Dockge)
1. **Data folder:** create `/mnt/<pool>/alice-voice` (a dataset later; we'll move it).
2. **Code:** put this repo's `alice-voice/` folder on the NAS, e.g.
   `/mnt/<pool>/apps/alice-voice-code/` (git clone, or download the branch ZIP
   from GitHub and unzip it).
3. **Immich:** put the chosen videos in an album named `Alice voice`. Then go to
   Account Settings → API Keys → New API Key with the `album.read`,
   `asset.read` and `asset.download` permissions.
4. **Dockge:** create a new stack `alice-voice`. Paste `compose.yaml` and fill
   the `.env` editor from `env.example`. Deploy it (the first build takes a few minutes).
5. In Dockge, open the container's terminal (`>_` button → `bash`).

## Running
```
av fetch            # copy album videos -> 00_raw_videos/, write manifest.csv
av summary          # text-only overview (safe to paste into chat)
av extract --limit 1   # timing test on one video
av extract          # all included videos -> 01_audio/*.wav
av summary
```
Everything can be re-run safely. Finished files are skipped, and the
`include` / `notes` columns you edit in `manifest.csv` are kept.

## Data layout (on the NAS, never in git)
```
alice-voice/
  manifest.csv          one row per video; set include=no to skip a video
  00_raw_videos/        read-only copies of the originals
  01_audio/             mono 24-bit WAV, native sample rate + extract_report.csv
  .cache/huggingface/   model downloads (later steps)
```
