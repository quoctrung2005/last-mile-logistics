param([ValidateSet('Create','Inspect','ShiftCollection','PrepareUi','Drop')][string]$Mode='Create',[string]$Database)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if($Database -notmatch '^CodexAdmin_[a-f0-9]{32}$'){throw 'Only isolated GUID test databases allowed'}
$baseMode=if($Mode -in @('ShiftCollection','PrepareUi')){'Inspect'}else{$Mode}
$raw=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/admin-fixture.ps1" -Mode $baseMode -Database $Database
if($LASTEXITCODE -ne 0){throw 'Isolated fixture failed'}
$fixture=$raw|ConvertFrom-Json
if($Mode -eq 'Drop'){[Console]::Write('{"dropped":true}');exit}
$connection=New-Object System.Data.SqlClient.SqlConnection $fixture.connectionString
try{
 $connection.Open()
 if($Mode -eq 'ShiftCollection'){
  $cmd=$connection.CreateCommand();$cmd.CommandText="UPDATE c SET ThoiGianThuTien='2026-09-30T16:59:59' FROM dbo.ThuTienCOD c JOIN dbo.DonHang d ON d.MaDonHang=c.MaDonHang WHERE RIGHT(d.KyHieuDonHang,4)='0007';";try{[void]$cmd.ExecuteNonQuery()}finally{$cmd.Dispose()}
 }
 if($Mode -eq 'PrepareUi'){
  $cmd=$connection.CreateCommand();$cmd.CommandText=@'
UPDATE ds SET TrangThaiDoiSoat='CANCELLED' FROM dbo.DoiSoatCOD ds JOIN dbo.ChiTietDoiSoatCOD ct ON ct.MaDoiSoatCOD=ds.MaDoiSoatCOD
JOIN dbo.DonHang d ON d.MaDonHang=ct.MaDonHang WHERE RIGHT(d.KyHieuDonHang,4)='0007';
UPDATE n SET TrangThaiNop='CANCELLED' FROM dbo.NopTienCOD n JOIN dbo.ChiTietNopTienCOD ct ON ct.MaNopTienCOD=n.MaNopTienCOD
JOIN dbo.DonHang d ON d.MaDonHang=ct.MaDonHang WHERE RIGHT(d.KyHieuDonHang,4)='0007';
INSERT dbo.VaiTroQuyen(MaVaiTro,MaQuyen) SELECT v.MaVaiTro,q.MaQuyen FROM dbo.VaiTro v CROSS JOIN dbo.Quyen q
WHERE v.KyHieuVaiTro='ADMIN' AND q.KyHieuQuyen='COD_NOPTIEN' AND NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen x WHERE x.MaVaiTro=v.MaVaiTro AND x.MaQuyen=q.MaQuyen);
'@;try{[void]$cmd.ExecuteNonQuery()}finally{$cmd.Dispose()}
 }
 $cmd=$connection.CreateCommand();$cmd.CommandText=@'
SELECT (SELECT (SELECT d.MaDonHang AS id,d.KyHieuDonHang AS code,d.TienCOD AS cod,d.MaBuuCuc AS branchId,
 pc.MaNhanVienGiaoHang AS shipperId,n.MaTaiKhoan AS shipperAccountId
 FROM dbo.DonHang d OUTER APPLY(SELECT TOP(1) * FROM dbo.PhanCongGiaoHang p WHERE p.MaDonHang=d.MaDonHang ORDER BY p.MaPhanCongGiaoHang DESC) pc
 LEFT JOIN dbo.NhanVienGiaoHang n ON n.MaNhanVienGiaoHang=pc.MaNhanVienGiaoHang
 ORDER BY d.MaDonHang FOR JSON PATH,INCLUDE_NULL_VALUES) AS orders,
 (SELECT LoaiThaoTac AS action,TenDoiTuong AS objectType,MaDoiTuong AS objectId FROM dbo.NhatKyHoatDong
 WHERE LoaiThaoTac IN ('CREATE_COD_DEPOSIT','CONFIRM_COD_DEPOSIT','CREATE_COD_RECONCILIATION','CONFIRM_COD_RECONCILIATION') FOR JSON PATH) AS audit
 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
'@
 try{$data=$cmd.ExecuteScalar()|ConvertFrom-Json}finally{$cmd.Dispose()}
 $fixture|Add-Member -NotePropertyName codData -NotePropertyValue $data
 [Console]::Write(($fixture|ConvertTo-Json -Depth 10 -Compress))
}finally{$connection.Dispose()}
