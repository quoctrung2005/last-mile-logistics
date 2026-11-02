param([ValidateSet('Create','Inspect','ManyRows','Drop')][string]$Mode='Create', [string]$Database)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if ($Database -notmatch '^CodexAdmin_[a-f0-9]{32}$') {throw 'Only isolated GUID test databases allowed'}
$baseMode = if ($Mode -eq 'ManyRows') {'Inspect'} else {$Mode}
$raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/admin-fixture.ps1" -Mode $baseMode -Database $Database
if ($LASTEXITCODE -ne 0) {throw 'Isolated fixture setup failed'}
$fixture = $raw | ConvertFrom-Json
if ($Mode -eq 'Drop') { [Console]::Write('{"dropped":true}');exit }
$connection=New-Object System.Data.SqlClient.SqlConnection $fixture.connectionString
try {
  $connection.Open()
  if ($Mode -eq 'Create') {
    $cmd=$connection.CreateCommand();$cmd.CommandText=Get-Content -Raw -Encoding UTF8 "$PSScriptRoot/reports-fixture.sql"
    try{[void]$cmd.ExecuteNonQuery()}finally{$cmd.Dispose()}
  }
  if ($Mode -eq 'ManyRows') {
    $cmd=$connection.CreateCommand();$cmd.CommandText=@'
SET XACT_ABORT ON;
BEGIN TRAN;
DECLARE @Role INT=(SELECT MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='SHIPPER'),
 @Order BIGINT=(SELECT MIN(MaDonHang) FROM dbo.DonHang), @Branch INT,
 @Actor BIGINT=(SELECT MIN(MaTaiKhoan) FROM dbo.TaiKhoan), @Index INT=1, @Account BIGINT,@Shipper BIGINT;
SELECT @Branch=MaBuuCuc FROM dbo.DonHang WHERE MaDonHang=@Order;
WHILE @Index<=24
BEGIN
 INSERT dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,MaVaiTro,MaBuuCuc)
 VALUES('QA-REPORT-'+CONVERT(VARCHAR,@Index),'qa.report.'+CONVERT(VARCHAR,@Index),'QA_FIXTURE_NOT_A_PASSWORD',N'Nhân viên kiểm tra '+CONVERT(NVARCHAR,@Index),@Role,@Branch);
 SET @Account=SCOPE_IDENTITY();
 INSERT dbo.NhanVienGiaoHang(MaTaiKhoan,MaNhanVien) VALUES(@Account,'QA-REPORT-'+CONVERT(VARCHAR,@Index));
 SET @Shipper=SCOPE_IDENTITY();
 INSERT dbo.PhanCongGiaoHang(MaDonHang,MaNhanVienGiaoHang,MaTaiKhoanPhanCong,ThoiGianPhanCong,ThoiGianKetThuc,TrangThaiPhanCong)
 VALUES(@Order,@Shipper,@Actor,'2026-09-10T02:00:00','2026-09-10T03:00:00','CANCELLED');
 SET @Index+=1;
END;
COMMIT;
'@
    try{[void]$cmd.ExecuteNonQuery()}finally{$cmd.Dispose()}
  }
  $cmd=$connection.CreateCommand();$cmd.CommandText=@'
SELECT (SELECT MaBuuCuc AS id,TenBuuCuc AS name FROM dbo.BuuCuc ORDER BY MaBuuCuc FOR JSON PATH) AS branches,
 (SELECT MaNhanVienGiaoHang AS id,MaTaiKhoan AS accountId FROM dbo.NhanVienGiaoHang ORDER BY MaNhanVienGiaoHang FOR JSON PATH) AS shippers,
 JSON_QUERY((SELECT COUNT_BIG(*) AS orderCount,SUM(PhiVanChuyen) AS fees FROM dbo.DonHang FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) AS totals
FOR JSON PATH,WITHOUT_ARRAY_WRAPPER
'@
  try{$extra=$cmd.ExecuteScalar()|ConvertFrom-Json}finally{$cmd.Dispose()}
  $fixture | Add-Member -NotePropertyName reportData -NotePropertyValue $extra
  [Console]::Write(($fixture|ConvertTo-Json -Depth 9 -Compress))
}finally{$connection.Dispose()}
