$ErrorActionPreference='Stop'
$project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config=Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.json"|ConvertFrom-Json
$dev=Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.Development.json"|ConvertFrom-Json
$builder=New-Object System.Data.SqlClient.SqlConnectionStringBuilder $(if($dev.ConnectionStrings.DefaultConnection){$dev.ConnectionStrings.DefaultConnection}else{$config.ConnectionStrings.DefaultConnection})
if(!$builder.DataSource.StartsWith('(localdb)',[StringComparison]::OrdinalIgnoreCase)){throw 'Only existing LocalDB allowed'};$builder.Encrypt=$false
$connection=New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
function Query($sql,$params){$cmd=$connection.CreateCommand();$cmd.CommandText=$sql;foreach($key in $params.Keys){[void]$cmd.Parameters.AddWithValue($key,$params[$key])};try{return $cmd.ExecuteScalar()}finally{$cmd.Dispose()}}
function Sql($controller,$method){$source=Get-Content -Raw -Encoding UTF8 "$project/backend/LastMile/LastMile.Api/Controllers/$controller.cs";$sql=[regex]::Match($source.Substring($source.IndexOf($method+'(')),'const string sql = """([\s\S]*?)""";').Groups[1].Value;if(!$sql){throw 'SQL not found'};return $sql}
function Utc($value){return [datetime]::Parse($value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)}
try{
  $connection.Open();$checks=@();$details=@{};$orders=@{}
  $warehouses=Query (Sql 'WarehousesController' 'GetWarehouses') @{'@IsAdmin'=$true;'@BranchId'=[DBNull]::Value}|ConvertFrom-Json
  $base=@{'@IsAdmin'=$true;'@BranchId'=[DBNull]::Value;'@WarehouseId'=[DBNull]::Value;'@Type'=[DBNull]::Value;'@OrderId'=[DBNull]::Value;'@Keyword'=[DBNull]::Value;'@FromUtc'=[DBNull]::Value;'@ToUtcExclusive'=[DBNull]::Value;'@Page'=1;'@PageSize'=100;'@Offset'=0}
  $listSql=Sql 'WarehouseTransactionsController' 'GetTransactions';$detailSql=Sql 'WarehouseTransactionsController' 'GetTransaction'
  $first=Query $listSql $base|ConvertFrom-Json;$all=@($first.items)
  for($page=2;($page-1)*100 -lt $first.totalItems;$page++){$p=$base.Clone();$p['@Page']=$page;$p['@Offset']=($page-1)*100;$all+=@((Query $listSql $p|ConvertFrom-Json).items)}
  if($all.Count -ne $first.totalItems){throw 'Full list count mismatch'}
  foreach($row in $all){
    $detail=Query $detailSql @{'@IsAdmin'=$true;'@BranchId'=[DBNull]::Value;'@Id'=[long]$row.id}|ConvertFrom-Json
    if($detail.id -ne $row.id -or !$detail.branchName -or $null -eq $detail.items -or @($detail.items).Count -ne $row.orderCount){throw 'Detail response mismatch'}
    $details[$row.id.ToString()]=$detail
    foreach($item in @($detail.items)){if(!$orders.ContainsKey($item.orderId.ToString())){$orders[$item.orderId.ToString()]=Query (Sql 'OrdersController' 'GetOrder') @{'@Id'=[long]$item.orderId;'@IsAdmin'=$true;'@BranchId'=[DBNull]::Value}|ConvertFrom-Json}}
  }
  for($i=1;$i -lt $all.Count;$i++){if((Utc $all[$i].performedAt) -gt (Utc $all[$i-1].performedAt) -or ((Utc $all[$i].performedAt) -eq (Utc $all[$i-1].performedAt) -and $all[$i].id -gt $all[$i-1].id)){throw 'Newest-first ordering failed'}}
  $checks+=@{label='all scoped warehouses, newest first, details';totalItems=$all.Count;passed=$true}
  foreach($type in @('INBOUND','MOVE','OUTBOUND','RETURN_IN')){
    $p=$base.Clone();$p['@Type']=$type;$p['@PageSize']=1;$result=Query $listSql $p|ConvertFrom-Json;$expected=@($all|Where-Object type -eq $type)
    if($result.totalItems -ne $expected.Count -or @($result.items|Where-Object type -ne $type).Count){throw 'Type filter/count mismatch'};$checks+=@{label='type '+$type;totalItems=$result.totalItems;passed=$true}
  }
  if($all.Count){
    $sample=$all[0];$child=@($details[$sample.id.ToString()].items)[0]
    foreach($term in @($sample.transactionCode,$child.orderCode,$child.trackingNumber)|Where-Object{$_}){
      $expected=@($all|Where-Object{([string]$_.transactionCode).IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or @($details[$_.id.ToString()].items|Where-Object{([string]$_.orderCode).IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or ([string]$_.trackingNumber).IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0}).Count})
      $p=$base.Clone();$p['@Keyword']=[string]$term;$p['@PageSize']=1;$result=Query $listSql $p|ConvertFrom-Json
      if($result.totalItems -ne $expected.Count -or @($result.items|Where-Object id -notin @($expected.id)).Count){throw 'Keyword filter/count mismatch'};$checks+=@{label='keyword field matched';totalItems=$result.totalItems;passed=$true}
    }
    $day=(Utc $sample.performedAt).AddHours(7).Date;$from=$day.AddHours(-7);$to=$day.AddDays(1).AddHours(-7)
    $p=$base.Clone();$p['@FromUtc']=$from;$p['@ToUtcExclusive']=$to;$p['@PageSize']=1;$result=Query $listSql $p|ConvertFrom-Json
    $expected=@($all|Where-Object{(Utc $_.performedAt) -ge $from -and (Utc $_.performedAt) -lt $to})
    if($result.totalItems -ne $expected.Count){throw 'Vietnam day range mismatch'};$checks+=@{label='Vietnam calendar day maps to UTC boundaries';day=$day.ToString('yyyy-MM-dd');totalItems=$result.totalItems;passed=$true}
    $p=$base.Clone();$p['@FromUtc']=(Utc $sample.performedAt);$result=Query $listSql $p|ConvertFrom-Json
    if($result.totalItems -ne @($all|Where-Object{(Utc $_.performedAt) -ge (Utc $sample.performedAt)}).Count){throw 'Inclusive from boundary failed'};$checks+=@{label='from boundary inclusive';passed=$true}
    $p=$base.Clone();$p['@ToUtcExclusive']=(Utc $sample.performedAt);$result=Query $listSql $p|ConvertFrom-Json
    if($result.totalItems -ne @($all|Where-Object{(Utc $_.performedAt) -lt (Utc $sample.performedAt)}).Count){throw 'Exclusive to boundary failed'};$checks+=@{label='to boundary exclusive';passed=$true}
    if($child){$p=$base.Clone();$p['@OrderId']=[long]$child.orderId;$result=Query $listSql $p|ConvertFrom-Json;if($result.totalItems -ne @($all|Where-Object{@($details[$_.id.ToString()].items|Where-Object orderId -eq $child.orderId).Count}).Count){throw 'Legacy orderId filter failed'};$checks+=@{label='legacy orderId filter';passed=$true}}
    $p=$base.Clone();$p['@PageSize']=1;$p['@Page']=2;$p['@Offset']=1;$second=Query $listSql $p|ConvertFrom-Json
    if($all.Count -gt 1 -and $second.items[0].id -ne $all[1].id){throw 'Page 2 order/count failed'};$checks+=@{label='server page 2';passed=$true}
  }
  $p=$base.Clone();$p['@Keyword']='__NO_TRANSACTION_MATCH_20261009__';$none=Query $listSql $p|ConvertFrom-Json
  if($none.totalItems -ne 0 -or @($none.items).Count){throw 'Empty search response invalid'};$checks+=@{label='empty search response';passed=$true}
  $reader=Query "SELECT TOP(1) tk.MaBuuCuc FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE vt.KyHieuVaiTro<>'ADMIN' AND tk.TrangThaiTaiKhoan='ACTIVE' AND tk.MaBuuCuc IS NOT NULL AND EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE vq.MaVaiTro=tk.MaVaiTro AND q.KyHieuQuyen='KHO_XEM') ORDER BY tk.MaTaiKhoan" @{}
  if($reader){$p=$base.Clone();$p['@IsAdmin']=$false;$p['@BranchId']=[int]$reader;$scoped=Query $listSql $p|ConvertFrom-Json;if($scoped.totalItems -ne @($all|Where-Object branchId -eq $reader).Count -or @($scoped.items|Where-Object branchId -ne $reader).Count){throw 'Branch scope failed'};$checks+=@{label='non-admin branch scope';passed=$true}
    $other=@($all|Where-Object branchId -ne $reader|Select-Object -First 1);if($other.Count){$notFound=Query $detailSql @{'@IsAdmin'=$false;'@BranchId'=[int]$reader;'@Id'=[long]$other[0].id};if(![string]::IsNullOrWhiteSpace([string]$notFound)){throw 'Other branch detail must not be readable'};$checks+=@{label='other branch detail unavailable';passed=$true}}}
  $denied=Query (Sql 'WarehouseTransactionsController' 'GetScope') @{'@AccountId'=[long]-1};if(![string]::IsNullOrWhiteSpace([string]$denied)){throw 'Invalid account gained scope'};$checks+=@{label='invalid account has no read scope';passed=$true}
  $noPermission=Query "SELECT TOP(1) tk.MaTaiKhoan FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE tk.TrangThaiTaiKhoan='ACTIVE' AND vt.DangHoatDong=1 AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc<=SYSUTCDATETIME()) AND NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE vq.MaVaiTro=tk.MaVaiTro AND q.KyHieuQuyen='KHO_XEM') ORDER BY tk.MaTaiKhoan" @{}
  if($noPermission){$scopeDenied=Query (Sql 'WarehouseTransactionsController' 'GetScope') @{'@AccountId'=[long]$noPermission};if(![string]::IsNullOrWhiteSpace([string]$scopeDenied)){throw 'Account without KHO_XEM gained scope'};$checks+=@{label='account without KHO_XEM has no read scope';passed=$true}}
  [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
  [Console]::Write((@{warehouses=@($warehouses);transactions=$all;details=$details;orders=$orders;sqlChecks=$checks}|ConvertTo-Json -Depth 35 -Compress))
}finally{$connection.Dispose()}
