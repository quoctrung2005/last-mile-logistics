param([switch]$Apply, [string]$ExpectedDatabase)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot -Parent
$project = Join-Path $root 'backend/LastMile/LastMile.Api'
$connectionText = $null
$source = $null
function Read-Connection([string]$path) {
    if (Test-Path -LiteralPath $path) {
        $config = Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
        if ($config.'ConnectionStrings:DefaultConnection') { return $config.'ConnectionStrings:DefaultConnection' }
        if ($config.ConnectionStrings.DefaultConnection) { return $config.ConnectionStrings.DefaultConnection }
    }
}
$paths = @((Join-Path $project 'appsettings.json'), (Join-Path $project 'appsettings.Development.json'))
[xml]$projectXml = Get-Content -Raw (Join-Path $project 'LastMile.Api.csproj')
$secretsId = [string]($projectXml.Project.PropertyGroup.UserSecretsId | Select-Object -First 1)
if ($secretsId -and $env:APPDATA) { $paths += Join-Path $env:APPDATA "Microsoft/UserSecrets/$secretsId/secrets.json" }
foreach ($path in $paths) { $value = Read-Connection $path; if ($value) { $connectionText = $value; $source = $path } }
$value = [Environment]::GetEnvironmentVariable('ConnectionStrings__DefaultConnection')
if ($value) { $connectionText = $value; $source = 'ConnectionStrings__DefaultConnection' }
if (!$connectionText) { throw 'DefaultConnection is not configured' }
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionText
$database = [string]$builder['Initial Catalog']
if (!$database -or $database -in @('master','model','msdb','tempdb')) { throw 'Application database required' }
if (!$builder.DataSource.StartsWith('(localdb)\',[StringComparison]::OrdinalIgnoreCase) -or !$builder.IntegratedSecurity) {
    throw 'This Development helper requires Windows-authenticated LocalDB; use the SQL migration through your deployment process for other environments.'
}
if ($Apply -and (!$ExpectedDatabase -or $ExpectedDatabase -cne $database)) { throw 'ExpectedDatabase must exactly match the inspected database' }
$builder.Encrypt = $false
$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
function Scalar([string]$sql) {
    $command = $connection.CreateCommand()
    try { $command.CommandText = $sql; $command.CommandTimeout = 120; return $command.ExecuteScalar() }
    finally { $command.Dispose() }
}
function BusinessSnapshot {
    return [string](Scalar @'
SELECT (SELECT MaKhachHang,KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong,ThoiGianTao
        FROM dbo.KhachHang ORDER BY MaKhachHang FOR JSON PATH,INCLUDE_NULL_VALUES)
    + (SELECT MaDiaChiKhachHang,MaKhachHang,NhanDiaChi,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc,
        ViDo,KinhDo,ToaDoDiaLy.STAsText() AS ToaDoDiaLy,LaMacDinh,DangHoatDong
        FROM dbo.DiaChiKhachHang ORDER BY MaDiaChiKhachHang FOR JSON PATH,INCLUDE_NULL_VALUES);
'@)
}
function VersionSnapshot {
    return [string](Scalar @'
SELECT (SELECT MaKhachHang id,CONVERT(VARBINARY(8),PhienBan) version FROM dbo.KhachHang ORDER BY MaKhachHang FOR JSON PATH)
    + (SELECT MaDiaChiKhachHang id,CONVERT(VARBINARY(8),PhienBan) version FROM dbo.DiaChiKhachHang ORDER BY MaDiaChiKhachHang FOR JSON PATH);
'@)
}
try {
    $connection.Open()
    $actualDatabase = [string](Scalar 'SELECT DB_NAME();')
    if ($actualDatabase -cne $database) { throw 'Connected database does not match configuration' }
    $columnsBefore = [int](Scalar "SELECT COUNT(*) FROM sys.columns WHERE object_id IN (OBJECT_ID('dbo.KhachHang'),OBJECT_ID('dbo.DiaChiKhachHang')) AND name='PhienBan' AND system_type_id=189 AND max_length=8;")
    $report = [ordered]@{environment='Development';server=$builder.DataSource;database=$actualDatabase;configurationSource=$source;rowversionColumnsBefore=$columnsBefore;migration='20261019_customer_versions.sql';applied=$false}
    if ($Apply) {
        $before = BusinessSnapshot
        $sql = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'database/migrations/20261019_customer_versions.sql')
        [void](Scalar $sql)
        $versions = VersionSnapshot
        [void](Scalar $sql)
        if ($before -cne (BusinessSnapshot)) { throw 'Business data changed; inspect concurrent activity' }
        if ($versions -cne (VersionSnapshot)) { throw 'Repeated migration changed existing rowversions' }
        $report.applied = $true
        $report.businessDataPreserved = $true
        $report.versionsStableOnRerun = $true
    }
    $report.rowversionColumnsAfter = [int](Scalar "SELECT COUNT(*) FROM sys.columns WHERE object_id IN (OBJECT_ID('dbo.KhachHang'),OBJECT_ID('dbo.DiaChiKhachHang')) AND name='PhienBan' AND system_type_id=189 AND max_length=8;")
    if ($Apply -and $report.rowversionColumnsAfter -ne 2) { throw 'Customer/address rowversion schema is not ready' }
    $report.customers = [long](Scalar 'SELECT COUNT_BIG(*) FROM dbo.KhachHang;')
    $report.addresses = [long](Scalar 'SELECT COUNT_BIG(*) FROM dbo.DiaChiKhachHang;')
    $report | ConvertTo-Json -Depth 4
} finally { $connection.Dispose() }
