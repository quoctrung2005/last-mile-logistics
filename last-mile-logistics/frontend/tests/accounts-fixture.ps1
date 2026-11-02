param([ValidateSet('Create','Inspect','RestrictReader','GrantManager','LastAdmin','Drop')][string]$Mode='Create', [string]$Database, [long]$TargetId=0)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($Database -notmatch '^CodexAccounts_[a-f0-9]{32}$') {throw 'Only isolated CodexAccounts GUID databases allowed'}
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
 if($Mode -eq 'Create') {
  $migration=Get-Content -Raw -Encoding UTF8 "$project/database/migrations/20261019_auth_sessions.sql"
  Run $migration
 }
 if($Mode -eq 'Create') {
  Run "DECLARE @Role INT=(SELECT MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='SHIPPER'), @Branch INT=(SELECT MIN(MaBuuCuc) FROM dbo.BuuCuc);
INSERT dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,MaVaiTro,MaBuuCuc,SoLanDangNhapSai,KhoaDenLuc)
VALUES('QA-TEMPLOCK','qa.templock','QA_FIXTURE_NOT_A_PASSWORD',N'QA Khóa tạm',@Role,@Branch,5,DATEADD(DAY,1,SYSUTCDATETIME()));"
 }
 if($Mode -eq 'RestrictReader') {
  Run "DELETE vq FROM dbo.VaiTroQuyen vq JOIN dbo.VaiTro vt ON vt.MaVaiTro=vq.MaVaiTro JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE vt.KyHieuVaiTro='ADMIN' AND q.KyHieuQuyen='TAIKHOAN_QUANLY';"
 }
 if($Mode -eq 'LastAdmin') {
  if($TargetId -le 0){throw 'TargetId required'}
  Run "UPDATE tk SET TrangThaiTaiKhoan='INACTIVE' FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE vt.KyHieuVaiTro='ADMIN' AND tk.MaTaiKhoan<>$TargetId;"
 }
 if($Mode -eq 'GrantManager') {
  Run "INSERT dbo.VaiTroQuyen(MaVaiTro,MaQuyen) SELECT vt.MaVaiTro,q.MaQuyen FROM dbo.VaiTro vt CROSS JOIN dbo.Quyen q WHERE vt.KyHieuVaiTro='BRANCH_MANAGER' AND q.KyHieuQuyen='TAIKHOAN_QUANLY' AND NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen x WHERE x.MaVaiTro=vt.MaVaiTro AND x.MaQuyen=q.MaQuyen);"
 }
 # Synthetic browser actors still need a real server session. These deterministic
 # IDs are fixture-only; revoked sessions are never reactivated by Inspect.
 Run "INSERT dbo.PhienDangNhap(MaPhien,MaTaiKhoan,ThoiGianTao,HetHanLuc)
 SELECT CONVERT(UNIQUEIDENTIFIER,CONVERT(BINARY(16),tk.MaTaiKhoan)),tk.MaTaiKhoan,SYSUTCDATETIME(),DATEADD(HOUR,2,SYSUTCDATETIME())
 FROM dbo.TaiKhoan tk WHERE NOT EXISTS(SELECT 1 FROM dbo.PhienDangNhap p WHERE p.MaPhien=CONVERT(UNIQUEIDENTIFIER,CONVERT(BINARY(16),tk.MaTaiKhoan)));"
 $actors=Scalar "SELECT (SELECT tk.MaTaiKhoan AS accountId,tk.TenDangNhap AS username,tk.HoTen AS fullName,vt.KyHieuVaiTro AS role,tk.MaBuuCuc AS branchId FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro ORDER BY tk.MaTaiKhoan FOR JSON PATH,INCLUDE_NULL_VALUES)"|ConvertFrom-Json
 $audit=Scalar "SELECT (SELECT LoaiThaoTac AS action,DuLieuCuJson AS oldJson,DuLieuMoiJson AS newJson FROM dbo.NhatKyHoatDong WHERE LoaiThaoTac LIKE '%ACCOUNT%' OR LoaiThaoTac='ADMIN_RESET_PASSWORD' FOR JSON PATH)"|ConvertFrom-Json
 $stats=Scalar "SELECT (SELECT COUNT(*) FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro WHERE vt.KyHieuVaiTro='ADMIN' AND tk.TrangThaiTaiKhoan='ACTIVE' AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc<=SYSUTCDATETIME())) AS activeAdmins FOR JSON PATH,WITHOUT_ARRAY_WRAPPER"|ConvertFrom-Json
 $builder['Initial Catalog']=$Database
 [Console]::Write((@{connectionString=$builder.ConnectionString;actors=@($actors);audit=@($audit);stats=$stats}|ConvertTo-Json -Depth 8 -Compress))
} finally {$connection.Dispose()}
