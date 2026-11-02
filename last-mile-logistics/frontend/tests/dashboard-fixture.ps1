param([ValidateSet('Create','Inspect','HideStock','RestoreStock','NoGrants','LargeData','Drop')][string]$Mode='Create',[string]$Database)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if($Database -notmatch '^CodexAdmin_[a-f0-9]{32}$'){throw 'Isolated GUID test database only'}
$baseMode=if($Mode -in @('Create','Drop')){$Mode}else{'Inspect'}
$raw=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/admin-fixture.ps1" -Mode $baseMode -Database $Database
if($LASTEXITCODE -ne 0){throw 'Isolated fixture failed'}
$fixture=$raw|ConvertFrom-Json
if($Mode -eq 'Drop'){[Console]::Write('{"dropped":true}');exit}
$connection=[System.Data.SqlClient.SqlConnection]::new($fixture.connectionString)
function Run($sql){$command=$connection.CreateCommand();try{$command.CommandText=$sql;$command.CommandTimeout=120;[void]$command.ExecuteNonQuery()}finally{$command.Dispose()}}
try{
 $connection.Open()
 if($Mode -eq 'Create'){Run (Get-Content -LiteralPath "$PSScriptRoot/dashboard-fixture.sql" -Raw -Encoding UTF8)}
 if($Mode -eq 'LargeData'){Run (Get-Content -LiteralPath "$PSScriptRoot/dashboard-large-fixture.sql" -Raw -Encoding UTF8)}
 if($Mode -eq 'HideStock'){Run "EXEC sys.sp_rename N'dbo.TonKhoDonHang',N'QA_HiddenStock';"}
 if($Mode -eq 'RestoreStock'){Run "EXEC sys.sp_rename N'dbo.QA_HiddenStock',N'TonKhoDonHang';"}
 if($Mode -eq 'NoGrants'){Run "DELETE p FROM dbo.VaiTroQuyen p JOIN dbo.VaiTro r ON r.MaVaiTro=p.MaVaiTro WHERE r.KyHieuVaiTro='WAREHOUSE_STAFF';"}
 $command=$connection.CreateCommand();$command.CommandText=@'
DECLARE @start DATETIME2=DATEADD(HOUR,-7,CAST(CAST(DATEADD(HOUR,7,SYSUTCDATETIME()) AS DATE) AS DATETIME2));
SELECT(SELECT
 (SELECT MaBuuCuc FROM dbo.BuuCuc WHERE KyHieuBuuCuc='QA-EMPTY') emptyBranchId,
 JSON_QUERY((SELECT MaBuuCuc id,TenBuuCuc name FROM dbo.BuuCuc ORDER BY MaBuuCuc FOR JSON PATH)) branches,
 JSON_QUERY((SELECT d.MaDonHang id,d.KyHieuDonHang code,d.MaBuuCuc branchId,s.KyHieuTrangThai status FROM dbo.DonHang d JOIN dbo.TrangThaiDonHang s ON s.MaTrangThaiDonHang=d.MaTrangThaiHienTai WHERE d.KyHieuDonHang LIKE 'QA-DASH-%' ORDER BY d.KyHieuDonHang FOR JSON PATH)) orders,
 (SELECT COUNT_BIG(*) FROM dbo.LanGiaoHang WHERE ThoiGianThuGiao>=@start AND ThoiGianThuGiao<DATEADD(DAY,1,@start)) attemptCount,
 (SELECT COUNT_BIG(*) FROM dbo.LanGiaoHang WHERE ThoiGianThuGiao>=@start AND ThoiGianThuGiao<DATEADD(DAY,1,@start) AND KetQua='SUCCESS') successfulCount,
 (SELECT COUNT_BIG(*) FROM dbo.LanGiaoHang WHERE ThoiGianThuGiao>=@start AND ThoiGianThuGiao<DATEADD(DAY,1,@start) AND KetQua='FAILED') failedCount,
 (SELECT COUNT_BIG(*) FROM dbo.PhanCongGiaoHang) assignmentCount,
 (SELECT COUNT_BIG(*) FROM dbo.YeuCauGiaoLaiHoacHoan) resolutionCount,
 (SELECT COUNT_BIG(*) FROM dbo.NopTienCOD WHERE TrangThaiNop='PENDING') pendingDeposits,
 (SELECT COUNT_BIG(*) FROM dbo.NopTienCOD WHERE TrangThaiNop='CONFIRMED') confirmedDeposits
 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
'@
 $fixture|Add-Member -NotePropertyName dashboardData -NotePropertyValue ($command.ExecuteScalar()|ConvertFrom-Json)
 $command.Dispose();[Console]::Write(($fixture|ConvertTo-Json -Depth 10 -Compress))
}finally{$connection.Dispose()}
