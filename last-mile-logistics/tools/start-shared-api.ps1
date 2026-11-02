param(
    [ValidateSet('localhost', '0.0.0.0')][string]$BindAddress = 'localhost',
    [ValidateRange(1024, 65535)][int]$Port = 5038
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$apiProject = Join-Path $projectRoot 'backend/LastMile/LastMile.Api/LastMile.Api.csproj'
Write-Host "Starting the shared web + shipper API at http://${BindAddress}:$Port"
Push-Location $projectRoot
try {
    & dotnet run --no-restore --project $apiProject --launch-profile http --urls "http://${BindAddress}:$Port"
    if ($LASTEXITCODE -ne 0) { throw 'Shared API did not start successfully.' }
} finally {
    Pop-Location
}
