#!/usr/bin/env python3
"""
SF6 Meaty Calculator (偷帧方案枚举)

枚举击倒后，通过若干前置动作消耗帧数，最终用一个动作在对手起身时达到
meaty 效果（命中持续帧，偷取帧优势）的所有方案。

Usage:
    python calc_meaty.py <character> [options]

Examples:
    python calc_meaty.py Ryu
    python calc_meaty.py Ryu --perfect-only
    python calc_meaty.py Ryu --hit-type pc --kd-type hkd
    python calc_meaty.py Ryu --max-prefix 2 --no-safe

Meaty 原理:
    击倒优势 K 帧，经过若干前置动作共消耗 T 帧后，剩余 K' = K - T 帧。
    最后动作前摇 S 帧、持续 A 帧，持续帧窗口 [S, S+A-1]。
    meaty 条件: S <= K' <= S+A-1
    命中第 N 个持续帧: N = K'-S+1，额外偷帧 = N-1
    完美 meaty: N = A（最后一帧，偷帧最多）
"""

import sys
import json
import re
from pathlib import Path
from dataclasses import dataclass, field
from collections import defaultdict
from itertools import product


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def load_character(name: str) -> tuple[str, dict]:
    data_dir = Path("data")
    filename = f"{name.replace(' ', '_').replace('.', '').lower()}.json"
    path = data_dir / filename
    if not path.exists():
        for p in data_dir.glob("*.json"):
            if p.stem.lower() == filename.replace(".json", "").lower():
                path = p
                break
        else:
            print(f"Data file not found for '{name}'. Run: python fetch_data.py \"{name}\"")
            sys.exit(1)
    with open(path) as f:
        data = json.load(f)
    char_name = next(iter(data))
    return char_name, data[char_name]


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_int(val) -> int | None:
    if val is None:
        return None
    if isinstance(val, int):
        return val
    if isinstance(val, str):
        m = re.search(r"-?\d+", val)
        if m:
            return int(m.group())
    return None


def parse_int_worst(val) -> int | None:
    """Parse frame value, returning the worst (minimum) numeric value found.
    Used for onBlock to get the most negative scenario."""
    if val is None:
        return None
    if isinstance(val, int):
        return val
    if isinstance(val, str):
        nums = [int(m) for m in re.findall(r"-?\d+", val)]
        if nums:
            return min(nums)
    return None


@dataclass
class KDInfo:
    hit_type: str   # "normal", "pc", "cc"
    kd_type: str    # "KD" or "HKD"
    advantage: int  # frame advantage (+XX in "KD +XX")


@dataclass
class Move:
    name: str
    cmd: str
    startup: int
    active: int
    recovery: int
    total: int          # startup + active + recovery - 1
    on_block: int | None
    on_hit: int | None
    move_type: str
    is_attack: bool     # True if move has an attack level (atkLvl != None)
    knockdowns: list[KDInfo] = field(default_factory=list)


def parse_kd_field(val, hit_type: str) -> list[KDInfo]:
    if val is None or isinstance(val, (int, float)):
        return []
    results = []
    for m in re.finditer(r"(H?KD)\s*\+(\d+)", str(val)):
        results.append(KDInfo(hit_type=hit_type, kd_type=m.group(1), advantage=int(m.group(2))))
    return results


def extract_dash(char_data: dict) -> list[Move]:
    """Create synthetic Move entries for forward/back dash from stats."""
    moves = []
    stats = char_data.get("stats", {})
    for key, cmd, name in [("fDash", "66", "Forward Dash")]:
        frames = parse_int(stats.get(key))
        if frames:
            moves.append(Move(
                name=name, cmd=cmd,
                startup=frames, active=0, recovery=0,
                total=frames,
                on_block=None, on_hit=None, move_type="dash", is_attack=False,
            ))
    return moves


def extract_moves(char_data: dict) -> list[Move]:
    moves = []
    for cat_name, cat_moves in char_data.get("moves", {}).items():
        if not isinstance(cat_moves, dict):
            continue
        for move_key, mv in cat_moves.items():
            if not isinstance(mv, dict):
                continue
            startup = parse_int(mv.get("startup"))
            active = parse_int(mv.get("active"))
            recovery = parse_int(mv.get("recovery"))
            if startup is None or active is None or active <= 0:
                continue
            total = mv.get("total")
            if total is None:
                total = startup + active + (recovery or 0) - 1
            else:
                total = parse_int(total) or (startup + active + (recovery or 0) - 1)

            knockdowns = (
                parse_kd_field(mv.get("onHit"), "normal")
                + parse_kd_field(mv.get("onPC"), "pc")
                + parse_kd_field(mv.get("onCC"), "cc")
            )
            cmd = mv.get("numCmd") or mv.get("plnCmd") or move_key
            moves.append(Move(
                name=mv.get("moveName") or move_key,
                cmd=cmd,
                startup=startup,
                active=active,
                recovery=recovery or 0,
                total=total,
                on_block=parse_int_worst(mv.get("onBlock")),
                on_hit=parse_int(mv.get("onHit")),
                move_type=cat_name,
                is_attack=mv.get("atkLvl") is not None,
                knockdowns=knockdowns,
            ))
    return moves


