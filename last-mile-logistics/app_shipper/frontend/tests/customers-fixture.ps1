param([ValidateSet('Create','Inspect','RestrictReader','Drop')][string]$Mode='Create', [string]$Database)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($Database -notmatch '^CodexCustomers_[a-f0-9]{32}$') {throw 'Only isolated CodexCustomers GUID databases allowed'}
$config=Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.json"|ConvertFrom-Json
$dev=Get-Content -Raw "$project/backend/LastMile/LastMile.Api/appsettings.Development.json"|ConvertFrom-Json
$text=if($dev.ConnectionStrings.DefaultConnection){$dev.ConnectionStrings.DefaultConnection}else{$config.ConnectionStrings.DefaultConnection}
$builder=New-Object System.Data.SqlClient.SqlConnectionStringBuilder $text
if(!$builder.DataSource.StartsWith('(localdb)',[StringComparison]::OrdinalIgnoreCase)){throw 'LocalDB only'}
$builder['Initial Catalog']='master';$builder.Encrypt=$false
$connection=New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
function Run($sql){$cmd=$connection.CreateCommand();$cmd.CommandText=$sql;$cmd.CommandTimeout=120;try{[void]$cmd.ExecuteNonQuery()}finally{$cmd.Dispose()}}
function Scalar($sql){$cmd=$connection.CreateCommand();$cmd.CommandText=$sql;try{return $cmd.ExecuteScalar()}finally{$cmd.Dispose()}}
try {
 $connection.Open()
 if($Mode -eq 'Drop') {Run "IF DB_ID(N'$Database') IS NOT NULL BEGIN ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Database]; END;"; [Console]::Write('{"dropped":true}');exit}
 if($Mode -eq 'Create') {
  if(Scalar "SELECT CASE WHEN DB_ID(N'$Database') IS NULL THEN 0 ELSE 1 END"){throw 'Test database already exists'}
  foreach($file in @('QLGiaoHangChangCuoi_SQLServer_V5 .sql','DuLieuThucTe_QLGiaoHangChangCuoi_V5 .sql')) {
   $sql=(Get-Content -Raw -Encoding UTF8 "$project/database/$file").Replace('QLGiaoHangChangCuoi',$Database)
   foreach($batch in [regex]::Split($sql,'(?im)^\s*GO\s*(?:--[^\r\n]*)?\r?$')){if($batch.Trim()){Run $batch}}
  }
 }
 Run "USE [$Database];"
 if($Mode -eq 'RestrictReader') {
  Run "DELETE vq FROM dbo.VaiTroQuyen vq JOIN dbo.VaiTro vt ON vt.MaVaiTro=vq.MaVaiTro JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE vt.KyHieuVaiTro='BRANCH_MANAGER' AND q.KyHieuQuyen IN ('DONHANG_TAO','DONHANG_CAPNHAT'); UPDATE tk SET MaBuuCuc=NULL FROM dbo.TaiKhoan tk WHERE TenDangNhap='dp.tan.phu';"
 }
 $actors=Scalar "SELECT tk.MaTaiKhoan AS accountId,tk.TenDangNhap AS username,tk.HoTen AS fullName,vt.KyHieuVaiTro AS role,tk.MaBuuCuc AS branchId FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro ORDER BY tk.MaTaiKhoan FOR JSON PATH,INCLUDE_NULL_VALUES"|ConvertFrom-Json
 $points=Scalar 'SELECT MaDiemGiaoNhan,MaDonHang,LoaiDiem,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc,ViDo,KinhDo,GhiChu FROM dbo.DiemGiaoNhan ORDER BY MaDiemGiaoNhan FOR JSON PATH,INCLUDE_NULL_VALUES'
 $counts=Scalar 'SELECT (SELECT COUNT(*) FROM dbo.KhachHang) AS customers,(SELECT COUNT(*) FROM dbo.DiaChiKhachHang) AS addresses,(SELECT COUNT(*) FROM dbo.NhatKyHoatDong) AS audits FOR JSON PATH,WITHOUT_ARRAY_WRAPPER'|ConvertFrom-Json
 $builder['Initial Catalog']=$Database
 [Console]::Write((@{connectionString=$builder.ConnectionString;actors=@($actors);orderPoints=$points;counts=$counts}|ConvertTo-Json -Depth 8 -Compress))
} finally {$connection.Dispose()}


