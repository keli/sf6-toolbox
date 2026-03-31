# AI Review Guide

This guide defines the AI workflow for deciding and applying manual overrides to character data, based on conflicts files. In conflicts files Supercombo's data is more up-to-date but were manually editted by human so hard to parse by code, your job is to understand them and decide which items should be used to override existing values.

## Workflow Contract

1. Use `data/<Character>.conflicts.csv` as evidence when selecting values. 
2. Do not batch process these files. Manually go through each items, one file at a time.
4. Keep override values index-friendly when possible.
5. Write manual corrections into `data/<Character>.overrides.json`. 
6. Run `apply_character_overrides.py` to apply overrides and write `data/<Character>.json`.

## Apply Script Modes

`apply_character_overrides.py` supports two base sources:

- `--apply-base fat` (default): read from `data/<Character>.fat.json`
- `--apply-base final`: read from existing `data/<Character>.json`

Strict value-format validation is optional:

- default: non-strict (simple override application)
- `--strict`: enforce index-friendly value format checks

## Index-Friendly Value Constraints (Strict Mode)

- Numeric fields (`startup`, `active`, `recovery`, `onBlock`):
  - integer, or
  - integer string (e.g. `"12"`, `"-3"`)
- Advantage fields (`onHit`, `onPC`):
  - integer, or
  - integer string, or
  - `KD +N` / `HKD +N` string forms
- Avoid unstable text forms (ranges, notes, free-form timing text) in strict mode.
