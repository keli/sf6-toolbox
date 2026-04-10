# SF6 Structured Data Export

`sf6_structured_export` exports machine-friendly SF6 battle/action data for tooling and analysis.

## Files and Roles

- Deploy entrypoint: `sf6-toolbox/deploy_sf6_toolbox.bat`
- Deploy script: `sf6-toolbox/scripts/deploy_reframework.ps1`
- Core exporter: `sf6-toolbox/reframework/sf6_structured_export_core.lua`
- REFramework bootstrap (auto-generated): `reframework/autorun/sf6_structured_export.lua`
- Data sandbox root: `reframework/data/sf6-toolbox`
- Alias map (runtime): `reframework/data/sf6-toolbox/sf6_character_aliases.json`
- Output root (runtime): `reframework/data/sf6-toolbox/structured`

## Deploy

From `reframework/autorun/sf6-toolbox` run:

`deploy_sf6_toolbox.bat`

What deploy does:

- creates `reframework/data/sf6-toolbox/structured` and `.../characters`
- writes/updates `reframework/autorun/sf6_structured_export.lua`
- seeds runtime files from repository if runtime files are missing:
  - `autorun/sf6-toolbox/data/sf6_character_aliases.json` -> `reframework/data/sf6-toolbox/sf6_character_aliases.json`
- migrates legacy files if found:
  - `sf6_character_aliases.json`
  - `sf6_structured_export.json`
  - `sf6_structured_index.json`
- migrates older nested runtime layout if found:
  - `reframework/data/sf6-toolbox/data/sf6_character_aliases.json`
  - `reframework/data/sf6-toolbox/data/structured/*`

After deploy, reload scripts in REFramework.

## Daily Usage

1. Enter training/versus/replay so battle resources are loaded.
2. Open REFramework UI -> `SF6 Structured Export`.
3. Use `Export P1` / `Export P2`.
4. Read outputs under `reframework/data/sf6-toolbox/structured/characters`.

## Update Flow

Use this after pulling `sf6-toolbox` changes:

1. Update files (`git pull` or sync).
2. Re-run `deploy_sf6_toolbox.bat`.
3. Reload REFramework scripts.
4. Run one export as smoke test.

## New Character Flow

1. Update game and run deploy.
2. Load the new character once in battle/replay context.
3. In exporter UI click `Refresh Roster`.
4. Export P1/P2.
5. If needed, edit alias in `reframework/data/sf6-toolbox/sf6_character_aliases.json`.

## Output Data

- Per-character file:
  `reframework/data/sf6-toolbox/structured/characters/sf6_structured_<chara_id>.json`
- Index/roster:
  `reframework/data/sf6-toolbox/structured/sf6_structured_index.json`

Primary identifiers are `chara_id` and `action_id`.
Display names are soft labels from alias + enum data.

## Troubleshooting

1. UI entry missing: run deploy again, then reload scripts.
2. Export inactive: ensure you are in an active battle resource context.
3. New character missing: load character once, then `Refresh Roster`.
4. Name shows `PL_XXX`: add alias in `reframework/data/sf6-toolbox/sf6_character_aliases.json`.
5. Output not found: check `reframework/data/sf6-toolbox/structured`.

## Limitations

- Exports are based on currently loaded battle resources.
- Full roster export requires loading each character at least once.
