$ErrorActionPreference='Stop'
$project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config=Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.json" | ConvertFrom-Json
$dev=Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.Development.json" | ConvertFrom-Json
$builder=New-Object System.Data.SqlClient.SqlConnectionStringBuilder $(if($dev.ConnectionStrings.DefaultConnection){$dev.ConnectionStrings.DefaultConnection}else{$config.ConnectionStrings.DefaultConnection})
if(!$builder.DataSource.StartsWith('(localdb)',[StringComparison]::OrdinalIgnoreCase)){throw 'Only existing LocalDB is allowed'}
$builder.Encrypt=$false
$connection=New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
function Query($sql,$parameters){$cmd=$connection.CreateCommand();$cmd.CommandText=$sql;foreach($key in $parameters.Keys){[void]$cmd.Parameters.AddWithValue($key,$parameters[$key])};try{return $cmd.ExecuteScalar()}finally{$cmd.Dispose()}}
function Sql($method){$source=Get-Content -Raw -Encoding UTF8 "$project/backend/LastMile/LastMile.Api/Controllers/WarehousesController.cs";$value=[regex]::Match($source.Substring($source.IndexOf($method+'(')),'const string sql = """([\s\S]*?)""";').Groups[1].Value;if(!$value){throw 'SQL not found'};return $value}
try{
  $connection.Open();$checks=@();$locations=@{};$inventory=@{}
  $warehouses=Query (Sql 'GetWarehouses') @{'@IsAdmin'=$true;'@BranchId'=[DBNull]::Value}|ConvertFrom-Json
  foreach($warehouse in @($warehouses)){
    $all=Query (Sql 'GetLocations') @{'@Id'=[int]$warehouse.id;'@Status'='ALL';'@Keyword'=[DBNull]::Value}|ConvertFrom-Json
    $locations[$warehouse.id.ToString()]=@($all)
    foreach($status in @('ACTIVE','INACTIVE','ALL')){
      $result=Query (Sql 'GetLocations') @{'@Id'=[int]$warehouse.id;'@Status'=$status;'@Keyword'=[DBNull]::Value}|ConvertFrom-Json
      $expected=@($all | Where-Object { $status -eq 'ALL' -or $_.isActive -eq ($status -eq 'ACTIVE') })
      if(@($result).Count -ne $expected.Count){throw 'Status count mismatch'}
      if(@($result | Where-Object warehouseId -ne $warehouse.id).Count){throw 'Wrong warehouse returned'}
      $checks+=@{warehouseId=$warehouse.id;status=$status;rows=@($result).Count}
    }
    foreach($row in @($all)){
      $p=@{'@Id'=[int]$warehouse.id;'@LocationId'=[long]$row.id;'@OrderStatus'=[DBNull]::Value;'@Keyword'=[DBNull]::Value;'@Page'=1;'@PageSize'=10;'@Offset'=0}
      $stock=Query (Sql 'GetInventory') $p|ConvertFrom-Json
      if(@($stock.items|Where-Object locationId -ne $row.id).Count){throw 'Inventory location filter failed'}
      $inventory[$row.id.ToString()]=$stock
    }
    $sample=@($all)[0]
    if($sample){foreach($field in @('code','storageArea','rack','slot')){if($sample.$field){
      $matches=Query (Sql 'GetLocations') @{'@Id'=[int]$warehouse.id;'@Status'='ALL';'@Keyword'=[string]$sample.$field}|ConvertFrom-Json
      if(!@($matches|Where-Object id -eq $sample.id).Count){throw "Search $field failed"}
      $checks+=@{warehouseId=$warehouse.id;searchField=$field;passed=$true}
    }}}
    $empty=Query (Sql 'GetLocations') @{'@Id'=[int]$warehouse.id;'@Status'='ALL';'@Keyword'='__LOCATION_NO_MATCH_20261009__'}|ConvertFrom-Json
    if(@($empty).Count){throw 'No-match search not empty'}
  }
  $reader=Query "SELECT TOP(1) tk.MaBuuCuc FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE vt.KyHieuVaiTro<>'ADMIN' AND tk.TrangThaiTaiKhoan='ACTIVE' AND tk.MaBuuCuc IS NOT NULL AND EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE vq.MaVaiTro=tk.MaVaiTro AND q.KyHieuQuyen='KHO_XEM') ORDER BY tk.MaTaiKhoan" @{}
  if($reader){
    $scoped=Query (Sql 'GetWarehouses') @{'@IsAdmin'=$false;'@BranchId'=[int]$reader}|ConvertFrom-Json
    if(@($scoped|Where-Object branchId -ne $reader).Count){throw 'Warehouse branch scope failed'}
    $other=@($warehouses|Where-Object branchId -ne $reader|Select-Object -First 1)
    if($other.Count){$access=Query (Sql 'CanAccessWarehouse') @{'@IsAdmin'=$false;'@BranchId'=[int]$reader;'@Id'=[int]$other[0].id};if($access -ne 0){throw 'Other branch warehouse must be denied'};$checks+=@{otherBranchDenied=$true}}
  }
  [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
  [Console]::Write((@{warehouses=@($warehouses);locations=$locations;inventory=$inventory;sqlChecks=$checks}|ConvertTo-Json -Depth 25 -Compress))
}finally{$connection.Dispose()}
