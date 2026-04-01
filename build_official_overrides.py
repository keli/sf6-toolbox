#!/usr/bin/env python3
"""
Fetch SF6 frame data from official streetfighter.com pages, then compare
against FAT per-character data to regenerate overrides JSON files.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import html
import json
import os
import re
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

from build_character_data import char_filename

CHARACTER_PAGE_URL = "https://www.streetfighter.com/6/character"
FRAME_PAGE_TEMPLATE = "https://www.streetfighter.com/6/character/{slug}/frame"

REQ_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9",
}

# Slugs that do not map 1:1 to local character names.
SLUG_NAME_ALIASES = {
    "gouki_akuma": "Akuma",
    "vega_mbison": "M.Bison",
}

STRENGTH_GROUPS = {
    "L": "L",
    "M": "M",
    "H": "H",
    "OD": "OD",
    "LP": "L",
    "LK": "L",
    "MP": "M",
    "MK": "M",
    "HP": "H",
    "HK": "H",
}

FIELD_CLASS_MAP = {
    "frame_startup_frame__": "startup",
    "frame_active_frame__": "active",
    "frame_recovery_frame__": "recovery",
    "frame_hit_frame__": "onHit",
    "frame_block_frame__": "onBlock",
}

TOKEN_ALIASES = {
    "standing": "stand",
    "crouching": "crouch",
    "jumping": "jump",
    "light": "l",
    "medium": "m",
    "heavy": "h",
    "punch": "p",
    "kick": "k",
}


@dataclass
class ParsedMove:
    category: str
    name: str
    startup: str | None
    active: str | None
    recovery: str | None
    onHit: str | None
    onBlock: str | None


def fetch_text(url: str, timeout: int = 30, referer: str | None = None) -> str:
    headers = dict(REQ_HEADERS)
    if referer:
        headers["Referer"] = referer
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)


def clean_html_text(fragment: str) -> str:
    s = fragment
    s = re.sub(r"<br\\s*/?>", " ", s, flags=re.IGNORECASE)
    s = re.sub(r"<!--.*?-->", "", s, flags=re.DOTALL)
    s = re.sub(r"<[^>]+>", " ", s)
    s = html.unescape(s)
    s = s.replace("\u2212", "-")
    return " ".join(s.split()).strip()


def normalize_value_text(value: Any) -> str:
    if value is None:
        return ""
    s = str(value).strip()
    s = s.replace("\u2212", "-").replace("\u2013", "-").replace("\u2014", "-")
    s = re.sub(r"\bframe\(s\)\s+after\s+landing\b", "land", s, flags=re.IGNORECASE)
    s = re.sub(
        r"\bframes?\s+of\s+recovery\s+upon\s+landing\b", "land", s, flags=re.IGNORECASE
    )
    s = " ".join(s.split())
    return s


def canonical_token(text: str) -> str:
    low = text.lower()
    parts = re.split(r"[^a-z0-9]+", low)
    out: list[str] = []
    for p in parts:
        if not p:
            continue
        out.append(TOKEN_ALIASES.get(p, p))
    return "".join(out)


def split_strength(name: str) -> tuple[str, str]:
    s = " ".join(name.split()).strip()
    if not s:
        return "", ""
    parts = s.split(" ", 1)
    first = parts[0].upper()
    rest = parts[1] if len(parts) > 1 else ""
    grp = STRENGTH_GROUPS.get(first, "")
    if grp:
        return grp, rest
    return "", s


def compare_equal(a: Any, b: Any) -> bool:
    an = normalize_value_text(a)
    bn = normalize_value_text(b)
    if an == bn:
        return True
    if re.fullmatch(r"[+-]?\\d+", an) and re.fullmatch(r"[+-]?\\d+", bn):
        return int(an) == int(bn)
    return False


def should_include_hitblock(value: str, allow_opaque: bool) -> bool:
    if not value:
        return False
    if allow_opaque:
        return True
    v = value.upper()
    # Default mode only includes values with concrete numeric signal.
    return bool(re.search(r"[+-]?\\d", v))


def parse_simple_int(value: Any) -> int | None:
    s = normalize_value_text(value)
    if re.fullmatch(r"-?\\d+", s):
        return int(s)
    return None


def parse_active_segments(value: str) -> list[tuple[int, int]] | None:
    ranges = re.findall(r"(\\d+)\\s*-\\s*(\\d+)", value)
    if not ranges:
        return None
    out: list[tuple[int, int]] = []
    for a, b in ranges:
        x = int(a)
        y = int(b)
        if y < x:
            return None
        seg = (x, y)
        if seg not in out:
            out.append(seg)
    return out or None


def active_segments_to_fat_expr(segments: list[tuple[int, int]]) -> str | None:
    if not segments:
        return None
    expr = ""
    prev_end: int | None = None
    for i, (start, end) in enumerate(segments):
        length = end - start + 1
        if length <= 0:
            return None
        if i == 0:
            expr = str(length)
            prev_end = end
            continue
        if prev_end is None:
            return None
        gap = start - prev_end - 1
        if gap < 0:
            return None
        expr += f"({gap}){length}"
        prev_end = end
    return expr


def normalize_active_expr(value: str) -> str:
    return re.sub(r"\\s+", "", value)


def compare_active_with_startup(
    official_active_raw: str,
    fat_active: Any,
    fat_startup: Any,
) -> tuple[bool, str | None, bool]:
    segments = parse_active_segments(official_active_raw)
    if not segments:
        return False, None, False
    startup = parse_simple_int(fat_startup)
    if startup is None:
        return False, None, False
    if segments[0][0] != startup:
        return False, None, False

    converted = active_segments_to_fat_expr(segments)
    if not converted:
        return False, None, False

    fat_norm = normalize_active_expr(normalize_value_text(fat_active))
    conv_norm = normalize_active_expr(converted)
    return fat_norm == conv_norm, converted, True


def normalize_official_field(field: str, value: str | None) -> str | None:
    if value is None:
        return None
    s = normalize_value_text(value)
    if not s:
        return None

    low = s.lower()
    if field == "recovery" and ("total" in low) and ("land" not in low):
        # FAT recovery and official "total frames" are not directly comparable.
        return None

    if field == "startup":
        # Keep leading numeric token; drop supplementary text.
        m = re.match(r"([0-9][0-9+*~()\\-]*)", s)
        if not m:
            return None
        s = m.group(1)

    return s


def extract_character_slugs(character_page_html: str) -> list[str]:
    slugs = sorted(
        set(re.findall(r'href="/6/character/([^"/?#]+)"', character_page_html))
    )
    return slugs


def parse_frame_rows(frame_html: str) -> list[ParsedMove]:
    m = re.search(r"<tbody>(.*?)</tbody>", frame_html, flags=re.DOTALL)
    if not m:
        return []
    tbody = m.group(1)
    rows: list[ParsedMove] = []
    category = ""

    tr_iter = re.finditer(r"<tr([^>]*)>(.*?)</tr>", tbody, flags=re.DOTALL)
    for trm in tr_iter:
        tr_attrs = trm.group(1) or ""
        tr_inner = trm.group(2) or ""

        if "frame_heading__" in tr_attrs:
            category = clean_html_text(tr_inner)
            continue

        td_matches = list(
            re.finditer(r"<td([^>]*)>(.*?)</td>", tr_inner, flags=re.DOTALL)
        )
        if not td_matches:
            continue

        move_name = ""
        values: dict[str, str | None] = {
            "startup": None,
            "active": None,
            "recovery": None,
            "onHit": None,
            "onBlock": None,
        }

        for tdm in td_matches:
            td_attrs = tdm.group(1) or ""
            td_inner = tdm.group(2) or ""
            class_m = re.search(r'class="([^"]+)"', td_attrs)
            classes = class_m.group(1).split() if class_m else []

            if any("frame_skill__" in c for c in classes):
                mm = re.search(
                    r'<span class="[^"]*frame_arts__[^"]*"[^>]*>(.*?)</span>',
                    td_inner,
                    flags=re.DOTALL,
                )
                move_name = clean_html_text(mm.group(1) if mm else td_inner)
                continue

            field = None
            for c in classes:
                for klass, fname in FIELD_CLASS_MAP.items():
                    if klass in c:
                        field = fname
                        break
                if field:
                    break

            if field:
                txt = clean_html_text(td_inner)
                values[field] = txt or None

        if not move_name:
            continue

        rows.append(
            ParsedMove(
                category=category or "Unknown",
                name=move_name,
                startup=values["startup"],
                active=values["active"],
                recovery=values["recovery"],
                onHit=values["onHit"],
                onBlock=values["onBlock"],
            )
        )
    return rows


def load_parsed_rows_from_raw(path: str) -> list[ParsedMove] | None:
    if not os.path.exists(path):
        return None
    try:
        payload = read_json(path)
    except Exception:
        return None
    moves = payload.get("moves") if isinstance(payload, dict) else None
    if not isinstance(moves, list):
        return None
    out: list[ParsedMove] = []
    for row in moves:
        if not isinstance(row, dict):
            continue
        out.append(
            ParsedMove(
                category=str(row.get("category", "")),
                name=str(row.get("name", "")),
                startup=row.get("startup"),
                active=row.get("active"),
                recovery=row.get("recovery"),
                onHit=row.get("onHit"),
                onBlock=row.get("onBlock"),
            )
        )
    return out


def build_slug_to_char_map(slugs: list[str], char_names: list[str]) -> dict[str, str]:
    name_index: dict[str, list[str]] = {}
    for n in char_names:
        name_index.setdefault(canonical_token(n), []).append(n)

    out: dict[str, str] = {}
    for slug in slugs:
        if slug in SLUG_NAME_ALIASES:
            out[slug] = SLUG_NAME_ALIASES[slug]
            continue

        key = canonical_token(slug.replace("_", " "))
        cands = name_index.get(key, [])
        if len(cands) == 1:
            out[slug] = cands[0]
            continue
    return out


def build_fat_lookup(
    char_fat: dict[str, Any],
) -> tuple[dict[str, tuple[str, str]], dict[str, list[tuple[str, str, str]]]]:
    # exact key -> (category, move_name)
    exact: dict[str, tuple[str, str]] = {}
    # base key -> list[(strength_group, category, move_name)]
    base: dict[str, list[tuple[str, str, str]]] = {}

    for category, moves in char_fat.get("moves", {}).items():
        if not isinstance(moves, dict):
            continue
        for move_name in moves.keys():
            full_key = canonical_token(move_name)
            exact[full_key] = (category, move_name)

            sg, rest = split_strength(move_name)
            rest_key = canonical_token(rest)
            if rest_key:
                base.setdefault(rest_key, []).append((sg, category, move_name))

    return exact, base


def match_fat_move(
    official_move_name: str,
    exact: dict[str, tuple[str, str]],
    base: dict[str, list[tuple[str, str, str]]],
) -> tuple[str, str] | None:
    full_key = canonical_token(official_move_name)
    if full_key in exact:
        return exact[full_key]

    off_sg, off_rest = split_strength(official_move_name)
    rest_key = canonical_token(off_rest)
    if not rest_key:
        return None
    cands = base.get(rest_key, [])
    if not cands:
        return None

    if off_sg:
        sg_cands = [c for c in cands if c[0] == off_sg]
        if len(sg_cands) == 1:
            _, cat, mv = sg_cands[0]
            return cat, mv

    # No strength in official name or still ambiguous: only accept unique.
    if len(cands) == 1:
        _, cat, mv = cands[0]
        return cat, mv
    return None


def make_override_payload(
    char_name: str,
    frame_url: str,
    frame_rows: list[ParsedMove],
    char_fat: dict[str, Any],
    allow_opaque_hitblock: bool,
) -> tuple[dict[str, Any], dict[str, int], list[dict[str, Any]]]:
    exact, base = build_fat_lookup(char_fat)

    fat_moves = char_fat.get("moves", {})
    entries: list[dict[str, Any]] = []
    conflict_rows: list[dict[str, Any]] = []
    stats = {
        "official_rows": len(frame_rows),
        "matched_rows": 0,
        "unmatched_rows": 0,
        "entries": 0,
        "changed_fields": 0,
    }

    for row in frame_rows:
        matched = match_fat_move(row.name, exact, base)
        if not matched:
            stats["unmatched_rows"] += 1
            continue

        category, move_name = matched
        fat_move = fat_moves.get(category, {}).get(move_name, {})
        if not isinstance(fat_move, dict):
            stats["unmatched_rows"] += 1
            continue

        stats["matched_rows"] += 1
        change_set: dict[str, Any] = {}

        pairs = {
            "startup": row.startup,
            "active": row.active,
            "recovery": row.recovery,
            "onHit": row.onHit,
            "onBlock": row.onBlock,
        }
        for field, off_v in pairs.items():
            if off_v is None or off_v == "":
                continue
            off_norm = normalize_official_field(field, off_v)
            if not off_norm:
                continue

            if field in {"onHit", "onBlock"} and (
                not should_include_hitblock(off_norm, allow_opaque_hitblock)
            ):
                continue

            fat_v = fat_move.get(field)
            if compare_equal(off_norm, fat_v):
                continue
            out_value = off_norm
            if field == "active":
                active_equal, converted, comparable = compare_active_with_startup(
                    official_active_raw=off_v,
                    fat_active=fat_v,
                    fat_startup=fat_move.get("startup"),
                )
                if not comparable:
                    # Skip ambiguous active forms to avoid noisy false positives.
                    continue
                if active_equal:
                    continue
                out_value = converted

            change_set[field] = out_value
            conflict_rows.append(
                {
                    "character": char_name,
                    "category": category,
                    "move": move_name,
                    "field": field,
                    "fat_value": normalize_value_text(fat_v),
                    "official_value": out_value,
                }
            )

        if change_set:
            entries.append(
                {
                    "category": category,
                    "move": move_name,
                    "set": change_set,
                }
            )
            stats["entries"] += 1
            stats["changed_fields"] += len(change_set)

    entries.sort(key=lambda x: (str(x.get("category", "")), str(x.get("move", ""))))

    payload = {
        "character": char_name,
        "source": "official-streetfighter-com-frame-vs-fat",
        "sourceUrl": frame_url,
        "generatedAt": dt.datetime.now(dt.UTC).isoformat(),
        "notes": [
            "Auto-generated from official SF6 frame pages and FAT comparison.",
            "Review before apply; move matching is name-based and may miss/skip ambiguous rows.",
        ],
        "entries": entries,
    }
    return payload, stats, conflict_rows


def write_conflict_reports(
    conflict_rows_by_char: dict[str, list[dict[str, Any]]],
    per_char_dir: str,
    audit_out: str,
) -> None:
    os.makedirs(per_char_dir, exist_ok=True)
    fields = [
        "character",
        "category",
        "move",
        "field",
        "fat_value",
        "official_value",
    ]

    all_rows: list[dict[str, Any]] = []
    for char_name in sorted(conflict_rows_by_char.keys()):
        rows = conflict_rows_by_char.get(char_name, [])
        all_rows.extend(rows)
        out_path = os.path.join(
            per_char_dir, f"{char_filename(char_name)}.official.conflicts.csv"
        )
        with open(out_path, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=fields)
            w.writeheader()
            w.writerows(rows)

    with open(audit_out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(all_rows)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=(
            "Fetch official SF6 frame pages, save raw parsed rows, and regenerate "
            "per-character overrides by comparing with FAT."
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
        help="Data directory for *.fat.json and output overrides (default: data)",
    )
    ap.add_argument(
        "--raw-dir",
        default="data/official-frame",
        help="Directory to store parsed official frame raw files (default: data/official-frame)",
    )
    ap.add_argument(
        "--conflicts-dir",
        default="data/official-frame",
        help=(
            "Directory for per-character official-vs-fat conflict CSV files "
            "(default: data/official-frame)"
        ),
    )
    ap.add_argument(
        "--audit-out",
        default="data/official-frame/official_overrides.conflicts.csv",
        help=(
            "Output CSV path for aggregated official-vs-fat conflicts "
            "(default: data/official-frame/official_overrides.conflicts.csv)"
        ),
    )
    ap.add_argument(
        "--character-page-url",
        default=CHARACTER_PAGE_URL,
        help=f"Character list URL (default: {CHARACTER_PAGE_URL})",
    )
    ap.add_argument(
        "--frame-url-template",
        default=FRAME_PAGE_TEMPLATE,
        help=f"Frame page template with {{slug}} (default: {FRAME_PAGE_TEMPLATE})",
    )
    ap.add_argument(
        "--allow-opaque-hitblock",
        action="store_true",
        help=(
            "Allow non-numeric onHit/onBlock values (e.g. 'D') to be written "
            "to overrides. Default skips these."
        ),
    )
    ap.add_argument(
        "--chars",
        default="",
        help=(
            "Optional comma-separated character names to process "
            "(local names from characters.index.json)."
        ),
    )
    ap.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Network timeout seconds (default: 30)",
    )
    ap.add_argument(
        "--refresh",
        action="store_true",
        help=(
            "Force re-fetch frame pages from official website even if local "
            "raw files already exist."
        ),
    )
    args = ap.parse_args()

    index_payload = read_json(args.char_index)
    rows = list(index_payload.get("characters", []))
    chars_by_name = {
        str(r.get("name", "")).strip(): r
        for r in rows
        if str(r.get("name", "")).strip()
    }
    char_names = sorted(chars_by_name.keys())
    if not char_names:
        raise ValueError("No characters found in char index.")

    selected: set[str] | None = None
    if args.chars.strip():
        selected = {x.strip() for x in args.chars.split(",") if x.strip()}
        unknown = sorted(selected - set(char_names))
        if unknown:
            raise ValueError(f"Unknown characters in --chars: {', '.join(unknown)}")

    os.makedirs(args.raw_dir, exist_ok=True)

    char_page_html = fetch_text(args.character_page_url, timeout=args.timeout)
    slugs = extract_character_slugs(char_page_html)
    slug_to_char = build_slug_to_char_map(slugs, char_names)

    unresolved = sorted(set(slugs) - set(slug_to_char.keys()))
    if unresolved:
        print(f"Warning: unresolved slugs (skipped): {', '.join(unresolved)}")

    total_stats = {
        "characters_processed": 0,
        "characters_written": 0,
        "official_rows": 0,
        "matched_rows": 0,
        "unmatched_rows": 0,
        "entries": 0,
        "changed_fields": 0,
        "reused_raw": 0,
        "fetched_web": 0,
    }
    conflict_rows_by_char: dict[str, list[dict[str, Any]]] = {}

    for slug in slugs:
        char_name = slug_to_char.get(slug)
        if not char_name:
            continue
        if selected is not None and char_name not in selected:
            continue

        row = chars_by_name.get(char_name)
        if not row:
            print(f"Skip {slug}: missing character index row for {char_name}")
            continue
        fat_file = str(row.get("fatFile", "")).strip()
        if not fat_file:
            print(f"Skip {char_name}: missing fatFile in character index")
            continue

        raw_out = os.path.join(
            args.raw_dir, f"{char_filename(char_name)}.official.frame.json"
        )
        frame_url = args.frame_url_template.format(slug=slug)

        parsed_rows: list[ParsedMove] | None = None
        if not args.refresh:
            parsed_rows = load_parsed_rows_from_raw(raw_out)
            if parsed_rows is not None:
                total_stats["reused_raw"] += 1

        if parsed_rows is None:
            try:
                frame_html = fetch_text(
                    frame_url,
                    timeout=args.timeout,
                    referer=args.character_page_url,
                )
            except urllib.error.URLError as e:
                print(f"Skip {char_name}: fetch failed: {e}")
                continue

            parsed_rows = parse_frame_rows(frame_html)
            raw_payload = {
                "character": char_name,
                "slug": slug,
                "url": frame_url,
                "fetchedAt": dt.datetime.now(dt.UTC).isoformat(),
                "moveCount": len(parsed_rows),
                "moves": [m.__dict__ for m in parsed_rows],
            }
            write_json(raw_out, raw_payload)
            total_stats["fetched_web"] += 1

        fat_path = os.path.join(args.data_dir, fat_file)
        if not os.path.exists(fat_path):
            print(f"Skip {char_name}: missing FAT file: {fat_path}")
            continue
        char_fat = read_json(fat_path)
        if not isinstance(char_fat, dict):
            print(f"Skip {char_name}: invalid FAT JSON object")
            continue

        overrides_payload, st, conflict_rows = make_override_payload(
            char_name=char_name,
            frame_url=frame_url,
            frame_rows=parsed_rows,
            char_fat=char_fat,
            allow_opaque_hitblock=args.allow_opaque_hitblock,
        )
        out_path = os.path.join(
            args.data_dir, f"{char_filename(char_name)}.overrides.json"
        )
        write_json(out_path, overrides_payload)
        conflict_rows_by_char[char_name] = conflict_rows

        total_stats["characters_processed"] += 1
        total_stats["characters_written"] += 1
        total_stats["official_rows"] += st["official_rows"]
        total_stats["matched_rows"] += st["matched_rows"]
        total_stats["unmatched_rows"] += st["unmatched_rows"]
        total_stats["entries"] += st["entries"]
        total_stats["changed_fields"] += st["changed_fields"]

        print(
            f"{char_name}: rows={st['official_rows']}, matched={st['matched_rows']}, "
            f"unmatched={st['unmatched_rows']}, entries={st['entries']}, "
            f"changed_fields={st['changed_fields']}"
        )

    write_conflict_reports(
        conflict_rows_by_char=conflict_rows_by_char,
        per_char_dir=args.conflicts_dir,
        audit_out=args.audit_out,
    )
    print("Done.")
    for k, v in total_stats.items():
        print(f"  {k}: {v}")
    print(f"  raw_dir: {args.raw_dir}")
    print(f"  conflicts_dir: {args.conflicts_dir}")
    print(f"  audit_out: {args.audit_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
