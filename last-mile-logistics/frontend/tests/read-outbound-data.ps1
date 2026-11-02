$ErrorActionPreference = 'Stop'
$project = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config = Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.json" | ConvertFrom-Json
$dev = Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.Development.json" | ConvertFrom-Json
$connectionText = if ($dev.ConnectionStrings.DefaultConnection) { $dev.ConnectionStrings.DefaultConnection } else { $config.ConnectionStrings.DefaultConnection }
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionText
if (!$builder.DataSource.StartsWith('(localdb)', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'QA is restricted to local SQL Server LocalDB' }
$builder.Encrypt = $false
$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
function Query($sql, $parameters) {
    $command = $connection.CreateCommand(); $command.CommandText = $sql
    foreach ($key in $parameters.Keys) { [void]$command.Parameters.AddWithValue($key, $parameters[$key]) }
    try { return $command.ExecuteScalar() } finally { $command.Dispose() }
}
function ControllerSql($name, $method) {
    $source = Get-Content -Raw -Encoding UTF8 "$project/backend/LastMile/LastMile.Api/Controllers/$name.cs"
    $start = $source.IndexOf($method + '(')
    $sql = [regex]::Match($source.Substring($start), 'const string sql = """([\s\S]*?)""";').Groups[1].Value
    if (!$sql) { throw 'Controller SQL not found' }
    return $sql
}
try {
    $connection.Open()
    $accountId = Query "SELECT TOP (1) tk.MaTaiKhoan FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE vt.KyHieuVaiTro='ADMIN' AND tk.TrangThaiTaiKhoan='ACTIVE' AND vt.DangHoatDong=1 AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc<=SYSUTCDATETIME()) ORDER BY tk.MaTaiKhoan" @{}
    if (!$accountId) { throw 'No existing active admin for read-only controller SQL QA' }
    $warehouses = Query (ControllerSql 'WarehousesController' 'GetWarehouses') @{ '@IsAdmin'=$true; '@BranchId'=[DBNull]::Value } | ConvertFrom-Json
    $warehouses = @($warehouses)
    $locations = @{}; $orders = @{}; $checks = @(); $details = @{}
    $handoverSql = ControllerSql 'WarehouseHandoverOrdersController' 'GetHandoverOrders'
    foreach ($warehouse in $warehouses) {
        $warehouseLocations = Query (ControllerSql 'WarehousesController' 'GetLocations') @{ '@Id'=$warehouse.id; '@Status'='ACTIVE'; '@Keyword'=[DBNull]::Value } | ConvertFrom-Json
        $locations[$warehouse.id.ToString()] = @($warehouseLocations)
        $parameters = @{ '@AccountId'=[long]$accountId; '@WarehouseId'=[int]$warehouse.id; '@Keyword'=[DBNull]::Value; '@ShipperId'=[DBNull]::Value; '@AcceptedOnly'=$false; '@LocationId'=[DBNull]::Value; '@AssignmentStatus'=[DBNull]::Value; '@Page'=1; '@PageSize'=100; '@Offset'=0 }
        $first = Query $handoverSql $parameters | ConvertFrom-Json
        $rows = @($first.items)
        for ($page=2; ($page-1)*100 -lt $first.totalItems; $page++) {
            $parameters['@Page']=$page; $parameters['@Offset']=($page-1)*100
            $rows += @( (Query $handoverSql $parameters | ConvertFrom-Json).items )
        }
        $orders[$warehouse.id.ToString()] = $rows
        $parameters['@Page']=1; $parameters['@PageSize']=1; $parameters['@Offset']=0
        foreach ($status in @('PENDING','ACCEPTED')) {
            $parameters['@AssignmentStatus']=$status
            $filtered = Query $handoverSql $parameters | ConvertFrom-Json
            $expected = @($rows | Where-Object assignmentStatus -eq $status).Count
            if ($filtered.totalItems -ne $expected -or @($filtered.items | Where-Object assignmentStatus -ne $status).Count) { throw 'Assignment filtering/count mismatch' }
            $checks += "warehouse $($warehouse.id): $status total=$expected, pageSize=1"
        }
        $parameters['@AssignmentStatus']=[DBNull]::Value
        foreach ($location in $locations[$warehouse.id.ToString()]) {
            $parameters['@LocationId']=[long]$location.id
            $filtered = Query $handoverSql $parameters | ConvertFrom-Json
            $expected = @($rows | Where-Object locationId -eq $location.id).Count
            if ($filtered.totalItems -ne $expected) { throw 'Location filtering/count mismatch' }
        }
        $parameters['@LocationId']=[DBNull]::Value
        $parameters['@Keyword']='__outbound_QA_no_match_20261009__'
        $empty = Query $handoverSql $parameters | ConvertFrom-Json
        if ($empty.totalItems -ne 0 -or @($empty.items).Count) { throw 'No-match search must return an empty page' }
        foreach ($row in $rows) {
            if (!$details.ContainsKey($row.orderId.ToString())) {
                $details[$row.orderId.ToString()] = Query (ControllerSql 'OrdersController' 'GetOrder') @{ '@Id'=[long]$row.orderId; '@IsAdmin'=$true; '@BranchId'=[DBNull]::Value } | ConvertFrom-Json
            }
        }
    }
    # Actual DB records pass directly to the isolated browser QA process in memory.
    # No inserts/updates, JWTs, connection strings or order payload files.
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::Write((@{ warehouses=$warehouses; locations=$locations; orders=$orders; details=$details; sqlChecks=$checks } | ConvertTo-Json -Depth 30 -Compress))
} finally { $connection.Dispose() }
