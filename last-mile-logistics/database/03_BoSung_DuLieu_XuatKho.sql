/* Bổ sung 3 đơn mới/kho: 2 ACCEPTED + 1 PENDING.
   Chạy sau 02_Nap_DuLieu_ThucTe.sql, hoặc chạy riêng để bổ sung database hiện có.
   Không xóa/reset dữ liệu; không sửa đơn cũ; không vô hiệu hóa trigger.
   Chạy lại bỏ qua mã mẫu đã tồn tại, kể cả đơn đã được người dùng xuất kho.
   Kho hàng hoàn cũng có lô gửi lại mẫu riêng để thử thao tác xuất tại mọi kho.
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
    DECLARE @XKLock INT;
    EXEC @XKLock = sys.sp_getapplock @Resource=N'SeedOutboundDemoV1',
        @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=10000;
    IF @XKLock < 0 THROW 52030, N'Không khóa được lần bổ sung dữ liệu xuất kho.', 1;

    DECLARE @XKNow DATETIME2(0)=SYSUTCDATETIME(), @XKNew SMALLINT;
    SELECT @XKNew=MaTrangThaiDonHang FROM dbo.TrangThaiDonHang WHERE KyHieuTrangThai='NEW';
    DECLARE @XKWarehouses TABLE (Seq INT IDENTITY PRIMARY KEY, Id INT, BranchId INT, Code VARCHAR(30));
    INSERT @XKWarehouses(Id,BranchId,Code)
    SELECT k.MaKho,k.MaBuuCuc,k.KyHieuKho FROM dbo.Kho k
    JOIN dbo.BuuCuc b ON b.MaBuuCuc=k.MaBuuCuc
    WHERE k.DangHoatDong=1 AND b.DangHoatDong=1;
    IF NOT EXISTS(SELECT 1 FROM @XKWarehouses) THROW 52031,N'Chưa có kho mẫu hoạt động.',1;

    DECLARE @XKi INT=1,@XKn INT,@XKWarehouse INT,@XKBranch INT,@XKCode VARCHAR(30),
        @XKLocation BIGINT,@XKActor BIGINT,@XKShipper BIGINT,@XKVehicle BIGINT,
        @XKTemplate BIGINT,@XKOrder BIGINT,@XKTxn BIGINT,@XKOrderCode VARCHAR(40),
        @XKWeight DECIMAL(10,3),@XKCreated INT=0;
    WHILE @XKi <= (SELECT COUNT(*) FROM @XKWarehouses)
    BEGIN
        SELECT @XKWarehouse=Id,@XKBranch=BranchId,@XKCode=Code FROM @XKWarehouses WHERE Seq=@XKi;
        SELECT @XKLocation=NULL,@XKActor=NULL,@XKShipper=NULL,@XKVehicle=NULL,@XKTemplate=NULL;
        SELECT TOP(1) @XKLocation=MaViTriLuuKho FROM dbo.ViTriLuuKho
        WHERE MaKho=@XKWarehouse AND DangHoatDong=1 ORDER BY MaViTriLuuKho;
        SELECT TOP(1) @XKActor=t.MaTaiKhoan FROM dbo.TaiKhoan t JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro
        WHERE t.TrangThaiTaiKhoan='ACTIVE' AND v.DangHoatDong=1
          AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=@XKNow)
          AND (v.KyHieuVaiTro='ADMIN' OR (t.MaBuuCuc=@XKBranch AND v.KyHieuVaiTro='DISPATCHER'))
        ORDER BY CASE WHEN v.KyHieuVaiTro='DISPATCHER' THEN 0 ELSE 1 END,t.MaTaiKhoan;
        SELECT TOP(1) @XKShipper=n.MaNhanVienGiaoHang,@XKVehicle=p.MaPhuongTien
        FROM dbo.NhanVienGiaoHang n JOIN dbo.TaiKhoan t ON t.MaTaiKhoan=n.MaTaiKhoan
        JOIN dbo.VaiTro r ON r.MaVaiTro=t.MaVaiTro
        JOIN dbo.PhanCongPhuongTien p ON p.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang AND p.ThoiGianKetThuc IS NULL
        JOIN dbo.PhuongTien v ON v.MaPhuongTien=p.MaPhuongTien
        WHERE t.MaBuuCuc=@XKBranch AND t.TrangThaiTaiKhoan='ACTIVE' AND r.KyHieuVaiTro='SHIPPER' AND r.DangHoatDong=1
          AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=@XKNow)
          AND n.DangHoatDong=1 AND n.TrangThaiSanSang IN ('AVAILABLE','DELIVERING')
          AND (n.NgayHetHanBangLai IS NULL OR n.NgayHetHanBangLai>=CONVERT(DATE,DATEADD(HOUR,7,@XKNow)))
          AND v.DangHoatDong=1 AND v.TrangThaiPhuongTien IN ('AVAILABLE','IN_USE') AND v.KhoiLuongDenKg>=5
        ORDER BY n.MaNhanVienGiaoHang;
        SELECT TOP(1) @XKTemplate=d.MaDonHang FROM dbo.DonHang d
        JOIN dbo.DiemGiaoNhan g ON g.MaDonHang=d.MaDonHang AND g.LoaiDiem='DELIVERY'
        JOIN dbo.KhuVucNhanVienGiaoHang kv ON kv.MaNhanVienGiaoHang=@XKShipper AND kv.MaKhuVuc=g.MaKhuVuc
        WHERE d.MaBuuCuc=@XKBranch AND d.KyHieuDonHang NOT LIKE 'DH-XK-%'
          AND EXISTS(SELECT 1 FROM dbo.DiemGiaoNhan p WHERE p.MaDonHang=d.MaDonHang AND p.LoaiDiem='PICKUP')
        ORDER BY d.MaDonHang;
        IF @XKLocation IS NULL OR @XKActor IS NULL OR @XKShipper IS NULL OR @XKTemplate IS NULL
            THROW 52032,N'Kho thiếu vị trí, tài khoản, shipper/xe hoặc đơn gốc đúng khu vực; chưa bổ sung dữ liệu.',1;

        SET @XKn=1;
        WHILE @XKn<=3
        BEGIN
            SET @XKOrderCode=CONCAT('DH-XK-',@XKCode,'-',@XKn);
            IF NOT EXISTS(SELECT 1 FROM dbo.DonHang WITH(UPDLOCK,HOLDLOCK) WHERE KyHieuDonHang=@XKOrderCode)
            BEGIN
                INSERT dbo.DonHang(KyHieuDonHang,MaVanDon,MaBuuCuc,MaNguoiGui,MaNguoiNhan,MaLoaiDichVu,
                    MaTrangThaiHienTai,ThoiGianSanSang,ThoiGianYeuCauGiao,ThoiGianDuKienGiao,
                    MucDoUuTien,GiaTriKhaiBao,TienCOD,PhiVanChuyen,GhiChuDacBiet,MaTaiKhoanTao,MaTaiKhoanCapNhatCuoi)
                SELECT @XKOrderCode,CONCAT('VD-XK-',@XKCode,'-',@XKn),@XKBranch,MaNguoiGui,MaNguoiNhan,MaLoaiDichVu,
                    @XKNew,DATEADD(MINUTE,-30,@XKNow),@XKNow,DATEADD(HOUR,8,@XKNow),
                    @XKn,150000,CASE WHEN @XKn=2 THEN 150000 ELSE 0 END,25000,
                    N'Dữ liệu mẫu xuất kho: kiểm tra phân công và bàn giao.',@XKActor,@XKActor
                FROM dbo.DonHang WHERE MaDonHang=@XKTemplate;
                SET @XKOrder=SCOPE_IDENTITY();
                INSERT dbo.DiemGiaoNhan(MaDonHang,LoaiDiem,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc,ViDo,KinhDo,GhiChu)
                SELECT @XKOrder,LoaiDiem,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc,ViDo,KinhDo,N'Điểm giao nhận của đơn mẫu xuất kho'
                FROM dbo.DiemGiaoNhan WHERE MaDonHang=@XKTemplate;
                SET @XKWeight=0.5+@XKn*0.25;
                INSERT dbo.ChiTietDonHang(MaDonHang,TenHang,LoaiHang,SoLuong,KhoiLuongDonViKg,ChieuDaiCm,ChieuRongCm,ChieuCaoCm,GiaTriHang,HangDeVo)
                VALUES(@XKOrder,CASE @XKn WHEN 1 THEN N'Áo thun đóng gói' WHEN 2 THEN N'Bình giữ nhiệt' ELSE N'Sách và văn phòng phẩm' END,
                    N'Hàng mẫu xuất kho',1,@XKWeight,20,15,10,150000,0);
                INSERT dbo.KhoanPhiDonHang(MaDonHang,LoaiKhoanPhi,SoTien,MoTa)
                VALUES(@XKOrder,'SHIPPING',25000,N'Cước đơn mẫu xuất kho');
                EXEC dbo.sp_XacNhanDonHang @MaDonHang=@XKOrder,@MaTaiKhoan=@XKActor;
                EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@XKOrder,@KyHieuTrangThaiMoi='WAITING_INBOUND',@MaTaiKhoan=@XKActor,@NguonCapNhat='SYSTEM';
                INSERT dbo.GiaoDichKho(KyHieuGiaoDich,MaKho,LoaiGiaoDich,TrangThaiGiaoDich,MaTaiKhoanThucHien,GhiChu)
                VALUES(CONCAT('NK-XK-',@XKCode,'-',@XKn),@XKWarehouse,'INBOUND','COMPLETED',@XKActor,N'Nhập hàng mẫu để chờ xuất kho');
                SET @XKTxn=SCOPE_IDENTITY();
                INSERT dbo.ChiTietGiaoDichKho(MaGiaoDichKho,MaDonHang,MaViTriDich,TinhTrangHang)
                VALUES(@XKTxn,@XKOrder,@XKLocation,'NORMAL');
                INSERT dbo.TonKhoDonHang(MaDonHang,MaKho,MaViTriLuuKho,TrangThaiTonKho,ThoiGianNhapKho,ThoiGianDiChuyenCuoi,MaTaiKhoanCapNhatCuoi)
                VALUES(@XKOrder,@XKWarehouse,@XKLocation,'STORED',@XKNow,@XKNow,@XKActor);
                UPDATE dbo.DonHang SET MaKhoHienTai=@XKWarehouse WHERE MaDonHang=@XKOrder;
                EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@XKOrder,@KyHieuTrangThaiMoi='IN_WAREHOUSE',@MaTaiKhoan=@XKActor,@NguonCapNhat='SYSTEM';
                EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@XKOrder,@KyHieuTrangThaiMoi='WAITING_ASSIGNMENT',@MaTaiKhoan=@XKActor,@NguonCapNhat='SYSTEM';
                INSERT dbo.PhanCongGiaoHang(MaDonHang,MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,TrangThaiPhanCong)
                VALUES(@XKOrder,@XKShipper,@XKVehicle,@XKActor,'PENDING');
                EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@XKOrder,@KyHieuTrangThaiMoi='ASSIGNED',@MaTaiKhoan=@XKActor,@NguonCapNhat='SYSTEM';
                IF @XKn<=2
                BEGIN
                    UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong='ACCEPTED',ThoiGianChapNhan=SYSUTCDATETIME()
                    WHERE MaDonHang=@XKOrder AND ThoiGianKetThuc IS NULL;
                    UPDATE dbo.TonKhoDonHang SET TrangThaiTonKho='ALLOCATED' WHERE MaDonHang=@XKOrder;
                END;
                SET @XKCreated+=1;
            END;
            SET @XKn+=1;
        END;
        -- Check all current vehicle assignments, matching outbound capacity rules.
        IF EXISTS(SELECT 1 FROM dbo.PhuongTien v WHERE v.MaPhuongTien=@XKVehicle AND
            ((SELECT SUM(d.TongKhoiLuongKg) FROM dbo.PhanCongGiaoHang p JOIN dbo.DonHang d ON d.MaDonHang=p.MaDonHang
              WHERE p.MaPhuongTien=v.MaPhuongTien AND p.ThoiGianKetThuc IS NULL)>v.KhoiLuongDenKg
             OR (v.TheTichToiDaM3 IS NOT NULL AND
                 (EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang p JOIN dbo.ChiTietDonHang c ON c.MaDonHang=p.MaDonHang
                    WHERE p.MaPhuongTien=v.MaPhuongTien AND p.ThoiGianKetThuc IS NULL AND
                    (c.ChieuDaiCm IS NULL OR c.ChieuRongCm IS NULL OR c.ChieuCaoCm IS NULL))
                  OR (SELECT SUM(CAST(c.SoLuong AS DECIMAL(18,6))*c.ChieuDaiCm*c.ChieuRongCm*c.ChieuCaoCm/1000000.0)
                      FROM dbo.PhanCongGiaoHang p JOIN dbo.ChiTietDonHang c ON c.MaDonHang=p.MaDonHang
                      WHERE p.MaPhuongTien=v.MaPhuongTien AND p.ThoiGianKetThuc IS NULL)>v.TheTichToiDaM3))))
            THROW 52033,N'Xe không đủ tải/thể tích cho lô mẫu; đã hủy toàn bộ lần bổ sung.',1;
        SET @XKi+=1;
    END;
    COMMIT;
    SELECT @XKCreated AS newOrders;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;
GO
