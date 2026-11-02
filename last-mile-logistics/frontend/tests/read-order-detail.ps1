param(
    [long[]]$OrderIds = @(1,2),
    [string]$OrderCode
)
$ErrorActionPreference = 'Stop'
$project = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config = Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.json" | ConvertFrom-Json
$dev = Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.Development.json" | ConvertFrom-Json
$connectionText = if ($dev.ConnectionStrings.DefaultConnection) { $dev.ConnectionStrings.DefaultConnection } else { $config.ConnectionStrings.DefaultConnection }
$source = Get-Content -Raw "$project/backend/LastMile/LastMile.Api/Controllers/OrdersController.cs"
$start = $source.IndexOf('GetOrder(')
$sql = [regex]::Match($source.Substring($start), 'const string sql = """([\s\S]*?)""";').Groups[1].Value
if (!$sql) { throw 'Detail query not found' }
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionText
if (!$builder.DataSource.StartsWith('(localdb)', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'QA is restricted to local SQL Server LocalDB' }
# Legacy Windows PowerShell SQL client uses the local LocalDB connection only.
# This does not edit appsettings, API/TLS settings, or authentication configuration.
$builder.Encrypt = $false
$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
$orders = @()
try {
  $connection.Open()
    if ($OrderCode) {
        $lookup = $connection.CreateCommand()
        $lookup.CommandText = 'SELECT MaDonHang FROM dbo.DonHang WHERE KyHieuDonHang=@Code'
        [void]$lookup.Parameters.AddWithValue('@Code', $OrderCode)
        try { $found = $lookup.ExecuteScalar(); if (!$found) { throw 'Order code not found' }; $OrderIds = @([long]$found) } finally { $lookup.Dispose() }
    }
    foreach ($id in $OrderIds) {
    $command = $connection.CreateCommand(); $command.CommandText = $sql
    [void]$command.Parameters.AddWithValue('@Id', [long]$id)
    [void]$command.Parameters.AddWithValue('@IsAdmin', $true)
    [void]$command.Parameters.AddWithValue('@BranchId', [DBNull]::Value)
    try { $json = $command.ExecuteScalar(); if ($json -is [string] -and $json) { $orders += ($json | ConvertFrom-Json) } } finally { $command.Dispose() }
  }
  # This output is consumed only through the child-process pipe, never written to file/log.
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  [Console]::Write(($orders | ConvertTo-Json -Depth 25 -Compress))
} finally { $connection.Dispose() }
