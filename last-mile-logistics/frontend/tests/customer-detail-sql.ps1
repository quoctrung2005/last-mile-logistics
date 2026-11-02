param([switch]$ReproduceOldSyntax)
$ErrorActionPreference = 'Stop'
$project = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config = Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.json" | ConvertFrom-Json
$dev = Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.Development.json" | ConvertFrom-Json
$connectionText = if ($dev.ConnectionStrings.DefaultConnection) { $dev.ConnectionStrings.DefaultConnection } else { $config.ConnectionStrings.DefaultConnection }
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionText
if (!$builder.DataSource.StartsWith('(localdb)', [StringComparison]::OrdinalIgnoreCase)) { throw 'Test restricted to local SQL Server LocalDB' }
$builder.Encrypt = $false
$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
$source = Get-Content -Raw -Encoding UTF8 "$project/backend/LastMile/LastMile.Api/Controllers/CustomerDetailController.cs"
$sql = [regex]::Match($source, 'const string sql = """([\s\S]*?)""";').Groups[1].Value
if (!$sql) { throw 'Customer detail SQL not found' }
if ($ReproduceOldSyntax) { $sql = $sql.Replace('AS [statistics]', 'AS statistics') }
function Scalar($query, $parameters) {
    $command = $connection.CreateCommand(); $command.CommandText = $query
    foreach ($key in $parameters.Keys) { [void]$command.Parameters.AddWithValue($key, $parameters[$key]) }
    try { return $command.ExecuteScalar() } finally { $command.Dispose() }
}
$checks = @()
try {
    $connection.Open()
    $accounts = Scalar @'
SELECT tk.MaTaiKhoan AS id, tk.MaBuuCuc AS branchId, vt.KyHieuVaiTro AS role
FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro
WHERE tk.TrangThaiTaiKhoan='ACTIVE' AND vt.DangHoatDong=1
  AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc<=SYSUTCDATETIME())
  AND (vt.KyHieuVaiTro='ADMIN' OR tk.MaBuuCuc IS NOT NULL)
  AND EXISTS (SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen
              WHERE vq.MaVaiTro=tk.MaVaiTro AND q.KyHieuQuyen='DONHANG_XEM')
ORDER BY tk.MaTaiKhoan FOR JSON PATH
'@ @{} | ConvertFrom-Json
    $admin = @($accounts | Where-Object role -eq 'ADMIN' | Select-Object -First 1)
    if (!$admin.Count) { throw 'No active admin with read permission available' }
    $branchReader = @($accounts | Where-Object role -ne 'ADMIN' | Select-Object -First 1)
    $readers = $admin + $branchReader
    $customerIds = @(1,10)
    if ($ReproduceOldSyntax) {
        try {
            [void](Scalar $sql @{ '@AccountId'=[long]$admin[0].id; '@CustomerId'=[long]$customerIds[0]; '@IncludeInactive'=$false })
            throw 'Old syntax unexpectedly succeeded'
        } catch [System.Management.Automation.MethodInvocationException] {
            $sqlError = $_.Exception.InnerException
            if ($sqlError -isnot [System.Data.SqlClient.SqlException] -or $sqlError.Number -ne 156) { throw }
            $messages = @($sqlError.Errors | ForEach-Object Message)
            if (!($messages -match 'statistics')) { throw 'Expected statistics syntax failure' }
            [Console]::Write((@{ reproduced=$true; sqlNumber=$sqlError.Number; errors=$messages } | ConvertTo-Json -Compress))
            exit 0
        }
    }
    foreach ($reader in $readers) {
        foreach ($customerId in $customerIds) {
            foreach ($includeInactive in @($false,$true)) {
                $response = Scalar $sql @{ '@AccountId'=[long]$reader.id; '@CustomerId'=[long]$customerId; '@IncludeInactive'=$includeInactive } | ConvertFrom-Json
                if ($response.id -ne $customerId -or $null -eq $response.statistics -or $null -eq $response.addresses -or $null -eq $response.recentOrders) { throw 'Customer detail response contract invalid' }
                $expectedScope = if ($reader.role -eq 'ADMIN') { 'ALL_BRANCHES' } else { 'CURRENT_BRANCH' }
                if ($response.statistics.scope -ne $expectedScope) { throw 'Scope mismatch' }
                if ($reader.role -ne 'ADMIN' -and @($response.recentOrders | Where-Object branchId -ne $reader.branchId).Count) { throw 'Orders outside reader branch' }
                if (!$includeInactive -and @($response.addresses | Where-Object isActive -ne $true).Count) { throw 'Inactive address returned by default' }
                $expectedCount = Scalar 'SELECT COUNT(*) FROM dbo.DonHang WHERE (MaNguoiGui=@CustomerId OR MaNguoiNhan=@CustomerId) AND (@IsAdmin=1 OR MaBuuCuc=@BranchId)' @{ '@CustomerId'=[long]$customerId; '@IsAdmin'=($reader.role -eq 'ADMIN'); '@BranchId'=$(if ($null -eq $reader.branchId) { [DBNull]::Value } else { [int]$reader.branchId }) }
                if ($response.statistics.totalOrders -ne $expectedCount -or @($response.recentOrders).Count -gt 10) { throw 'Statistics/recent order limit mismatch' }
                $expectedAddressCount = Scalar 'SELECT COUNT(*) FROM dbo.DiaChiKhachHang WHERE MaKhachHang=@CustomerId AND (@IncludeInactive=1 OR DangHoatDong=1)' @{ '@CustomerId'=[long]$customerId; '@IncludeInactive'=$includeInactive }
                if (@($response.addresses).Count -ne $expectedAddressCount) { throw 'Address count mismatch' }
                $checks += @{ role=$reader.role; customerId=$customerId; includeInactive=$includeInactive; totalOrders=$response.statistics.totalOrders; addressCount=@($response.addresses).Count; recentOrderCount=@($response.recentOrders).Count }
            }
        }
    }
    foreach ($case in @(@{ accountId=-1; customerId=1; expected=54601 }, @{ accountId=[long]$admin[0].id; customerId=-1; expected=54603 })) {
        try { [void](Scalar $sql @{ '@AccountId'=[long]$case.accountId; '@CustomerId'=[long]$case.customerId; '@IncludeInactive'=$false }); throw 'Expected scope/data rejection' }
        catch [System.Management.Automation.MethodInvocationException] { if ($_.Exception.InnerException.Number -ne $case.expected) { throw }; $checks += @{ expectedSqlError=$case.expected; passed=$true } }
    }
    [Console]::Write((@{ mode='Existing LocalDB, controller SQL only, no persistent writes'; checks=$checks; count=$checks.Count } | ConvertTo-Json -Depth 8 -Compress))
} finally { $connection.Dispose() }
