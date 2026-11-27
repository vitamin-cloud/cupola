"""CLI: `av <step>` (inside the container) or `python -m alicevoice <step>`."""
import argparse
import os


def main() -> None:
    p = argparse.ArgumentParser(prog="av", description="Alice voice dataset tools")
    sub = p.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fetch", help="step 0: copy album videos from Immich + build manifest")
    f.add_argument("--album", help="album name or id (default: $IMMICH_ALBUM)")
    f.add_argument("--no-verify", action="store_true",
                   help="skip re-hashing files that are already downloaded")

    e = sub.add_parser("extract", help="step 1: video -> full-quality mono WAV")
    e.add_argument("--jobs", type=int, default=max(1, min(4, (os.cpu_count() or 2) // 2)))
    e.add_argument("--limit", type=int, help="only the first N videos (for a timing test)")
    e.add_argument("--only", help="only videos whose filename contains this text")
    e.add_argument("--overwrite", action="store_true")

    sub.add_parser("summary", help="text-only progress summary, safe to share")

    args = p.parse_args()
    if args.cmd == "fetch":
        from . import fetch as mod
    elif args.cmd == "extract":
        from . import extract as mod
    else:
        from . import summary as mod
    mod.main(args)


if __name__ == "__main__":
    main()
