param(
    [string]$EnvironmentName = 'Development',
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$project = Join-Path $root 'backend/LastMile/LastMile.Api'
$connectionText = $null
$configSource = $null

function Read-ConnectionSetting([string]$path) {
    if (Test-Path -LiteralPath $path) {
        $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.'ConnectionStrings:DefaultConnection') { return $config.'ConnectionStrings:DefaultConnection' }
        if ($config.ConnectionStrings.DefaultConnection) { return $config.ConnectionStrings.DefaultConnection }
    }
}

$settingsPaths = @(
    (Join-Path $project 'appsettings.json'),
    (Join-Path $project "appsettings.$EnvironmentName.json")
)
if ($EnvironmentName -eq 'Development') {
    [xml]$projectXml = Get-Content -LiteralPath (Join-Path $project 'LastMile.Api.csproj') -Raw
    $secretsId = [string]($projectXml.Project.PropertyGroup.UserSecretsId | Select-Object -First 1)
    if ($secretsId -and $env:APPDATA) {
        $settingsPaths += Join-Path $env:APPDATA "Microsoft/UserSecrets/$secretsId/secrets.json"
    }
}
foreach ($path in $settingsPaths) {
    $setting = Read-ConnectionSetting $path
    if ($setting) { $connectionText = $setting; $configSource = $path }
}
$environmentConnection = [Environment]::GetEnvironmentVariable('ConnectionStrings__DefaultConnection')
if ($environmentConnection) {
    $connectionText = $environmentConnection
    $configSource = 'ConnectionStrings__DefaultConnection'
}
if (!$connectionText) { throw 'DefaultConnection is not configured.' }
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionText
if (!$builder.InitialCatalog -or $builder.InitialCatalog -in @('master', 'model', 'msdb', 'tempdb')) {
    throw 'Select the application database before applying this migration.'
}
# Windows PowerShell's legacy SQL client cannot negotiate TLS with LocalDB.
# This local Windows-authenticated connection does not change API configuration.
if ($builder.DataSource.StartsWith('(localdb)\', [StringComparison]::OrdinalIgnoreCase) -and $builder.IntegratedSecurity) {
    $builder.Encrypt = $false
}

$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
function Read-Scalar([string]$sql) {
    $command = $connection.CreateCommand()
    try { $command.CommandText = $sql; $command.CommandTimeout = 60; return $command.ExecuteScalar() }
    finally { $command.Dispose() }
}
function Read-BusinessCounts {
    $counts = [ordered]@{}
    foreach ($table in @('TaiKhoan', 'Kho', 'DonHang', 'ChuyenGiaoHang')) {
        $counts[$table] = [long](Read-Scalar "SELECT COUNT_BIG(*) FROM dbo.[$table];")
    }
    return $counts
}

try {
    $connection.Open()
    $before = Read-BusinessCounts
    $migration = Get-Content -LiteralPath (Join-Path $root 'database/migrations/20261017_dispatch_planning.sql') -Raw -Encoding UTF8
    $batches = [regex]::Split($migration, '(?im)^\s*GO\s*(?:--[^\r\n]*)?\r?$')
    # The second pass verifies that the migration can safely be run again.
    foreach ($pass in 1..2) {
        foreach ($batch in $batches) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }
            $command = $connection.CreateCommand()
            try {
                $command.CommandText = $batch
                $command.CommandTimeout = 120
                [void]$command.ExecuteNonQuery()
            } finally { $command.Dispose() }
        }
    }
    $schemaReady = [int](Read-Scalar @"
SELECT CASE WHEN OBJECT_ID('dbo.DispatchRoutePlan','U') IS NOT NULL
 AND OBJECT_ID('dbo.TripRouteGeometry','U') IS NOT NULL
 AND COL_LENGTH('dbo.Kho','ViDo') IS NOT NULL
 AND COL_LENGTH('dbo.Kho','KinhDo') IS NOT NULL
 AND COL_LENGTH('dbo.Kho','NguonToaDo') IS NOT NULL
 AND EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_Kho_DepotCoordinates' AND is_disabled=0)
 AND EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.DispatchRoutePlan') AND name='IX_DispatchRoutePlan_Expiry')
 THEN 1 ELSE 0 END;
"@)
    if ($schemaReady -ne 1) { throw 'Dispatch schema verification failed.' }
    $after = Read-BusinessCounts
    $countsUnchanged = ($before | ConvertTo-Json -Compress) -eq ($after | ConvertTo-Json -Compress)
    if (!$countsUnchanged) { throw 'Business row counts changed during migration; inspect concurrent activity.' }
    $report = [ordered]@{
        checkedAt = (Get-Date).ToString('o')
        environment = $EnvironmentName
        server = $builder.DataSource
        database = $builder.InitialCatalog
        configurationSource = $configSource
        migration = '20261017_dispatch_planning.sql'
        schemaReady = $true
        idempotentSecondPass = $true
        businessCountsBefore = $before
        businessCountsAfter = $after
        businessCountsUnchanged = $countsUnchanged
        warehousesWithCoordinates = [int](Read-Scalar 'SELECT COUNT(*) FROM dbo.Kho WHERE ViDo IS NOT NULL AND KinhDo IS NOT NULL;')
        warehouseCoordinatesWritten = $false
    }
    $json = $report | ConvertTo-Json -Depth 5
    if ($ReportPath) { [IO.File]::WriteAllText($ReportPath, $json, (New-Object Text.UTF8Encoding $false)) }
    $json
} finally { $connection.Dispose() }
