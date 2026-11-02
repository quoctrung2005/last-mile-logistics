param(
    [ValidateSet('Prepare','Migrate','Recovery','Legacy','BreakLookup')][string]$Mode = 'Prepare',
    [Parameter(Mandatory=$true)][string]$Database,
    [long]$TargetId = 0
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if ($Database -notmatch '^CodexAccounts_[a-f0-9]{32}$') { throw 'Isolated GUID account test database required' }
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$settings = Get-Content -Raw "$root/backend/LastMile/LastMile.Api/appsettings.json" | ConvertFrom-Json
$development = Get-Content -Raw "$root/backend/LastMile/LastMile.Api/appsettings.Development.json" | ConvertFrom-Json
$connectionText = if ($development.ConnectionStrings.DefaultConnection) { $development.ConnectionStrings.DefaultConnection } else { $settings.ConnectionStrings.DefaultConnection }
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionText
if (!$builder.DataSource.StartsWith('(localdb)', [StringComparison]::OrdinalIgnoreCase)) { throw 'LocalDB only' }
$builder['Initial Catalog'] = $Database
$builder.Encrypt = $false
$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
function Run([string]$sql) {
    $command = $connection.CreateCommand()
    try { $command.CommandText = $sql; $command.CommandTimeout = 120; [void]$command.ExecuteNonQuery() }
    finally { $command.Dispose() }
}
try {
    $connection.Open()
    if ($Mode -in @('Prepare','Migrate')) {
        $sql = Get-Content -Raw -Encoding utf8 "$root/database/migrations/20261019_auth_sessions.sql"
        Run $sql
        Run $sql
    }
    if ($Mode -eq 'BreakLookup') {
        # Reproduce missing migration only in a GUID fixture, never the app DB.
        Run @'
ALTER TABLE dbo.TokenLamMoi DROP CONSTRAINT FK_TokenLamMoi_PhienDangNhap;
DROP INDEX IX_TokenLamMoi_Phien ON dbo.TokenLamMoi;
ALTER TABLE dbo.TokenLamMoi DROP COLUMN MaPhien;
'@
        [Console]::Write('{"lookupSchemaRemoved":true}')
    } elseif ($Mode -eq 'Prepare') {
        # This table is an existing recovery prerequisite, absent from the V5
        # bootstrap file. Only the isolated fixture supplies it here.
        Run @'
CREATE TABLE dbo.TokenKhoiPhucMatKhau (
    MaTokenKhoiPhucMatKhau BIGINT IDENTITY PRIMARY KEY,
    MaTaiKhoan BIGINT NOT NULL REFERENCES dbo.TaiKhoan(MaTaiKhoan),
    GiaTriBamToken VARCHAR(64) NOT NULL UNIQUE,
    ThoiGianTao DATETIME2(0) NOT NULL,
    HetHanLuc DATETIME2(0) NOT NULL,
    DaDungLuc DATETIME2(0) NULL
);
'@
        $command = $connection.CreateCommand()
        $command.CommandText = @'
DECLARE @AccountId BIGINT = (SELECT TOP(1) tk.MaTaiKhoan FROM dbo.TaiKhoan tk
    JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE vt.KyHieuVaiTro='ADMIN' ORDER BY tk.MaTaiKhoan);
DECLARE @Sid UNIQUEIDENTIFIER=NEWID(), @Now DATETIME2(0)=SYSUTCDATETIME();
INSERT dbo.PhienDangNhap(MaPhien,MaTaiKhoan,ThoiGianTao,HetHanLuc) VALUES(@Sid,@AccountId,@Now,DATEADD(HOUR,1,@Now));
SELECT REPLACE(CONVERT(VARCHAR(36),@Sid),'-','');
'@
        try { $sid = [string]$command.ExecuteScalar() } finally { $command.Dispose() }
        [Console]::Write((@{ sessionId=$sid } | ConvertTo-Json -Compress))
    } elseif ($Mode -in @('Recovery','Legacy')) {
        if ($TargetId -le 0) { throw 'TargetId required' }
        $raw = $env:AUTH_SESSION_TEST_TOKEN
        if ($raw -notmatch '^[A-Za-z0-9_-]{43}$') { throw 'Ephemeral fixture token required' }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))).Replace('-','') }
        finally { $sha.Dispose() }
        $command = $connection.CreateCommand()
        try {
            $command.CommandText = if ($Mode -eq 'Recovery') {
                'INSERT dbo.TokenKhoiPhucMatKhau(MaTaiKhoan,GiaTriBamToken,ThoiGianTao,HetHanLuc) VALUES(@Id,@Hash,SYSUTCDATETIME(),DATEADD(MINUTE,15,SYSUTCDATETIME()));'
            } else {
                'INSERT dbo.TokenLamMoi(MaTaiKhoan,GiaTriBamToken,ThoiGianTao,HetHanLuc) VALUES(@Id,@Hash,SYSUTCDATETIME(),DATEADD(DAY,1,SYSUTCDATETIME()));'
            }
            [void]$command.Parameters.AddWithValue('@Id',$TargetId)
            [void]$command.Parameters.AddWithValue('@Hash',$hash)
            [void]$command.ExecuteNonQuery()
        } finally { $command.Dispose() }
        [Console]::Write('{"prepared":true}')
    } else { [Console]::Write('{"idempotent":true}') }
} finally { $connection.Dispose() }
