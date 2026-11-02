-- Test data only; the PowerShell caller enforces the GUID database name.
SET XACT_ABORT ON;
BEGIN TRAN;
DECLARE @start DATETIME2=DATEADD(HOUR,-7,CAST(CAST(DATEADD(HOUR,7,SYSUTCDATETIME()) AS DATE) AS DATETIME2));
UPDATE dbo.DonHang SET ThoiGianTao=DATEADD(DAY,-5,@start);
;WITH numbered AS(SELECT MaLanGiaoHang,ROW_NUMBER()OVER(ORDER BY MaLanGiaoHang) n FROM dbo.LanGiaoHang)
UPDATE g SET ThoiGianThuGiao=CASE n.n WHEN 1 THEN DATEADD(SECOND,-1,@start) WHEN 2 THEN @start WHEN 3 THEN DATEADD(SECOND,-1,DATEADD(DAY,1,@start)) WHEN 4 THEN DATEADD(DAY,1,@start) ELSE DATEADD(DAY,-1,@start) END
FROM dbo.LanGiaoHang g JOIN numbered n ON n.MaLanGiaoHang=g.MaLanGiaoHang;
INSERT dbo.BuuCuc(KyHieuBuuCuc,TenBuuCuc,MaKhuVuc,DiaChi)
SELECT TOP(1)'QA-EMPTY',N'Bưu cục kiểm thử chưa có dữ liệu',MaKhuVuc,DiaChi FROM dbo.BuuCuc;
DECLARE @source BIGINT=(SELECT MIN(MaDonHang) FROM dbo.DonHang),@branch INT,@actor BIGINT=(SELECT MIN(MaTaiKhoan) FROM dbo.TaiKhoan),
 @shipper BIGINT=(SELECT MIN(MaNhanVienGiaoHang) FROM dbo.NhanVienGiaoHang),@shipperAccount BIGINT,@order BIGINT,@assignment BIGINT,@i INT=1,@reason INT=(SELECT MIN(MaLyDoGiaoThatBai) FROM dbo.LyDoGiaoThatBai WHERE DangHoatDong=1 AND BatBuocMinhChung=0);
