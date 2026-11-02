/* Sửa dữ liệu mẫu điều phối, chạy sau 02 hoặc bổ sung vào database hiện có.
   Chỉ sửa đơn BULK còn WAITING_ASSIGNMENT, STORED, không còn phân công hoặc chuyến đang hoạt động.
   Giữ người nhận và địa chỉ; sửa kho/bưu cục theo vùng phục vụ có sẵn.
   Bổ sung một shipper/xe mẫu rảnh cho mỗi bưu cục; không hủy nhiệm vụ xuất kho.
   Tài khoản mới chỉ có vai trò SHIPPER sẵn có, dùng mật khẩu băm của tài khoản
   shipper mẫu cùng bưu cục. Không cấp thêm quyền và không đặt lại mật khẩu cũ.
*/
USE QLGiaoHangChangCuoi;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
BEGIN TRY
 BEGIN TRAN;
 DECLARE @Lock INT,@Now DATETIME2(0)=SYSUTCDATETIME(),@Actor BIGINT,@Role INT;
 EXEC @Lock=sys.sp_getapplock @Resource=N'SeedDispatchUsabilityV1',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 52050,N'Không khóa được dữ liệu mẫu điều phối.',1;
 SELECT TOP(1) @Actor=t.MaTaiKhoan FROM dbo.TaiKhoan t JOIN dbo.VaiTro r ON r.MaVaiTro=t.MaVaiTro
 WHERE r.KyHieuVaiTro='ADMIN' AND r.DangHoatDong=1 AND t.TrangThaiTaiKhoan='ACTIVE'
 AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=@Now) ORDER BY t.MaTaiKhoan;
 SELECT @Role=MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='SHIPPER' AND DangHoatDong=1;
 IF @Actor IS NULL OR @Role IS NULL THROW 52051,N'Thiếu tài khoản quản trị hoặc vai trò shipper mẫu.',1;

 DECLARE @Branches TABLE(Seq INT IDENTITY PRIMARY KEY,BranchId INT,Code VARCHAR(8),Name NVARCHAR(150),Lat DECIMAL(9,6),Lng DECIMAL(10,6));
 INSERT @Branches(BranchId,Code,Name,Lat,Lng)
 SELECT b.MaBuuCuc,x.Code,b.TenBuuCuc,b.ViDo,b.KinhDo FROM dbo.BuuCuc b
 JOIN (VALUES('HCM-BT01','BT'),('HCM-TP01','TP'),('HCM-Q601','Q6')) x(BranchCode,Code) ON b.KyHieuBuuCuc=x.BranchCode
 WHERE b.DangHoatDong=1;
 IF (SELECT COUNT(*) FROM @Branches)<>3 THROW 52052,N'Không tìm thấy đủ ba bưu cục mẫu BT/TP/Q6.',1;
 DECLARE @i INT=1,@Branch INT,@Code VARCHAR(8),@Name NVARCHAR(150),@Lat DECIMAL(9,6),@Lng DECIMAL(10,6),
 @Account BIGINT,@Shipper BIGINT,@Vehicle BIGINT,@Hash VARCHAR(255),@Plate NVARCHAR(20),@Added INT=0;
 WHILE @i<=(SELECT COUNT(*) FROM @Branches)
 BEGIN
  SELECT @Branch=BranchId,@Code=Code,@Name=Name,@Lat=Lat,@Lng=Lng FROM @Branches WHERE Seq=@i;
  SELECT @Account=NULL,@Shipper=NULL,@Vehicle=NULL,@Hash=NULL;
  SELECT @Account=MaTaiKhoan FROM dbo.TaiKhoan WHERE TenDangNhap=CONCAT('demo.route.',LOWER(@Code));
  IF @Account IS NULL
  BEGIN
   SELECT TOP(1) @Hash=t.MatKhauBam FROM dbo.TaiKhoan t JOIN dbo.NhanVienGiaoHang n ON n.MaTaiKhoan=t.MaTaiKhoan
   WHERE t.MaBuuCuc=@Branch AND t.MaVaiTro=@Role AND t.TrangThaiTaiKhoan='ACTIVE' ORDER BY t.MaTaiKhoan;
   IF @Hash IS NULL THROW 52053,N'Thiếu tài khoản shipper mẫu để tạo hồ sơ lập tuyến.',1;
   INSERT dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
   VALUES(CONCAT('TK-DEMO-VRP-',@Code),CONCAT('demo.route.',LOWER(@Code)),@Hash,CONCAT(N'Shipper lập tuyến mẫu ',@Name),@Role,@Branch,'ACTIVE');
   SET @Account=SCOPE_IDENTITY();SET @Added+=1;
  END;
  IF NOT EXISTS(SELECT 1 FROM dbo.TaiKhoan WHERE MaTaiKhoan=@Account AND MaVaiTro=@Role AND MaBuuCuc=@Branch)
   THROW 52054,N'Tài khoản mẫu trùng tên nhưng sai vai trò/bưu cục; không tự sửa.',1;
  SELECT @Shipper=MaNhanVienGiaoHang FROM dbo.NhanVienGiaoHang WHERE MaTaiKhoan=@Account;
  IF @Shipper IS NULL
  BEGIN
   INSERT dbo.NhanVienGiaoHang(MaTaiKhoan,MaNhanVien,SoBangLai,NgayHetHanBangLai,TrangThaiSanSang,ViDoHienTai,KinhDoHienTai,ThoiGianCapNhatViTri,DangHoatDong)
   VALUES(@Account,CONCAT('GH-DEMO-VRP-',@Code),CONCAT('DEMO-VRP-',@Code),'2035-12-31','AVAILABLE',@Lat,@Lng,@Now,1);
   SET @Shipper=SCOPE_IDENTITY();
  END;
  SELECT @Vehicle=MaPhuongTien FROM dbo.PhuongTien WHERE KyHieuPhuongTien=CONCAT('XE-DEMO-VRP-',@Code);
  SET @Plate=CASE @Code WHEN 'BT' THEN N'59H1-990.01' WHEN 'TP' THEN N'59D2-990.02' ELSE N'59K1-990.03' END;
  IF @Vehicle IS NULL
  BEGIN
   INSERT dbo.PhuongTien(KyHieuPhuongTien,BienSo,LoaiXe,KhoiLuongDenKg,TheTichToiDaM3,TrangThaiPhuongTien,DangHoatDong)
   VALUES(CONCAT('XE-DEMO-VRP-',@Code),@Plate,'MOTORBIKE',100,.5,'AVAILABLE',1);
   SET @Vehicle=SCOPE_IDENTITY();
  END;
  IF NOT EXISTS(SELECT 1 FROM dbo.PhanCongPhuongTien WHERE MaNhanVienGiaoHang=@Shipper AND ThoiGianKetThuc IS NULL)
   AND NOT EXISTS(SELECT 1 FROM dbo.PhanCongPhuongTien WHERE MaPhuongTien=@Vehicle AND ThoiGianKetThuc IS NULL)
   INSERT dbo.PhanCongPhuongTien(MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,GhiChu)
   VALUES(@Shipper,@Vehicle,@Actor,N'Xe dành cho kịch bản mẫu lập tuyến; không lấy xe đang xử lý xuất kho');
  INSERT dbo.KhuVucNhanVienGiaoHang(MaNhanVienGiaoHang,MaKhuVuc,LaChinh)
  SELECT @Shipper,b.MaKhuVuc,0 FROM dbo.KhuVucPhucVuBuuCuc b JOIN dbo.KhuVuc a ON a.MaKhuVuc=b.MaKhuVuc AND a.DangHoatDong=1
  WHERE b.MaBuuCuc=@Branch AND NOT EXISTS(SELECT 1 FROM dbo.KhuVucNhanVienGiaoHang n WHERE n.MaNhanVienGiaoHang=@Shipper AND n.MaKhuVuc=b.MaKhuVuc);
  SET @i+=1;
 END;

 -- Correct only untouched waiting BULK demo orders; recipient snapshots stay intact.
 SELECT d.MaDonHang OrderId,d.MaBuuCuc OldBranch,d.MaKhoHienTai OldWarehouse,t.MaViTriLuuKho OldLocation,
        target.BranchId,target.WarehouseId,target.LocationId
 INTO #Repair
 FROM dbo.DonHang d WITH(UPDLOCK,HOLDLOCK)
 JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
 JOIN dbo.TonKhoDonHang t WITH(UPDLOCK,HOLDLOCK) ON t.MaDonHang=d.MaDonHang AND t.MaKho=d.MaKhoHienTai
 JOIN dbo.DiemGiaoNhan g ON g.MaDonHang=d.MaDonHang AND g.LoaiDiem='DELIVERY'
 CROSS APPLY(SELECT TOP(1) b.MaBuuCuc BranchId,k.MaKho WarehouseId,v.MaViTriLuuKho LocationId
   FROM dbo.KhuVucPhucVuBuuCuc a JOIN dbo.BuuCuc b ON b.MaBuuCuc=a.MaBuuCuc AND b.DangHoatDong=1
   JOIN dbo.Kho k ON k.MaBuuCuc=b.MaBuuCuc AND k.DangHoatDong=1
   JOIN dbo.ViTriLuuKho v ON v.MaKho=k.MaKho AND v.DangHoatDong=1
   WHERE a.MaKhuVuc=g.MaKhuVuc AND k.KyHieuKho IN('KHO-BT-PL','KHO-TP-PL','KHO-Q6-PL')
   ORDER BY CASE WHEN b.MaBuuCuc=d.MaBuuCuc THEN 0 ELSE 1 END,k.MaKho,v.MaViTriLuuKho) target
 WHERE d.KyHieuDonHang LIKE 'DH-HCM-261023-BULK-%' AND tt.KyHieuTrangThai='WAITING_ASSIGNMENT' AND t.TrangThaiTonKho='STORED'
 AND d.MaBuuCuc<>target.BranchId
 AND NOT EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang p WHERE p.MaDonHang=d.MaDonHang AND p.ThoiGianKetThuc IS NULL)
 AND NOT EXISTS(SELECT 1 FROM dbo.ChiTietChuyenGiao c JOIN dbo.ChuyenGiaoHang trip ON trip.MaChuyenGiao=c.MaChuyenGiao WHERE c.MaDonHang=d.MaDonHang AND trip.TrangThaiChuyen NOT IN('COMPLETED','CANCELLED'));
 INSERT dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuCuJson,DuLieuMoiJson)
 SELECT @Actor,'REPAIR_DEMO_DISPATCH','DonHang',CONVERT(VARCHAR(100),r.OrderId),
 (SELECT r.OldBranch branchId,r.OldWarehouse warehouseId,r.OldLocation locationId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
 (SELECT r.BranchId branchId,r.WarehouseId warehouseId,r.LocationId locationId,N'Sửa dữ liệu mẫu gán sai bưu cục, giữ địa chỉ người nhận' reason FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
 FROM #Repair r;
 UPDATE d SET MaBuuCuc=r.BranchId,MaKhoHienTai=r.WarehouseId,MaTaiKhoanCapNhatCuoi=@Actor,ThoiGianCapNhat=@Now
 FROM dbo.DonHang d JOIN #Repair r ON r.OrderId=d.MaDonHang;
 UPDATE t SET MaKho=r.WarehouseId,MaViTriLuuKho=r.LocationId,ThoiGianDiChuyenCuoi=@Now,MaTaiKhoanCapNhatCuoi=@Actor
 FROM dbo.TonKhoDonHang t JOIN #Repair r ON r.OrderId=t.MaDonHang;
 SELECT @Added AS addedDemoShippers,COUNT(*) AS repairedWaitingOrders FROM #Repair;
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
