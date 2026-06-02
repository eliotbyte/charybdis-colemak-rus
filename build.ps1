# Build UF2 firmware inside Docker (nothing written to git — see dist/).
#   .\build.ps1           # left + right + dongle + reset + dist/charybdis-firmware.zip
#   .\build.ps1 verify    # compile dongle only (quick check)

param(
    [Parameter(Position = 0)]
    [ValidateSet("firmware", "verify")]
    [string]$Target = "firmware"
)

Set-Location $PSScriptRoot
docker compose run --rm zmk-build $Target
exit $LASTEXITCODE
