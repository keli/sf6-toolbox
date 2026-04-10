param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "[deploy] $msg"
}

function Ensure-Dir($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
        Write-Step "created dir: $path"
    }
}

function Ensure-FileIfMissing($from, $to) {
    if ((Test-Path -LiteralPath $from) -and (-not (Test-Path -LiteralPath $to))) {
        $toDir = Split-Path -Parent $to
        if ($toDir) {
            Ensure-Dir $toDir
        }
        Copy-Item -LiteralPath $from -Destination $to -Force
        Write-Step "migrated: $from -> $to"
    }
}

function Ensure-DirCopiedIfMissing($from, $to) {
    if ((Test-Path -LiteralPath $from) -and (-not (Test-Path -LiteralPath $to))) {
        $toParent = Split-Path -Parent $to
        if ($toParent) {
            Ensure-Dir $toParent
        }
        Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
        Write-Step "migrated dir: $from -> $to"
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolboxDir = Resolve-Path (Join-Path $scriptDir "..")
$autorunDir = Resolve-Path (Join-Path $toolboxDir "..")
$reframeworkDir = Resolve-Path (Join-Path $autorunDir "..")

$corePath = Join-Path $toolboxDir "reframework\sf6_structured_export_core.lua"
if (-not (Test-Path -LiteralPath $corePath)) {
    throw "core script not found: $corePath"
}

$sandboxToolboxDir = Join-Path $reframeworkDir "data\sf6-toolbox"
$structuredDir = Join-Path $sandboxToolboxDir "structured"
$structuredCharsDir = Join-Path $structuredDir "characters"
$newAliasPath = Join-Path $sandboxToolboxDir "sf6_character_aliases.json"

$legacyAliasPath = Join-Path $autorunDir "sf6_character_aliases.json"
$legacyConfigPath = Join-Path $autorunDir "sf6_structured_export.json"
$legacyIndexPath = Join-Path $autorunDir "sf6_structured_index.json"
$legacyNestedDataRoot = Join-Path $sandboxToolboxDir "data"
$legacyNestedAliasPath = Join-Path $legacyNestedDataRoot "sf6_character_aliases.json"
$legacyNestedStructuredDir = Join-Path $legacyNestedDataRoot "structured"
$legacyNestedConfigPath = Join-Path $legacyNestedStructuredDir "sf6_structured_export.json"
$legacyNestedIndexPath = Join-Path $legacyNestedStructuredDir "sf6_structured_index.json"
$legacyNestedCharsDir = Join-Path $legacyNestedStructuredDir "characters"

$repoAliasPath = Join-Path $toolboxDir "data\sf6_character_aliases.json"
$repoStructuredDir = Join-Path $toolboxDir "data\structured"
$repoConfigPath = Join-Path $repoStructuredDir "sf6_structured_export.json"
$repoIndexPath = Join-Path $repoStructuredDir "sf6_structured_index.json"

$bootstrapPath = Join-Path $autorunDir "sf6_structured_export.lua"
$bootstrapContent = @'
local source_path = debug.getinfo(1, "S").source:gsub("^@", "")
local base_dir = source_path:match("^(.*)[/\\][^/\\]+$") or "."
local core_path = base_dir .. "\\sf6-toolbox\\reframework\\sf6_structured_export_core.lua"

local ok, err = pcall(dofile, core_path)
if not ok then
    log.error("[sf6_structured_export] Failed to load core: " .. tostring(err))
end
'@

Write-Step "toolbox dir: $toolboxDir"
Write-Step "autorun dir: $autorunDir"
Write-Step "reframework dir: $reframeworkDir"
Write-Step "data sandbox: $sandboxToolboxDir"

Ensure-Dir (Join-Path $toolboxDir "reframework")
Ensure-Dir (Join-Path $reframeworkDir "data")
Ensure-Dir $sandboxToolboxDir
Ensure-Dir $structuredDir
Ensure-Dir $structuredCharsDir

# Seed from repository files on first deploy.
Ensure-FileIfMissing $repoAliasPath $newAliasPath
Ensure-FileIfMissing $repoConfigPath (Join-Path $structuredDir "sf6_structured_export.json")
Ensure-FileIfMissing $repoIndexPath (Join-Path $structuredDir "sf6_structured_index.json")

# Migrate very old root files.
Ensure-FileIfMissing $legacyAliasPath $newAliasPath
Ensure-FileIfMissing $legacyConfigPath (Join-Path $structuredDir "sf6_structured_export.json")
Ensure-FileIfMissing $legacyIndexPath (Join-Path $structuredDir "sf6_structured_index.json")

# Migrate from older nested sandbox path: reframework/data/sf6-toolbox/data/*
Ensure-FileIfMissing $legacyNestedAliasPath $newAliasPath
Ensure-FileIfMissing $legacyNestedConfigPath (Join-Path $structuredDir "sf6_structured_export.json")
Ensure-FileIfMissing $legacyNestedIndexPath (Join-Path $structuredDir "sf6_structured_index.json")
Ensure-DirCopiedIfMissing $legacyNestedCharsDir $structuredCharsDir

$shouldWriteBootstrap = $Force -or (-not (Test-Path -LiteralPath $bootstrapPath))
if (-not $shouldWriteBootstrap) {
    $current = Get-Content -LiteralPath $bootstrapPath -Raw
    if ($current -ne $bootstrapContent) {
        $shouldWriteBootstrap = $true
    }
}

if ($shouldWriteBootstrap) {
    Set-Content -LiteralPath $bootstrapPath -Value $bootstrapContent -NoNewline
    Write-Step "updated bootstrap: $bootstrapPath"
} else {
    Write-Step "bootstrap already up to date"
}

Write-Step "done"
Write-Host ""
Write-Host "Now reload scripts in REFramework and open:"
Write-Host "  SF6 Structured Export"
