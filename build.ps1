# Build UF2 firmware inside Docker (outputs in dist/, gitignored).
#
#   .\build.ps1              # fast: incremental, parallel halves + dongle (~3–6 min)
#   .\build.ps1 right        # one half after keymap tweak (~1–2 min)
#   .\build.ps1 firmware     # full clean bundle + reset (~15 min first time)
#   .\build.ps1 verify       # compile dongle only, no dist/
#   .\build.ps1 firmware -Pristine   # force pristine rebuild all targets

param(
    [Parameter(Position = 0)]
    [ValidateSet("fast", "halves", "left", "right", "dongle", "firmware", "verify")]
    [string]$Target = "fast",

    [switch]$Pristine,
    [switch]$WestUpdate
)

Set-Location $PSScriptRoot

if ($Pristine) {
    $env:PRISTINE = "1"
    $env:SKIP_PRISTINE = "0"
    $env:INCREMENTAL = "0"
} elseif ($Target -eq "firmware") {
    Remove-Item Env:SKIP_PRISTINE -ErrorAction SilentlyContinue
    Remove-Item Env:INCREMENTAL -ErrorAction SilentlyContinue
} else {
    $env:INCREMENTAL = "1"
    $env:SKIP_PRISTINE = "1"
}

if ($WestUpdate) {
    $env:SKIP_WEST_UPDATE = "0"
} elseif (-not $env:SKIP_WEST_UPDATE) {
    $env:SKIP_WEST_UPDATE = "1"
}

if ($Target -eq "firmware" -and -not $Pristine) {
    $env:PARALLEL_HALVES = "1"
}

docker compose run --rm zmk-build $Target
exit $LASTEXITCODE
