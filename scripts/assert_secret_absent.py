#!/usr/bin/env python3

import argparse
import pathlib
import sys


CHUNK_SIZE = 1024 * 1024


def file_contains(path: pathlib.Path, secret: bytes) -> bool:
    overlap_size = max(len(secret) - 1, 0)
    overlap = b""
    with path.open("rb") as artifact:
        while chunk := artifact.read(CHUNK_SIZE):
            candidate = overlap + chunk
            if secret in candidate:
                return True
            overlap = candidate[-overlap_size:] if overlap_size else b""
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail when a stdin-provided secret occurs in an artifact tree.")
    parser.add_argument("root")
    args = parser.parse_args()

    root = pathlib.Path(args.root).resolve()
    if not root.is_dir():
        parser.error(f"artifact directory does not exist: {root}")

    secret = sys.stdin.buffer.readline().rstrip(b"\r\n")
    if not secret:
        parser.error("secret must be provided on stdin")

    try:
        for path in root.rglob("*"):
            if path.is_file() and not path.is_symlink() and file_contains(path, secret):
                print(f"error: secret found in artifact: {path}", file=sys.stderr)
                return 1
    except OSError as error:
        print(f"error: could not scan proof artifacts: {error}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
