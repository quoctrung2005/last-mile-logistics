param([ValidateSet('Create','Inspect','RestrictReader','Drop')][string]$Mode='Create', [string]$Database)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($Database -notmatch '^CodexShippers_[a-f0-9]{32}$') {throw 'Only isolated CodexShippers GUID databases allowed'}
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
  Run (Get-Content -Raw -Encoding utf8 "$project/database/migrations/20261019_auth_sessions.sql")
  Run "DECLARE @ShipperRole INT=(SELECT MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='SHIPPER');
DECLARE @BranchA INT=(SELECT MIN(MaBuuCuc) FROM dbo.BuuCuc WHERE DangHoatDong=1);
DECLARE @BranchB INT=(SELECT MAX(MaBuuCuc) FROM dbo.BuuCuc WHERE DangHoatDong=1);
INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan,KhoaDenLuc) VALUES
('QA-UNLINKED-A','qa.unlinked.a','QA_FIXTURE_NOT_A_PASSWORD','QA Unlinked A',@ShipperRole,@BranchA,'ACTIVE',NULL),
('QA-UNLINKED-B','qa.unlinked.b','QA_FIXTURE_NOT_A_PASSWORD','QA Unlinked B',@ShipperRole,@BranchB,'ACTIVE',NULL),
('QA-LOCKED','qa.locked','QA_FIXTURE_NOT_A_PASSWORD','QA Locked',@ShipperRole,@BranchA,'LOCKED',NULL),
('QA-TEMPLOCKED','qa.templocked','QA_FIXTURE_NOT_A_PASSWORD','QA Temp Locked',@ShipperRole,@BranchA,'ACTIVE',DATEADD(DAY,1,SYSUTCDATETIME())),
('QA-NOBRANCH','qa.nobranch','QA_FIXTURE_NOT_A_PASSWORD','QA No Branch',@ShipperRole,NULL,'ACTIVE',NULL);"
  Run "INSERT dbo.PhienDangNhap(MaPhien,MaTaiKhoan,ThoiGianTao,HetHanLuc)
SELECT CONVERT(UNIQUEIDENTIFIER,CONVERT(BINARY(16),MaTaiKhoan)),MaTaiKhoan,SYSUTCDATETIME(),DATEADD(HOUR,2,SYSUTCDATETIME()) FROM dbo.TaiKhoan;"
 }

 if($Mode -eq 'RestrictReader') {
  Run "DELETE vq FROM dbo.VaiTroQuyen vq JOIN dbo.VaiTro vt ON vt.MaVaiTro=vq.MaVaiTro JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE vt.KyHieuVaiTro='ADMIN' AND q.KyHieuQuyen='TAIKHOAN_QUANLY';"
 }
 $actors=Scalar "SELECT (SELECT tk.MaTaiKhoan AS accountId,tk.TenDangNhap AS username,tk.HoTen AS fullName,vt.KyHieuVaiTro AS role,tk.MaBuuCuc AS branchId FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro ORDER BY tk.MaTaiKhoan FOR JSON PATH,INCLUDE_NULL_VALUES)"|ConvertFrom-Json
 $points=Scalar 'SELECT (SELECT MaDiemGiaoNhan,MaDonHang,LoaiDiem,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc,ViDo,KinhDo,GhiChu FROM dbo.DiemGiaoNhan ORDER BY MaDiemGiaoNhan FOR JSON PATH,INCLUDE_NULL_VALUES)'
 $counts=Scalar 'SELECT (SELECT COUNT(*) FROM dbo.NhanVienGiaoHang) AS shippers,(SELECT COUNT(*) FROM dbo.PhanCongGiaoHang) AS assignments,(SELECT COUNT(*) FROM dbo.ChuyenGiaoHang) AS trips FOR JSON PATH,WITHOUT_ARRAY_WRAPPER'|ConvertFrom-Json
 $builder['Initial Catalog']=$Database
 [Console]::Write((@{connectionString=$builder.ConnectionString;actors=@($actors);orderPoints=$points;counts=$counts}|ConvertTo-Json -Depth 8 -Compress))
} finally {$connection.Dispose()}