SELECT @shipperAccount=MaTaiKhoan FROM dbo.NhanVienGiaoHang WHERE MaNhanVienGiaoHang=@shipper;
SELECT @branch=MaBuuCuc FROM dbo.DonHang WHERE MaDonHang=@source;
WHILE @i<=8
BEGIN
 INSERT dbo.DonHang(KyHieuDonHang,MaVanDon,MaBuuCuc,MaNguoiGui,MaNguoiNhan,MaLoaiDichVu,MaTrangThaiHienTai,TongKhoiLuongKg,ThoiGianTao,ThoiGianDuKienGiao,MaTaiKhoanTao)
 SELECT CONCAT('QA-DASH-',@i),CASE WHEN @i=2 THEN 'LM-AF1CEB7CB6124AACB8FAE10C974006BB' ELSE CONCAT('QA-DASH-',@i) END,@branch,MaNguoiGui,MaNguoiNhan,MaLoaiDichVu,
 (SELECT MaTrangThaiDonHang FROM dbo.TrangThaiDonHang WHERE KyHieuTrangThai='NEW'),0,DATEADD(DAY,-4,@start),CASE WHEN @i=3 THEN NULL ELSE DATEADD(HOUR,-2,SYSUTCDATETIME()) END,@actor
 FROM dbo.DonHang WHERE MaDonHang=@source;
 SET @order=SCOPE_IDENTITY();
 INSERT dbo.DiemGiaoNhan(MaDonHang,LoaiDiem,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc)
 SELECT @order,LoaiDiem,N'Nguyễn Thị Hoàng Phương Linh - bộ phận tiếp nhận hàng hóa',SoDienThoaiLienHe,DiaChi,MaKhuVuc FROM dbo.DiemGiaoNhan WHERE MaDonHang=@source;
 INSERT dbo.ChiTietDonHang(MaDonHang,TenHang,SoLuong,KhoiLuongDonViKg)VALUES(@order,N'Kiểm thử Tổng quan',1,2);
 EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='CONFIRMED',@MaTaiKhoan=@actor,@LyDo=N'Isolated dashboard fixture';
 IF @i>1 EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='WAITING_ASSIGNMENT',@MaTaiKhoan=@actor,@LyDo=N'Isolated dashboard fixture';
 IF @i=8
 BEGIN
  INSERT dbo.PhanCongGiaoHang(MaDonHang,MaNhanVienGiaoHang,MaTaiKhoanPhanCong,TrangThaiPhanCong)
  VALUES(@order,@shipper,@actor,'PENDING');
  EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='ASSIGNED',@MaTaiKhoan=@actor,@LyDo=N'Isolated dashboard handover';
 END;
 IF @i BETWEEN 4 AND 7
 BEGIN
  INSERT dbo.PhanCongGiaoHang(MaDonHang,MaNhanVienGiaoHang,MaTaiKhoanPhanCong,ThoiGianPhanCong,ThoiGianChapNhan,TrangThaiPhanCong)
  VALUES(@order,@shipper,@actor,DATEADD(DAY,-2,@start),DATEADD(DAY,-2,@start),'IN_PROGRESS');SET @assignment=SCOPE_IDENTITY();
  EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='ASSIGNED',@MaTaiKhoan=@actor,@LyDo=N'Isolated dashboard fixture';
  EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='HANDED_OVER',@MaTaiKhoan=@actor,@LyDo=N'Isolated dashboard fixture';
  EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='PICKED_UP',@MaTaiKhoan=@actor,@LyDo=N'Isolated dashboard fixture';
  EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='IN_DELIVERY',@MaTaiKhoan=@actor,@LyDo=N'Isolated dashboard fixture';
  EXEC dbo.sp_XacNhanGiaoHangThatBai @MaDonHang=@order,@MaNhanVienGiaoHang=@shipper,@MaTaiKhoan=@shipperAccount,@MaLyDoGiaoThatBai=@reason,@GhiChu=N'Isolated dashboard failure';
  UPDATE dbo.LanGiaoHang SET ThoiGianThuGiao=DATEADD(HOUR,1,@start) WHERE MaDonHang=@order;
  IF @i IN(5,6,7)
   INSERT dbo.YeuCauGiaoLaiHoacHoan(MaDonHang,LoaiYeuCau,TrangThaiYeuCau,MaBuuCucHoan,LyDo,MaTaiKhoanYeuCau,ThoiGianYeuCau,ThoiGianHoanTat)
   VALUES(@order,'RETURN',CASE @i WHEN 5 THEN 'APPROVED' ELSE 'COMPLETED' END,@branch,N'Isolated resolution',@actor,
    CASE WHEN @i=7 THEN DATEADD(DAY,-1,@start) ELSE DATEADD(HOUR,2,@start) END,
    CASE WHEN @i=5 THEN NULL WHEN @i=7 THEN DATEADD(HOUR,-1,@start) ELSE DATEADD(HOUR,3,@start) END);
  IF @i=7 INSERT dbo.LanGiaoHang(MaDonHang,MaPhanCongGiaoHang,SoLanThu,ThoiGianThuGiao,KetQua,MaLyDoGiaoThatBai,MaTaiKhoanGhiNhan)
   VALUES(@order,@assignment,2,DATEADD(HOUR,2,@start),'FAILED',@reason,@actor);
 END;
 SET @i+=1;
END;
INSERT dbo.NopTienCOD(KyHieuNopTien,MaNhanVienGiaoHang,MaBuuCuc,SoTienNop,PhuongThucNop,TrangThaiNop,ThoiGianNop)
VALUES('QA-DASH-COD-PENDING',@shipper,@branch,1000,'CASH','PENDING',DATEADD(DAY,-3,@start));
COMMIT;