# ---------------------------------------------------------------------------
# Meaty calculation
# ---------------------------------------------------------------------------

@dataclass
class MeatyResult:
    kd_move: Move
    kd_info: KDInfo
    prefix: list[Move]      # actions taken before the meaty move (may be empty)
    meaty_move: Move
    frames_remaining: int   # K' = KD advantage after prefix
    active_frame_hit: int   # which active frame hits (1=first, A=last=perfect)
    is_perfect: bool
    total_advantage: int | None  # on_hit + stolen frames (None if on_hit unknown)


def is_safe_on_block(move: Move, threshold: int = -4) -> bool:
    """Return True if move is safe on block (on_block > threshold).
    Moves with on_block <= threshold are considered unsafe and filtered out."""
    if move.on_block is None:
        return True  # unknown, don't filter
    return move.on_block > threshold


def calc_meatys(
    moves: list[Move],
    dash_frames: int = 0,
    hit_type_filter: str = "both",
    kd_type_filter: str = "both",
    max_prefix: int = 2,
    safe_only: bool = True,
    first_move: str = "move",  # "move" = non-attack only, "any" = any move
) -> list[MeatyResult]:
    results = []

    # Pre-filter meaty candidates: must be an attack, optionally safe on block
    meaty_candidates = [
        m for m in moves
        if m.is_attack
        and (not safe_only or is_safe_on_block(m))
    ]

    # All moves can be used as prefix actions
    prefix_pool = moves

    for kd_move in moves:
        for kd_info in kd_move.knockdowns:
            if hit_type_filter != "both" and kd_info.hit_type != hit_type_filter:
                continue
            if kd_type_filter != "both" and kd_info.kd_type.lower() != kd_type_filter:
                continue

            K_base = kd_info.advantage - dash_frames
            if K_base <= 0:
                continue

            # Enumerate prefix lengths 1..max_prefix
            first_pool = [m for m in prefix_pool if not m.is_attack] if first_move == "move" else prefix_pool
            for prefix_len in range(1, max_prefix + 1):
                if prefix_len == 1:
                    prefix_combos = [(m,) for m in first_pool]
                else:
                    prefix_combos = (
                        (first,) + rest
                        for first in first_pool
                        for rest in product(prefix_pool, repeat=prefix_len - 1)
                    )

                for prefix in prefix_combos:
                    prefix_cost = sum(m.total for m in prefix)
                    K = K_base - prefix_cost
                    if K <= 0:
                        continue

                    for meaty in meaty_candidates:
                        S = meaty.startup
                        A = meaty.active
                        if S <= K <= S + A - 1:
                            active_frame_hit = K - S + 1
                            stolen = active_frame_hit - 1
                            on_hit = meaty.on_hit
                            if meaty.knockdowns:
                                total_adv = None  # meaty move itself causes KD, don't compute
                            else:
                                total_adv = (on_hit + stolen) if on_hit is not None else None
                            results.append(MeatyResult(
                                kd_move=kd_move,
                                kd_info=kd_info,
                                prefix=list(prefix),
                                meaty_move=meaty,
                                frames_remaining=K,
                                active_frame_hit=active_frame_hit,
                                is_perfect=(active_frame_hit == A),
                                total_advantage=total_adv,
                            ))

    return results


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def format_sequence(prefix: list[Move], meaty: Move) -> str:
    parts = [m.cmd for m in prefix] + [meaty.cmd]
    return " → ".join(parts)


