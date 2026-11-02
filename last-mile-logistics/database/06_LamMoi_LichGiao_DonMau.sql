/* Lịch mẫu cho kiểm thử điều phối: đơn còn hạn được giao trong 7 ngày tới.
   Đơn đã quá hạn giữ nguyên, chờ CSKH xác nhận tiếp tục giao hoặc hủy.
   Không xóa đơn/lịch sử, không đổi lịch đơn đã phân công hoặc thuộc chuyến mở.
*/
USE QLGiaoHangChangCuoi;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
BEGIN TRY
 BEGIN TRAN;
 DECLARE @Now DATETIME2(0)=SYSUTCDATETIME(),@Actor BIGINT;
 SELECT TOP(1) @Actor=t.MaTaiKhoan FROM dbo.TaiKhoan t JOIN dbo.VaiTro r ON r.MaVaiTro=t.MaVaiTro
 WHERE r.KyHieuVaiTro='ADMIN' AND r.DangHoatDong=1 AND t.TrangThaiTaiKhoan='ACTIVE'
 AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=@Now) ORDER BY t.MaTaiKhoan;
 IF @Actor IS NULL THROW 52060,N'Thiếu tài khoản quản trị mẫu.',1;
 SELECT d.MaDonHang,d.ThoiGianSanSang,d.ThoiGianYeuCauGiao,d.ThoiGianDuKienGiao INTO #Schedule
 FROM dbo.DonHang d WITH(UPDLOCK,HOLDLOCK) JOIN dbo.TrangThaiDonHang t ON t.MaTrangThaiDonHang=d.MaTrangThaiHienTai
 WHERE (d.KyHieuDonHang LIKE 'DH-HCM-261023-BULK-%' OR d.KyHieuDonHang LIKE 'DH-HCM-261002-%')
 AND t.KyHieuTrangThai='WAITING_ASSIGNMENT'
 AND d.ThoiGianDuKienGiao>=@Now AND d.ThoiGianDuKienGiao<DATEADD(DAY,6,@Now)
 AND NOT EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang p WHERE p.MaDonHang=d.MaDonHang AND p.ThoiGianKetThuc IS NULL)
 AND NOT EXISTS(SELECT 1 FROM dbo.ChiTietChuyenGiao c JOIN dbo.ChuyenGiaoHang trip ON trip.MaChuyenGiao=c.MaChuyenGiao WHERE c.MaDonHang=d.MaDonHang AND trip.TrangThaiChuyen NOT IN('COMPLETED','CANCELLED'));
 INSERT dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuCuJson,DuLieuMoiJson)
 SELECT @Actor,'REFRESH_DEMO_SCHEDULE','DonHang',CONVERT(VARCHAR(100),s.MaDonHang),
 (SELECT s.ThoiGianSanSang readyAt,s.ThoiGianYeuCauGiao earliestAt,s.ThoiGianDuKienGiao deadline FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER),
 (SELECT DATEADD(MINUTE,-30,@Now) readyAt,@Now earliestAt,DATEADD(DAY,7,@Now) deadline FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
 FROM #Schedule s;
 UPDATE d SET ThoiGianSanSang=DATEADD(MINUTE,-30,@Now),ThoiGianYeuCauGiao=@Now,
 ThoiGianDuKienGiao=DATEADD(DAY,7,@Now),MaTaiKhoanCapNhatCuoi=@Actor,ThoiGianCapNhat=@Now
 FROM dbo.DonHang d JOIN #Schedule s ON s.MaDonHang=d.MaDonHang;
 SELECT COUNT(*) refreshedDemoOrders FROM #Schedule;
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
