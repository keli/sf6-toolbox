#!/usr/bin/env python3
"""
Fetch SF6 frame data for a specific character from FAT (Frame Assistant Tool).
Usage: python fetch_data.py <character_name>
       python fetch_data.py --list
"""

import sys
import json
import urllib.request
from pathlib import Path

DATA_URL = "https://raw.githubusercontent.com/D4RKONION/FAT/master/src/js/constants/framedata/SF6FrameData.json"
CACHE_DIR = Path("data")


def fetch_full_data() -> dict:
    """Fetch the full SF6 frame data JSON (cached locally)."""
    cache_file = CACHE_DIR / "sf6framedata.json"
    if cache_file.exists():
        with open(cache_file) as f:
            return json.load(f)
    print(f"Downloading SF6 frame data from FAT...")
    with urllib.request.urlopen(DATA_URL) as resp:
        raw = resp.read()
    CACHE_DIR.mkdir(exist_ok=True)
    cache_file.write_bytes(raw)
    print(f"Saved to {cache_file}")
    return json.loads(raw)


def list_characters(data: dict):
    chars = sorted(data.keys())
    print(f"Available characters ({len(chars)}):")
    for c in chars:
        print(f"  {c}")


def fetch_character(name: str, update: bool = False) -> dict:
    """Fetch and save frame data for a single character."""
    CACHE_DIR.mkdir(exist_ok=True)
    out_file = CACHE_DIR / f"{name.replace(' ', '_').replace('.', '').lower()}.json"
    if out_file.exists() and not update:
        print(f"Using cached data: {out_file}")
        with open(out_file) as f:
            return json.load(f)

    # Force re-download of source data
    source_cache = CACHE_DIR / "sf6framedata.json"
    if update and source_cache.exists():
        source_cache.unlink()
        print("Cleared cached source data, re-downloading...")

    data = fetch_full_data()

    # Case-insensitive match
    match = None
    for key in data:
        if key.lower() == name.lower():
            match = key
            break
    if match is None:
        # Try partial match
        candidates = [k for k in data if name.lower() in k.lower()]
        if len(candidates) == 1:
            match = candidates[0]
        elif len(candidates) > 1:
            print(f"Ambiguous name '{name}', matches: {candidates}")
            sys.exit(1)
        else:
            print(f"Character '{name}' not found.")
            print("Run with --list to see available characters.")
            sys.exit(1)

    char_data = {match: data[match]}
    with open(out_file, "w") as f:
        json.dump(char_data, f, indent=2, ensure_ascii=False)
    print(f"Saved {match} data to {out_file}")
    return char_data


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("character", nargs="*", help="Character name(s) to fetch")
    parser.add_argument("--list", action="store_true", help="List all available characters")
    parser.add_argument("--update", action="store_true", help="Force re-download even if cached")
    args = parser.parse_args()

    if args.list:
        data = fetch_full_data()
        list_characters(data)
    elif args.character:
        char_name = " ".join(args.character)
        fetch_character(char_name, update=args.update)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