def print_results(results: list[MeatyResult], char_name: str, dash_frames: int, safe_only: bool):
    if not results:
        print("No meaty setups found.")
        return

    grouped: dict[tuple, list[MeatyResult]] = defaultdict(list)
    for r in results:
        key = (r.kd_move.name, r.kd_move.cmd, r.kd_info.hit_type, r.kd_info.kd_type, r.kd_info.advantage)
        grouped[key].append(r)

    dash_str = f" → dash({dash_frames}f)" if dash_frames > 0 else ""
    safe_str = "  [safe on block only]" if safe_only else ""
    print(f"\n{'='*72}")
    print(f"  SF6 Meaty Setups — {char_name}{safe_str}")
    if dash_frames:
        print(f"  (with forward dash: {dash_frames} frames)")
    print(f"{'='*72}\n")

    for (mv_name, mv_cmd, hit_type, kd_type, adv), rs in sorted(grouped.items(), key=lambda x: -x[0][4]):
        print(f"KD Move : {mv_name} ({mv_cmd})  [{hit_type.upper()}] {kd_type} +{adv}")
        if dash_str:
            print(f"          KD +{adv}{dash_str} → {adv - rs[0].frames_remaining + (adv - rs[0].kd_info.advantage + dash_frames)}f remaining")
        kprime = "K'"
        print(f"  {'Sequence':<40} {kprime:<5} {'S':<4} {'A':<4} {'Hit frame':<12} {'Stolen':<8} {'Total adv':<10} {'On block':<10} {'Perfect?'}")
        print(f"  {'-'*40} {'-'*5} {'-'*4} {'-'*4} {'-'*12} {'-'*8} {'-'*10} {'-'*10} {'-'*8}")
        for r in sorted(rs, key=lambda x: (-int(x.is_perfect), -x.active_frame_hit, len(x.prefix))):
            seq = format_sequence(r.prefix, r.meaty_move)
            stolen = r.active_frame_hit - 1
            perfect_str = "★" if r.is_perfect else ""
            if r.meaty_move.knockdowns:
                total_str = "KD"
            elif r.total_advantage is not None:
                total_str = f"+{r.total_advantage}"
            else:
                total_str = "?"
            ob = r.meaty_move.on_block
            ob_str = f"{ob:+d}" if ob is not None else "?"
            print(f"  {seq:<40} {r.frames_remaining:<5} {r.meaty_move.startup:<4} {r.meaty_move.active:<4} "
                  f"{r.active_frame_hit}/{r.meaty_move.active:<10} +{stolen:<8} {total_str:<10} {ob_str:<10} {perfect_str}")
        print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("character", nargs="+", help="Character name")
    parser.add_argument("--hit-type", choices=["normal", "pc", "cc", "both"], default="both")
    parser.add_argument("--kd-type", choices=["kd", "hkd", "both"], default="both")
    parser.add_argument("--dash", type=int, default=0, help="Forward dash frames (default: 0)")
    parser.add_argument("--max-prefix", type=int, default=2,
                        help="Max number of actions before the meaty move (default: 2)")
    parser.add_argument("--safe", action=argparse.BooleanOptionalAction, default=True,
                        help="Filter meaty move to safe on block >= -4 (default: on)")
    parser.add_argument("--safe-threshold", type=int, default=-4,
                        help="On-block threshold for --safe (default: -4)")
    parser.add_argument("--first", choices=["move", "any"], default="move",
                        help="First prefix action type: 'move' = movement only (default), 'any' = any move")
    parser.add_argument("--min-advantage", type=int, default=4,
                        help="Minimum total frame advantage on hit after stealing (default: 4)")
    parser.add_argument("--perfect-only", action="store_true",
                        help="Only show perfect meatys (last active frame)")
    args = parser.parse_args()

    char_name = " ".join(args.character)
    char_key, char_data = load_character(char_name)
    moves = extract_moves(char_data) + extract_dash(char_data)
    print(f"Loaded {len(moves)} moves for {char_key}")

    results = calc_meatys(
        moves,
        dash_frames=args.dash,
        hit_type_filter=args.hit_type,
        kd_type_filter=args.kd_type,
        max_prefix=args.max_prefix,
        safe_only=args.safe,
        first_move=args.first,
    )

    if args.perfect_only:
        results = [r for r in results if r.is_perfect]

    results = [
        r for r in results
        if r.meaty_move.knockdowns or r.total_advantage is None or r.total_advantage >= args.min_advantage
    ]

    # Apply safe threshold (if custom)
    if args.safe and args.safe_threshold != -4:
        results = [r for r in results if r.meaty_move.on_block is None or r.meaty_move.on_block > args.safe_threshold]

    print_results(results, char_key, args.dash, args.safe)

    total = len(results)
    perfect = sum(1 for r in results if r.is_perfect)
    print(f"Total: {total}  (perfect ★: {perfect})")


if __name__ == "__main__":
    main()
