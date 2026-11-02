$ErrorActionPreference='Stop'
$project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config=Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.json"|ConvertFrom-Json
$dev=Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.Development.json"|ConvertFrom-Json
$builder=New-Object System.Data.SqlClient.SqlConnectionStringBuilder $(if($dev.ConnectionStrings.DefaultConnection){$dev.ConnectionStrings.DefaultConnection}else{$config.ConnectionStrings.DefaultConnection})
if(!$builder.DataSource.StartsWith('(localdb)',[StringComparison]::OrdinalIgnoreCase)){throw 'Only existing LocalDB is allowed'};$builder.Encrypt=$false
$connection=New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
function Scalar($query,$parameters){$cmd=$connection.CreateCommand();$cmd.CommandText=$query;foreach($key in $parameters.Keys){[void]$cmd.Parameters.AddWithValue($key,$parameters[$key])};try{return $cmd.ExecuteScalar()}finally{$cmd.Dispose()}}
function NonQuery($query,$parameters=@{}){$cmd=$connection.CreateCommand();$cmd.CommandText=$query;foreach($key in $parameters.Keys){[void]$cmd.Parameters.AddWithValue($key,$parameters[$key])};try{[void]$cmd.ExecuteNonQuery()}finally{$cmd.Dispose()}}
$source=Get-Content -Raw -Encoding UTF8 "$project/backend/LastMile/LastMile.Api/Controllers/CatalogSaveController.cs"
$block=$source.Substring($source.IndexOf('"LOCATIONS" => new('));$block=$block.Substring(0,$block.IndexOf('_ => null'))
$parts=@([regex]::Matches($block,'"""([\s\S]*?)"""|"([^"]*)"')|ForEach-Object{if($_.Groups[1].Success){$_.Groups[1].Value}else{$_.Groups[2].Value}})
if($parts.Count -ne 7 -or $parts[1] -ne 'ViTriLuuKho'){throw 'Location catalog definition shape changed'}
$sql=[regex]::Match($source,'var sql = \$"""([\s\S]*?)""";').Groups[1].Value
$definitions=@{Table=$parts[1];IdColumn=$parts[2];Projection=$parts[3];InsertColumns=$parts[4];InsertValues=$parts[5];UpdateColumns=$parts[6]}
foreach($key in $definitions.Keys){$sql=$sql.Replace('{definition.'+$key+'}',$definitions[$key])}
if(!$sql -or $sql.Contains('{definition.')){throw 'SQL extraction failed'}
function Params($row,$actor,$isActive){return @{'@ActorId'=[long]$actor;'@Type'='LOCATIONS';'@ObjectName'='ViTriLuuKho';'@Id'=$(if($row.id){[long]$row.id}else{[DBNull]::Value});'@Code'=[string]$row.code;'@Name'=[DBNull]::Value;'@IsActive'=[bool]$isActive;'@ParentId'=[DBNull]::Value;'@AreaType'=[DBNull]::Value;'@AreaId'=[DBNull]::Value;'@Address'=[DBNull]::Value;'@Phone'=[DBNull]::Value;'@Email'=[DBNull]::Value;'@Latitude'=[DBNull]::Value;'@Longitude'=[DBNull]::Value;'@BranchId'=[DBNull]::Value;'@WarehouseId'=[int]$row.warehouseId;'@StorageArea'=$(if($row.storageArea){[string]$row.storageArea}else{[DBNull]::Value});'@Rack'=$(if($row.rack){[string]$row.rack}else{[DBNull]::Value});'@Slot'=$(if($row.slot){[string]$row.slot}else{[DBNull]::Value})}}
function Trial($label,$parameters,$expectedError=0,$setup=''){
  # Controller's inner COMMIT cannot commit this outer transaction. Always roll it back.
  NonQuery 'BEGIN TRAN;'
  try{
    if($setup){NonQuery $setup @{'@Id'=$parameters['@Id']}}
    try{$result=Scalar $sql $parameters|ConvertFrom-Json;if($expectedError){throw 'Expected SQL rejection not returned'};if(!$result.id -or $result.code -ne $parameters['@Code'] -or $result.warehouseId -ne $parameters['@WarehouseId'] -or $result.isActive -ne $parameters['@IsActive']){throw 'Save response mismatch'};return @{label=$label;passed=$true}}
    catch [System.Management.Automation.MethodInvocationException]{$number=$_.Exception.InnerException.Number;if(!$expectedError -or $number -ne $expectedError){throw};return @{label=$label;passed=$true;sqlError=$number}}
  }finally{NonQuery 'IF @@TRANCOUNT > 0 ROLLBACK;'}
}
try{
  $connection.Open();$checks=@()
  $before=Scalar 'SELECT (SELECT COUNT(*) FROM dbo.ViTriLuuKho)*1000000 + (SELECT COUNT(*) FROM dbo.NhatKyHoatDong)' @{}
  $admin=Scalar "SELECT TOP(1) tk.MaTaiKhoan FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE vt.KyHieuVaiTro='ADMIN' AND tk.TrangThaiTaiKhoan='ACTIVE' AND EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE vq.MaVaiTro=tk.MaVaiTro AND q.KyHieuQuyen='BUUCUC_QUANLY') ORDER BY tk.MaTaiKhoan" @{}
  $nonAdmin=Scalar "SELECT TOP(1) tk.MaTaiKhoan FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE vt.KyHieuVaiTro<>'ADMIN' AND tk.TrangThaiTaiKhoan='ACTIVE' ORDER BY tk.MaTaiKhoan" @{}
  $rows=Scalar 'SELECT vt.MaViTriLuuKho AS id,vt.MaKho AS warehouseId,vt.KyHieuViTri AS code,vt.TenKhuLuu AS storageArea,vt.MaKe AS rack,vt.MaO AS slot,vt.DangHoatDong AS isActive,CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.TonKhoDonHang t WHERE t.MaViTriLuuKho=vt.MaViTriLuuKho AND t.TrangThaiTonKho IN (''RECEIVED'',''STORED'',''ALLOCATED'',''RETURNED'')) THEN 1 ELSE 0 END AS BIT) AS occupied FROM dbo.ViTriLuuKho vt JOIN dbo.Kho k ON k.MaKho=vt.MaKho JOIN dbo.BuuCuc b ON b.MaBuuCuc=k.MaBuuCuc WHERE k.DangHoatDong=1 AND b.DangHoatDong=1 ORDER BY vt.MaViTriLuuKho FOR JSON PATH,INCLUDE_NULL_VALUES' @{}|ConvertFrom-Json
  $first=@($rows)[0];if(!$admin -or !$first){throw 'Existing admin/location missing'}
  $new=@{code='QA-LOC-'+[Guid]::NewGuid().ToString('N').ToUpperInvariant();warehouseId=$first.warehouseId;storageArea='QA rollback';rack='R1';slot='S1'}
  $checks+=Trial 'create location' (Params $new $admin $true)
  $duplicate=Params @{code=$first.code;warehouseId=$first.warehouseId} $admin $true
  $checks+=Trial 'duplicate code in same warehouse' $duplicate 2627
  $edited=@{id=$first.id;code=$first.code;warehouseId=$first.warehouseId;storageArea='QA edited rollback';rack='R2';slot='S2'}
  $checks+=Trial 'edit allowed fields' (Params $edited $admin $first.isActive)
  $changed=Params $edited $admin $first.isActive;$changed['@Code']='QA-CHANGE-CODE';$checks+=Trial 'existing code immutable' $changed 56504
  $other=@($rows|Where-Object warehouseId -ne $first.warehouseId|Select-Object -First 1)
  if($other.Count){$moved=Params $edited $admin $first.isActive;$moved['@WarehouseId']=[int]$other[0].warehouseId;$checks+=Trial 'existing warehouse immutable' $moved 56504}
  $occupied=@($rows|Where-Object occupied -eq $true|Select-Object -First 1)
  if($occupied.Count){$checks+=Trial 'occupied location cannot be disabled' (Params $occupied[0] $admin $false) 56504}else{$checks+=@{label='occupied location cannot be disabled';skipped='No occupied location in current data'}}
  $empty=@($rows|Where-Object occupied -eq $false|Select-Object -First 1)
  if($empty.Count){
    $checks+=Trial 'disable empty location' (Params $empty[0] $admin $false)
    $checks+=Trial 'reactivate inactive location' (Params $empty[0] $admin $true) 0 'UPDATE dbo.ViTriLuuKho SET DangHoatDong=0 WHERE MaViTriLuuKho=@Id;'
    $warehouseSource=Get-Content -Raw -Encoding UTF8 "$project/backend/LastMile/LastMile.Api/Controllers/WarehousesController.cs"
    $locationSql=[regex]::Match($warehouseSource.Substring($warehouseSource.IndexOf('GetLocations(')),'const string sql = """([\s\S]*?)""";').Groups[1].Value
    NonQuery 'BEGIN TRAN;'
    try{
      NonQuery 'UPDATE dbo.ViTriLuuKho SET DangHoatDong=0 WHERE MaViTriLuuKho=@Id;' @{'@Id'=[long]$empty[0].id}
      foreach($status in @('ACTIVE','INACTIVE','ALL')){
        $listed=Scalar $locationSql @{'@Id'=[int]$empty[0].warehouseId;'@Status'=$status;'@Keyword'=[DBNull]::Value}|ConvertFrom-Json
        $contains=@($listed|Where-Object id -eq $empty[0].id).Count -gt 0
        if($contains -ne ($status -ne 'ACTIVE')){throw 'Inactive location selection/management visibility failed'}
      }
      $checks+=@{label='inactive excluded from default selection, visible to management';passed=$true}
    }finally{NonQuery 'IF @@TRANCOUNT > 0 ROLLBACK;'}
  }
  if($nonAdmin){$checks+=Trial 'non-admin denied catalog management' (Params $edited $nonAdmin $true) 56502}
  $checks+=Trial 'invalid account denied' (Params $edited -1 $true) 56501
  $after=Scalar 'SELECT (SELECT COUNT(*) FROM dbo.ViTriLuuKho)*1000000 + (SELECT COUNT(*) FROM dbo.NhatKyHoatDong)' @{}
  if($before -ne $after){throw 'Persistent location/audit counts changed'}
  [Console]::Write((@{mode='Actual CatalogSave SQL inside outer rollback transactions';checks=$checks;persistentCountsUnchanged=$true}|ConvertTo-Json -Depth 8 -Compress))
}finally{if($connection.State -eq 'Open'){NonQuery 'IF @@TRANCOUNT > 0 ROLLBACK;'};$connection.Dispose()}
