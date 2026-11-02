-- Executed only in the GUID test database made by reports-fixture.ps1.
SET XACT_ABORT ON;
BEGIN TRAN;
INSERT dbo.VaiTroQuyen(MaVaiTro,MaQuyen)
SELECT v.MaVaiTro,q.MaQuyen FROM dbo.VaiTro v CROSS JOIN dbo.Quyen q
WHERE v.KyHieuVaiTro='BRANCH_MANAGER' AND q.KyHieuQuyen='BAOCAO_XEM'
AND NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen x WHERE x.MaVaiTro=v.MaVaiTro AND x.MaQuyen=q.MaQuyen);

UPDATE dbo.DonHang SET ThoiGianTao=CASE RIGHT(KyHieuDonHang,4)
 WHEN '0001' THEN '2026-09-09T16:59:59' WHEN '0002' THEN '2026-09-09T17:00:00'
 WHEN '0003' THEN '2026-09-10T16:59:59' ELSE '2026-09-10T17:00:00' END;
UPDATE dbo.PhanCongGiaoHang SET ThoiGianPhanCong='2026-09-10T00:00:00';
UPDATE dbo.LanGiaoHang SET ThoiGianThuGiao='2026-09-10T01:00:00';
UPDATE dbo.ThuTienCOD SET ThoiGianThuTien=CASE WHEN MaDonHang=(SELECT MaDonHang FROM dbo.DonHang WHERE RIGHT(KyHieuDonHang,4)='0003') THEN '2026-09-10T00:00:00' ELSE '2026-09-09T00:00:00' END;
UPDATE dbo.NopTienCOD SET ThoiGianNop='2026-09-10T01:00:00',ThoiGianXacNhan='2026-09-10T02:00:00';
-- Leave 79,999.75 outstanding, fully reserved by a pending deposit. Rejected/cancelled
-- proposals for that same amount must not reduce the balance or available amount.
UPDATE dbo.ChiTietNopTienCOD SET SoTienPhanBo=340000.25
WHERE MaDonHang=(SELECT MaDonHang FROM dbo.DonHang WHERE RIGHT(KyHieuDonHang,4)='0003');
UPDATE dbo.NopTienCOD SET SoTienNop=600000.25;
DECLARE @OriginalDeposit BIGINT=(SELECT MIN(MaNopTienCOD) FROM dbo.NopTienCOD);
INSERT dbo.NopTienCOD(KyHieuNopTien,MaNhanVienGiaoHang,MaBuuCuc,SoTienNop,PhuongThucNop,TrangThaiNop,ThoiGianNop)
SELECT 'QA-'+v.status, d.MaNhanVienGiaoHang,d.MaBuuCuc,79999.75,'CASH',v.status,'2026-09-10T03:00:00'
FROM dbo.NopTienCOD d CROSS JOIN (VALUES('PENDING'),('REJECTED'),('CANCELLED')) v(status)
WHERE d.MaNopTienCOD=@OriginalDeposit;
INSERT dbo.ChiTietNopTienCOD(MaNopTienCOD,MaDonHang,SoTienPhanBo)
SELECT n.MaNopTienCOD,d.MaDonHang,79999.75 FROM dbo.NopTienCOD n CROSS JOIN dbo.DonHang d
WHERE n.KyHieuNopTien LIKE 'QA-%' AND RIGHT(d.KyHieuDonHang,4)='0003';

DECLARE @Actor BIGINT=(SELECT MIN(MaTaiKhoan) FROM dbo.TaiKhoan),
 @Shipper BIGINT=(SELECT MAX(MaNhanVienGiaoHang) FROM dbo.NhanVienGiaoHang),
 @Order BIGINT=(SELECT MaDonHang FROM dbo.DonHang WHERE RIGHT(KyHieuDonHang,4)='0001');
-- A later assignee with no attempt must not inherit the previous assignee's success.
INSERT dbo.PhanCongGiaoHang(MaDonHang,MaNhanVienGiaoHang,MaTaiKhoanPhanCong,ThoiGianPhanCong,ThoiGianKetThuc,TrangThaiPhanCong)
VALUES(@Order,@Shipper,@Actor,'2026-09-10T02:00:00','2026-09-10T03:00:00','CANCELLED');
SET @Order=(SELECT MaDonHang FROM dbo.DonHang WHERE RIGHT(KyHieuDonHang,4)='0005');
SET @Shipper=(SELECT MIN(MaNhanVienGiaoHang) FROM dbo.NhanVienGiaoHang);
INSERT dbo.PhanCongGiaoHang(MaDonHang,MaNhanVienGiaoHang,MaTaiKhoanPhanCong,ThoiGianPhanCong,ThoiGianChapNhan,ThoiGianKetThuc,TrangThaiPhanCong)
VALUES(@Order,@Shipper,@Actor,'2026-09-10T02:00:00','2026-09-10T02:10:00','2026-09-10T03:00:00','ATTEMPT_FAILED');
DECLARE @Assignment BIGINT=SCOPE_IDENTITY(),@Reason INT=(SELECT MIN(MaLyDoGiaoThatBai) FROM dbo.LyDoGiaoThatBai);
INSERT dbo.LanGiaoHang(MaDonHang,MaPhanCongGiaoHang,SoLanThu,ThoiGianThuGiao,KetQua,MaLyDoGiaoThatBai,MaTaiKhoanGhiNhan)
VALUES(@Order,@Assignment,2,'2026-09-10T03:00:00','FAILED',@Reason,@Actor);
UPDATE dbo.TaiKhoan SET HoTen=N'=SUM(1,2), "Nhân viên"' WHERE MaTaiKhoan=(SELECT MaTaiKhoan FROM dbo.NhanVienGiaoHang WHERE MaNhanVienGiaoHang=@Shipper);
COMMIT;
