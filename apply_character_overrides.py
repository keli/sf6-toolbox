#!/usr/bin/env python3
"""
Apply manually curated per-character overrides and generate frontend-ready
JSON files (`data/<Character>.json`) from FAT or existing final source files.
See AI_REVIEW_GUIDE.md for the AI-facing review/apply workflow contract.
"""

from __future__ import annotations

import argparse
import json
import os
import re
from typing import Any

from build_character_data import (
    char_filename,
    normalize_adv_field,
    normalize_numeric_field,
)

NUMERIC_FIELDS = {"startup", "active", "recovery", "onBlock"}
ADV_FIELDS = {"onHit", "onPC"}
ALLOWED_FIELDS = NUMERIC_FIELDS | ADV_FIELDS


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)


def normalize_move_block(move: dict[str, Any]) -> None:
    move["normalized"] = {
        "startup": normalize_numeric_field(move.get("startup")),
        "active": normalize_numeric_field(move.get("active")),
        "recovery": normalize_numeric_field(move.get("recovery")),
        "onHit": normalize_adv_field(move.get("onHit")),
        "onBlock": normalize_adv_field(move.get("onBlock")),
        "onPC": normalize_adv_field(move.get("onPC")),
    }


def is_index_friendly(field: str, value: Any) -> bool:
    if field in NUMERIC_FIELDS:
        if isinstance(value, int):
            return True
        if isinstance(value, str) and re.fullmatch(r"-?\d+", value.strip()):
            return True
        return False

    if field in ADV_FIELDS:
        if isinstance(value, int):
            return True
        if isinstance(value, str):
            s = value.strip()
            if re.fullmatch(r"-?\d+", s):
                return True
            if re.fullmatch(r"(H?KD)\s*\+\s*-?\d+", s, flags=re.IGNORECASE):
                return True
        return False

    return False


def load_char_overrides(path: str, char_name: str) -> list[dict[str, Any]]:
    if not os.path.exists(path):
        return []
    payload = read_json(path)
    payload_char = str(payload.get("character", "")).strip()
    if payload_char and payload_char != char_name:
        raise ValueError(
            f"{os.path.basename(path)}: character mismatch "
            f"(expected '{char_name}', got '{payload_char}')"
        )
    entries = payload.get("entries", [])
    if not isinstance(entries, list):
        raise ValueError(f"{os.path.basename(path)}: entries must be a list")
    return entries


def apply_overrides_to_character(
    char_name: str,
    char_data: dict[str, Any],
    entries: list[dict[str, Any]],
    strict: bool,
) -> int:
    changed_fields = 0
    for entry in entries:
        category = str(entry.get("category", "")).strip()
        move_name = str(entry.get("move", "")).strip()
        sets = entry.get("set", {})
        if not category or not move_name or not isinstance(sets, dict):
            raise ValueError(f"{char_name}: invalid override entry: {entry}")

        cat_moves = char_data.get("moves", {}).get(category)
        if not isinstance(cat_moves, dict):
            raise KeyError(f"{char_name}: missing category '{category}'")
        mv = cat_moves.get(move_name)
        if not isinstance(mv, dict):
            raise KeyError(f"{char_name}: missing move '{move_name}' in '{category}'")

        for field, new_value in sets.items():
            if field not in ALLOWED_FIELDS:
                raise ValueError(
                    f"{char_name}/{move_name}: unsupported field '{field}'"
                )
            if strict and (not is_index_friendly(field, new_value)):
                raise ValueError(
                    f"{char_name}/{move_name}/{field}: non index-friendly value '{new_value}'"
                )
            old_value = mv.get(field)
            if old_value != new_value:
                mv[field] = new_value
                changed_fields += 1
        normalize_move_block(mv)

    return changed_fields


def main() -> int:
    ap = argparse.ArgumentParser(
        description=(
            "Apply per-character index-friendly overrides and write "
            "frontend-ready merged character JSON files."
        )
    )
    ap.add_argument(
        "--char-index",
        default="data/characters.index.json",
        help="Character index JSON path (default: data/characters.index.json)",
    )
    ap.add_argument(
        "--data-dir",
        default="data",
        help="Directory containing per-character data files (default: data)",
    )
    ap.add_argument(
        "--overrides-dir",
        default="data",
        help="Directory containing per-character overrides (default: data)",
    )
    ap.add_argument(
        "--apply-base",
        choices=("fat", "final"),
        default="fat",
        help=(
            "Source dataset before applying overrides: "
            "`fat` reads `<char>.fat.json`; "
            "`final` reads existing `<char>.json` (default: fat)"
        ),
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help=(
            "Enable strict index-friendly value validation for override values "
            "(default: off)"
        ),
    )
    args = ap.parse_args()

    index_payload = read_json(args.char_index)
    rows = list(index_payload.get("characters", []))
    total_changes = 0
    for row in rows:
        char_name = str(row.get("name", "")).strip()
        fat_file = str(row.get("fatFile", "")).strip()
        out_file = str(row.get("file", "")).strip() or f"{char_name}.json"
        if not char_name or not fat_file:
            continue

        source_file = fat_file if args.apply_base == "fat" else out_file
        source_path = os.path.join(args.data_dir, source_file)
        out_path = os.path.join(args.data_dir, out_file)
        if not os.path.exists(source_path):
            raise FileNotFoundError(f"Missing source file: {source_path}")
        char_data = read_json(source_path)

        overrides_file = f"{char_filename(char_name)}.overrides.json"
        overrides_path = os.path.join(args.overrides_dir, overrides_file)
        entries = load_char_overrides(overrides_path, char_name)
        changed = (
            apply_overrides_to_character(
                char_name, char_data, entries, strict=args.strict
            )
            if entries
            else 0
        )
        total_changes += changed
        write_json(out_path, char_data)
        print(
            f"{char_name}: wrote {os.path.basename(out_path)} "
            f"(base={args.apply_base}, strict={args.strict}, changed_fields={changed})"
        )

    print(f"Done. total_changed_fields={total_changes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
