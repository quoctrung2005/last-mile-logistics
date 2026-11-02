param(
    [ValidateSet('Create','Inspect','Deny','Grant','FailInsert','RestoreInsert','Drop')][string]$Mode='Create',
    [Parameter(Mandatory=$true)][string]$Database
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if ($Database -notmatch '^CodexAccounts_[a-f0-9]{32}$') { throw 'Isolated GUID test database required' }
$baseMode=if($Mode -in @('Create','Drop')){$Mode}else{'Inspect'}
$raw=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/accounts-fixture.ps1" -Mode $baseMode -Database $Database
if($LASTEXITCODE -ne 0){throw 'Isolated fixture failed'}
if($Mode -eq 'Drop'){[Console]::Write('{"dropped":true}');exit}
$fixture=$raw|ConvertFrom-Json
$connection=New-Object System.Data.SqlClient.SqlConnection $fixture.connectionString
function Run([string]$sql) {
    $cmd=$connection.CreateCommand()
    try {$cmd.CommandText=$sql;[void]$cmd.ExecuteNonQuery()} finally {$cmd.Dispose()}
}
function Json([string]$sql) {
    $cmd=$connection.CreateCommand()
    try {
        $cmd.CommandText=$sql
        $value=$cmd.ExecuteScalar()
        if($null -eq $value -or $value -is [DBNull] -or [string]::IsNullOrWhiteSpace([string]$value)){return @()}
        return ($value|ConvertFrom-Json)
    } finally {$cmd.Dispose()}
}
try {
    $connection.Open()
    if($Mode -eq 'Deny') {Run @'
DELETE vq FROM dbo.VaiTroQuyen vq JOIN dbo.VaiTro v ON v.MaVaiTro=vq.MaVaiTro
JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE v.KyHieuVaiTro='SHIPPER' AND q.KyHieuQuyen='BANGCHUNG_TAO';
'@}
    if($Mode -eq 'Grant') {Run @'
INSERT dbo.VaiTroQuyen(MaVaiTro,MaQuyen) SELECT v.MaVaiTro,q.MaQuyen FROM dbo.VaiTro v CROSS JOIN dbo.Quyen q
WHERE v.KyHieuVaiTro='SHIPPER' AND q.KyHieuQuyen='BANGCHUNG_TAO'
AND NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen x WHERE x.MaVaiTro=v.MaVaiTro AND x.MaQuyen=q.MaQuyen);
'@}
    if($Mode -eq 'FailInsert') {Run @'
CREATE TRIGGER dbo.QA_Evidence_Failure ON dbo.BangChungGiaoHang AFTER INSERT AS
BEGIN THROW 57003, N'Controlled isolated insert failure', 1; END;
'@}
    if($Mode -eq 'RestoreInsert') {Run 'DROP TRIGGER IF EXISTS dbo.QA_Evidence_Failure;'}
    $attempts=Json @'
SELECT lg.MaLanGiaoHang id,lg.MaDonHang orderId,nv.MaTaiKhoan accountId
FROM dbo.LanGiaoHang lg JOIN dbo.PhanCongGiaoHang pc ON pc.MaPhanCongGiaoHang=lg.MaPhanCongGiaoHang
JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang=pc.MaNhanVienGiaoHang ORDER BY lg.MaLanGiaoHang FOR JSON PATH;
'@
    $counts=Json @'
SELECT (SELECT COUNT_BIG(*) FROM dbo.BangChungGiaoHang) evidence,
(SELECT COUNT_BIG(*) FROM dbo.NhatKyHoatDong WHERE LoaiThaoTac='UPLOAD_DELIVERY_EVIDENCE') uploads
FOR JSON PATH,WITHOUT_ARRAY_WRAPPER;
'@
    $files=Json @'
SELECT bc.MaBangChung id,bc.DuongDanTep path FROM dbo.BangChungGiaoHang bc
WHERE EXISTS(SELECT 1 FROM dbo.NhatKyHoatDong n WHERE n.LoaiThaoTac='UPLOAD_DELIVERY_EVIDENCE'
AND n.MaDoiTuong=CONVERT(VARCHAR(100),bc.MaBangChung)) FOR JSON PATH;
'@
    [Console]::Write((@{connectionString=$fixture.connectionString;actors=$fixture.actors;attempts=@($attempts);counts=$counts;files=@($files)}|ConvertTo-Json -Depth 8 -Compress))
} finally {$connection.Dispose()}
