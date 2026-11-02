param(
    [ValidateSet('State','Expire','RaceLock','RaceHash')][string]$Mode = 'State',
    [Parameter(Mandatory=$true)][string]$Database,
    [Parameter(Mandatory=$true)][long]$TargetId,
    [long]$SourceId = 0
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if ($Database -notmatch '^CodexAccounts_[a-f0-9]{32}$') { throw 'Isolated GUID database required' }
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$settings = Get-Content -Raw "$root/backend/LastMile/LastMile.Api/appsettings.json" | ConvertFrom-Json
$development = Get-Content -Raw "$root/backend/LastMile/LastMile.Api/appsettings.Development.json" | ConvertFrom-Json
$text = if ($development.ConnectionStrings.DefaultConnection) { $development.ConnectionStrings.DefaultConnection } else { $settings.ConnectionStrings.DefaultConnection }
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $text
if (!$builder.DataSource.StartsWith('(localdb)', [StringComparison]::OrdinalIgnoreCase)) { throw 'LocalDB only' }
$builder['Initial Catalog'] = $Database
$builder.Encrypt = $false
$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
$transaction = $null
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    try {
        $command.CommandText = "SELECT COUNT(*) FROM dbo.TaiKhoan WHERE MaTaiKhoan=@Id AND TenDangNhap LIKE 'qa.login.%';"
        [void]$command.Parameters.AddWithValue('@Id',$TargetId)
        if ([int]$command.ExecuteScalar() -ne 1) { throw 'Only dedicated QA login accounts may be modified' }
        if ($Mode -eq 'State') {
            $command.CommandText = @'
SELECT SoLanDangNhapSai AS failedCount, TrangThaiTaiKhoan AS status, KhoaDenLuc AS lockedUntil,
    DATEDIFF(SECOND,SYSUTCDATETIME(),KhoaDenLuc) AS secondsUntilUnlock, DangNhapCuoiLuc AS lastLoginAt,
    (SELECT COUNT(*) FROM dbo.PhienDangNhap p WHERE p.MaTaiKhoan=tk.MaTaiKhoan) AS sessionCount
FROM dbo.TaiKhoan tk WHERE MaTaiKhoan=@Id FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER;
'@
            [Console]::Write([string]$command.ExecuteScalar())
        } elseif ($Mode -eq 'Expire') {
            $command.CommandText = 'UPDATE dbo.TaiKhoan SET KhoaDenLuc=DATEADD(SECOND,-2,SYSUTCDATETIME()) WHERE MaTaiKhoan=@Id;'
            [void]$command.ExecuteNonQuery()
            [Console]::Write('{"expired":true}')
        } else {
            if ($Mode -eq 'RaceHash') {
                $command.Parameters['@Id'].Value = $SourceId
                if ([int]$command.ExecuteScalar() -ne 1) { throw 'QA source account required' }
                $command.Parameters['@Id'].Value = $TargetId
                [void]$command.Parameters.AddWithValue('@SourceId',$SourceId)
            }
            $transaction = $connection.BeginTransaction()
            $command.Transaction = $transaction
            $command.CommandText = 'SELECT COUNT(*) FROM dbo.TaiKhoan WITH (UPDLOCK,HOLDLOCK) WHERE MaTaiKhoan=@Id;'
            [void]$command.ExecuteScalar()
            [Console]::WriteLine('READY')
            $command.CommandText = if ($Mode -eq 'RaceLock') {
                "WAITFOR DELAY '00:00:03'; UPDATE dbo.TaiKhoan SET KhoaDenLuc=DATEADD(MINUTE,15,SYSUTCDATETIME()),SoLanDangNhapSai=5 WHERE MaTaiKhoan=@Id;"
            } else {
                "WAITFOR DELAY '00:00:03'; UPDATE dbo.TaiKhoan SET MatKhauBam=(SELECT MatKhauBam FROM dbo.TaiKhoan WHERE MaTaiKhoan=@SourceId) WHERE MaTaiKhoan=@Id;"
            }
            [void]$command.ExecuteNonQuery()
            $transaction.Commit()
            [Console]::Write('{"committed":true}')
        }
    } finally { $command.Dispose() }
} finally { if ($transaction) { $transaction.Dispose() }; $connection.Dispose() }
