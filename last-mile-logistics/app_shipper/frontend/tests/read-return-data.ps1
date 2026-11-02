$ErrorActionPreference = 'Stop'
$project = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config = Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.json" | ConvertFrom-Json
$dev = Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.Development.json" | ConvertFrom-Json
$connectionText = if ($dev.ConnectionStrings.DefaultConnection) { $dev.ConnectionStrings.DefaultConnection } else { $config.ConnectionStrings.DefaultConnection }
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionText
if (!$builder.DataSource.StartsWith('(localdb)', [StringComparison]::OrdinalIgnoreCase)) { throw 'QA is restricted to existing LocalDB' }
$builder.Encrypt = $false
$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
function Query($sql, $parameters) {
    $command = $connection.CreateCommand(); $command.CommandText = $sql
    foreach ($key in $parameters.Keys) { [void]$command.Parameters.AddWithValue($key, $parameters[$key]) }
    try { return $command.ExecuteScalar() } finally { $command.Dispose() }
}
function ControllerSql($name, $method) {
    $source = Get-Content -Raw -Encoding UTF8 "$project/backend/LastMile/LastMile.Api/Controllers/$name.cs"
    $sql = [regex]::Match($source.Substring($source.IndexOf($method + '(')), 'const string sql = """([\s\S]*?)""";').Groups[1].Value
    if (!$sql) { throw 'Controller SQL not found' }; return $sql
}
try {
    $connection.Open()
    $accountId = Query "SELECT TOP (1) tk.MaTaiKhoan FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE vt.KyHieuVaiTro='ADMIN' AND tk.TrangThaiTaiKhoan='ACTIVE' AND vt.DangHoatDong=1 AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc<=SYSUTCDATETIME()) ORDER BY tk.MaTaiKhoan" @{}
    if (!$accountId) { throw 'No active admin available for read-only SQL check' }
    $warehouses = Query (ControllerSql 'WarehousesController' 'GetWarehouses') @{ '@IsAdmin'=$true; '@BranchId'=[DBNull]::Value } | ConvertFrom-Json
    $locations=@{}; $requests=@{}; $checks=@()
    $returnSql=ControllerSql 'WarehouseReturnRequestsController' 'GetReturnRequests'
    foreach ($warehouse in @($warehouses)) {
        $warehouseLocations=Query (ControllerSql 'WarehousesController' 'GetLocations') @{ '@Id'=[int]$warehouse.id; '@Status'='ACTIVE'; '@Keyword'=[DBNull]::Value } | ConvertFrom-Json
        $locations[$warehouse.id.ToString()]=@($warehouseLocations)
        $parameters=@{ '@AccountId'=[long]$accountId; '@WarehouseId'=[int]$warehouse.id; '@Keyword'=[DBNull]::Value; '@OrderId'=[DBNull]::Value; '@ReturnRequestId'=[DBNull]::Value; '@Page'=1; '@PageSize'=100; '@Offset'=0 }
        $first=Query $returnSql $parameters | ConvertFrom-Json
        if ($first.warehouseId -ne $warehouse.id -or $first.canReturnIn -ne $true -or $null -eq $first.items) { throw 'Return request response invalid' }
        $rows=@($first.items)
        for ($page=2;($page-1)*100 -lt $first.totalItems;$page++) { $parameters['@Page']=$page; $parameters['@Offset']=($page-1)*100; $rows+=@((Query $returnSql $parameters | ConvertFrom-Json).items) }
        if ($rows.Count -ne $first.totalItems) { throw 'Pagination count mismatch' }
        foreach ($row in $rows) {
            if ($row.orderStatus -ne 'RETURNING' -or $row.requestStatus -ne 'IN_PROGRESS' -or $row.stockStatus -ne 'HANDED_OVER' -or $row.branchId -ne $warehouse.branchId -or $row.returnBranchId -ne $row.branchId) { throw 'Ineligible request returned' }
            $parameters['@OrderId']=[long]$row.orderId; $parameters['@ReturnRequestId']=[long]$row.returnRequestId; $parameters['@Page']=1; $parameters['@Offset']=0
            $exact=Query $returnSql $parameters | ConvertFrom-Json
            if ($exact.totalItems -ne 1 -or $exact.items[0].returnRequestId -ne $row.returnRequestId) { throw 'Compound order/request filter mismatch' }
        }
        $requests[$warehouse.id.ToString()]=$rows
        $parameters['@OrderId']=[DBNull]::Value; $parameters['@ReturnRequestId']=[DBNull]::Value; $parameters['@Keyword']='__RETURN_QA_NO_MATCH_20261009__'; $parameters['@Page']=1; $parameters['@Offset']=0
        $empty=Query $returnSql $parameters | ConvertFrom-Json
        if ($empty.totalItems -ne 0 -or @($empty.items).Count -ne 0) { throw 'No-match keyword must return empty page' }
        $checks+=@{ warehouseId=$warehouse.id; totalItems=$first.totalItems; pageSize=100; emptySearchPassed=$true }
    }
    # Full records travel only through the QA child-process pipe, never into logs/artifacts.
    [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
    [Console]::Write((@{ warehouses=@($warehouses); locations=$locations; requests=$requests; sqlChecks=$checks } | ConvertTo-Json -Depth 25 -Compress))
} finally { $connection.Dispose() }
