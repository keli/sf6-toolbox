#!/usr/bin/env python3
"""
Fetch SF6 data from FAT + SuperCombo raw pages and build per-character files.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

FAT_URL = (
    "https://raw.githubusercontent.com/D4RKONION/FAT/master/"
    "src/js/constants/framedata/SF6FrameData.json"
)
SC_PAGE_TEMPLATE = (
    "https://wiki.supercombo.gg/w/Street_Fighter_6/{char}/Data?action=raw"
)


def fetch_text(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "sf6-toolbox-merge/1.0",
            "Accept": "text/plain, text/x-wiki, application/json;q=0.9, */*;q=0.1",
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
    # Keep character names readable in filenames; only block path separators.
    s = s.replace("/", "_").replace("\\", "_")
    s = s.rstrip(".")
    return s or "unknown"


def write_character_sources(
    base_data: dict[str, Any],
    supplement: dict[str, Any],
    out_dir: str,
    index_out: str,
) -> dict[str, int]:
    os.makedirs(out_dir, exist_ok=True)
    sc_chars = supplement.get("characters", {})
    index_rows: list[dict[str, Any]] = []

    for char_name in sorted(base_data.keys()):
        fname = char_filename(char_name)
        fat_file = f"{fname}.fat.json"
        sc_file = f"{fname}.supercombo.json"

        write_json_pretty_file(os.path.join(out_dir, fat_file), base_data[char_name])
        write_json_pretty_file(
            os.path.join(out_dir, sc_file),
            sc_chars.get(
                char_name,
                {
                    "missing": True,
                    "reason": "No parsed SuperCombo data for this character.",
                    "moves": [],
                },
            ),
        )

        index_rows.append(
            {
                "name": char_name,
                "file": f"{fname}.json",
                "fatFile": fat_file,
                "supercomboFile": sc_file,
                "conflictsFile": f"{fname}.conflicts.csv",
                "hasSupercombo": char_name in sc_chars,
            }
        )

    write_json_pretty_file(
        index_out,
        {
            "generatedAt": dt.datetime.now(dt.UTC).isoformat(),
            "characters": index_rows,
        },
    )
    return {
        "characters": len(index_rows),
        "with_supercombo": sum(1 for r in index_rows if r["hasSupercombo"]),
    }


def load_sc_supplement_from_character_files(
    char_names: list[str], data_dir: str
) -> dict[str, Any]:
    characters: dict[str, Any] = {}
    for char_name in char_names:
        fname = char_filename(char_name)
        path = os.path.join(data_dir, f"{fname}.supercombo.json")
        if not os.path.exists(path):
            characters[char_name] = {
                "missing": True,
                "reason": f"Missing file: {os.path.basename(path)}",
                "moves": [],
            }
            continue
        payload = read_json_file(path)
        if isinstance(payload, dict):
            characters[char_name] = payload
        else:
            characters[char_name] = {
                "missing": True,
                "reason": f"Invalid JSON object in {os.path.basename(path)}",
                "moves": [],
            }
    return {"characters": characters}


def load_review_base_from_character_files(
    char_names: list[str],
    data_dir: str,
    use_final_json: bool,
    fallback_base_data: dict[str, Any],
) -> tuple[dict[str, Any], list[str]]:
    base_data: dict[str, Any] = {}
    warnings: list[str] = []
    suffix = ".json" if use_final_json else ".fat.json"

    for char_name in char_names:
        fname = char_filename(char_name)
        path = os.path.join(data_dir, f"{fname}{suffix}")
        if not os.path.exists(path):
            base_fallback = fallback_base_data.get(char_name)
            if base_fallback is None:
                warnings.append(
                    f"{char_name}: missing {os.path.basename(path)} and no fallback base data."
                )
                continue
            base_data[char_name] = base_fallback
            warnings.append(
                f"{char_name}: missing {os.path.basename(path)}, fallback to --base-file data."
            )
            continue
        payload = read_json_file(path)
        if not isinstance(payload, dict):
            warnings.append(
                f"{char_name}: invalid JSON object in {os.path.basename(path)}, fallback to --base-file data."
            )
            base_data[char_name] = fallback_base_data.get(char_name, {})
            continue
        base_data[char_name] = payload

    return base_data, warnings


def write_character_conflicts(
    conflict_rows: list[dict[str, Any]],
    char_names: list[str],
    out_dir: str,
    audit_out: str,
) -> dict[str, int]:
    os.makedirs(out_dir, exist_ok=True)
    conflict_fields = [
        "character",
        "category",
        "move_name",
        "num_cmd",
        "field",
        "fat_value",
        "supercombo_parsed",
        "supercombo_raw",
        "fat_first",
        "fat_min",
        "fat_max",
        "fat_kd_min",
        "fat_kd_max",
        "sc_first",
        "sc_min",
        "sc_max",
        "sc_kd_min",
        "sc_kd_max",
        "supercombo_input",
        "supercombo_move_id",
    ]
    rows_by_char: dict[str, list[dict[str, Any]]] = {}
    for row in conflict_rows:
        rows_by_char.setdefault(str(row.get("character", "")), []).append(row)

    for char_name in sorted(char_names):
        fname = char_filename(char_name)
        path = os.path.join(out_dir, f"{fname}.conflicts.csv")
        with open(path, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=conflict_fields)
            w.writeheader()
            w.writerows(rows_by_char.get(char_name, []))

    with open(audit_out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=conflict_fields)
        w.writeheader()
        w.writerows(conflict_rows)

    return {
        "characters": len(char_names),
        "conflict_rows": len(conflict_rows),
    }


def parse_first_int(text: str | None) -> int | None:
    if not text:
        return None
    m = re.search(r"-?\d+", text)
    return int(m.group(0)) if m else None


def cleanup_adv_text(text: str) -> str:
    # Common form: {{sf6-adv|VP|+5}}
    m = re.search(r"\{\{sf6-adv\|[^|]+\|([^}]+)\}\}", text, flags=re.IGNORECASE)
    if m:
        text = m.group(1)
    text = re.sub(r"\{\{[^{}]+\}\}", "", text)
    text = text.replace("&nbsp;", " ")
    return " ".join(text.strip().split())


def parse_adv_value(text: str | None) -> int | str | None:
    if not text:
        return None
    t = cleanup_adv_text(text)
    if not t or t == "-":
        return None

    kd = re.search(r"(HKD|KD)\s*([+-]?\d+)?", t, flags=re.IGNORECASE)
    if kd:
        kind = kd.group(1).upper()
        num = kd.group(2)
        return f"{kind} {int(num):+d}" if num else kind

    num = parse_first_int(t)
    return num


def normalize_spaces(text: str | None) -> str:
    if text is None:
        return ""
    return " ".join(str(text).split())


def normalize_wiki_text(text: str | None) -> str:
    if text is None:
        return ""
    s = str(text)
    s = re.sub(r"\{\{sf6-adv\|[^|]+\|([^}]+)\}\}", r"\1", s, flags=re.IGNORECASE)
    s = re.sub(r"\{\{[^{}]+\}\}", "", s)
    s = re.sub(r"<br\s*/?>", " ", s, flags=re.IGNORECASE)
    s = s.replace("&nbsp;", " ")
    return normalize_spaces(s)


def _parse_first_int(text: str) -> int | None:
    m = re.search(r"-?\d+", text)
    return int(m.group(0)) if m else None


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
            # Prefix form: KD +43, KD +43~45, KD +43(+45)
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
            # Suffix form: 11 (KD), 13~19 (KD)
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
        for cat_moves in char_data.get("moves", {}).values():
            for move in cat_moves.values():
                if not isinstance(move, dict):
                    continue
                move["normalized"] = {
                    "startup": normalize_numeric_field(move.get("startup")),
                    "active": normalize_numeric_field(move.get("active")),
                    "recovery": normalize_numeric_field(move.get("recovery")),
                    "onHit": normalize_adv_field(move.get("onHit")),
                    "onBlock": normalize_adv_field(move.get("onBlock")),
                    "onPC": normalize_adv_field(move.get("onPC")),
                }


def parse_cancel_types(text: str | None) -> list[str]:
    if not text:
        return []
    cleaned = re.sub(r"\{\{[^{}]+\}\}", "", text)
    tokens = re.split(r"[,\s/]+", cleaned.strip())
    out: list[str] = []
    for tok in tokens:
        t = tok.strip().upper()
        if not t or t == "-":
            continue
        if t.startswith("CHN") and "ch" not in out:
            out.append("ch")
        elif t == "SP" and "sp" not in out:
            out.append("sp")
        elif t.startswith("SA") and "su" not in out:
            out.append("su")
        elif t == "TC" and "tc" not in out:
            out.append("tc")
    return out


def normalize_input_key(text: str | None) -> str:
    if not text:
        return ""
    return re.sub(r"\s+", "", text).upper()


def parse_framedata_blocks(raw_wikitext: str) -> list[dict[str, Any]]:
    lines = raw_wikitext.splitlines()
    in_block = False
    block: list[str] = []
    blocks: list[list[str]] = []

    for line in lines:
        s = line.strip()
        if not in_block and s.startswith("{{FrameData-SF6"):
            in_block = True
            block = [line]
            if s.endswith("}}") and s.count("{{") == s.count("}}"):
                blocks.append(block)
                in_block = False
                block = []
            continue
        if in_block:
            block.append(line)
            if s == "}}":
                blocks.append(block)
                in_block = False
                block = []

    moves: list[dict[str, Any]] = []
    for b in blocks:
        fields: dict[str, str] = {}
        for line in b[1:]:
            s = line.strip()
            if s == "}}":
                break
            if not s.startswith("|") or "=" not in s:
                continue
            key, val = s[1:].split("=", 1)
            fields[key.strip()] = val.strip()

        move_input = fields.get("input", "").strip()
        move_name = fields.get("name", "").strip()
        if not move_input and not move_name:
            continue

        move = {
            "moveId": fields.get("moveId", "").strip(),
            "moveType": fields.get("moveType", "").strip(),
            "input": move_input,
            "name": move_name,
            "startup": parse_first_int(fields.get("startup")),
            "active": parse_first_int(fields.get("active")),
            "recovery": parse_first_int(fields.get("recovery")),
            "onHit": parse_adv_value(fields.get("hitAdv")),
            "onBlock": parse_adv_value(fields.get("blockAdv")),
            "onPC": parse_adv_value(fields.get("punishAdv")),
            "xx": parse_cancel_types(fields.get("cancel")),
            "raw": {
                "startup": fields.get("startup"),
                "active": fields.get("active"),
                "recovery": fields.get("recovery"),
                "hitAdv": fields.get("hitAdv"),
                "blockAdv": fields.get("blockAdv"),
                "punishAdv": fields.get("punishAdv"),
                "cancel": fields.get("cancel"),
            },
        }
        moves.append(move)
    return moves


def build_sc_supplement(base_data: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    supplement: dict[str, Any] = {
        "meta": {
            "generatedAt": dt.datetime.now(dt.UTC).isoformat(),
            "source": "wiki.supercombo.gg",
            "pageTemplate": SC_PAGE_TEMPLATE,
            "notes": "Parsed from FrameData-SF6 templates in raw wikitext.",
        },
        "characters": {},
    }
    errors: list[str] = []

    for char_name in base_data.keys():
        enc = urllib.parse.quote(char_name, safe="")
        url = SC_PAGE_TEMPLATE.format(char=enc)
        try:
            raw = fetch_text(url)
        except (urllib.error.URLError, TimeoutError) as e:
            errors.append(f"{char_name}: {e}")
            continue

        moves = parse_framedata_blocks(raw)
        supplement["characters"][char_name] = {
            "url": url,
            "moveCount": len(moves),
            "moves": moves,
        }
    return supplement, errors


def build_conflicts(
    base_data: dict[str, Any], supplement: dict[str, Any]
) -> list[dict[str, Any]]:
    fields = ("startup", "active", "recovery", "onHit", "onBlock", "onPC")
    rows: list[dict[str, Any]] = []
    sc_chars = supplement.get("characters", {})

    def norm_summary(field: str, value: Any) -> dict[str, Any]:
        norm = (
            normalize_adv_field(value)
            if field in {"onHit", "onBlock", "onPC"}
            else normalize_numeric_field(value)
        )
        if not isinstance(norm, dict):
            return {
                "first": None,
                "min": None,
                "max": None,
                "kd_min": None,
                "kd_max": None,
            }

        kd_vals: list[int] = []
        for item in norm.get("kd", []):
            if not isinstance(item, dict):
                continue
            for key in ("advantageMin", "advantage", "advantageMax"):
                v = item.get(key)
                if isinstance(v, int):
                    kd_vals.append(v)
                    break

        return {
            "first": norm.get("first"),
            "min": norm.get("min"),
            "max": norm.get("max"),
            "kd_min": min(kd_vals) if kd_vals else None,
            "kd_max": max(kd_vals) if kd_vals else None,
        }

    for char_name, char_data in base_data.items():
        sc_char = sc_chars.get(char_name, {})
        sc_by_input = {
            normalize_input_key(m.get("input")): m
            for m in sc_char.get("moves", [])
            if normalize_input_key(m.get("input"))
        }

        for category, cat_moves in char_data.get("moves", {}).items():
            for move_name, base_move in cat_moves.items():
                num_cmd = base_move.get("numCmd")
                sc_move = sc_by_input.get(normalize_input_key(num_cmd))
                if not sc_move:
                    continue

                for f in fields:
                    fat_v = base_move.get(f)
                    sc_v = sc_move.get(f)
                    if fat_v is None or sc_v is None or fat_v == sc_v:
                        continue
                    raw_key = {
                        "onHit": "hitAdv",
                        "onBlock": "blockAdv",
                        "onPC": "punishAdv",
                    }.get(f, f)
                    sc_raw = sc_move.get("raw", {}).get(raw_key)
                    fat_norm = normalize_wiki_text(fat_v)
                    sc_raw_norm = normalize_wiki_text(sc_raw)
                    if fat_norm and sc_raw_norm and fat_norm == sc_raw_norm:
                        continue
                    fat_s = norm_summary(f, fat_v)
                    sc_basis = sc_raw if sc_raw is not None else sc_v
                    sc_s = norm_summary(f, sc_basis)
                    rows.append(
                        {
                            "character": char_name,
                            "category": category,
                            "move_name": move_name,
                            "num_cmd": normalize_spaces(num_cmd),
                            "field": f,
                            "fat_value": normalize_spaces(fat_v),
                            "supercombo_parsed": normalize_spaces(sc_v),
                            "supercombo_raw": normalize_spaces(sc_raw),
                            "fat_first": fat_s["first"],
                            "fat_min": fat_s["min"],
                            "fat_max": fat_s["max"],
                            "fat_kd_min": fat_s["kd_min"],
                            "fat_kd_max": fat_s["kd_max"],
                            "sc_first": sc_s["first"],
                            "sc_min": sc_s["min"],
                            "sc_max": sc_s["max"],
                            "sc_kd_min": sc_s["kd_min"],
                            "sc_kd_max": sc_s["kd_max"],
                            "supercombo_input": normalize_spaces(sc_move.get("input")),
                            "supercombo_move_id": normalize_spaces(
                                sc_move.get("moveId")
                            ),
                        }
                    )
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Fetch SF6 data from FAT + SuperCombo and build per-character files."
    )
    ap.add_argument(
        "action",
        nargs="?",
        choices=("fetch", "review", "normalize"),
        default="review",
        help=(
            "fetch: write per-character FAT + SuperCombo source files; "
            "review: write per-character conflict CSV files; "
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
        "--audit-out",
        default="data/sf6framedata.conflicts.csv",
        help="CSV path for aggregated FAT vs SuperCombo conflicts",
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
    ap.add_argument(
        "--review-base",
        choices=("fat", "final"),
        default="fat",
        help=(
            "Base dataset for `review`: `fat` compares SuperCombo against "
            "`<char>.fat.json`; `final` compares against `<char>.json` "
            "(default: fat)"
        ),
    )
    args = ap.parse_args()

    def load_base() -> dict[str, Any]:
        if args.download_base:
            data = fetch_json(args.base_url)
            source = args.base_url
            # Persist downloaded base locally so later `merge` can run without
            # requiring --download-base again.
            write_json_file(args.base_file, data)
            print(f"Base saved to: {args.base_file}")
        else:
            data = read_json_file(args.base_file)
            source = args.base_file
        if not isinstance(data, dict):
            raise ValueError("Base data is not a JSON object.")
        print(f"Base loaded from: {source}")
        return data

    if args.action == "fetch":
        base_data = load_base()
        normalize_character_moves(base_data)
        supplement, errors = build_sc_supplement(base_data)
        print(f"Characters fetched: {len(supplement.get('characters', {}))}")
        source_stats = write_character_sources(
            base_data=base_data,
            supplement=supplement,
            out_dir=args.char_data_dir,
            index_out=args.index_out,
        )
        print(f"Per-character source files written under: {args.char_data_dir}")
        print(f"Character index written: {args.index_out}")
        print("Source stats:")
        for k, v in source_stats.items():
            print(f"  {k}: {v}")
        if errors:
            print(f"Warnings ({len(errors)}):")
            for e in errors[:20]:
                print(f"  - {e}")
            if len(errors) > 20:
                print(f"  ... and {len(errors) - 20} more")

    if args.action == "review":
        fallback_base_data = load_base()
        char_names = list(fallback_base_data.keys())
        use_final_json = args.review_base == "final"
        base_data, base_warnings = load_review_base_from_character_files(
            char_names=char_names,
            data_dir=args.char_data_dir,
            use_final_json=use_final_json,
            fallback_base_data=fallback_base_data,
        )
        supplement = load_sc_supplement_from_character_files(
            char_names=char_names,
            data_dir=args.char_data_dir,
        )
        conflict_rows = build_conflicts(base_data, supplement)
        review_stats = write_character_conflicts(
            conflict_rows=conflict_rows,
            char_names=char_names,
            out_dir=args.char_data_dir,
            audit_out=args.audit_out,
        )
        base_label = "final *.json" if use_final_json else "*.fat.json"
        print(f"Review base source: {base_label} under {args.char_data_dir}")
        print(f"Per-character conflicts written under: {args.char_data_dir}")
        print(f"Aggregated conflicts written: {args.audit_out}")
        print("Review stats:")
        for k, v in review_stats.items():
            print(f"  {k}: {v}")
        if base_warnings:
            print(f"Warnings ({len(base_warnings)}):")
            for e in base_warnings[:20]:
                print(f"  - {e}")
            if len(base_warnings) > 20:
                print(f"  ... and {len(base_warnings) - 20} more")

    if args.action == "normalize":
        base_data = load_base()
        normalize_character_moves(base_data)
        supplement = load_sc_supplement_from_character_files(
            char_names=list(base_data.keys()),
            data_dir=args.char_data_dir,
        )
        source_stats = write_character_sources(
            base_data=base_data,
            supplement=supplement,
            out_dir=args.char_data_dir,
            index_out=args.index_out,
        )
        print(f"Per-character source files rewritten under: {args.char_data_dir}")
        print(f"Character index written: {args.index_out}")
        print("Normalize stats:")
        for k, v in source_stats.items():
            print(f"  {k}: {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
