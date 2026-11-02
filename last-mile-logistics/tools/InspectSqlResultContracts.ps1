$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot -Parent
$settings = Get-Content -Raw -Encoding UTF8 "$root/backend/LastMile/LastMile.Api/appsettings.json" | ConvertFrom-Json
$development = Get-Content -Raw -Encoding UTF8 "$root/backend/LastMile/LastMile.Api/appsettings.Development.json" | ConvertFrom-Json
$connectionText = if ($env:ConnectionStrings__DefaultConnection) { $env:ConnectionStrings__DefaultConnection } elseif ($development.ConnectionStrings.DefaultConnection) { $development.ConnectionStrings.DefaultConnection } else { $settings.ConnectionStrings.DefaultConnection }
$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionText)
if (!$builder.DataSource.StartsWith('(localdb)', [StringComparison]::OrdinalIgnoreCase)) { throw 'Read-only inspection is restricted to LocalDB' }
$builder.Encrypt = $false
$ddl = Get-Content -Raw -Encoding UTF8 "$root/database/QLGiaoHangChangCuoi_SQLServer_V5 .sql"
$definitions = @{}
foreach ($match in [regex]::Matches($ddl, '(?ims)^CREATE OR ALTER (?:PROCEDURE|TRIGGER) dbo\.(\w+)\b.*?(?=^GO\s*$)')) {
    $definitions[$match.Groups[1].Value] = $match.Value
}
function Normalize([string]$definition) {
    # SSMS/SQL Server may retain leading batch comments and replace OR ALTER
    # with spaces in sys.sql_modules; compare the actual module body.
    $start = [regex]::Match($definition, '(?im)^\s*(?:CREATE(?:\s+OR\s+ALTER)?|ALTER)\s+(?:PROCEDURE|TRIGGER)\b')
    if (!$start.Success) { throw 'Module declaration not found' }
    $definition = $definition.Substring($start.Index)
    $definition = [regex]::Replace($definition.Trim(), '^(?:CREATE(?:\s+OR\s+ALTER)?|ALTER)\s+(PROCEDURE|TRIGGER)', 'CREATE OR ALTER $1', 'IgnoreCase')
    return [regex]::Replace($definition, '\s+', ' ').Trim()
}
$connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
$rows = @()
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    # SELECT metadata only; no DDL, writes, or procedure execution on this database.
    $command.CommandText = @'
SELECT o.name, o.type_desc, m.definition
FROM sys.objects o JOIN sys.sql_modules m ON m.object_id=o.object_id
WHERE o.name IN ('sp_XacNhanDonHang','sp_ChuyenTrangThaiDonHang')
 OR (o.type='TR' AND o.parent_object_id IN (
   OBJECT_ID('dbo.DonHang'),OBJECT_ID('dbo.ChiTietDonHang'),OBJECT_ID('dbo.DiemGiaoNhan'),
   OBJECT_ID('dbo.KhoanPhiDonHang'),OBJECT_ID('dbo.TonKhoDonHang'),OBJECT_ID('dbo.GiaoDichKho'),
   OBJECT_ID('dbo.ChiTietGiaoDichKho'),OBJECT_ID('dbo.NhatKyHoatDong')))
ORDER BY o.name;
'@
    $reader = $command.ExecuteReader()
    try {
        while ($reader.Read()) {
            if ($reader.IsDBNull(0) -or $reader.IsDBNull(1) -or $reader.IsDBNull(2)) { throw 'Missing SQL module definition' }
            $name = $reader.GetString(0); $definition = $reader.GetString(2)
            $rows += [pscustomobject]@{name=$name;type=$reader.GetString(1);setNoCount=[bool]($definition -match '(?i)SET\s+NOCOUNT\s+ON');matchesRepository=($definitions.ContainsKey($name) -and (Normalize $definition) -ceq (Normalize $definitions[$name]))}
        }
    } finally { $reader.Dispose(); $command.Dispose() }
    if ($rows.Count -eq 0) { throw 'No SQL contract definitions found' }
    $report = [ordered]@{mode='Read-only SQL module inspection; JSON configuration with environment override; no application writes';server=$builder.DataSource;database=$builder.InitialCatalog;modules=$rows}
    $json = $report | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText("$root/docs/sql-results-database-inspection.json", $json + "`n", [Text.UTF8Encoding]::new($false))
    [Console]::Write($json)
} finally { $connection.Dispose() }
