# Runs the SilkRoad smoke test (tests/smoke_test.py) with API validation.
# First run sets up tests/.venv (with lupa) and downloads the Forever API
# lists into tests/.api; later runs reuse both.
#
#   powershell -ExecutionPolicy Bypass -File scripts/test.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$venv = Join-Path $root "tests/.venv"
$api = Join-Path $root "tests/.api"
$python = Join-Path $venv "Scripts/python.exe"

if (-not (Test-Path $python)) {
    Write-Host "Creating tests/.venv ..."
    python -m venv $venv
    & $python -m pip install --quiet lupa
}

if (-not (Test-Path (Join-Path $api "Resources"))) {
    Write-Host "Downloading the Forever API lists into tests/.api ..."
    git clone --quiet --depth 1 --branch forever --single-branch `
        https://github.com/Ketho/BlizzardInterfaceResources.git $api
}

& $python -I (Join-Path $root "tests/smoke_test.py") --api (Join-Path $api "Resources")
exit $LASTEXITCODE
