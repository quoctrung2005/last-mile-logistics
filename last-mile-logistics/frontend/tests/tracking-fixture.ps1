param([ValidateSet('Create','Inspect','NoGps','StaleGps','Drop')][string]$Mode='Create', [string]$Database)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if($Database -notmatch '^CodexAdmin_[a-f0-9]{32}$'){throw 'Isolated test databases only'}
$baseMode=if($Mode -in @('NoGps','StaleGps')){'Inspect'}else{$Mode}
$raw=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/admin-fixture.ps1" -Mode $baseMode -Database $Database
if($LASTEXITCODE -ne 0){throw 'Isolated fixture failed'}
$fixture=$raw|ConvertFrom-Json
if($Mode -eq 'Drop'){[Console]::Write('{"dropped":true}');exit}
$connection=New-Object System.Data.SqlClient.SqlConnection $fixture.connectionString
try{
 $connection.Open()
 $cmd=$connection.CreateCommand()
 if($Mode -eq 'Create'){
  $cmd.CommandText=@'
INSERT dbo.LanGiaoHang(MaDonHang,MaPhanCongGiaoHang,SoLanThu,ThoiGianThuGiao,KetQua,MaLyDoGiaoThatBai,GhiChu,MaTaiKhoanGhiNhan)
SELECT TOP(1) l.MaDonHang,l.MaPhanCongGiaoHang,l.SoLanThu+1,DATEADD(SECOND,1,l.ThoiGianThuGiao),'FAILED',l.MaLyDoGiaoThatBai,N'QA second failed delivery',l.MaTaiKhoanGhiNhan
FROM dbo.LanGiaoHang l WHERE l.KetQua='FAILED' AND NOT EXISTS(SELECT 1 FROM dbo.LanGiaoHang x WHERE x.MaDonHang=l.MaDonHang AND x.SoLanThu>l.SoLanThu)
ORDER BY l.MaLanGiaoHang;
'@
  [void]$cmd.ExecuteNonQuery()
 }
 if($Mode -eq 'NoGps'){$cmd.CommandText='UPDATE dbo.NhanVienGiaoHang SET ViDoHienTai=NULL,KinhDoHienTai=NULL,ThoiGianCapNhatViTri=NULL;';[void]$cmd.ExecuteNonQuery()}
 if($Mode -eq 'StaleGps'){$cmd.CommandText='UPDATE dbo.NhanVienGiaoHang SET ViDoHienTai=10.7987,KinhDoHienTai=106.6221,ThoiGianCapNhatViTri=DATEADD(HOUR,-2,SYSUTCDATETIME());';[void]$cmd.ExecuteNonQuery()}
 $cmd.CommandText=@'
SELECT (SELECT (SELECT d.MaDonHang AS id,d.KyHieuDonHang AS code,d.MaVanDon AS trackingNumber,d.MaBuuCuc AS branchId,t.KyHieuTrangThai AS status,
 (SELECT TOP(1) pc.MaNhanVienGiaoHang FROM dbo.PhanCongGiaoHang pc WHERE pc.MaDonHang=d.MaDonHang AND pc.ThoiGianKetThuc IS NULL ORDER BY pc.MaPhanCongGiaoHang DESC) AS shipperId,
 (SELECT COUNT(*) FROM dbo.LanGiaoHang l WHERE l.MaDonHang=d.MaDonHang) AS attempts
 FROM dbo.DonHang d JOIN dbo.TrangThaiDonHang t ON t.MaTrangThaiDonHang=d.MaTrangThaiHienTai ORDER BY d.MaDonHang FOR JSON PATH,INCLUDE_NULL_VALUES) AS orders,
 (SELECT COUNT(*) FROM dbo.NhatKyHoatDong) AS auditCount,
 (SELECT SUM(CONVERT(BIGINT,d.PhienBan)) FROM dbo.DonHang d) AS versionSum
 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
'@
 $fixture|Add-Member -NotePropertyName trackingData -NotePropertyValue ($cmd.ExecuteScalar()|ConvertFrom-Json)
 [Console]::Write(($fixture|ConvertTo-Json -Depth 12 -Compress))
 $cmd.Dispose()
}finally{$connection.Dispose()}
