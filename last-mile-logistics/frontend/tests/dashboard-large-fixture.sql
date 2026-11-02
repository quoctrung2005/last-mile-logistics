-- Only executed by the GUID-database harness; exercises actual COUNT_BIG responses.
SET XACT_ABORT ON;
BEGIN TRAN;
DECLARE @source BIGINT=(SELECT MIN(MaDonHang) FROM dbo.DonHang),@branch INT;
SELECT @branch=MaBuuCuc FROM dbo.DonHang WHERE MaDonHang=@source;
UPDATE dbo.BuuCuc SET TenBuuCuc=LEFT(REPLICATE(N'Bưu cục trung tâm tiếp nhận và điều phối hàng hóa khu vực mở rộng ',3),140) WHERE MaBuuCuc=@branch;
;WITH n AS(SELECT TOP(1000) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT dbo.DonHang(KyHieuDonHang,MaVanDon,MaBuuCuc,MaNguoiGui,MaNguoiNhan,MaLoaiDichVu,MaTrangThaiHienTai,TongKhoiLuongKg,ThoiGianTao,MaTaiKhoanTao)
SELECT CONCAT('QA-LARGE-',n.n),CONCAT('QA-LARGE-',n.n),@branch,d.MaNguoiGui,d.MaNguoiNhan,d.MaLoaiDichVu,
 (SELECT MaTrangThaiDonHang FROM dbo.TrangThaiDonHang WHERE KyHieuTrangThai='NEW'),0,DATEADD(DAY,-4,SYSUTCDATETIME()),d.MaTaiKhoanTao
FROM n CROSS JOIN dbo.DonHang d WHERE d.MaDonHang=@source;
INSERT dbo.DiemGiaoNhan(MaDonHang,LoaiDiem,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc)
SELECT d.MaDonHang,p.LoaiDiem,p.TenNguoiLienHe,p.SoDienThoaiLienHe,p.DiaChi,p.MaKhuVuc
FROM dbo.DonHang d CROSS JOIN dbo.DiemGiaoNhan p WHERE d.KyHieuDonHang LIKE 'QA-LARGE-%' AND p.MaDonHang=@source;
INSERT dbo.ChiTietDonHang(MaDonHang,TenHang,SoLuong,KhoiLuongDonViKg)
SELECT MaDonHang,N'Isolated large dashboard fixture',1,1 FROM dbo.DonHang WHERE KyHieuDonHang LIKE 'QA-LARGE-%';
UPDATE dbo.DonHang SET MaTrangThaiHienTai=(SELECT MaTrangThaiDonHang FROM dbo.TrangThaiDonHang WHERE KyHieuTrangThai='CONFIRMED') WHERE KyHieuDonHang LIKE 'QA-LARGE-%';
COMMIT;
