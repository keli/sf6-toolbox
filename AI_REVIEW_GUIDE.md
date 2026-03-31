# AI Review Guide

This guide defines the AI workflow for deciding and applying manual overrides to character data, based on conflicts files. In conflicts files Supercombo's data is more up-to-date but were manually editted by human so hard to parse by code, your job is to understand them and decide which items should be used to override existing values.

## Workflow Contract

1. Use `data/<Character>.conflicts.csv` as evidence when selecting values. 
2. Do not batch process these files. Manually go through each items, one file at a time.
3. Write manual corrections into `data/<Character>.overrides.json` based on your understanding, one file at a time. You are not allowed to use code to do this.
4. Prefer preserving Supercombo/FAT-style value shapes in overrides when semantics depend on ranges/variants.
5. Treat `normalized` output as the source of truth for search/calculation behavior.
6. Rebuild normalized data and apply overrides in the order shown below.

## Apply Script Modes

`apply_character_overrides.py` supports two base sources:

- `--apply-base fat` (default): read from `data/<Character>.fat.json`
- `--apply-base final`: read from existing `data/<Character>.json`

Strict value-format validation is optional:

- default: non-strict (simple override application)
- `--strict`: enforce index-friendly value format checks

## Override Authoring Policy (Current)

- `overrides.json` may use FAT-like raw forms, not only single numbers.
- Recommended when copying from evidence:
  - Numeric/range: `12`, `-3`, `13~19`, `2(5)2`, `33(1)(11)`
  - KD/HKD forms: `KD +33`, `KD +33(+45)`, `KD +43~45`, `13~19 (KD)`, `15 (HKD)`
- Avoid rewriting range/variant text into a single number unless evidence is explicitly single-valued.
- Final behavior is determined by shared normalize logic in `build_character_data.py` (also used by apply script for changed moves).

## Current Normalize Limits

The current normalize logic preserves raw text and extracts some numbers, but it does **not** fully understand every FAT/SuperCombo text shape. When writing overrides, keep the following limits in mind:

- Correctly/mostly handled:
  - Plain integers: `12`, `-3`
  - Simple numeric ranges for min/max extraction: `13~19`
  - KD/HKD forms: `KD +33`, `HKD +21`, `KD +33(+45)`, `KD +43~45`, `13~19 (KD)`
- Only partially understood:
  - Multi-hit timing strings such as `2(4)2(3)1(3)...`, `2,7(6)5(6)...`
  - Recovery/timing notes such as `21+14 land`, `16(7)+3 land`, `50+100`
  - Bracketed supplement forms such as `[10(20)10]`, `17[14]`
  - Mixed advantage variants such as `+1(+4)`, `-12(-1)`, `+5(+10) / KD +37`
  - Text with notes/tags such as `Crumple`, `Wall Splat`, `Launch`, `Tumble`, `OTG`
- Important consequence:
  - `normalize_numeric_field()` mainly extracts `numbers`, `first`, `min`, `max`, and raw `text`.
  - It does **not** build a structured representation of multi-hit sequences, bracketed alternates, land-recovery variants, or conditional branches.
  - `normalize_adv_field()` only has dedicated handling for KD/HKD patterns; non-KD variant text is mostly reduced to first/min/max numbers plus raw text.
- Authoring rule:
  - It is acceptable to preserve these raw text forms in overrides when they are the best evidence.
  - But do **not** assume current search/calculation/UI logic fully understands them just because `normalized` exists.
  - If a downstream feature requires exact behavior, that feature or the normalize logic must be enhanced explicitly.

## Index-Friendly Value Constraints (Strict Mode)

- Numeric fields (`startup`, `active`, `recovery`, `onBlock`):
  - integer, or
  - integer string (e.g. `"12"`, `"-3"`)
- Advantage fields (`onHit`, `onPC`):
  - integer, or
  - integer string, or
  - `KD +N` / `HKD +N` string forms
- Avoid unstable text forms (ranges, notes, free-form timing text) in strict mode.

`--strict` is a lint mode for index-friendly-only overrides.  
If overrides intentionally preserve FAT-style ranges/variants, use non-strict apply.

## Regenerate + Apply (Recommended)

1. Regenerate per-character FAT normalized fields:
   - `python3 build_character_data.py normalize`
2. Apply manual overrides from FAT base:
   - `python3 apply_character_overrides.py --apply-base fat`
3. Optional strict lint run (only if your overrides intentionally avoid FAT-style range forms):
   - `python3 apply_character_overrides.py --apply-base fat --strict`

## KD Value Format Rules

The meaty calculator parses every `KD +N` / `HKD +N` token it finds in `onHit`/`onPC` strings. Each match becomes a separate knockdown entry. Write these values carefully:

### Tumble air-state vs ground wakeup

Some moves knock the opponent into a "Tumble" (mid-air tumbling) state before they land. The advantage during the air state is **not** a wakeup timing and must **not** be prefixed with `KD`/`HKD`.

| Situation | Correct format | Wrong format |
|---|---|---|
| Tumble air advantage + landing KD | `Tumble +66 (KD +44~50)` | `KD +66 Tumble (KD +44~50)` ← generates two entries |
| Tumble only, no separate landing KD | `KD +96~102 Tumble` | — |

Rule: if evidence shows a `Tumble +N` value alongside a separate landing `KD +M`, only the landing value should carry the `KD` prefix.

### Two KD entries that are both valid

When a move has genuinely different wakeup timings by location (open area vs corner/wall splat), **both** entries should be kept with their KD prefix. Two entries in the calculator is correct behavior here.

Example — both are intentional:
```
"KD +60 Tumble (HKD +128 Wallsplat)"   → open-area KD +60 and corner HKD +128
"KD +70 Tumble (HKD +138 Wall Splat)"  → same structure
```

## Review Checklist For AI-Generated Overrides

1. Every override entry is traceable to a row in `data/<Character>.conflicts.csv`.
2. Fields are limited to: `startup`, `active`, `recovery`, `onHit`, `onBlock`, `onPC`.
3. Range/KD semantics from evidence are not collapsed accidentally.
4. KD prefix is only on ground-wakeup values, not air/Tumble-state advantages (see KD Value Format Rules above).
5. After regenerate+apply, inspect target `data/<Character>.json` `normalized` values (especially `kd.advantageMin/advantageMax`).
