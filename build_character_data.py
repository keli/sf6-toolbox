#!/usr/bin/env python3
"""
Fetch SF6 FAT data and build per-character FAT source files.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import urllib.request
from typing import Any

FAT_URL = (
    "https://raw.githubusercontent.com/D4RKONION/FAT/master/"
    "src/js/constants/framedata/SF6FrameData.json"
)


def fetch_text(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "sf6-toolbox-fat/1.0",
            "Accept": "application/json,text/plain,*/*",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def fetch_json(url: str, timeout: int = 20) -> Any:
    return json.loads(fetch_text(url, timeout=timeout))


def read_json_file(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json_file(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))


def write_json_pretty_file(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)


def char_filename(name: str) -> str:
    s = (name or "").strip()
    s = s.replace("/", "_").replace("\\", "_")
    s = s.rstrip(".")
    return s or "unknown"


def write_character_sources(
    base_data: dict[str, Any],
    out_dir: str,
    index_out: str,
) -> dict[str, int]:
    os.makedirs(out_dir, exist_ok=True)
    index_rows: list[dict[str, Any]] = []

    for char_name in sorted(base_data.keys()):
        fname = char_filename(char_name)
        char_dir = os.path.join(out_dir, fname)
        os.makedirs(char_dir, exist_ok=True)
        fat_file = os.path.join(fname, "fat.json")
        final_file = os.path.join(fname, "final.json")
        overrides_file = os.path.join(fname, "overrides.json")
        official_frame_file = os.path.join(fname, "official.json")
        official_conflicts_file = os.path.join(fname, "official.conflicts.csv")

        write_json_pretty_file(os.path.join(out_dir, fat_file), base_data[char_name])

        index_rows.append(
            {
                "name": char_name,
                "dir": fname,
                "file": final_file,
                "fatFile": fat_file,
                "overridesFile": overrides_file,
                "officialFrameFile": official_frame_file,
                "officialConflictsFile": official_conflicts_file,
            }
        )

    write_json_pretty_file(
        index_out,
        {
            "generatedAt": dt.datetime.now(dt.UTC).isoformat(),
            "characters": index_rows,
        },
    )
    return {"characters": len(index_rows)}


def parse_first_int(text: str | None) -> int | None:
    if not text:
        return None
    m = re.search(r"-?\d+", text)
    return int(m.group(0)) if m else None


def parse_strict_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        s = normalize_spaces(value)
        if re.fullmatch(r"-?\d+", s):
            return int(s)
    return None


def normalize_spaces(text: str | None) -> str:
    if text is None:
        return ""
    return " ".join(str(text).split())


def _parse_all_ints(text: str) -> list[int]:
    return [int(m.group(0)) for m in re.finditer(r"-?\d+", text)]


def normalize_numeric_field(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        n = int(value)
        return {
            "raw": value,
            "text": str(value),
            "numbers": [n],
            "first": n,
            "min": n,
            "max": n,
            "uncertain": False,
        }

    text = normalize_spaces(str(value))
    if not text:
        return None
    nums = _parse_all_ints(text)
    first = nums[0] if nums else None
    return {
        "raw": value,
        "text": text,
        "numbers": nums,
        "first": first,
        "min": min(nums) if nums else None,
        "max": max(nums) if nums else None,
        "uncertain": ("~" in text)
        or ("notes" in text.lower())
        or ("or" in text.lower()),
    }


def normalize_adv_field(value: Any) -> dict[str, Any] | None:
    base = normalize_numeric_field(value)
    if base is None:
        return None

    text = base["text"]
    kd: list[dict[str, Any]] = []
    for m in re.finditer(r"(H?KD)\s*\+?\s*(-?\d+)?", text, flags=re.IGNORECASE):
        kd_type = m.group(1).upper()
        adv_raw = m.group(2)
        advantage: int | None = None
        advantage_min: int | None = None
        advantage_max: int | None = None

        if adv_raw is not None:
            right = text[m.end() :]
            rm = re.match(r"\s*[~〜-]\s*(-?\d+)", right)
            pm = re.match(r"\s*\(\s*\+?\s*(-?\d+)\s*\)", right)
            if rm:
                a = int(adv_raw)
                b = int(rm.group(1))
                advantage_min = min(a, b)
                advantage_max = max(a, b)
            elif pm:
                a = int(adv_raw)
                b = int(pm.group(1))
                advantage_min = min(a, b)
                advantage_max = max(a, b)
            else:
                n = int(adv_raw)
                advantage_min = n
                advantage_max = n
        else:
            left = text[: m.start()]
            lm = re.search(r"(-?\d+)\s*([~〜-])\s*(-?\d+)\s*\(?\s*$", left)
            if lm:
                a = int(lm.group(1))
                b = int(lm.group(3))
                advantage_min = min(a, b)
                advantage_max = max(a, b)
            else:
                prefix_nums = _parse_all_ints(left)
                if prefix_nums:
                    n = prefix_nums[-1]
                    advantage_min = n
                    advantage_max = n
                elif isinstance(base.get("first"), int):
                    n = base["first"]
                    advantage_min = n
                    advantage_max = n

        if advantage_min is not None:
            advantage = advantage_min
        kd.append(
            {
                "type": kd_type,
                "advantage": advantage,
                "advantageMin": advantage_min,
                "advantageMax": advantage_max,
            }
        )

    tags: list[str] = []
    text_low = text.lower()
    for tag in ("crumple", "tumble", "wall bounce", "wall splat", "otg"):
        if tag in text_low:
            tags.append(tag)

    out = dict(base)
    out["kd"] = kd
    out["tags"] = tags
    return out


def normalize_character_moves(base_data: dict[str, Any]) -> None:
    for char_data in base_data.values():
        for cat_name, cat_moves in char_data.get("moves", {}).items():
            for move in cat_moves.values():
                if not isinstance(move, dict):
                    continue
                # Manual/parry Drive Rush follow-up frame data for grounded normals.
                if (
                    cat_name == "normal"
                    and move.get("airmove") is not True
                    and move.get("atkLvl") in {"L", "M", "H"}
                ):
                    on_block = parse_strict_int(move.get("onBlock"))
                    on_hit = parse_strict_int(move.get("onHit"))
                    if on_block is not None:
                        move["rawDRoB"] = on_block + 4
                    if on_hit is not None:
                        move["rawDRoH"] = on_hit + 4
                move["normalized"] = {
                    "startup": normalize_numeric_field(move.get("startup")),
                    "active": normalize_numeric_field(move.get("active")),
                    "recovery": normalize_numeric_field(move.get("recovery")),
                    "onHit": normalize_adv_field(move.get("onHit")),
                    "onBlock": normalize_adv_field(move.get("onBlock")),
                    "onPC": normalize_adv_field(move.get("onPC")),
                }


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Fetch SF6 FAT data and build per-character FAT source files."
    )
    ap.add_argument(
        "action",
        nargs="?",
        choices=("fetch", "normalize"),
        default="normalize",
        help=(
            "fetch: write per-character FAT files from base data; "
            "normalize: rewrite per-character FAT files with normalized fields"
        ),
    )
    ap.add_argument(
        "--base-file",
        default="data/sf6framedata.json",
        help="Base JSON file path (default: data/sf6framedata.json)",
    )
    ap.add_argument(
        "--base-url",
        default=FAT_URL,
        help="Base JSON URL (used only with --download-base)",
    )
    ap.add_argument(
        "--download-base",
        action="store_true",
        help="Download base JSON from --base-url instead of reading --base-file",
    )
    ap.add_argument(
        "--char-data-dir",
        default="data",
        help="Output directory for per-character files",
    )
    ap.add_argument(
        "--index-out",
        default="data/characters.index.json",
        help="Character index JSON path for frontend loading",
    )
    args = ap.parse_args()

    if args.download_base:
        data = fetch_json(args.base_url)
        write_json_file(args.base_file, data)
        print(f"Base saved to: {args.base_file}")
        source = args.base_url
    else:
        data = read_json_file(args.base_file)
        source = args.base_file

    if not isinstance(data, dict):
        raise ValueError("Base data is not a JSON object.")

    print(f"Base loaded from: {source}")
    normalize_character_moves(data)

    stats = write_character_sources(
        base_data=data,
        out_dir=args.char_data_dir,
        index_out=args.index_out,
    )
    print(f"Per-character FAT files written under: {args.char_data_dir}")
    print(f"Character index written: {args.index_out}")
    print("Stats:")
    for k, v in stats.items():
        print(f"  {k}: {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
