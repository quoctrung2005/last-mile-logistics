param([ValidateSet('Create','Inspect','ChangeOrder','WindowSchedule','ChangeRequestedTime','ChangeExpectedTime','InvalidSchedule','NoDeadline','ResetSchedule','TamperTimings','CheckDepotScripts','DepotNoSource','OffRoadDepot','InvalidDepot','NoDepot','RestoreDepot','LongLabels','HideDispatchSchema','RestoreDispatchSchema','Drop')][string]$Mode='Create',[string]$Database)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if($Database -notmatch '^CodexAdmin_[a-f0-9]{32}$'){throw 'Isolated GUID test database only'}
$baseMode=if($Mode -in @('Create','Drop')){$Mode}else{'Inspect'}
$raw=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/admin-fixture.ps1" -Mode $baseMode -Database $Database
if($LASTEXITCODE -ne 0){throw 'Isolated fixture failed'}
$fixture=$raw|ConvertFrom-Json
if($Mode -eq 'Drop'){[Console]::Write('{"dropped":true}');exit}
$connection=[System.Data.SqlClient.SqlConnection]::new($fixture.connectionString)
function Run($sql){$c=$connection.CreateCommand();$c.CommandText=$sql;$c.CommandTimeout=120;try{[void]$c.ExecuteNonQuery()}finally{$c.Dispose()}}
try{
 $connection.Open()
 if($Mode -eq 'Create'){
  $migration=Get-Content -Raw -Encoding utf8 "$PSScriptRoot/../../database/migrations/20261017_dispatch_planning.sql"
  foreach($batch in [regex]::Split($migration,'(?im)^\s*GO\s*(?:--[^\r\n]*)?\r?$')){if($batch.Trim()){Run $batch}}
  Run @'
-- Test-only depot coordinates: the seed explicitly places these warehouses inside their branch premises.
UPDATE k SET ViDo=b.ViDo,KinhDo=b.KinhDo,NguonToaDo=N'Isolated test fixture: warehouse inside seed branch premises'
FROM dbo.Kho k JOIN dbo.BuuCuc b ON b.MaBuuCuc=k.MaBuuCuc;
DECLARE @branch INT=(SELECT MaBuuCuc FROM dbo.BuuCuc WHERE KyHieuBuuCuc='HCM-BT01'),
 @warehouse INT=(SELECT MaKho FROM dbo.Kho WHERE KyHieuKho='KHO-BT-PL'),
 @role INT=(SELECT MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='SHIPPER'),
 @admin BIGINT=(SELECT MIN(t.MaTaiKhoan) FROM dbo.TaiKhoan t JOIN dbo.VaiTro r ON r.MaVaiTro=t.MaVaiTro WHERE r.KyHieuVaiTro='ADMIN'),
 @i INT=1,@account BIGINT,@shipper BIGINT,@vehicle BIGINT;
WHILE @i<=2
BEGIN
 INSERT dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
 VALUES(CONCAT('QA-DISPATCH-',@i),CONCAT('qa.dispatch.',@i),'QA_FIXTURE_NOT_A_PASSWORD',CONCAT(N'Shipper kiểm thử ',@i),@role,@branch,'ACTIVE');
 SET @account=SCOPE_IDENTITY();
 INSERT dbo.NhanVienGiaoHang(MaTaiKhoan,MaNhanVien,TrangThaiSanSang,DangHoatDong,NgayHetHanBangLai)
 VALUES(@account,CONCAT('QA-DISPATCH-',@i),'AVAILABLE',1,'2035-01-01');SET @shipper=SCOPE_IDENTITY();
 INSERT dbo.PhuongTien(KyHieuPhuongTien,BienSo,LoaiXe,KhoiLuongDenKg,TheTichToiDaM3,TrangThaiPhuongTien,DangHoatDong)
 VALUES(CONCAT('QA-DISPATCH-',@i),CONCAT('QA-ROUTE-',@i),'MOTORBIKE',CASE WHEN @i=1 THEN 15 ELSE 12 END,1,'AVAILABLE',1);SET @vehicle=SCOPE_IDENTITY();
 INSERT dbo.PhanCongPhuongTien(MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong)VALUES(@shipper,@vehicle,@admin);
 INSERT dbo.KhuVucNhanVienGiaoHang(MaNhanVienGiaoHang,MaKhuVuc,LaChinh)SELECT @shipper,MaKhuVuc,LaChinh FROM dbo.KhuVucPhucVuBuuCuc WHERE MaBuuCuc=@branch;
 SET @i+=1;
END;
DECLARE @source BIGINT=(SELECT TOP(1)d.MaDonHang FROM dbo.DonHang d JOIN dbo.DiemGiaoNhan g ON g.MaDonHang=d.MaDonHang AND g.LoaiDiem='DELIVERY'
 WHERE d.MaBuuCuc=@branch AND g.MaKhuVuc=(SELECT TOP(1)MaKhuVuc FROM dbo.KhuVucPhucVuBuuCuc WHERE MaBuuCuc=@branch AND LaChinh=1) ORDER BY d.MaDonHang),
 @location BIGINT=(SELECT MIN(MaViTriLuuKho) FROM dbo.ViTriLuuKho WHERE MaKho=@warehouse AND DangHoatDong=1),@order BIGINT;
SET @i=1;
WHILE @i<=4
BEGIN
 INSERT dbo.DonHang(KyHieuDonHang,MaVanDon,MaBuuCuc,MaNguoiGui,MaNguoiNhan,MaLoaiDichVu,MaTrangThaiHienTai,MaKhoHienTai,ThoiGianSanSang,ThoiGianDuKienGiao,MucDoUuTien,TongKhoiLuongKg,MaTaiKhoanTao)
 SELECT CONCAT('QA-ROUTE-',@i),CONCAT('QA-ROUTE-',@i),@branch,MaNguoiGui,MaNguoiNhan,MaLoaiDichVu,
  (SELECT MaTrangThaiDonHang FROM dbo.TrangThaiDonHang WHERE KyHieuTrangThai='NEW'),@warehouse,SYSUTCDATETIME(),DATEADD(HOUR,8,SYSUTCDATETIME()),3,
  0,@admin FROM dbo.DonHang WHERE MaDonHang=@source;
 SET @order=SCOPE_IDENTITY();
 INSERT dbo.DiemGiaoNhan(MaDonHang,LoaiDiem,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc,ViDo,KinhDo)
 SELECT @order,LoaiDiem,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc,
  CASE WHEN @i%2=0 THEN 10.814300 ELSE 10.816000 END,CASE WHEN @i%2=0 THEN 106.603200 ELSE 106.598900 END
 FROM dbo.DiemGiaoNhan WHERE MaDonHang=@source;
 INSERT dbo.ChiTietDonHang(MaDonHang,TenHang,SoLuong,KhoiLuongDonViKg,ChieuDaiCm,ChieuRongCm,ChieuCaoCm)
 VALUES(@order,N'Hàng kiểm thử định tuyến',1,CASE WHEN @i=4 THEN 30 WHEN @i=3 THEN 7 ELSE 8 END,20,20,20);
 INSERT dbo.TonKhoDonHang(MaDonHang,MaKho,MaViTriLuuKho,TrangThaiTonKho,ThoiGianNhapKho,MaTaiKhoanCapNhatCuoi)
 VALUES(@order,@warehouse,@location,'STORED',SYSUTCDATETIME(),@admin);
 EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='CONFIRMED',@MaTaiKhoan=@admin,@LyDo=N'Isolated routing fixture',@NguonCapNhat='SYSTEM';
 EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='WAITING_ASSIGNMENT',@MaTaiKhoan=@admin,@LyDo=N'Isolated routing fixture',@NguonCapNhat='SYSTEM';
 SET @i+=1;
END;
'@
  $pickupMigration=Get-Content -Raw -Encoding utf8 "$PSScriptRoot/../../database/migrations/20261030_assignment_pickup_deadline.sql"
  Run ($pickupMigration.Replace("N'QLGiaoHangChangCuoi'", "N'$Database'"))
  Run ($pickupMigration.Replace("N'QLGiaoHangChangCuoi'", "N'$Database'"))
  $receiptMigration=Get-Content -Raw -Encoding utf8 "$PSScriptRoot/../../database/migrations/20261030_shipper_pickup_receipts.sql"
  Run ($receiptMigration.Replace("N'QLGiaoHangChangCuoi'", "N'$Database'"))
  Run ($receiptMigration.Replace("N'QLGiaoHangChangCuoi'", "N'$Database'"))
  $issueMigration=Get-Content -Raw -Encoding utf8 "$PSScriptRoot/../../database/migrations/20261030_shipper_pickup_issues.sql"
  Run ($issueMigration.Replace("N'QLGiaoHangChangCuoi'", "N'$Database'"))
  Run ($issueMigration.Replace("N'QLGiaoHangChangCuoi'", "N'$Database'"))
  Run (Get-Content -Raw -Encoding utf8 "$PSScriptRoot/../../database/migrations/20261019_auth_sessions.sql")
  # The production migration requires an exact database name. Substitute only
  # the already-validated isolated GUID name in this fixture-owned copy.
  $versionMigration=Get-Content -Raw -Encoding utf8 "$PSScriptRoot/../../database/migrations/20261019_shipper_vehicle_versions.sql"
  Run ($versionMigration.Replace("N'QLGiaoHangChangCuoi'", "N'$Database'"))
  $registrationMigration=Get-Content -Raw -Encoding utf8 "$PSScriptRoot/../../database/migrations/20261030_shipper_registrations.sql"
  Run ($registrationMigration.Replace("N'QLGiaoHangChangCuoi'", "N'$Database'"))
  Run "INSERT dbo.PhienDangNhap(MaPhien,MaTaiKhoan,ThoiGianTao,HetHanLuc) SELECT CONVERT(UNIQUEIDENTIFIER,CONVERT(BINARY(16),MaTaiKhoan)),MaTaiKhoan,SYSUTCDATETIME(),DATEADD(HOUR,2,SYSUTCDATETIME()) FROM dbo.TaiKhoan;"
 }
 if($Mode -eq 'WindowSchedule'){Run "UPDATE dbo.DonHang SET ThoiGianYeuCauGiao=DATEADD(HOUR,2,SYSUTCDATETIME()),ThoiGianDuKienGiao=DATEADD(HOUR,8,SYSUTCDATETIME()) WHERE KyHieuDonHang LIKE 'QA-ROUTE-%';"}
 if($Mode -eq 'ChangeRequestedTime'){Run "UPDATE dbo.DonHang SET ThoiGianYeuCauGiao=DATEADD(MINUTE,1,ThoiGianYeuCauGiao) WHERE KyHieuDonHang='QA-ROUTE-1';"}
 if($Mode -eq 'ChangeExpectedTime'){Run "UPDATE dbo.DonHang SET ThoiGianDuKienGiao=DATEADD(MINUTE,1,ThoiGianDuKienGiao) WHERE KyHieuDonHang='QA-ROUTE-1';"}
 if($Mode -eq 'InvalidSchedule'){Run "UPDATE dbo.DonHang SET ThoiGianYeuCauGiao=DATEADD(HOUR,9,SYSUTCDATETIME()),ThoiGianDuKienGiao=DATEADD(HOUR,8,SYSUTCDATETIME()) WHERE KyHieuDonHang='QA-ROUTE-1';"}
 if($Mode -eq 'NoDeadline'){Run "UPDATE dbo.DonHang SET ThoiGianDuKienGiao=NULL WHERE KyHieuDonHang LIKE 'QA-ROUTE-%';"}
 if($Mode -eq 'ResetSchedule'){Run "UPDATE dbo.DonHang SET ThoiGianYeuCauGiao=NULL,ThoiGianDuKienGiao=DATEADD(HOUR,8,SYSUTCDATETIME()) WHERE KyHieuDonHang LIKE 'QA-ROUTE-%';"}
 if($Mode -eq 'TamperTimings'){Run "UPDATE dbo.DispatchRoutePlan SET ResultJson=JSON_MODIFY(JSON_MODIFY(ResultJson,'$.routes[0].stops[0].waitingMinutes',0),'$.routes[0].stops[0].serviceStartAt','2000-01-01T00:00:00Z') WHERE ConfirmedJson IS NULL AND JSON_VALUE(ResultJson,'$.routes[0].stops[0].orderId') IS NOT NULL;"}
 if($Mode -eq 'ChangeOrder'){Run "UPDATE dbo.DonHang SET GhiChuDacBiet=N'QA version changed' WHERE MaVanDon='QA-ROUTE-1';"}
 if($Mode -eq 'CheckDepotScripts'){
  # Partial installation and re-running the additive migration retain warehouse data.
  Run "SELECT MaKho,ViDo,KinhDo,NguonToaDo INTO #DepotBefore FROM dbo.Kho; ALTER TABLE dbo.Kho DROP COLUMN NguonToaDo;"
  $migration=Get-Content -Raw -Encoding utf8 "$PSScriptRoot/../../database/migrations/20261017_dispatch_planning.sql"
  foreach($pass in 1..2){foreach($batch in [regex]::Split($migration,'(?im)^\s*GO\s*(?:--[^\r\n]*)?\r?$')){if($batch.Trim()){Run $batch}}}
  Run "IF EXISTS(SELECT MaKho,ViDo,KinhDo FROM dbo.Kho EXCEPT SELECT MaKho,ViDo,KinhDo FROM #DepotBefore) OR (SELECT COUNT(*) FROM dbo.Kho)<>(SELECT COUNT(*) FROM #DepotBefore) THROW 54999,'Migration changed warehouse data',1; UPDATE k SET NguonToaDo=b.NguonToaDo FROM dbo.Kho k JOIN #DepotBefore b ON b.MaKho=k.MaKho;"
  $template=Get-Content -Raw -Encoding utf8 "$PSScriptRoot/../../database/configure_warehouse_depot.sql"
  $template=$template.Replace("N'QLGiaoHangChangCuoi'", "N'$Database'")
  $refused=$false
  try{Run $template}catch{if($_.Exception.InnerException.Number -eq 54810){$refused=$true}else{throw}}
  if(-not $refused){throw 'Blank depot configuration template was not refused'}
  $configured=$template.Replace("= 'KHO-TP-PL'", "= 'KHO-BT-PL'")
  $configured=$configured.Replace('DECLARE @Latitude DECIMAL(9,6) = NULL;', 'DECLARE @Latitude DECIMAL(9,6) = (SELECT ViDo FROM dbo.Kho WHERE KyHieuKho=''KHO-BT-PL'');')
  $configured=$configured.Replace('DECLARE @Longitude DECIMAL(10,6) = NULL;', 'DECLARE @Longitude DECIMAL(10,6) = (SELECT KinhDo FROM dbo.Kho WHERE KyHieuKho=''KHO-BT-PL'');')
  $configured=$configured.Replace('DECLARE @Source NVARCHAR(300) = NULL;', 'DECLARE @Source NVARCHAR(300) = N''Verified synthetic SQL script fixture'';')
  $configured=$configured.Replace('DECLARE @AdminAccountId BIGINT = NULL;', 'DECLARE @AdminAccountId BIGINT = (SELECT MIN(t.MaTaiKhoan) FROM dbo.TaiKhoan t JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro WHERE v.KyHieuVaiTro=''ADMIN'');')
  $configured=$configured.Replace('DECLARE @CoordinatesConfirmed BIT = 0;', 'DECLARE @CoordinatesConfirmed BIT = 1;')
  $configured=$configured.Replace('DECLARE @ExpectedLatitude DECIMAL(9,6) = NULL;', 'DECLARE @ExpectedLatitude DECIMAL(9,6) = @Latitude;')
  $configured=$configured.Replace('DECLARE @ExpectedLongitude DECIMAL(10,6) = NULL;', 'DECLARE @ExpectedLongitude DECIMAL(10,6) = @Longitude;')
  $configured=$configured.Replace('DECLARE @ExpectedSource NVARCHAR(300) = NULL;', 'DECLARE @ExpectedSource NVARCHAR(300) = (SELECT NguonToaDo FROM dbo.Kho WHERE KyHieuKho=''KHO-BT-PL'');')
  Run "SELECT COUNT(*) n INTO #AuditBefore FROM dbo.NhatKyHoatDong WHERE LoaiThaoTac='UPDATE_WAREHOUSE_DEPOT';"
  Run $configured
  Run "IF (SELECT COUNT(*) FROM dbo.NhatKyHoatDong WHERE LoaiThaoTac='UPDATE_WAREHOUSE_DEPOT')<>(SELECT n+1 FROM #AuditBefore) THROW 54999,'Expected one depot audit entry',1; UPDATE k SET NguonToaDo=b.NguonToaDo FROM dbo.Kho k JOIN #DepotBefore b ON b.MaKho=k.MaKho; DROP TABLE #DepotBefore,#AuditBefore;"
 }
 if($Mode -eq 'DepotNoSource'){Run "UPDATE dbo.Kho SET NguonToaDo=NULL WHERE KyHieuKho IN('KHO-BT-PL','KHO-TP-PL');"}
 if($Mode -eq 'OffRoadDepot'){Run "UPDATE dbo.Kho SET ViDo=12,KinhDo=108 WHERE KyHieuKho='KHO-BT-PL';"}
 if($Mode -eq 'InvalidDepot'){Run "UPDATE dbo.Kho SET ViDo=0,KinhDo=0 WHERE KyHieuKho='KHO-BT-PL';"}
 if($Mode -eq 'NoDepot'){Run "UPDATE dbo.Kho SET ViDo=NULL,KinhDo=NULL WHERE KyHieuKho='KHO-BT-PL';"}
 if($Mode -eq 'RestoreDepot'){Run "UPDATE k SET ViDo=b.ViDo,KinhDo=b.KinhDo FROM dbo.Kho k JOIN dbo.BuuCuc b ON b.MaBuuCuc=k.MaBuuCuc WHERE k.KyHieuKho='KHO-BT-PL';"}
 if($Mode -eq 'LongLabels'){Run @'
UPDATE dbo.DonHang SET MaVanDon='LM-AF1CEB7CB6124AACB8FAE10C974006BB' WHERE KyHieuDonHang='QA-ROUTE-1';
UPDATE g SET TenNguoiLienHe=N'Nguyễn Thị Hoàng Phương Linh - Bộ phận tiếp nhận hàng hóa',
 DiaChi=N'Tầng 12, khu tiếp nhận hàng hóa, tòa nhà văn phòng phía sau cổng số 3, đường số 18B, phường Bình Hưng Hòa B, quận Bình Tân, Thành phố Hồ Chí Minh'
FROM dbo.DiemGiaoNhan g JOIN dbo.DonHang d ON d.MaDonHang=g.MaDonHang WHERE d.KyHieuDonHang LIKE 'QA-ROUTE-%' AND g.LoaiDiem='DELIVERY';
UPDATE kv SET TenKhuVuc=N'Khu vực giao hàng phường Bình Hưng Hòa B - tuyến nội đô và khu dân cư phía Tây'
FROM dbo.KhuVuc kv WHERE EXISTS(SELECT 1 FROM dbo.DiemGiaoNhan g JOIN dbo.DonHang d ON d.MaDonHang=g.MaDonHang WHERE d.KyHieuDonHang LIKE 'QA-ROUTE-%' AND g.LoaiDiem='DELIVERY' AND g.MaKhuVuc=kv.MaKhuVuc);
'@}
 if($Mode -eq 'HideDispatchSchema'){Run "EXEC sys.sp_rename N'dbo.DispatchRoutePlan', N'QA_HiddenDispatchRoutePlan';"}
 if($Mode -eq 'RestoreDispatchSchema'){Run "EXEC sys.sp_rename N'dbo.QA_HiddenDispatchRoutePlan', N'DispatchRoutePlan';"}
 $cmd=$connection.CreateCommand();$cmd.CommandText=@'
 SELECT(SELECT
  JSON_QUERY((SELECT MaKho id,KyHieuKho code,MaBuuCuc branchId,ViDo latitude,KinhDo longitude,NguonToaDo coordinateSource FROM dbo.Kho FOR JSON PATH,INCLUDE_NULL_VALUES)) depots,
  (SELECT MaKho FROM dbo.Kho WHERE KyHieuKho='KHO-BT-PL') warehouseId,
  (SELECT MaBuuCuc FROM dbo.BuuCuc WHERE KyHieuBuuCuc='HCM-BT01') branchId,
  JSON_QUERY((SELECT n.MaNhanVienGiaoHang id,t.MaTaiKhoan accountId,v.MaPhuongTien vehicleId,t.HoTen name
   FROM dbo.NhanVienGiaoHang n JOIN dbo.TaiKhoan t ON t.MaTaiKhoan=n.MaTaiKhoan JOIN dbo.PhanCongPhuongTien p ON p.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang AND p.ThoiGianKetThuc IS NULL
   JOIN dbo.PhuongTien v ON v.MaPhuongTien=p.MaPhuongTien WHERE n.MaNhanVien LIKE 'QA-DISPATCH-%' ORDER BY n.MaNhanVien FOR JSON PATH)) drivers,
  JSON_QUERY((SELECT d.MaDonHang id,d.MaVanDon trackingNumber,d.TongKhoiLuongKg weightKg,s.KyHieuTrangThai status,
   (SELECT COUNT(*) FROM dbo.PhanCongGiaoHang p WHERE p.MaDonHang=d.MaDonHang AND p.ThoiGianKetThuc IS NULL) activeAssignments
   FROM dbo.DonHang d JOIN dbo.TrangThaiDonHang s ON s.MaTrangThaiDonHang=d.MaTrangThaiHienTai WHERE d.KyHieuDonHang LIKE 'QA-ROUTE-%' ORDER BY d.KyHieuDonHang FOR JSON PATH)) orders,
  (SELECT COUNT(*) FROM dbo.ChuyenGiaoHang WHERE KyHieuChuyenGiao LIKE 'CG-%') tripCount,
  (SELECT COUNT(*) FROM dbo.PhanCongGiaoHang) assignmentCount
 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
'@
 $fixture|Add-Member -NotePropertyName testData -NotePropertyValue ($cmd.ExecuteScalar()|ConvertFrom-Json)
 [Console]::Write(($fixture|ConvertTo-Json -Depth 12 -Compress));$cmd.Dispose()
}finally{$connection.Dispose()}
