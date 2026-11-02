/*
===============================================================================
BỘ DỮ LIỆU THỰC TẾ TOÀN DIỆN VÀ MỞ RỘNG (ALL-IN-ONE)
HỆ THỐNG QUẢN LÝ ĐIỀU PHỐI GIAO HÀNG CHẶNG CUỐI (QLGiaoHangChangCuoi - V5)
===============================================================================
Mục tiêu:
- Tự động làm sạch dữ liệu cũ nếu đã tồn tại để F5 bất kỳ lúc nào cũng thành công.
- Bao phủ 162 đơn hàng thực tế qua đầy đủ 8 trạng thái vận hành.
- 162 khách hàng (33 shop doanh nghiệp + 129 cá nhân), 324 điểm lấy/giao.
- Đầy đủ chuyến giao VRP, POD, nộp COD, đối soát khớp 100%, khiếu nại, cảnh báo.
===============================================================================
*/

USE QLGiaoHangChangCuoi;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.DonHang', N'U') IS NULL
BEGIN
    ;THROW 52000, N'Lỗi: Không tìm thấy bảng dbo.DonHang. Hãy chạy script khởi tạo Schema V5 trước!', 1;
END;

DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

DECLARE
    -- Khu vực
    @KV_HCM INT, @KV_BT INT, @KV_TP INT, @KV_Q6 INT,
    @KV_BHB INT, @KV_AL INT, @KV_SK INT, @KV_TT INT, @KV_Q6P10 INT, @KV_Q6P12 INT,

    -- Bưu cục & Kho
    @BC_BT INT, @BC_TP INT, @BC_Q6 INT,
    @Kho_BT INT, @Kho_BT_Return INT, @Kho_TP INT, @Kho_Q6 INT,
    @VT_BT_A1 BIGINT, @VT_BT_A2 BIGINT, @VT_BT_A3 BIGINT,
    @VT_BTR_R1 BIGINT, @VT_BTR_R2 BIGINT,
    @VT_TP_A1 BIGINT, @VT_TP_A2 BIGINT, @VT_TP_A3 BIGINT,
    @VT_Q6_A1 BIGINT, @VT_Q6_A2 BIGINT, @VT_Q6_A3 BIGINT, @VT_Q6_A4 BIGINT,

    -- Vai trò & Danh mục
    @RoleAdmin INT, @RoleManager INT, @RoleDispatcher INT,
    @RoleWarehouse INT, @RoleAccountant INT, @RoleShipper INT,
    @DV_STD INT, @DV_EXP INT, @TT_NEW SMALLINT, @LyDoNoAnswer INT,

    -- Tài khoản nhân sự
    @TK_Admin BIGINT,
    @TK_MgrBT BIGINT, @TK_MgrTP BIGINT, @TK_MgrQ6 BIGINT,
    @TK_DPBT BIGINT, @TK_DPTP BIGINT, @TK_DPQ6 BIGINT,
    @TK_KhoBT BIGINT, @TK_KhoTP BIGINT, @TK_KhoQ6 BIGINT,
    @TK_KeToan BIGINT,
    @TK_S1 BIGINT, @TK_S2 BIGINT, @TK_S3 BIGINT, @TK_S4 BIGINT, @TK_S5 BIGINT,

    -- Khách hàng mẫu
    @KH_ShopAnPhuc BIGINT, @KH_ShopMinhTam BIGINT, @KH_ShopNhaXinh BIGINT,
    @KH_01 BIGINT, @KH_02 BIGINT, @KH_03 BIGINT, @KH_04 BIGINT, @KH_05 BIGINT,
    @KH_06 BIGINT, @KH_07 BIGINT, @KH_08 BIGINT, @KH_09 BIGINT,

    -- Shipper & Phương tiện
    @S1 BIGINT, @S2 BIGINT, @S3 BIGINT, @S4 BIGINT, @S5 BIGINT,
    @Xe1 BIGINT, @Xe2 BIGINT, @Xe3 BIGINT, @Xe4 BIGINT, @Xe5 BIGINT,

    -- Chuyến giao & Nghiệp vụ phát sinh
    @Trip1 BIGINT, @Trip2 BIGINT, @Trip3 BIGINT,
    @Handover1 BIGINT, @Handover2 BIGINT, @Handover3 BIGINT,
    @WT_BT_IN BIGINT, @WT_TP_IN BIGINT, @WT_Q6_IN BIGINT,
    @WT_BT_OUT1 BIGINT, @WT_BT_OUT2 BIGINT, @WT_TP_OUT BIGINT,
    @Deposit BIGINT, @Recon BIGINT,
    @Complaint1 BIGINT, @Complaint2 BIGINT;

-- Lấy ID danh mục hệ thống
SELECT @RoleAdmin = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro = 'ADMIN';
SELECT @RoleManager = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro = 'BRANCH_MANAGER';
SELECT @RoleDispatcher = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro = 'DISPATCHER';
SELECT @RoleWarehouse = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro = 'WAREHOUSE_STAFF';
SELECT @RoleAccountant = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro = 'ACCOUNTANT';
SELECT @RoleShipper = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro = 'SHIPPER';
SELECT @DV_STD = MaLoaiDichVu FROM dbo.LoaiDichVu WHERE KyHieuDichVu = 'STANDARD';
SELECT @DV_EXP = MaLoaiDichVu FROM dbo.LoaiDichVu WHERE KyHieuDichVu = 'EXPRESS';
SELECT @TT_NEW = MaTrangThaiDonHang FROM dbo.TrangThaiDonHang WHERE KyHieuTrangThai = 'NEW';
SELECT @LyDoNoAnswer = MaLyDoGiaoThatBai FROM dbo.LyDoGiaoThatBai WHERE KyHieuLyDo = 'NO_ANSWER';

BEGIN TRY
BEGIN TRAN;

/* =============================================================================
   BƯỚC CHUẨN BỊ: TỰ ĐỘNG DỌN DẸP DỮ LIỆU CŨ NẾU ĐÃ TỒN TẠI
   ============================================================================= */
IF EXISTS (SELECT 1 FROM dbo.KhuVuc WHERE KyHieuKhuVuc = 'HCM')
   OR EXISTS (SELECT 1 FROM dbo.DonHang WHERE KyHieuDonHang LIKE 'DH-HCM-%')
BEGIN
    PRINT N'Phát hiện dữ liệu cũ, tiến hành dọn dẹp an toàn trước khi nạp mới...';
    
    -- Tắt trigger trên các bảng có trigger nghiệp vụ chặn xóa
    ALTER TABLE dbo.ChiTietDonHang DISABLE TRIGGER ALL;
    ALTER TABLE dbo.DonHang DISABLE TRIGGER ALL;
    ALTER TABLE dbo.DiemGiaoNhan DISABLE TRIGGER ALL;
    ALTER TABLE dbo.PhanCongGiaoHang DISABLE TRIGGER ALL;
    ALTER TABLE dbo.ChuyenGiaoHang DISABLE TRIGGER ALL;
    ALTER TABLE dbo.ChiTietChuyenGiao DISABLE TRIGGER ALL;
    ALTER TABLE dbo.ChiTietGiaoDichKho DISABLE TRIGGER ALL;
    ALTER TABLE dbo.ChiTietBanGiaoHang DISABLE TRIGGER ALL;
    ALTER TABLE dbo.NhanVienGiaoHang DISABLE TRIGGER ALL;
    ALTER TABLE dbo.QuyTacTinhPhi DISABLE TRIGGER ALL;
    ALTER TABLE dbo.DanhGia DISABLE TRIGGER ALL;
    ALTER TABLE dbo.KhieuNai DISABLE TRIGGER ALL;

    -- Xóa theo đúng thứ tự 107 Foreign Keys
    DELETE FROM dbo.ChiTietDoiSoatCOD;
    DELETE FROM dbo.DoiSoatCOD;
    DELETE FROM dbo.ChiTietNopTienCOD;
    DELETE FROM dbo.NopTienCOD;
    DELETE FROM dbo.ThuTienCOD;
    DELETE FROM dbo.BangChungGiaoHang;
    DELETE FROM dbo.LanGiaoHang;
    DELETE FROM dbo.YeuCauGiaoLaiHoacHoan;
    DELETE FROM dbo.CanhBaoGiaoHang;
    DELETE FROM dbo.DanhGia;
    DELETE FROM dbo.LichSuKhieuNai;
    DELETE FROM dbo.KhieuNai;
    DELETE FROM dbo.ThongBao;
    DELETE FROM dbo.NhatKyHoatDong;
    DELETE FROM dbo.DiemDungTuyen;
    DELETE FROM dbo.PhanCongGiaoHang;
    DELETE FROM dbo.ChiTietChuyenGiao;
    DELETE FROM dbo.ChuyenGiaoHang;
    DELETE FROM dbo.ChiTietBanGiaoHang;
    DELETE FROM dbo.BanGiaoHang;
    DELETE FROM dbo.ChiTietGiaoDichKho;
    DELETE FROM dbo.GiaoDichKho;
    DELETE FROM dbo.TonKhoDonHang;
    DELETE FROM dbo.KhoanPhiDonHang;
    DELETE FROM dbo.ChiTietDonHang;
    DELETE FROM dbo.DiemGiaoNhan;
    DELETE FROM dbo.LichSuTrangThaiDonHang;
    DELETE FROM dbo.DonHang;
    DELETE FROM dbo.LichSuViTriNhanVienGiaoHang;
    DELETE FROM dbo.PhanCongPhuongTien;
    DELETE FROM dbo.KhuVucNhanVienGiaoHang;
    DELETE FROM dbo.NhanVienGiaoHang;
    DELETE FROM dbo.PhuongTien;
    DELETE FROM dbo.DiaChiKhachHang;
    DELETE FROM dbo.KhachHang;
    DELETE FROM dbo.TokenLamMoi;
    DELETE FROM dbo.TaiKhoan;
    DELETE FROM dbo.ViTriLuuKho;
    DELETE FROM dbo.Kho;
    DELETE FROM dbo.KhuVucPhucVuBuuCuc;
    DELETE FROM dbo.BuuCuc;
    DELETE FROM dbo.QuyTacTinhPhi;
    DELETE FROM dbo.KhuVuc WHERE MaKhuVucCha IS NOT NULL;
    DELETE FROM dbo.KhuVuc;

    -- Bật lại toàn bộ trigger
    ALTER TABLE dbo.ChiTietDonHang ENABLE TRIGGER ALL;
    ALTER TABLE dbo.DonHang ENABLE TRIGGER ALL;
    ALTER TABLE dbo.DiemGiaoNhan ENABLE TRIGGER ALL;
    ALTER TABLE dbo.PhanCongGiaoHang ENABLE TRIGGER ALL;
    ALTER TABLE dbo.ChuyenGiaoHang ENABLE TRIGGER ALL;
    ALTER TABLE dbo.ChiTietChuyenGiao ENABLE TRIGGER ALL;
    ALTER TABLE dbo.ChiTietGiaoDichKho ENABLE TRIGGER ALL;
    ALTER TABLE dbo.ChiTietBanGiaoHang ENABLE TRIGGER ALL;
    ALTER TABLE dbo.NhanVienGiaoHang ENABLE TRIGGER ALL;
    ALTER TABLE dbo.QuyTacTinhPhi ENABLE TRIGGER ALL;
    ALTER TABLE dbo.DanhGia ENABLE TRIGGER ALL;
    ALTER TABLE dbo.KhieuNai ENABLE TRIGGER ALL;
    
    PRINT N'Dọn dẹp thành công. Bắt đầu nạp bộ dữ liệu toàn diện...';
END;

/* =============================================================================
   PHẦN 1. KHU VỰC, BƯU CỤC, KHO VẬN HÀNH & VỊ TRÍ LƯU KHO
   ============================================================================= */
PRINT N'1/16 - Thiết lập khu vực, bưu cục, kho và vị trí lưu kho...';

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM', N'Thành phố Hồ Chí Minh', NULL, 'CITY', 1);
SET @KV_HCM = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM-BT', N'Quận Bình Tân', @KV_HCM, 'DISTRICT', 1);
SET @KV_BT = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM-TP', N'Quận Tân Phú', @KV_HCM, 'DISTRICT', 1);
SET @KV_TP = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM-Q6', N'Quận 6', @KV_HCM, 'DISTRICT', 1);
SET @KV_Q6 = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM-BT-BHB', N'Phường Bình Hưng Hòa B', @KV_BT, 'WARD', 1);
SET @KV_BHB = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM-BT-AL', N'Phường An Lạc', @KV_BT, 'WARD', 1);
SET @KV_AL = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM-TP-SK', N'Phường Sơn Kỳ', @KV_TP, 'WARD', 1);
SET @KV_SK = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM-TP-TT', N'Phường Tân Thành', @KV_TP, 'WARD', 1);
SET @KV_TT = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM-Q6-P10', N'Phường 10, Quận 6', @KV_Q6, 'WARD', 1);
SET @KV_Q6P10 = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc, TenKhuVuc, MaKhuVucCha, LoaiKhuVuc, DangHoatDong)
VALUES ('HCM-Q6-P12', N'Phường 12, Quận 6', @KV_Q6, 'WARD', 1);
SET @KV_Q6P12 = SCOPE_IDENTITY();

INSERT INTO dbo.BuuCuc(KyHieuBuuCuc, TenBuuCuc, MaKhuVuc, DiaChi, ViDo, KinhDo, SoDienThoai, Email, DangHoatDong)
VALUES
('HCM-BT01', N'Bưu cục Bình Tân 01', @KV_BT, N'621 Quốc lộ 1A, Bình Hưng Hòa B, Bình Tân, TP.HCM', 10.810500, 106.604800, '02870001001', 'bt01@lastmile.local', 1);
SET @BC_BT = SCOPE_IDENTITY();

INSERT INTO dbo.BuuCuc(KyHieuBuuCuc, TenBuuCuc, MaKhuVuc, DiaChi, ViDo, KinhDo, SoDienThoai, Email, DangHoatDong)
VALUES
('HCM-TP01', N'Bưu cục Tân Phú 01', @KV_TP, N'88 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM', 10.802900, 106.617900, '02870001002', 'tp01@lastmile.local', 1);
SET @BC_TP = SCOPE_IDENTITY();

INSERT INTO dbo.BuuCuc(KyHieuBuuCuc, TenBuuCuc, MaKhuVuc, DiaChi, ViDo, KinhDo, SoDienThoai, Email, DangHoatDong)
VALUES
('HCM-Q601', N'Bưu cục Quận 6 01', @KV_Q6, N'180 Hậu Giang, Phường 10, Quận 6, TP.HCM', 10.746900, 106.635800, '02870001003', 'q601@lastmile.local', 1);
SET @BC_Q6 = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVucPhucVuBuuCuc(MaBuuCuc, MaKhuVuc, LaChinh) VALUES
(@BC_BT, @KV_BHB, 1), (@BC_BT, @KV_AL, 0),
(@BC_TP, @KV_SK, 1), (@BC_TP, @KV_TT, 0),
(@BC_Q6, @KV_Q6P10, 1), (@BC_Q6, @KV_Q6P12, 0);

INSERT INTO dbo.Kho(KyHieuKho, TenKho, MaBuuCuc, DiaChi, DangHoatDong)
VALUES ('KHO-BT-PL', N'Kho phân loại Bình Tân', @BC_BT, N'Khu A - Bưu cục Bình Tân 01', 1);
SET @Kho_BT = SCOPE_IDENTITY();

INSERT INTO dbo.Kho(KyHieuKho, TenKho, MaBuuCuc, DiaChi, DangHoatDong)
VALUES ('KHO-BT-HOAN', N'Kho hàng hoàn Bình Tân', @BC_BT, N'Khu B - Bưu cục Bình Tân 01', 1);
SET @Kho_BT_Return = SCOPE_IDENTITY();

INSERT INTO dbo.Kho(KyHieuKho, TenKho, MaBuuCuc, DiaChi, DangHoatDong)
VALUES ('KHO-TP-PL', N'Kho phân loại Tân Phú', @BC_TP, N'Tầng trệt - Bưu cục Tân Phú 01', 1);
SET @Kho_TP = SCOPE_IDENTITY();

INSERT INTO dbo.Kho(KyHieuKho, TenKho, MaBuuCuc, DiaChi, DangHoatDong)
VALUES ('KHO-Q6-PL', N'Kho phân loại Quận 6', @BC_Q6, N'Tầng trệt - Bưu cục Quận 6 01', 1);
SET @Kho_Q6 = SCOPE_IDENTITY();

INSERT INTO dbo.ViTriLuuKho(MaKho, KyHieuViTri, TenKhuLuu, MaKe, MaO, DangHoatDong)
VALUES
(@Kho_BT, 'BT-A1-01', N'Hàng mới nhập', 'A1', '01', 1),
(@Kho_BT, 'BT-A1-02', N'Hàng mới nhập', 'A1', '02', 1),
(@Kho_BT, 'BT-B1-01', N'Hàng chờ giao', 'B1', '01', 1);
SELECT @VT_BT_A1 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_BT AND KyHieuViTri = 'BT-A1-01';
SELECT @VT_BT_A2 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_BT AND KyHieuViTri = 'BT-A1-02';
SELECT @VT_BT_A3 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_BT AND KyHieuViTri = 'BT-B1-01';

INSERT INTO dbo.ViTriLuuKho(MaKho, KyHieuViTri, TenKhuLuu, MaKe, MaO, DangHoatDong)
VALUES
(@Kho_BT_Return, 'BTR-R1-01', N'Hàng hoàn chờ xử lý', 'R1', '01', 1),
(@Kho_BT_Return, 'BTR-R1-02', N'Hàng hoàn đã kiểm', 'R1', '02', 1);
SELECT @VT_BTR_R1 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_BT_Return AND KyHieuViTri = 'BTR-R1-01';
SELECT @VT_BTR_R2 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_BT_Return AND KyHieuViTri = 'BTR-R1-02';

INSERT INTO dbo.ViTriLuuKho(MaKho, KyHieuViTri, TenKhuLuu, MaKe, MaO, DangHoatDong)
VALUES
(@Kho_TP, 'TP-A1-01', N'Hàng mới nhập', 'A1', '01', 1),
(@Kho_TP, 'TP-A1-02', N'Hàng chờ phân công', 'A1', '02', 1),
(@Kho_TP, 'TP-B1-01', N'Hàng chờ giao', 'B1', '01', 1);
SELECT @VT_TP_A1 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_TP AND KyHieuViTri = 'TP-A1-01';
SELECT @VT_TP_A2 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_TP AND KyHieuViTri = 'TP-A1-02';
SELECT @VT_TP_A3 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_TP AND KyHieuViTri = 'TP-B1-01';

INSERT INTO dbo.ViTriLuuKho(MaKho, KyHieuViTri, TenKhuLuu, MaKe, MaO, DangHoatDong)
VALUES
(@Kho_Q6, 'Q6-A1-01', N'Hàng mới nhập', 'A1', '01', 1),
(@Kho_Q6, 'Q6-A1-02', N'Hàng mới nhập', 'A1', '02', 1),
(@Kho_Q6, 'Q6-B1-01', N'Hàng chờ phân công', 'B1', '01', 1),
(@Kho_Q6, 'Q6-C1-01', N'Hàng ngoại lệ', 'C1', '01', 1);
SELECT @VT_Q6_A1 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_Q6 AND KyHieuViTri = 'Q6-A1-01';
SELECT @VT_Q6_A2 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_Q6 AND KyHieuViTri = 'Q6-A1-02';
SELECT @VT_Q6_A3 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_Q6 AND KyHieuViTri = 'Q6-B1-01';
SELECT @VT_Q6_A4 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho = @Kho_Q6 AND KyHieuViTri = 'Q6-C1-01';

/* =============================================================================
   PHẦN 2. TÀI KHOẢN NHÂN SỰ NGHIỆP VỤ & TOKEN BẢO MẬT
   ============================================================================= */
PRINT N'2/16 - Tạo tài khoản nhân sự và token làm mới...';

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-ADMIN-001', 'admin.system', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Nguyễn Hoàng Minh', '0900001001', 'admin@lastmile.local', @RoleAdmin, NULL, 'ACTIVE');
SET @TK_Admin = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-BT-QL-001', 'ql.binh.tan', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Trần Thị Thanh Hương', '0900001002', 'huong.tt@lastmile.local', @RoleManager, @BC_BT, 'ACTIVE');
SET @TK_MgrBT = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-TP-QL-001', 'ql.tan.phu', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Phạm Quốc Khánh', '0900001003', 'khanh.pq@lastmile.local', @RoleManager, @BC_TP, 'ACTIVE');
SET @TK_MgrTP = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-Q6-QL-001', 'ql.quan.6', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Lê Ngọc Mai', '0900001004', 'mai.ln@lastmile.local', @RoleManager, @BC_Q6, 'ACTIVE');
SET @TK_MgrQ6 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-BT-DP-001', 'dp.binh.tan', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Võ Minh Tân', '0900001010', 'tan.vm@lastmile.local', @RoleDispatcher, @BC_BT, 'ACTIVE');
SET @TK_DPBT = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-TP-DP-001', 'dp.tan.phu', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Nguyễn Thùy Linh', '0900001011', 'linh.nt@lastmile.local', @RoleDispatcher, @BC_TP, 'ACTIVE');
SET @TK_DPTP = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-Q6-DP-001', 'dp.quan.6', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Đặng Anh Tuấn', '0900001012', 'tuan.da@lastmile.local', @RoleDispatcher, @BC_Q6, 'ACTIVE');
SET @TK_DPQ6 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-BT-KHO-001', 'kho.binh.tan', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Bùi Văn Long', '0900001020', 'long.bv@lastmile.local', @RoleWarehouse, @BC_BT, 'ACTIVE');
SET @TK_KhoBT = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-TP-KHO-001', 'kho.tan.phu', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Phan Thị Hạnh', '0900001021', 'hanh.pt@lastmile.local', @RoleWarehouse, @BC_TP, 'ACTIVE');
SET @TK_KhoTP = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-Q6-KHO-001', 'kho.quan.6', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Hoàng Minh Đức', '0900001022', 'duc.hm@lastmile.local', @RoleWarehouse, @BC_Q6, 'ACTIVE');
SET @TK_KhoQ6 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NV-KT-001', 'ke.toan.cod', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Đỗ Thu Trang', '0900001030', 'trang.dt@lastmile.local', @RoleAccountant, @BC_BT, 'ACTIVE');
SET @TK_KeToan = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NVGH-BT-001', 'shipper.tuan', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Nguyễn Minh Tuấn', '0900001101', 'tuan.nm@lastmile.local', @RoleShipper, @BC_BT, 'ACTIVE');
SET @TK_S1 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NVGH-BT-002', 'shipper.bao', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Trần Quốc Bảo', '0900001102', 'bao.tq@lastmile.local', @RoleShipper, @BC_BT, 'ACTIVE');
SET @TK_S2 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NVGH-TP-001', 'shipper.phuc', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Lê Hoàng Phúc', '0900001103', 'phuc.lh@lastmile.local', @RoleShipper, @BC_TP, 'ACTIVE');
SET @TK_S3 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NVGH-Q6-001', 'shipper.huy', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Phạm Gia Huy', '0900001104', 'huy.pg@lastmile.local', @RoleShipper, @BC_Q6, 'ACTIVE');
SET @TK_S4 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan, TenDangNhap, MatKhauBam, HoTen, SoDienThoai, Email, MaVaiTro, MaBuuCuc, TrangThaiTaiKhoan)
VALUES ('NVGH-Q6-002', 'shipper.dat', '$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi', N'Võ Thành Đạt', '0900001105', 'dat.vt@lastmile.local', @RoleShipper, @BC_Q6, 'ACTIVE');
SET @TK_S5 = SCOPE_IDENTITY();

INSERT INTO dbo.TokenLamMoi(MaTaiKhoan, GiaTriBamToken, HetHanLuc, ThuHoiLuc, ThoiGianTao, DiaChiIPTao, TokenThayTheBam)
VALUES
(@TK_DPBT, 'sha256:rt_dpbt_20261002', DATEADD(DAY, 7, @Now), NULL, @Now, '10.10.1.15', NULL),
(@TK_DPTP, 'sha256:rt_dptp_20261002', DATEADD(DAY, 7, @Now), NULL, @Now, '10.20.1.15', NULL),
(@TK_S1, 'sha256:rt_shipper_tuan_20261002', DATEADD(DAY, 7, @Now), NULL, @Now, '10.10.2.101', NULL),
(@TK_S2, 'sha256:rt_shipper_bao_20261002', DATEADD(DAY, 7, @Now), NULL, @Now, '10.10.2.102', NULL),
(@TK_S3, 'sha256:rt_shipper_phuc_20261002', DATEADD(DAY, 7, @Now), NULL, @Now, '10.20.2.101', NULL);

/* =============================================================================
   PHẦN 3. HỒ SƠ SHIPPER, PHƯƠNG TIỆN, PHÂN XE & LỊCH SỬ GPS
   ============================================================================= */
PRINT N'3/16 - Tạo hồ sơ shipper, phương tiện và lịch sử GPS...';

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan, MaNhanVien, CCCD, SoBangLai, NgayHetHanBangLai, TrangThaiSanSang, ViDoHienTai, KinhDoHienTai, ThoiGianCapNhatViTri, DangHoatDong)
VALUES (@TK_S1, 'GH-BT-001', '079260000001', 'A1-260001', '2031-06-30', 'AVAILABLE', 10.810500, 106.604800, @Now, 1);
SET @S1 = SCOPE_IDENTITY();

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan, MaNhanVien, CCCD, SoBangLai, NgayHetHanBangLai, TrangThaiSanSang, ViDoHienTai, KinhDoHienTai, ThoiGianCapNhatViTri, DangHoatDong)
VALUES (@TK_S2, 'GH-BT-002', '079260000002', 'A1-260002', '2030-11-30', 'AVAILABLE', 10.812000, 106.602900, @Now, 1);
SET @S2 = SCOPE_IDENTITY();

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan, MaNhanVien, CCCD, SoBangLai, NgayHetHanBangLai, TrangThaiSanSang, ViDoHienTai, KinhDoHienTai, ThoiGianCapNhatViTri, DangHoatDong)
VALUES (@TK_S3, 'GH-TP-001', '079260000003', 'A1-260003', '2031-03-31', 'AVAILABLE', 10.802900, 106.617900, @Now, 1);
SET @S3 = SCOPE_IDENTITY();

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan, MaNhanVien, CCCD, SoBangLai, NgayHetHanBangLai, TrangThaiSanSang, ViDoHienTai, KinhDoHienTai, ThoiGianCapNhatViTri, DangHoatDong)
VALUES (@TK_S4, 'GH-Q6-001', '079260000004', 'A1-260004', '2030-08-31', 'AVAILABLE', 10.746900, 106.635800, @Now, 1);
SET @S4 = SCOPE_IDENTITY();

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan, MaNhanVien, CCCD, SoBangLai, NgayHetHanBangLai, TrangThaiSanSang, ViDoHienTai, KinhDoHienTai, ThoiGianCapNhatViTri, DangHoatDong)
VALUES (@TK_S5, 'GH-Q6-002', '079260000005', 'A1-260005', '2031-01-31', 'BREAK', 10.748000, 106.637100, @Now, 1);
SET @S5 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien, BienSo, LoaiXe, KhoiLuongDenKg, TheTichToiDaM3, TrangThaiPhuongTien, DangHoatDong)
VALUES ('XE-BT-001', N'59H1-812.34', 'MOTORBIKE', 85, 0.32, 'AVAILABLE', 1);
SET @Xe1 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien, BienSo, LoaiXe, KhoiLuongDenKg, TheTichToiDaM3, TrangThaiPhuongTien, DangHoatDong)
VALUES ('XE-BT-002', N'59H2-463.27', 'MOTORBIKE', 90, 0.35, 'AVAILABLE', 1);
SET @Xe2 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien, BienSo, LoaiXe, KhoiLuongDenKg, TheTichToiDaM3, TrangThaiPhuongTien, DangHoatDong)
VALUES ('XE-TP-001', N'59D2-375.61', 'MOTORBIKE', 80, 0.30, 'AVAILABLE', 1);
SET @Xe3 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien, BienSo, LoaiXe, KhoiLuongDenKg, TheTichToiDaM3, TrangThaiPhuongTien, DangHoatDong)
VALUES ('XE-Q6-001', N'59K1-724.18', 'MOTORBIKE', 100, 0.38, 'AVAILABLE', 1);
SET @Xe4 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien, BienSo, LoaiXe, KhoiLuongDenKg, TheTichToiDaM3, TrangThaiPhuongTien, DangHoatDong)
VALUES ('XE-Q6-002', N'59K2-518.42', 'MOTORBIKE', 85, 0.32, 'MAINTENANCE', 1);
SET @Xe5 = SCOPE_IDENTITY();

INSERT INTO dbo.PhanCongPhuongTien(MaNhanVienGiaoHang, MaPhuongTien, ThoiGianPhanCong, ThoiGianKetThuc, MaTaiKhoanPhanCong, GhiChu)
VALUES
(@S1, @Xe1, DATEADD(HOUR, -8, @Now), NULL, @TK_DPBT, N'Phân xe ca sáng'),
(@S2, @Xe2, DATEADD(HOUR, -8, @Now), NULL, @TK_DPBT, N'Phân xe ca sáng'),
(@S3, @Xe3, DATEADD(HOUR, -8, @Now), NULL, @TK_DPTP, N'Phân xe ca sáng'),
(@S4, @Xe4, DATEADD(HOUR, -8, @Now), NULL, @TK_DPQ6, N'Phân xe ca sáng');

INSERT INTO dbo.KhuVucNhanVienGiaoHang(MaNhanVienGiaoHang, MaKhuVuc, LaChinh) VALUES
(@S1, @KV_BHB, 1), (@S1, @KV_AL, 0),
(@S2, @KV_AL, 1), (@S2, @KV_BHB, 0),
(@S3, @KV_SK, 1), (@S3, @KV_TT, 0),
(@S4, @KV_Q6P10, 1), (@S4, @KV_Q6P12, 0),
(@S5, @KV_Q6P12, 1);

INSERT INTO dbo.LichSuViTriNhanVienGiaoHang(MaNhanVienGiaoHang, ViDo, KinhDo, DoChinhXacMet, ThoiGianGhiNhan) VALUES
(@S1, 10.810500, 106.604800, 4.8, DATEADD(MINUTE, -45, @Now)),
(@S1, 10.798200, 106.608900, 6.2, DATEADD(MINUTE, -30, @Now)),
(@S1, 10.775900, 106.612600, 5.4, DATEADD(MINUTE, -15, @Now)),
(@S2, 10.812000, 106.602900, 5.1, DATEADD(MINUTE, -40, @Now)),
(@S2, 10.805500, 106.607300, 7.4, DATEADD(MINUTE, -20, @Now)),
(@S3, 10.802900, 106.617900, 4.6, DATEADD(MINUTE, -35, @Now)),
(@S3, 10.798700, 106.622100, 5.2, DATEADD(MINUTE, -15, @Now)),
(@S4, 10.746900, 106.635800, 5.0, DATEADD(MINUTE, -25, @Now)),
(@S5, 10.748000, 106.637100, 6.0, DATEADD(MINUTE, -25, @Now));

/* =============================================================================
   PHẦN 4. QUY TẮC CẤU HÌNH TÍNH PHÍ VẬN CHUYỂN
   ============================================================================= */
PRINT N'4/16 - Cấu hình bảng phí vận chuyển...';

INSERT INTO dbo.QuyTacTinhPhi
(MaLoaiDichVu, MaKhuVuc, KhoangCachTuKm, KhoangCachDenKm, KhoiLuongTuKg, KhoiLuongDenKg,
 PhiCoBan, PhiMoiKm, PhiMoiKg, HieuLucTu, HieuLucDen, DangHoatDong)
VALUES
(@DV_STD, @KV_BT, 0, 25, 0, 20, 18000, 3500, 2500, DATEADD(DAY, -30, @Now), NULL, 1),
(@DV_EXP, @KV_BT, 0, 25, 0, 20, 28000, 5000, 3000, DATEADD(DAY, -30, @Now), NULL, 1),
(@DV_STD, @KV_TP, 0, 25, 0, 20, 18000, 3500, 2500, DATEADD(DAY, -30, @Now), NULL, 1),
(@DV_EXP, @KV_TP, 0, 25, 0, 20, 28000, 5000, 3000, DATEADD(DAY, -30, @Now), NULL, 1),
(@DV_STD, @KV_Q6, 0, 25, 0, 20, 18000, 3500, 2500, DATEADD(DAY, -30, @Now), NULL, 1),
(@DV_EXP, @KV_Q6, 0, 25, 0, 20, 28000, 5000, 3000, DATEADD(DAY, -30, @Now), NULL, 1);

/* =============================================================================
   PHẦN 5. 12 KHÁCH HÀNG & 12 ĐƠN HÀNG CHI TIẾT ĐẦY ĐỦ TRẠNG THÁI
   ============================================================================= */
PRINT N'5/16 - Tạo 12 khách hàng và 12 đơn hàng mẫu...';

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-DN-0001', N'Công ty TNHH Thương mại An Phúc', '0912000001', 'lienhe@anphuc.example', 'BUSINESS', 1);
SET @KH_ShopAnPhuc = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-DN-0002', N'Cửa hàng Gia Dụng Minh Tâm', '0912000002', 'minhtam@shop.example', 'BUSINESS', 1);
SET @KH_ShopMinhTam = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-DN-0003', N'Nội thất Nhà Xinh Online', '0912000003', 'nhaxinh@shop.example', 'BUSINESS', 1);
SET @KH_ShopNhaXinh = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-CN-0001', N'Nguyễn Ngọc Anh', '0912000101', 'ngocanh@example.com', 'INDIVIDUAL', 1);
SET @KH_01 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-CN-0002', N'Trần Khánh Vy', '0912000102', 'khanhvy@example.com', 'INDIVIDUAL', 1);
SET @KH_02 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-CN-0003', N'Lê Minh Khang', '0912000103', 'minhkhang@example.com', 'INDIVIDUAL', 1);
SET @KH_03 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-CN-0004', N'Phạm Thảo Nhi', '0912000104', 'thaonhi@example.com', 'INDIVIDUAL', 1);
SET @KH_04 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-CN-0005', N'Võ Quốc Huy', '0912000105', 'quochuy@example.com', 'INDIVIDUAL', 1);
SET @KH_05 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-CN-0006', N'Đặng Thu Hà', '0912000106', 'thuha@example.com', 'INDIVIDUAL', 1);
SET @KH_06 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-CN-0007', N'Bùi Gia Bảo', '0912000107', 'giabao@example.com', 'INDIVIDUAL', 1);
SET @KH_07 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-CN-0008', N'Hoàng Mỹ Linh', '0912000108', 'mylinh@example.com', 'INDIVIDUAL', 1);
SET @KH_08 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
VALUES ('KH-CN-0009', N'Ngô Đức Anh', '0912000109', 'ducanh@example.com', 'INDIVIDUAL', 1);
SET @KH_09 = SCOPE_IDENTITY();

INSERT INTO dbo.DiaChiKhachHang
(MaKhachHang, NhanDiaChi, TenNguoiLienHe, SoDienThoaiLienHe, DiaChi, MaKhuVuc, ViDo, KinhDo, LaMacDinh, DangHoatDong)
VALUES
(@KH_ShopAnPhuc, N'Kho Bình Tân', N'Nguyễn Thị Yến', '0912000001', N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.811800, 106.601500, 1, 1),
(@KH_ShopMinhTam, N'Cửa hàng Tân Phú', N'Trần Văn Dũng', '0912000002', N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM', @KV_SK, 10.803400, 106.618800, 1, 1),
(@KH_ShopNhaXinh, N'Kho Quận 6', N'Lê Thanh Bình', '0912000003', N'96 Hậu Giang, Phường 10, Quận 6, TP.HCM', @KV_Q6P10, 10.747800, 106.634900, 1, 1),
(@KH_01, N'Nhà riêng', N'Nguyễn Ngọc Anh', '0912000101', N'118 Đường số 5, An Lạc, Bình Tân, TP.HCM', @KV_AL, 10.728900, 106.615200, 1, 1),
(@KH_02, N'Nhà riêng', N'Trần Khánh Vy', '0912000102', N'76 Đường số 18B, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.816000, 106.598900, 1, 1),
(@KH_03, N'Căn hộ', N'Lê Minh Khang', '0912000103', N'25 Tân Hương, Tân Thành, Tân Phú, TP.HCM', @KV_TT, 10.789900, 106.628000, 1, 1),
(@KH_04, N'Nhà riêng', N'Phạm Thảo Nhi', '0912000104', N'212 Lê Trọng Tấn, Sơn Kỳ, Tân Phú, TP.HCM', @KV_SK, 10.806700, 106.624600, 1, 1),
(@KH_05, N'Văn phòng', N'Võ Quốc Huy', '0912000105', N'310 Hậu Giang, Phường 12, Quận 6, TP.HCM', @KV_Q6P12, 10.744100, 106.629800, 1, 1),
(@KH_06, N'Nhà riêng', N'Đặng Thu Hà', '0912000106', N'74 Bình Phú, Phường 10, Quận 6, TP.HCM', @KV_Q6P10, 10.741300, 106.637900, 1, 1),
(@KH_07, N'Nhà riêng', N'Bùi Gia Bảo', '0912000107', N'55 Đường số 1, An Lạc, Bình Tân, TP.HCM', @KV_AL, 10.731800, 106.611900, 1, 1),
(@KH_08, N'Công ty', N'Hoàng Mỹ Linh', '0912000108', N'101 Tân Quý, Tân Thành, Tân Phú, TP.HCM', @KV_TT, 10.795300, 106.625400, 1, 1),
(@KH_09, N'Nhà riêng', N'Ngô Đức Anh', '0912000109', N'89 Đường số 12, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.814300, 106.603200, 1, 1);

DECLARE @OrderInput TABLE(
    KyHieu VARCHAR(40) PRIMARY KEY,
    VanDon VARCHAR(50),
    MaBC INT,
    Sender BIGINT,
    Receiver BIGINT,
    ServiceId INT,
    ReadyMin INT,
    RequestMin INT,
    EtaMin INT,
    Priority TINYINT,
    Declared DECIMAL(18,2),
    COD DECIMAL(18,2),
    Shipping DECIMAL(18,2),
    Note NVARCHAR(500)
);

INSERT INTO @OrderInput
(KyHieu, VanDon, MaBC, Sender, Receiver, ServiceId, ReadyMin, RequestMin, EtaMin,
 Priority, Declared, COD, Shipping, Note)
VALUES
('DH-HCM-261002-0001', 'LM261002000001', @BC_BT, @KH_ShopAnPhuc, @KH_01, @DV_STD, -150, 120, 180, 2, 450000, 185000, 32000, N'Gọi khách trước 10 phút; hàng điện tử'),
('DH-HCM-261002-0002', 'LM261002000002', @BC_BT, @KH_ShopAnPhuc, @KH_02, @DV_STD, -145, 130, 190, 3, 280000, 0, 29000, N'Không để kiện hàng dưới mưa'),
('DH-HCM-261002-0003', 'LM261002000003', @BC_BT, @KH_ShopAnPhuc, @KH_07, @DV_EXP, -140, 90, 140, 1, 850000, 420000, 45000, N'Đơn ưu tiên, khách nhận tại nhà'),
('DH-HCM-261002-0004', 'LM261002000004', @BC_BT, @KH_ShopMinhTam, @KH_02, @DV_STD, -135, 150, 210, 3, 180000, 75000, 30000, N'Gia dụng nhỏ, đóng gói chống sốc'),
('DH-HCM-261002-0005', 'LM261002000005', @BC_BT, @KH_ShopAnPhuc, @KH_09, @DV_EXP, -120, 80, 130, 2, 520000, 220000, 43000, N'Khách thường đi làm, ưu tiên gọi trước'),
('DH-HCM-261002-0006', 'LM261002000006', @BC_BT, @KH_ShopMinhTam, @KH_01, @DV_STD, -115, 170, 230, 3, 390000, 0, 30000, N'Giao trong ngày'),
('DH-HCM-261002-0007', 'LM261002000007', @BC_TP, @KH_ShopMinhTam, @KH_03, @DV_EXP, -110, 90, 150, 1, 620000, 310000, 46000, N'Hàng dễ vỡ'),
('DH-HCM-261002-0008', 'LM261002000008', @BC_TP, @KH_ShopMinhTam, @KH_04, @DV_STD, -100, 180, 260, 3, 250000, 0, 31000, N'Chờ phân công shipper'),
('DH-HCM-261002-0009', 'LM261002000009', @BC_TP, @KH_ShopMinhTam, @KH_08, @DV_STD, -90, 210, 290, 4, 310000, 125000, 33000, N'Hàng đang lưu kho'),
('DH-HCM-261002-0010', 'LM261002000010', @BC_Q6, @KH_ShopNhaXinh, @KH_05, @DV_STD, -80, 220, 300, 3, 780000, 350000, 37000, N'Kiện hàng cồng kềnh vừa'),
('DH-HCM-261002-0011', 'LM261002000011', @BC_Q6, @KH_ShopNhaXinh, @KH_06, @DV_EXP, -70, 150, 220, 2, 560000, 0, 44000, N'Đã tiếp nhận, chờ nhập kho'),
('DH-HCM-261002-0012', 'LM261002000012', @BC_Q6, @KH_ShopNhaXinh, @KH_05, @DV_STD, -60, 240, 320, 5, 200000, 0, 30000, N'Khách yêu cầu hủy trước khi nhập kho');

DECLARE @OrderMap TABLE(KyHieu VARCHAR(40) PRIMARY KEY, MaDonHang BIGINT);

INSERT INTO dbo.DonHang
(KyHieuDonHang, MaVanDon, MaBuuCuc, MaNguoiGui, MaNguoiNhan, MaLoaiDichVu, MaTrangThaiHienTai,
 MaKhoHienTai, ThoiGianSanSang, ThoiGianYeuCauGiao, ThoiGianDuKienGiao, MucDoUuTien,
 GiaTriKhaiBao, TienCOD, PhiVanChuyen, GhiChuDacBiet, MaTaiKhoanTao, MaTaiKhoanCapNhatCuoi)
OUTPUT inserted.KyHieuDonHang, inserted.MaDonHang INTO @OrderMap
SELECT o.KyHieu, o.VanDon, o.MaBC, o.Sender, o.Receiver, o.ServiceId, @TT_NEW, NULL,
       DATEADD(MINUTE, o.ReadyMin, @Now),
       DATEADD(MINUTE, o.RequestMin, @Now),
       DATEADD(MINUTE, o.EtaMin, @Now),
       o.Priority, o.Declared, o.COD, o.Shipping, o.Note,
       CASE WHEN o.MaBC = @BC_BT THEN @TK_DPBT WHEN o.MaBC = @BC_TP THEN @TK_DPTP ELSE @TK_DPQ6 END,
       CASE WHEN o.MaBC = @BC_BT THEN @TK_DPBT WHEN o.MaBC = @BC_TP THEN @TK_DPTP ELSE @TK_DPQ6 END
FROM @OrderInput o;

DECLARE
    @O1 BIGINT, @O2 BIGINT, @O3 BIGINT, @O4 BIGINT,
    @O5 BIGINT, @O6 BIGINT, @O7 BIGINT, @O8 BIGINT,
    @O9 BIGINT, @O10 BIGINT, @O11 BIGINT, @O12 BIGINT;

SELECT @O1 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0001';
SELECT @O2 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0002';
SELECT @O3 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0003';
SELECT @O4 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0004';
SELECT @O5 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0005';
SELECT @O6 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0006';
SELECT @O7 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0007';
SELECT @O8 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0008';
SELECT @O9 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0009';
SELECT @O10 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0010';
SELECT @O11 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0011';
SELECT @O12 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0012';

-- Điểm lấy và điểm giao
INSERT INTO dbo.DiemGiaoNhan(MaDonHang, LoaiDiem, TenNguoiLienHe, SoDienThoaiLienHe, DiaChi, MaKhuVuc, ViDo, KinhDo, GhiChu)
VALUES
(@O1, 'PICKUP', N'Nguyễn Thị Yến', '0912000001', N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.811800, 106.601500, N'Kho cửa hàng'),
(@O1, 'DELIVERY', N'Nguyễn Ngọc Anh', '0912000101', N'118 Đường số 5, An Lạc, Bình Tân, TP.HCM', @KV_AL, 10.728900, 106.615200, N'Gọi trước 10 phút'),
(@O2, 'PICKUP', N'Nguyễn Thị Yến', '0912000001', N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.811800, 106.601500, NULL),
(@O2, 'DELIVERY', N'Trần Khánh Vy', '0912000102', N'76 Đường số 18B, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.816000, 106.598900, NULL),
(@O3, 'PICKUP', N'Nguyễn Thị Yến', '0912000001', N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.811800, 106.601500, NULL),
(@O3, 'DELIVERY', N'Bùi Gia Bảo', '0912000107', N'55 Đường số 1, An Lạc, Bình Tân, TP.HCM', @KV_AL, 10.731800, 106.611900, N'Khách nhận trực tiếp'),
(@O4, 'PICKUP', N'Trần Văn Dũng', '0912000002', N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM', @KV_SK, 10.803400, 106.618800, N'Hàng đã chuyển về bưu cục Bình Tân'),
(@O4, 'DELIVERY', N'Trần Khánh Vy', '0912000102', N'76 Đường số 18B, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.816000, 106.598900, NULL),
(@O5, 'PICKUP', N'Nguyễn Thị Yến', '0912000001', N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.811800, 106.601500, NULL),
(@O5, 'DELIVERY', N'Ngô Đức Anh', '0912000109', N'89 Đường số 12, Bình Hưng Hòa B, Bình Tân, TP.HCM', @KV_BHB, 10.814300, 106.603200, N'Khách thường đi làm'),
(@O6, 'PICKUP', N'Trần Văn Dũng', '0912000002', N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM', @KV_SK, 10.803400, 106.618800, NULL),
(@O6, 'DELIVERY', N'Nguyễn Ngọc Anh', '0912000101', N'118 Đường số 5, An Lạc, Bình Tân, TP.HCM', @KV_AL, 10.728900, 106.615200, NULL),
(@O7, 'PICKUP', N'Trần Văn Dũng', '0912000002', N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM', @KV_SK, 10.803400, 106.618800, NULL),
(@O7, 'DELIVERY', N'Lê Minh Khang', '0912000103', N'25 Tân Hương, Tân Thành, Tân Phú, TP.HCM', @KV_TT, 10.789900, 106.628000, N'Hàng dễ vỡ'),
(@O8, 'PICKUP', N'Trần Văn Dũng', '0912000002', N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM', @KV_SK, 10.803400, 106.618800, NULL),
(@O8, 'DELIVERY', N'Phạm Thảo Nhi', '0912000104', N'212 Lê Trọng Tấn, Sơn Kỳ, Tân Phú, TP.HCM', @KV_SK, 10.806700, 106.624600, NULL),
(@O9, 'PICKUP', N'Trần Văn Dũng', '0912000002', N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM', @KV_SK, 10.803400, 106.618800, NULL),
(@O9, 'DELIVERY', N'Hoàng Mỹ Linh', '0912000108', N'101 Tân Quý, Tân Thành, Tân Phú, TP.HCM', @KV_TT, 10.795300, 106.625400, NULL),
(@O10, 'PICKUP', N'Lê Thanh Bình', '0912000003', N'96 Hậu Giang, Phường 10, Quận 6, TP.HCM', @KV_Q6P10, 10.747800, 106.634900, NULL),
(@O10, 'DELIVERY', N'Võ Quốc Huy', '0912000105', N'310 Hậu Giang, Phường 12, Quận 6, TP.HCM', @KV_Q6P12, 10.744100, 106.629800, NULL),
(@O11, 'PICKUP', N'Lê Thanh Bình', '0912000003', N'96 Hậu Giang, Phường 10, Quận 6, TP.HCM', @KV_Q6P10, 10.747800, 106.634900, NULL),
(@O11, 'DELIVERY', N'Đặng Thu Hà', '0912000106', N'74 Bình Phú, Phường 10, Quận 6, TP.HCM', @KV_Q6P10, 10.741300, 106.637900, NULL),
(@O12, 'PICKUP', N'Lê Thanh Bình', '0912000003', N'96 Hậu Giang, Phường 10, Quận 6, TP.HCM', @KV_Q6P10, 10.747800, 106.634900, NULL),
(@O12, 'DELIVERY', N'Võ Quốc Huy', '0912000105', N'310 Hậu Giang, Phường 12, Quận 6, TP.HCM', @KV_Q6P12, 10.744100, 106.629800, NULL);

-- Hàng hóa chi tiết (Đủ kích thước để trigger kiểm tra thể tích phương tiện)
INSERT INTO dbo.ChiTietDonHang(MaDonHang, TenHang, LoaiHang, SoLuong, KhoiLuongDonViKg, ChieuDaiCm, ChieuRongCm, ChieuCaoCm, GiaTriHang, HangDeVo, GhiChu)
VALUES
(@O1, N'Tai nghe Bluetooth', N'Điện tử', 1, 0.35, 18, 12, 6, 450000, 1, N'Đóng hộp chống sốc'),
(@O2, N'Áo khoác unisex', N'Thời trang', 1, 0.60, 35, 28, 8, 280000, 0, NULL),
(@O3, N'Máy xay mini', N'Gia dụng', 1, 1.20, 28, 22, 24, 850000, 1, N'Không lật ngược'),
(@O4, N'Bộ hộp đựng thực phẩm', N'Gia dụng', 1, 1.60, 38, 28, 24, 180000, 0, NULL),
(@O5, N'Bàn phím cơ', N'Điện tử', 1, 1.10, 48, 20, 8, 520000, 1, N'Tránh va đập'),
(@O6, N'Bộ khăn tắm cotton', N'Gia dụng', 2, 0.70, 32, 25, 10, 195000, 0, NULL),
(@O7, N'Bình giữ nhiệt inox', N'Gia dụng', 2, 0.55, 28, 12, 12, 310000, 1, N'Đóng chống sốc'),
(@O8, N'Giày thể thao', N'Thời trang', 1, 0.95, 34, 22, 13, 250000, 0, NULL),
(@O9, N'Chuột không dây', N'Điện tử', 1, 0.25, 16, 10, 6, 310000, 1, NULL),
(@O10, N'Đèn bàn trang trí', N'Nội thất', 2, 1.60, 36, 26, 24, 390000, 1, N'Kiện cồng kềnh vừa'),
(@O11, N'Bộ ga gối cotton', N'Nội thất', 1, 2.20, 42, 34, 18, 560000, 0, NULL),
(@O12, N'Kệ để đồ mini', N'Nội thất', 1, 3.00, 60, 35, 15, 200000, 0, NULL);

-- Các khoản phí
INSERT INTO dbo.KhoanPhiDonHang(MaDonHang, LoaiKhoanPhi, SoTien, MoTa)
VALUES
(@O1, 'SHIPPING', 32000, N'Phí giao tiêu chuẩn'),
(@O2, 'SHIPPING', 29000, N'Phí giao tiêu chuẩn'),
(@O3, 'SHIPPING', 45000, N'Phí giao nhanh'),
(@O3, 'SURCHARGE', 8000, N'Phụ phí ưu tiên'),
(@O4, 'SHIPPING', 30000, N'Phí giao tiêu chuẩn'),
(@O5, 'SHIPPING', 43000, N'Phí giao nhanh'),
(@O6, 'SHIPPING', 30000, N'Phí giao tiêu chuẩn'),
(@O7, 'SHIPPING', 46000, N'Phí giao nhanh'),
(@O7, 'SURCHARGE', 7000, N'Phụ phí hàng dễ vỡ'),
(@O8, 'SHIPPING', 31000, N'Phí giao tiêu chuẩn'),
(@O9, 'SHIPPING', 33000, N'Phí giao tiêu chuẩn'),
(@O10, 'SHIPPING', 37000, N'Phí giao tiêu chuẩn'),
(@O10, 'SURCHARGE', 12000, N'Phụ phí kiện cồng kềnh'),
(@O11, 'SHIPPING', 44000, N'Phí giao nhanh'),
(@O12, 'SHIPPING', 30000, N'Phí dự kiến trước khi hủy');

/* =============================================================================
   PHẦN 6. VẬN HÀNH ĐƠN 1..12 QUA STORED PROCEDURES
   ============================================================================= */
PRINT N'6/16 - Chuyển trạng thái đầu vòng đời đơn 1..12...';

-- Hủy đơn 12 trước khi vào kho
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O12,
     @KyHieuTrangThaiMoi = 'CANCELLED',
     @MaTaiKhoan = @TK_DPQ6,
     @LyDo = N'Khách hàng yêu cầu hủy trước khi hàng vào kho',
     @NguonCapNhat = 'WEB';

DECLARE
    @idx INT = 1,
    @oid BIGINT,
    @creator BIGINT,
    @warehouseAccount BIGINT,
    @retryTime DATETIME2(0);

WHILE @idx <= 11
BEGIN
    SELECT @oid = MaDonHang,
           @creator = CASE WHEN @idx <= 6 THEN @TK_DPBT WHEN @idx <= 9 THEN @TK_DPTP ELSE @TK_DPQ6 END
    FROM @OrderMap WHERE KyHieu = CONCAT('DH-HCM-261002-', RIGHT('0000' + CONVERT(VARCHAR(4), @idx), 4));

    EXEC dbo.sp_XacNhanDonHang
         @MaDonHang = @oid,
         @MaTaiKhoan = @creator;

    SET @warehouseAccount =
        CASE
            WHEN @idx <= 6 THEN @TK_KhoBT
            WHEN @idx <= 9 THEN @TK_KhoTP
            ELSE @TK_KhoQ6
        END;

    EXEC dbo.sp_ChuyenTrangThaiDonHang
         @MaDonHang = @oid,
         @KyHieuTrangThaiMoi = 'WAITING_INBOUND',
         @MaTaiKhoan = @warehouseAccount,
         @LyDo = NULL,
         @NguonCapNhat = 'WEB';
    SET @idx = @idx + 1;
END;

-- Nhập kho cho đơn 1..10 (Đơn 11 giữ WAITING_INBOUND)
PRINT N'7/16 - Nhập kho cho đơn 1..10...';

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich, MaKho, LoaiGiaoDich, TrangThaiGiaoDich, MaTaiKhoanThucHien, ThoiGianThucHien, GhiChu)
VALUES ('GD-BT-IN-261002-01', @Kho_BT, 'INBOUND', 'COMPLETED', @TK_KhoBT, DATEADD(MINUTE, -80, @Now), N'Nhập lô hàng đầu ca Bình Tân');
SET @WT_BT_IN = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho, MaDonHang, MaViTriNguon, MaViTriDich, TinhTrangHang, GhiChu)
VALUES
(@WT_BT_IN, @O1, NULL, @VT_BT_A1, 'NORMAL', N'Bao bì nguyên vẹn'),
(@WT_BT_IN, @O2, NULL, @VT_BT_A1, 'NORMAL', N'Bao bì nguyên vẹn'),
(@WT_BT_IN, @O3, NULL, @VT_BT_A2, 'NORMAL', N'Đã dán tem dễ vỡ'),
(@WT_BT_IN, @O4, NULL, @VT_BT_A2, 'NORMAL', N'Bao bì nguyên vẹn'),
(@WT_BT_IN, @O5, NULL, @VT_BT_A3, 'NORMAL', N'Bao bì nguyên vẹn'),
(@WT_BT_IN, @O6, NULL, @VT_BT_A3, 'NORMAL', N'Bao bì nguyên vẹn');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich, MaKho, LoaiGiaoDich, TrangThaiGiaoDich, MaTaiKhoanThucHien, ThoiGianThucHien, GhiChu)
VALUES ('GD-TP-IN-261002-01', @Kho_TP, 'INBOUND', 'COMPLETED', @TK_KhoTP, DATEADD(MINUTE, -75, @Now), N'Nhập hàng Tân Phú');
SET @WT_TP_IN = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho, MaDonHang, MaViTriNguon, MaViTriDich, TinhTrangHang, GhiChu)
VALUES
(@WT_TP_IN, @O7, NULL, @VT_TP_A1, 'NORMAL', N'Đã dán tem dễ vỡ'),
(@WT_TP_IN, @O8, NULL, @VT_TP_A2, 'NORMAL', N'Bao bì nguyên vẹn'),
(@WT_TP_IN, @O9, NULL, @VT_TP_A2, 'NORMAL', N'Bao bì nguyên vẹn');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich, MaKho, LoaiGiaoDich, TrangThaiGiaoDich, MaTaiKhoanThucHien, ThoiGianThucHien, GhiChu)
VALUES ('GD-Q6-IN-261002-01', @Kho_Q6, 'INBOUND', 'COMPLETED', @TK_KhoQ6, DATEADD(MINUTE, -70, @Now), N'Nhập hàng Quận 6');
SET @WT_Q6_IN = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho, MaDonHang, MaViTriNguon, MaViTriDich, TinhTrangHang, GhiChu)
VALUES (@WT_Q6_IN, @O10, NULL, @VT_Q6_A1, 'NORMAL', N'Bao bì nguyên vẹn');

INSERT INTO dbo.TonKhoDonHang(MaDonHang, MaKho, MaViTriLuuKho, TrangThaiTonKho, ThoiGianNhapKho, ThoiGianDiChuyenCuoi, MaTaiKhoanCapNhatCuoi)
VALUES
(@O1, @Kho_BT, @VT_BT_A1, 'STORED', DATEADD(MINUTE, -80, @Now), DATEADD(MINUTE, -78, @Now), @TK_KhoBT),
(@O2, @Kho_BT, @VT_BT_A1, 'STORED', DATEADD(MINUTE, -80, @Now), DATEADD(MINUTE, -78, @Now), @TK_KhoBT),
(@O3, @Kho_BT, @VT_BT_A2, 'STORED', DATEADD(MINUTE, -80, @Now), DATEADD(MINUTE, -78, @Now), @TK_KhoBT),
(@O4, @Kho_BT, @VT_BT_A2, 'STORED', DATEADD(MINUTE, -80, @Now), DATEADD(MINUTE, -78, @Now), @TK_KhoBT),
(@O5, @Kho_BT, @VT_BT_A3, 'STORED', DATEADD(MINUTE, -80, @Now), DATEADD(MINUTE, -78, @Now), @TK_KhoBT),
(@O6, @Kho_BT, @VT_BT_A3, 'STORED', DATEADD(MINUTE, -80, @Now), DATEADD(MINUTE, -78, @Now), @TK_KhoBT),
(@O7, @Kho_TP, @VT_TP_A1, 'STORED', DATEADD(MINUTE, -75, @Now), DATEADD(MINUTE, -73, @Now), @TK_KhoTP),
(@O8, @Kho_TP, @VT_TP_A2, 'STORED', DATEADD(MINUTE, -75, @Now), DATEADD(MINUTE, -73, @Now), @TK_KhoTP),
(@O9, @Kho_TP, @VT_TP_A2, 'STORED', DATEADD(MINUTE, -75, @Now), DATEADD(MINUTE, -73, @Now), @TK_KhoTP),
(@O10, @Kho_Q6, @VT_Q6_A1, 'STORED', DATEADD(MINUTE, -70, @Now), DATEADD(MINUTE, -68, @Now), @TK_KhoQ6);

UPDATE dbo.DonHang SET MaKhoHienTai = @Kho_BT, MaTaiKhoanCapNhatCuoi = @TK_KhoBT WHERE MaDonHang IN (@O1, @O2, @O3, @O4, @O5, @O6);
UPDATE dbo.DonHang SET MaKhoHienTai = @Kho_TP, MaTaiKhoanCapNhatCuoi = @TK_KhoTP WHERE MaDonHang IN (@O7, @O8, @O9);
UPDATE dbo.DonHang SET MaKhoHienTai = @Kho_Q6, MaTaiKhoanCapNhatCuoi = @TK_KhoQ6 WHERE MaDonHang = @O10;

SET @idx = 1;
WHILE @idx <= 10
BEGIN
    SELECT @oid = MaDonHang FROM @OrderMap
    WHERE KyHieu = CONCAT('DH-HCM-261002-', RIGHT('0000' + CONVERT(VARCHAR(4), @idx), 4));

    SET @warehouseAccount =
        CASE
            WHEN @idx <= 6 THEN @TK_KhoBT
            WHEN @idx <= 9 THEN @TK_KhoTP
            ELSE @TK_KhoQ6
        END;

    EXEC dbo.sp_ChuyenTrangThaiDonHang
         @MaDonHang = @oid,
         @KyHieuTrangThaiMoi = 'IN_WAREHOUSE',
         @MaTaiKhoan = @warehouseAccount,
         @LyDo = NULL,
         @NguonCapNhat = 'WEB';
    SET @idx = @idx + 1;
END;

-- Đơn 1..8 và 10 chuyển chờ phân công; đơn 9 giữ IN_WAREHOUSE
SET @idx = 1;
WHILE @idx <= 10
BEGIN
    IF @idx <> 9
    BEGIN
        SELECT @oid = MaDonHang FROM @OrderMap
        WHERE KyHieu = CONCAT('DH-HCM-261002-', RIGHT('0000' + CONVERT(VARCHAR(4), @idx), 4));

        SET @warehouseAccount =
            CASE
                WHEN @idx <= 6 THEN @TK_DPBT
                WHEN @idx <= 9 THEN @TK_DPTP
                ELSE @TK_DPQ6
            END;

        EXEC dbo.sp_ChuyenTrangThaiDonHang
             @MaDonHang = @oid,
             @KyHieuTrangThaiMoi = 'WAITING_ASSIGNMENT',
             @MaTaiKhoan = @warehouseAccount,
             @LyDo = NULL,
             @NguonCapNhat = 'WEB';
    END;
    SET @idx = @idx + 1;
END;

/* =============================================================================
   PHẦN 7. CHUYẾN 1 - BÌNH TÂN: 4 ĐƠN GIAO THÀNH CÔNG (COMPLETED)
   ============================================================================= */
PRINT N'8/16 - Chuyến 1 hoàn tất giao 4 đơn Bình Tân...';

INSERT INTO dbo.ChuyenGiaoHang
(KyHieuChuyenGiao, MaBuuCuc, MaKho, MaNhanVienGiaoHang, MaPhuongTien, TrangThaiChuyen,
 PhuongPhapToiUu, TongQuangDuongKm, ThoiGianDuKienPhut, ThoiGianBatDauDuKien, MaTaiKhoanTao)
VALUES ('CG-BT-261002-001', @BC_BT, @Kho_BT, @S1, @Xe1, 'PLANNED', 'VRP', 23.40, 105, DATEADD(MINUTE, -55, @Now), @TK_DPBT);
SET @Trip1 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietChuyenGiao(MaChuyenGiao, MaDonHang, ThuTuDuKien, ThoiGianDenDuKien, ThoiGianDenThucTe)
VALUES
(@Trip1, @O1, 1, DATEADD(MINUTE, -25, @Now), NULL),
(@Trip1, @O3, 2, DATEADD(MINUTE, -5, @Now), NULL),
(@Trip1, @O2, 3, DATEADD(MINUTE, 15, @Now), NULL),
(@Trip1, @O4, 4, DATEADD(MINUTE, 35, @Now), NULL);

DECLARE @D1 BIGINT, @D2 BIGINT, @D3 BIGINT, @D4 BIGINT;
SELECT @D1 = MaDiemGiaoNhan FROM dbo.DiemGiaoNhan WHERE MaDonHang = @O1 AND LoaiDiem = 'DELIVERY';
SELECT @D2 = MaDiemGiaoNhan FROM dbo.DiemGiaoNhan WHERE MaDonHang = @O2 AND LoaiDiem = 'DELIVERY';
SELECT @D3 = MaDiemGiaoNhan FROM dbo.DiemGiaoNhan WHERE MaDonHang = @O3 AND LoaiDiem = 'DELIVERY';
SELECT @D4 = MaDiemGiaoNhan FROM dbo.DiemGiaoNhan WHERE MaDonHang = @O4 AND LoaiDiem = 'DELIVERY';

INSERT INTO dbo.DiemDungTuyen(MaChuyenGiao, MaDonHang, MaDiemGiaoNhan, ThuTuDiemDung, LoaiDiem, ViDo, KinhDo, ThoiGianDenDuKien, KhoangCachTuDiemTruocKm, ThoiGianTuDiemTruocPhut)
VALUES
(@Trip1, NULL, NULL, 1, 'BRANCH', 10.810500, 106.604800, DATEADD(MINUTE, -55, @Now), NULL, NULL),
(@Trip1, @O1, @D1, 2, 'DELIVERY', 10.728900, 106.615200, DATEADD(MINUTE, -25, @Now), 10.4, 30),
(@Trip1, @O3, @D3, 3, 'DELIVERY', 10.731800, 106.611900, DATEADD(MINUTE, -5, @Now), 2.2, 15),
(@Trip1, @O2, @D2, 4, 'DELIVERY', 10.816000, 106.598900, DATEADD(MINUTE, 15, @Now), 11.1, 25),
(@Trip1, @O4, @D4, 5, 'DELIVERY', 10.816000, 106.598900, DATEADD(MINUTE, 35, @Now), 0.2, 5);

DECLARE @PC1 BIGINT, @PC2 BIGINT, @PC3 BIGINT, @PC4 BIGINT;
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang, MaChuyenGiao, MaNhanVienGiaoHang, MaPhuongTien, MaTaiKhoanPhanCong, ThoiGianPhanCong, TrangThaiPhanCong, BoQuaQuyTacKhuVuc)
VALUES (@O1, @Trip1, @S1, @Xe1, @TK_DPBT, DATEADD(MINUTE, -52, @Now), 'PENDING', 0); SET @PC1 = SCOPE_IDENTITY();
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang, MaChuyenGiao, MaNhanVienGiaoHang, MaPhuongTien, MaTaiKhoanPhanCong, ThoiGianPhanCong, TrangThaiPhanCong, BoQuaQuyTacKhuVuc)
VALUES (@O2, @Trip1, @S1, @Xe1, @TK_DPBT, DATEADD(MINUTE, -52, @Now), 'PENDING', 0); SET @PC2 = SCOPE_IDENTITY();
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang, MaChuyenGiao, MaNhanVienGiaoHang, MaPhuongTien, MaTaiKhoanPhanCong, ThoiGianPhanCong, TrangThaiPhanCong, BoQuaQuyTacKhuVuc)
VALUES (@O3, @Trip1, @S1, @Xe1, @TK_DPBT, DATEADD(MINUTE, -52, @Now), 'PENDING', 0); SET @PC3 = SCOPE_IDENTITY();
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang, MaChuyenGiao, MaNhanVienGiaoHang, MaPhuongTien, MaTaiKhoanPhanCong, ThoiGianPhanCong, TrangThaiPhanCong, BoQuaQuyTacKhuVuc)
VALUES (@O4, @Trip1, @S1, @Xe1, @TK_DPBT, DATEADD(MINUTE, -52, @Now), 'PENDING', 0); SET @PC4 = SCOPE_IDENTITY();

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O1, @KyHieuTrangThaiMoi = 'ASSIGNED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O2, @KyHieuTrangThaiMoi = 'ASSIGNED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O3, @KyHieuTrangThaiMoi = 'ASSIGNED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O4, @KyHieuTrangThaiMoi = 'ASSIGNED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'WEB';

UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong = 'ACCEPTED', ThoiGianChapNhan = DATEADD(MINUTE, -50, @Now) WHERE MaPhanCongGiaoHang IN (@PC1, @PC2, @PC3, @PC4);
UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen = 'ACCEPTED', ThoiGianBatDauThucTe = DATEADD(MINUTE, -48, @Now) WHERE MaChuyenGiao = @Trip1;
UPDATE dbo.TonKhoDonHang SET TrangThaiTonKho = 'ALLOCATED', ThoiGianDiChuyenCuoi = DATEADD(MINUTE, -47, @Now), MaTaiKhoanCapNhatCuoi = @TK_KhoBT WHERE MaDonHang IN (@O1, @O2, @O3, @O4);

INSERT INTO dbo.BanGiaoHang(KyHieuBanGiao, MaKho, MaNhanVienGiaoHang, MaTaiKhoanBanGiao, TrangThaiBanGiao, ThoiGianBanGiao, ThoiGianNhanVienXacNhan, GhiChu)
VALUES ('BG-BT-261002-001', @Kho_BT, @S1, @TK_KhoBT, 'CONFIRMED', DATEADD(MINUTE, -46, @Now), DATEADD(MINUTE, -45, @Now), N'Bàn giao chuyến sáng Bình Tân');
SET @Handover1 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietBanGiaoHang(MaBanGiao, MaDonHang, SoLuong, GhiChuTinhTrang)
VALUES
(@Handover1, @O1, 1, N'Nguyên vẹn'), (@Handover1, @O2, 1, N'Nguyên vẹn'),
(@Handover1, @O3, 1, N'Đã kiểm tem dễ vỡ'), (@Handover1, @O4, 1, N'Nguyên vẹn');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich, MaKho, LoaiGiaoDich, TrangThaiGiaoDich, MaTaiKhoanThucHien, ThoiGianThucHien, GhiChu)
VALUES ('GD-BT-OUT-261002-01', @Kho_BT, 'OUTBOUND', 'COMPLETED', @TK_KhoBT, DATEADD(MINUTE, -44, @Now), N'Xuất chuyến CG-BT-261002-001');
SET @WT_BT_OUT1 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho, MaDonHang, MaViTriNguon, MaViTriDich, TinhTrangHang, GhiChu)
VALUES
(@WT_BT_OUT1, @O1, @VT_BT_A1, NULL, 'NORMAL', N'Xuất giao'),
(@WT_BT_OUT1, @O2, @VT_BT_A1, NULL, 'NORMAL', N'Xuất giao'),
(@WT_BT_OUT1, @O3, @VT_BT_A2, NULL, 'NORMAL', N'Xuất giao'),
(@WT_BT_OUT1, @O4, @VT_BT_A2, NULL, 'NORMAL', N'Xuất giao');

UPDATE dbo.TonKhoDonHang SET TrangThaiTonKho = 'HANDED_OVER', MaViTriLuuKho = NULL, ThoiGianDiChuyenCuoi = DATEADD(MINUTE, -43, @Now), MaTaiKhoanCapNhatCuoi = @TK_KhoBT WHERE MaDonHang IN (@O1, @O2, @O3, @O4);

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O1, @KyHieuTrangThaiMoi = 'HANDED_OVER', @MaTaiKhoan = @TK_KhoBT, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O2, @KyHieuTrangThaiMoi = 'HANDED_OVER', @MaTaiKhoan = @TK_KhoBT, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O3, @KyHieuTrangThaiMoi = 'HANDED_OVER', @MaTaiKhoan = @TK_KhoBT, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O4, @KyHieuTrangThaiMoi = 'HANDED_OVER', @MaTaiKhoan = @TK_KhoBT, @LyDo = NULL, @NguonCapNhat = 'WEB';

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O1, @KyHieuTrangThaiMoi = 'PICKED_UP', @MaTaiKhoan = @TK_S1, @LyDo = NULL, @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O2, @KyHieuTrangThaiMoi = 'PICKED_UP', @MaTaiKhoan = @TK_S1, @LyDo = NULL, @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O3, @KyHieuTrangThaiMoi = 'PICKED_UP', @MaTaiKhoan = @TK_S1, @LyDo = NULL, @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O4, @KyHieuTrangThaiMoi = 'PICKED_UP', @MaTaiKhoan = @TK_S1, @LyDo = NULL, @NguonCapNhat = 'MOBILE';

UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong = 'IN_PROGRESS' WHERE MaPhanCongGiaoHang IN (@PC1, @PC2, @PC3, @PC4);
UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen = 'IN_PROGRESS' WHERE MaChuyenGiao = @Trip1;
UPDATE dbo.NhanVienGiaoHang SET TrangThaiSanSang = 'DELIVERING' WHERE MaNhanVienGiaoHang = @S1;
UPDATE dbo.PhuongTien SET TrangThaiPhuongTien = 'IN_USE' WHERE MaPhuongTien = @Xe1;

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O1, @KyHieuTrangThaiMoi = 'IN_DELIVERY', @MaTaiKhoan = @TK_S1, @LyDo = NULL, @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O2, @KyHieuTrangThaiMoi = 'IN_DELIVERY', @MaTaiKhoan = @TK_S1, @LyDo = NULL, @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O3, @KyHieuTrangThaiMoi = 'IN_DELIVERY', @MaTaiKhoan = @TK_S1, @LyDo = NULL, @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O4, @KyHieuTrangThaiMoi = 'IN_DELIVERY', @MaTaiKhoan = @TK_S1, @LyDo = NULL, @NguonCapNhat = 'MOBILE';

-- Xác nhận giao thành công với đủ 4 loại POD
EXEC dbo.sp_XacNhanGiaoHangThanhCong
     @MaDonHang = @O1, @MaNhanVienGiaoHang = @S1, @MaTaiKhoan = @TK_S1,
     @LoaiBangChung = 'PHOTO', @DuongDanTep = N'/pod/2026/10/02/LM261002000001.jpg',
     @MaXacNhanBam = NULL, @TenNguoiNhan = NULL, @ViDo = 10.728900, @KinhDo = 106.615200,
     @SoTienThucThu = 185000, @GhiChuCOD = N'Thu tiền mặt đủ 185.000đ';

EXEC dbo.sp_XacNhanGiaoHangThanhCong
     @MaDonHang = @O2, @MaNhanVienGiaoHang = @S1, @MaTaiKhoan = @TK_S1,
     @LoaiBangChung = 'OTP', @DuongDanTep = NULL,
     @MaXacNhanBam = 'OTP_HASH_928461', @TenNguoiNhan = NULL, @ViDo = 10.816000, @KinhDo = 106.598900,
     @SoTienThucThu = NULL, @GhiChuCOD = NULL;

EXEC dbo.sp_XacNhanGiaoHangThanhCong
     @MaDonHang = @O3, @MaNhanVienGiaoHang = @S1, @MaTaiKhoan = @TK_S1,
     @LoaiBangChung = 'SIGNATURE', @DuongDanTep = N'/pod/2026/10/02/LM261002000003-sign.png',
     @MaXacNhanBam = NULL, @TenNguoiNhan = NULL, @ViDo = 10.731800, @KinhDo = 106.611900,
     @SoTienThucThu = 420000, @GhiChuCOD = N'Thu tiền mặt đủ 420.000đ';

EXEC dbo.sp_XacNhanGiaoHangThanhCong
     @MaDonHang = @O4, @MaNhanVienGiaoHang = @S1, @MaTaiKhoan = @TK_S1,
     @LoaiBangChung = 'RECEIVER_CONFIRMATION', @DuongDanTep = NULL,
     @MaXacNhanBam = NULL, @TenNguoiNhan = N'Trần Khánh Vy', @ViDo = 10.816000, @KinhDo = 106.598900,
     @SoTienThucThu = 75000, @GhiChuCOD = N'Thu tiền mặt đủ 75.000đ';

-- Chuyển DELIVERED sang COMPLETED
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O1, @KyHieuTrangThaiMoi = 'COMPLETED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'SYSTEM';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O2, @KyHieuTrangThaiMoi = 'COMPLETED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'SYSTEM';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O3, @KyHieuTrangThaiMoi = 'COMPLETED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'SYSTEM';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O4, @KyHieuTrangThaiMoi = 'COMPLETED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'SYSTEM';

UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen = 'COMPLETED', ThoiGianKetThucThucTe = SYSUTCDATETIME() WHERE MaChuyenGiao = @Trip1;
UPDATE dbo.NhanVienGiaoHang SET TrangThaiSanSang = 'AVAILABLE' WHERE MaNhanVienGiaoHang = @S1;
UPDATE dbo.PhuongTien SET TrangThaiPhuongTien = 'AVAILABLE' WHERE MaPhuongTien = @Xe1;

/* =============================================================================
   PHẦN 8. CHUYẾN 2 - BÌNH TÂN: 1 ĐƠN THẤT BẠI CHỜ GIAO LẠI + 1 ĐƠN ĐANG GIAO
   ============================================================================= */
PRINT N'9/16 - Chuyến 2 Bình Tân đang hoạt động...';

INSERT INTO dbo.ChuyenGiaoHang
(KyHieuChuyenGiao, MaBuuCuc, MaKho, MaNhanVienGiaoHang, MaPhuongTien, TrangThaiChuyen,
 PhuongPhapToiUu, TongQuangDuongKm, ThoiGianDuKienPhut, ThoiGianBatDauDuKien, MaTaiKhoanTao)
VALUES ('CG-BT-261002-002', @BC_BT, @Kho_BT, @S2, @Xe2, 'PLANNED', 'VRP', 16.80, 80, DATEADD(MINUTE, -35, @Now), @TK_DPBT);
SET @Trip2 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietChuyenGiao(MaChuyenGiao, MaDonHang, ThuTuDuKien, ThoiGianDenDuKien)
VALUES (@Trip2, @O5, 1, DATEADD(MINUTE, -5, @Now)), (@Trip2, @O6, 2, DATEADD(MINUTE, 25, @Now));

DECLARE @D5 BIGINT, @D6 BIGINT;
SELECT @D5 = MaDiemGiaoNhan FROM dbo.DiemGiaoNhan WHERE MaDonHang = @O5 AND LoaiDiem = 'DELIVERY';
SELECT @D6 = MaDiemGiaoNhan FROM dbo.DiemGiaoNhan WHERE MaDonHang = @O6 AND LoaiDiem = 'DELIVERY';

INSERT INTO dbo.DiemDungTuyen(MaChuyenGiao, MaDonHang, MaDiemGiaoNhan, ThuTuDiemDung, LoaiDiem, ViDo, KinhDo, ThoiGianDenDuKien, KhoangCachTuDiemTruocKm, ThoiGianTuDiemTruocPhut)
VALUES
(@Trip2, NULL, NULL, 1, 'BRANCH', 10.810500, 106.604800, DATEADD(MINUTE, -35, @Now), NULL, NULL),
(@Trip2, @O5, @D5, 2, 'DELIVERY', 10.814300, 106.603200, DATEADD(MINUTE, -5, @Now), 3.2, 15),
(@Trip2, @O6, @D6, 3, 'DELIVERY', 10.728900, 106.615200, DATEADD(MINUTE, 25, @Now), 10.8, 30);

DECLARE @PC5 BIGINT, @PC6 BIGINT;
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang, MaChuyenGiao, MaNhanVienGiaoHang, MaPhuongTien, MaTaiKhoanPhanCong, ThoiGianPhanCong, TrangThaiPhanCong, BoQuaQuyTacKhuVuc)
VALUES (@O5, @Trip2, @S2, @Xe2, @TK_DPBT, DATEADD(MINUTE, -33, @Now), 'PENDING', 0); SET @PC5 = SCOPE_IDENTITY();
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang, MaChuyenGiao, MaNhanVienGiaoHang, MaPhuongTien, MaTaiKhoanPhanCong, ThoiGianPhanCong, TrangThaiPhanCong, BoQuaQuyTacKhuVuc)
VALUES (@O6, @Trip2, @S2, @Xe2, @TK_DPBT, DATEADD(MINUTE, -33, @Now), 'PENDING', 0); SET @PC6 = SCOPE_IDENTITY();

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O5, @KyHieuTrangThaiMoi = 'ASSIGNED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O6, @KyHieuTrangThaiMoi = 'ASSIGNED', @MaTaiKhoan = @TK_DPBT, @LyDo = NULL, @NguonCapNhat = 'WEB';

UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong = 'ACCEPTED', ThoiGianChapNhan = DATEADD(MINUTE, -31, @Now) WHERE MaPhanCongGiaoHang IN (@PC5, @PC6);
UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen = 'ACCEPTED', ThoiGianBatDauThucTe = DATEADD(MINUTE, -30, @Now) WHERE MaChuyenGiao = @Trip2;
UPDATE dbo.TonKhoDonHang SET TrangThaiTonKho = 'ALLOCATED', ThoiGianDiChuyenCuoi = DATEADD(MINUTE, -29, @Now), MaTaiKhoanCapNhatCuoi = @TK_KhoBT WHERE MaDonHang IN (@O5, @O6);

INSERT INTO dbo.BanGiaoHang(KyHieuBanGiao, MaKho, MaNhanVienGiaoHang, MaTaiKhoanBanGiao, TrangThaiBanGiao, ThoiGianBanGiao, ThoiGianNhanVienXacNhan, GhiChu)
VALUES ('BG-BT-261002-002', @Kho_BT, @S2, @TK_KhoBT, 'CONFIRMED', DATEADD(MINUTE, -28, @Now), DATEADD(MINUTE, -27, @Now), N'Bàn giao chuyến đang giao');
SET @Handover2 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietBanGiaoHang(MaBanGiao, MaDonHang, SoLuong, GhiChuTinhTrang)
VALUES (@Handover2, @O5, 1, N'Nguyên vẹn'), (@Handover2, @O6, 1, N'Nguyên vẹn');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich, MaKho, LoaiGiaoDich, TrangThaiGiaoDich, MaTaiKhoanThucHien, ThoiGianThucHien, GhiChu)
VALUES ('GD-BT-OUT-261002-02', @Kho_BT, 'OUTBOUND', 'COMPLETED', @TK_KhoBT, DATEADD(MINUTE, -26, @Now), N'Xuất chuyến CG-BT-261002-002');
SET @WT_BT_OUT2 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho, MaDonHang, MaViTriNguon, MaViTriDich, TinhTrangHang, GhiChu)
VALUES
(@WT_BT_OUT2, @O5, @VT_BT_A3, NULL, 'NORMAL', N'Xuất giao'),
(@WT_BT_OUT2, @O6, @VT_BT_A3, NULL, 'NORMAL', N'Xuất giao');

UPDATE dbo.TonKhoDonHang SET TrangThaiTonKho = 'HANDED_OVER', MaViTriLuuKho = NULL, ThoiGianDiChuyenCuoi = DATEADD(MINUTE, -25, @Now), MaTaiKhoanCapNhatCuoi = @TK_KhoBT WHERE MaDonHang IN (@O5, @O6);

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O5, @KyHieuTrangThaiMoi = 'HANDED_OVER', @MaTaiKhoan = @TK_KhoBT, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O6, @KyHieuTrangThaiMoi = 'HANDED_OVER', @MaTaiKhoan = @TK_KhoBT, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O5, @KyHieuTrangThaiMoi = 'PICKED_UP', @MaTaiKhoan = @TK_S2, @LyDo = NULL, @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O6, @KyHieuTrangThaiMoi = 'PICKED_UP', @MaTaiKhoan = @TK_S2, @LyDo = NULL, @NguonCapNhat = 'MOBILE';

UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong = 'IN_PROGRESS' WHERE MaPhanCongGiaoHang IN (@PC5, @PC6);
UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen = 'IN_PROGRESS' WHERE MaChuyenGiao = @Trip2;
UPDATE dbo.NhanVienGiaoHang SET TrangThaiSanSang = 'DELIVERING' WHERE MaNhanVienGiaoHang = @S2;
UPDATE dbo.PhuongTien SET TrangThaiPhuongTien = 'IN_USE' WHERE MaPhuongTien = @Xe2;

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O5, @KyHieuTrangThaiMoi = 'IN_DELIVERY', @MaTaiKhoan = @TK_S2, @LyDo = NULL, @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O6, @KyHieuTrangThaiMoi = 'IN_DELIVERY', @MaTaiKhoan = @TK_S2, @LyDo = NULL, @NguonCapNhat = 'MOBILE';

SET @retryTime = DATEADD(HOUR, 3, @Now);

EXEC dbo.sp_XacNhanGiaoHangThatBai
     @MaDonHang = @O5,
     @MaNhanVienGiaoHang = @S2,
     @MaTaiKhoan = @TK_S2,
     @MaLyDoGiaoThatBai = @LyDoNoAnswer,
     @GhiChu = N'Gọi 3 lần trong 15 phút nhưng khách chưa nghe máy',
     @ThoiGianGiaoLaiDuKien = @retryTime,
     @DuongDanTepMinhChung = NULL,
     @ViDo = 10.814300,
     @KinhDo = 106.603200;

INSERT INTO dbo.YeuCauGiaoLaiHoacHoan(MaDonHang, LoaiYeuCau, TrangThaiYeuCau, MaBuuCucHoan, LyDo, MaTaiKhoanYeuCau, ThoiGianYeuCau, ThoiGianHoanTat)
VALUES (@O5, 'RETRY', 'APPROVED', NULL, N'Đã liên hệ lại; khách hẹn nhận sau 17:00', @TK_DPBT, @Now, NULL);

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O5,
     @KyHieuTrangThaiMoi = 'RETRY_WAITING',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = N'Khách hẹn giao lại sau 17:00',
     @NguonCapNhat = 'WEB';

INSERT INTO dbo.CanhBaoGiaoHang(MaDonHang, MaChuyenGiao, LoaiCanhBao, MucDoCanhBao, NoiDungCanhBao, TrangThaiCanhBao, ThoiGianPhatHien)
VALUES (@O5, @Trip2, 'LATE_RISK', 'WARNING', N'Đơn giao thất bại lần 1, có nguy cơ trễ SLA.', 'OPEN', @Now);

/* =============================================================================
   PHẦN 9. CHUYẾN 3 - TÂN PHÚ: ĐƠN 7 ĐANG GIAO (IN_DELIVERY)
   ============================================================================= */
PRINT N'10/16 - Chuyến 3 Tân Phú đang giao hàng...';

INSERT INTO dbo.ChuyenGiaoHang
(KyHieuChuyenGiao, MaBuuCuc, MaKho, MaNhanVienGiaoHang, MaPhuongTien, TrangThaiChuyen,
 PhuongPhapToiUu, TongQuangDuongKm, ThoiGianDuKienPhut, ThoiGianBatDauDuKien, MaTaiKhoanTao)
VALUES ('CG-TP-261002-001', @BC_TP, @Kho_TP, @S3, @Xe3, 'PLANNED', 'ASTAR', 9.60, 50, DATEADD(MINUTE, -25, @Now), @TK_DPTP);
SET @Trip3 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietChuyenGiao(MaChuyenGiao, MaDonHang, ThuTuDuKien, ThoiGianDenDuKien)
VALUES (@Trip3, @O7, 1, DATEADD(MINUTE, 15, @Now));

DECLARE @D7 BIGINT;
SELECT @D7 = MaDiemGiaoNhan FROM dbo.DiemGiaoNhan WHERE MaDonHang = @O7 AND LoaiDiem = 'DELIVERY';

INSERT INTO dbo.DiemDungTuyen(MaChuyenGiao, MaDonHang, MaDiemGiaoNhan, ThuTuDiemDung, LoaiDiem, ViDo, KinhDo, ThoiGianDenDuKien, KhoangCachTuDiemTruocKm, ThoiGianTuDiemTruocPhut)
VALUES
(@Trip3, NULL, NULL, 1, 'BRANCH', 10.802900, 106.617900, DATEADD(MINUTE, -25, @Now), NULL, NULL),
(@Trip3, @O7, @D7, 2, 'DELIVERY', 10.789900, 106.628000, DATEADD(MINUTE, 15, @Now), 4.8, 22);

DECLARE @PC7 BIGINT;
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang, MaChuyenGiao, MaNhanVienGiaoHang, MaPhuongTien, MaTaiKhoanPhanCong, ThoiGianPhanCong, TrangThaiPhanCong, BoQuaQuyTacKhuVuc)
VALUES (@O7, @Trip3, @S3, @Xe3, @TK_DPTP, DATEADD(MINUTE, -23, @Now), 'PENDING', 0);
SET @PC7 = SCOPE_IDENTITY();

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O7, @KyHieuTrangThaiMoi = 'ASSIGNED', @MaTaiKhoan = @TK_DPTP, @LyDo = NULL, @NguonCapNhat = 'WEB';
UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong = 'ACCEPTED', ThoiGianChapNhan = DATEADD(MINUTE, -21, @Now) WHERE MaPhanCongGiaoHang = @PC7;
UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen = 'ACCEPTED', ThoiGianBatDauThucTe = DATEADD(MINUTE, -20, @Now) WHERE MaChuyenGiao = @Trip3;
UPDATE dbo.TonKhoDonHang SET TrangThaiTonKho = 'ALLOCATED', ThoiGianDiChuyenCuoi = DATEADD(MINUTE, -19, @Now), MaTaiKhoanCapNhatCuoi = @TK_KhoTP WHERE MaDonHang = @O7;

INSERT INTO dbo.BanGiaoHang(KyHieuBanGiao, MaKho, MaNhanVienGiaoHang, MaTaiKhoanBanGiao, TrangThaiBanGiao, ThoiGianBanGiao, ThoiGianNhanVienXacNhan, GhiChu)
VALUES ('BG-TP-261002-001', @Kho_TP, @S3, @TK_KhoTP, 'CONFIRMED', DATEADD(MINUTE, -18, @Now), DATEADD(MINUTE, -17, @Now), N'Bàn giao đơn dễ vỡ');
SET @Handover3 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietBanGiaoHang(MaBanGiao, MaDonHang, SoLuong, GhiChuTinhTrang)
VALUES (@Handover3, @O7, 1, N'Nguyên vẹn, tem dễ vỡ còn nguyên');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich, MaKho, LoaiGiaoDich, TrangThaiGiaoDich, MaTaiKhoanThucHien, ThoiGianThucHien, GhiChu)
VALUES ('GD-TP-OUT-261002-01', @Kho_TP, 'OUTBOUND', 'COMPLETED', @TK_KhoTP, DATEADD(MINUTE, -16, @Now), N'Xuất chuyến CG-TP-261002-001');
SET @WT_TP_OUT = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho, MaDonHang, MaViTriNguon, MaViTriDich, TinhTrangHang, GhiChu)
VALUES (@WT_TP_OUT, @O7, @VT_TP_A1, NULL, 'NORMAL', N'Xuất giao');

UPDATE dbo.TonKhoDonHang SET TrangThaiTonKho = 'HANDED_OVER', MaViTriLuuKho = NULL, ThoiGianDiChuyenCuoi = DATEADD(MINUTE, -15, @Now), MaTaiKhoanCapNhatCuoi = @TK_KhoTP WHERE MaDonHang = @O7;

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O7, @KyHieuTrangThaiMoi = 'HANDED_OVER', @MaTaiKhoan = @TK_KhoTP, @LyDo = NULL, @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O7, @KyHieuTrangThaiMoi = 'PICKED_UP', @MaTaiKhoan = @TK_S3, @LyDo = NULL, @NguonCapNhat = 'MOBILE';

UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong = 'IN_PROGRESS' WHERE MaPhanCongGiaoHang = @PC7;
UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen = 'IN_PROGRESS' WHERE MaChuyenGiao = @Trip3;
UPDATE dbo.NhanVienGiaoHang SET TrangThaiSanSang = 'DELIVERING', ViDoHienTai = 10.798700, KinhDoHienTai = 106.622100, ThoiGianCapNhatViTri = @Now WHERE MaNhanVienGiaoHang = @S3;
UPDATE dbo.PhuongTien SET TrangThaiPhuongTien = 'IN_USE' WHERE MaPhuongTien = @Xe3;

EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @O7, @KyHieuTrangThaiMoi = 'IN_DELIVERY', @MaTaiKhoan = @TK_S3, @LyDo = NULL, @NguonCapNhat = 'MOBILE';

/* =============================================================================
   PHẦN 10. NỘP TIỀN COD, ĐỐI SOÁT, ĐÁNH GIÁ, KHIẾU NẠI & AUDIT LOG
   ============================================================================= */
PRINT N'11/16 - Thu COD, nộp tiền, đối soát và CSKH...';

INSERT INTO dbo.NopTienCOD
(KyHieuNopTien, MaNhanVienGiaoHang, MaBuuCuc, SoTienNop, PhuongThucNop, TrangThaiNop, ThoiGianNop, MaThamChieuNgoai, GhiChu)
VALUES ('NOP-BT-261002-001', @S1, @BC_BT, 680000, 'CASH', 'PENDING', @Now, 'PHIEU-THU-BT-261002-001', N'Nộp COD sau chuyến sáng');
SET @Deposit = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietNopTienCOD(MaNopTienCOD, MaDonHang, SoTienPhanBo)
VALUES (@Deposit, @O1, 185000), (@Deposit, @O3, 420000), (@Deposit, @O4, 75000);

EXEC dbo.sp_XacNhanNopTienCOD
     @MaNopTienCOD = @Deposit,
     @MaTaiKhoanXacNhan = @TK_KeToan;

INSERT INTO dbo.DoiSoatCOD
(KyHieuDoiSoat, MaBuuCuc, MaNhanVienGiaoHang, TuThoiGian, DenThoiGian, TongTienPhaiThu, TongTienDaThu, TongTienDaNop, TrangThaiDoiSoat, GhiChu)
VALUES ('DS-BT-261002-S1', @BC_BT, @S1, DATEADD(HOUR, -3, @Now), DATEADD(HOUR, 1, @Now), 0, 0, 0, 'DRAFT', N'Đối soát COD chuyến sáng Nguyễn Minh Tuấn');
SET @Recon = SCOPE_IDENTITY();

EXEC dbo.sp_XacNhanDoiSoatCOD
     @MaDoiSoatCOD = @Recon,
     @MaTaiKhoanXacNhan = @TK_KeToan;

INSERT INTO dbo.DanhGia(MaDonHang, MaKhachHang, MaNhanVienGiaoHang, SoSao, NhanXet, ThoiGianTao)
VALUES
(@O1, @KH_01, @S1, 5, N'Giao đúng hẹn, shipper gọi trước và hỗ trợ kiểm hàng.', @Now),
(@O2, @KH_02, @S1, 4, N'Giao nhanh, kiện hàng sạch sẽ.', @Now),
(@O3, @KH_07, @S1, 5, N'Shipper lịch sự, hàng dễ vỡ vẫn nguyên vẹn.', @Now);

INSERT INTO dbo.KhieuNai(KyHieuKhieuNai, MaDonHang, MaKhachHang, LoaiKhieuNai, TieuDe, NoiDung, TrangThaiKhieuNai, MucDoUuTien, MaTaiKhoanXuLy, KetQuaXuLy, ThoiGianTao, ThoiGianXuLy)
VALUES
('KN-261002-001', @O3, @KH_07, 'OTHER', N'Kiểm tra tình trạng vỏ hộp', N'Khách phản ánh góc vỏ hộp bị móp nhẹ nhưng sản phẩm bên trong bình thường.', 'RESOLVED', 'NORMAL', @TK_MgrBT, N'Đã đối chiếu ảnh POD và xác nhận sản phẩm nguyên vẹn; khách đồng ý kết thúc.', DATEADD(MINUTE, -10, @Now), @Now);
SET @Complaint1 = SCOPE_IDENTITY();

INSERT INTO dbo.LichSuKhieuNai(MaKhieuNai, TrangThaiCu, TrangThaiMoi, MaTaiKhoanThucHien, ThoiGianThucHien, GhiChu)
VALUES
(@Complaint1, NULL, 'OPEN', @TK_MgrBT, DATEADD(MINUTE, -10, @Now), N'Tiếp nhận phản ánh'),
(@Complaint1, 'OPEN', 'IN_PROGRESS', @TK_MgrBT, DATEADD(MINUTE, -7, @Now), N'Kiểm tra ảnh bằng chứng'),
(@Complaint1, 'IN_PROGRESS', 'RESOLVED', @TK_MgrBT, @Now, N'Đã phản hồi khách');

INSERT INTO dbo.KhieuNai(KyHieuKhieuNai, MaDonHang, MaKhachHang, LoaiKhieuNai, TieuDe, NoiDung, TrangThaiKhieuNai, MucDoUuTien, MaTaiKhoanXuLy, KetQuaXuLy, ThoiGianTao, ThoiGianXuLy)
VALUES
('KN-261002-002', @O5, @KH_09, 'LATE', N'Đề nghị giao lại sau giờ làm', N'Khách không thể nhận trong giờ hành chính và đề nghị giao lại sau 17:00.', 'OPEN', 'NORMAL', @TK_DPBT, NULL, @Now, NULL);
SET @Complaint2 = SCOPE_IDENTITY();

INSERT INTO dbo.LichSuKhieuNai(MaKhieuNai, TrangThaiCu, TrangThaiMoi, MaTaiKhoanThucHien, ThoiGianThucHien, GhiChu)
VALUES (@Complaint2, NULL, 'OPEN', @TK_DPBT, @Now, N'Ghi nhận yêu cầu thay đổi thời điểm giao');

INSERT INTO dbo.ThongBao(MaTaiKhoan, LoaiThongBao, TieuDe, NoiDung, LoaiDoiTuongThamChieu, MaDoiTuongThamChieu, DaDoc, ThoiGianTao, ThoiGianDoc)
VALUES
(@TK_S2, 'DELIVERY_RETRY', N'Đơn cần giao lại', N'Đơn LM261002000005 được hẹn giao lại sau 17:00.', 'ORDER', @O5, 0, @Now, NULL),
(@TK_DPBT, 'DELIVERY_ALERT', N'Nguy cơ trễ SLA', N'Đơn LM261002000005 đã giao thất bại một lần.', 'ORDER', @O5, 1, DATEADD(MINUTE, -2, @Now), @Now),
(@TK_KeToan, 'COD_DEPOSIT', N'Phiếu nộp COD đã xác nhận', N'Phiếu NOP-BT-261002-001 trị giá 680.000đ đã được xác nhận.', 'COD_DEPOSIT', @Deposit, 1, DATEADD(MINUTE, -2, @Now), @Now),
(@TK_DPTP, 'TRIP_STARTED', N'Chuyến Tân Phú đang thực hiện', N'CG-TP-261002-001 đã xuất phát với 1 đơn hàng.', 'TRIP', @Trip3, 0, @Now, NULL);

INSERT INTO dbo.NhatKyHoatDong(MaTaiKhoan, LoaiThaoTac, TenDoiTuong, MaDoiTuong, DuLieuCuJson, DuLieuMoiJson, DiaChiIP, ThongTinThietBi, ThoiGianTao)
VALUES
(@TK_DPBT, 'CREATE_ORDER', 'DonHang', CONVERT(VARCHAR(100), @O1), NULL, N'{"tracking":"LM261002000001","branch":"HCM-BT01"}', '10.10.1.15', N'Web Dispatcher / Windows 11', DATEADD(MINUTE, -100, @Now)),
(@TK_KhoBT, 'WAREHOUSE_INBOUND', 'GiaoDichKho', CONVERT(VARCHAR(100), @WT_BT_IN), NULL, N'{"type":"INBOUND","orders":6}', '10.10.1.25', N'Warehouse Web / Chrome', DATEADD(MINUTE, -80, @Now)),
(@TK_DPBT, 'CREATE_TRIP', 'ChuyenGiaoHang', CONVERT(VARCHAR(100), @Trip1), NULL, N'{"method":"VRP","orders":4}', '10.10.1.15', N'Web Dispatcher / Windows 11', DATEADD(MINUTE, -55, @Now)),
(@TK_S2, 'DELIVERY_FAILED', 'DonHang', CONVERT(VARCHAR(100), @O5), N'{"status":"IN_DELIVERY"}', N'{"status":"RETRY_WAITING","reason":"NO_ANSWER"}', '10.10.2.102', N'Android Mobile App', @Now),
(@TK_KeToan, 'CONFIRM_COD_DEPOSIT', 'NopTienCOD', CONVERT(VARCHAR(100), @Deposit), N'{"status":"PENDING"}', N'{"status":"CONFIRMED","amount":680000}', '10.10.1.35', N'Finance Web / Edge', @Now),
(@TK_KeToan, 'CONFIRM_COD_RECON', 'DoiSoatCOD', CONVERT(VARCHAR(100), @Recon), N'{"status":"DRAFT"}', N'{"status":"CONFIRMED","amount":680000}', '10.10.1.35', N'Finance Web / Edge', @Now);

/* =============================================================================
   PHẦN 11. BỔ SUNG 150 KHÁCH HÀNG & 150 ĐƠN HÀNG THỰC TẾ
   ============================================================================= */
PRINT N'12/16 - Bổ sung 150 khách hàng và địa chỉ...';

DECLARE @ShopNames TABLE (Seq INT PRIMARY KEY, Ten NVARCHAR(150) NOT NULL);
INSERT INTO @ShopNames(Seq, Ten) VALUES
(1,N'Shop An Nhiên'),(2,N'Shop Minh Tâm'),(3,N'Nhà Xinh Online'),(4,N'Điện tử Phúc Khang'),(5,N'Mỹ phẩm Mộc Lan'),
(6,N'Thời trang Hạ Vy'),(7,N'Gia dụng Thành Đạt'),(8,N'Phụ kiện Sài Gòn'),(9,N'Bách hóa Hồng Phúc'),(10,N'Shop Bảo Ngọc'),
(11,N'Văn phòng phẩm Sao Mai'),(12,N'Đồ chơi Mặt Trời'),(13,N'Đặc sản Miền Nam'),(14,N'Giày dép Nhật Minh'),(15,N'Nhà sách Bình An'),
(16,N'Điện máy Gia Hưng'),(17,N'Chăm sóc cá nhân An Khang'),(18,N'Túi ví Lam Anh'),(19,N'Đồ dùng trẻ em Mây'),(20,N'Phụ kiện công nghệ 24H'),
(21,N'Gốm sứ Tân Phát'),(22,N'Bếp Việt Online'),(23,N'Vườn Nhà Nhỏ'),(24,N'Thời trang Lam Phương'),(25,N'Shop Khánh Linh'),
(26,N'Đồ thể thao Đại Việt'),(27,N'Quà tặng Tâm Giao'),(28,N'Đồ handmade Cỏ May'),(29,N'Laptop Phương Nam'),(30,N'Kho hàng Tiện Ích');

DECLARE @Ho TABLE (Seq INT PRIMARY KEY, Ten NVARCHAR(50) NOT NULL);
INSERT INTO @Ho VALUES
(1,N'Nguyễn'),(2,N'Trần'),(3,N'Lê'),(4,N'Phạm'),(5,N'Hoàng'),(6,N'Phan'),(7,N'Vũ'),(8,N'Võ'),(9,N'Đặng'),(10,N'Bùi');

DECLARE @Dem TABLE (Seq INT PRIMARY KEY, Ten NVARCHAR(50) NOT NULL);
INSERT INTO @Dem VALUES
(1,N'Minh'),(2,N'Ngọc'),(3,N'Thành'),(4,N'Quốc'),(5,N'Thảo'),(6,N'Gia'),(7,N'Khánh'),(8,N'Hoàng');

DECLARE @Ten TABLE (Seq INT PRIMARY KEY, Ten NVARCHAR(50) NOT NULL);
INSERT INTO @Ten VALUES
(1,N'An'),(2,N'Bình'),(3,N'Châu'),(4,N'Dũng'),(5,N'Đạt'),(6,N'Giang'),(7,N'Hà'),(8,N'Hân'),(9,N'Hải'),(10,N'Huy'),
(11,N'Khang'),(12,N'Linh'),(13,N'Long'),(14,N'Mai'),(15,N'Minh'),(16,N'Nam'),(17,N'Nhi'),(18,N'Phúc'),(19,N'Quân'),(20,N'Vy');

DECLARE @AreaMap TABLE
(
    AreaIdx INT PRIMARY KEY,
    MaKhuVuc INT NOT NULL,
    TenDuong NVARCHAR(180) NOT NULL,
    ViDoGoc DECIMAL(9,6) NOT NULL,
    KinhDoGoc DECIMAL(10,6) NOT NULL
);
INSERT INTO @AreaMap(AreaIdx, MaKhuVuc, TenDuong, ViDoGoc, KinhDoGoc) VALUES
(0, @KV_BHB, N'Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM', 10.811000, 106.601000),
(1, @KV_AL, N'Đường số 5, An Lạc, Bình Tân, TP.HCM', 10.729000, 106.615000),
(2, @KV_SK, N'Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM', 10.803000, 106.618000),
(3, @KV_TT, N'Tân Hương, Tân Thành, Tân Phú, TP.HCM', 10.790000, 106.628000),
(4, @KV_Q6P10, N'Hậu Giang, Phường 10, Quận 6, TP.HCM', 10.747000, 106.635000),
(5, @KV_Q6P12, N'Bình Phú, Phường 12, Quận 6, TP.HCM', 10.744000, 106.630000);

DECLARE @CustomerSeed TABLE
(
    Seq INT PRIMARY KEY,
    KyHieuKhachHang VARCHAR(30) NOT NULL,
    HoTen NVARCHAR(150) NOT NULL,
    SoDienThoai VARCHAR(20) NOT NULL,
    Email VARCHAR(150) NOT NULL,
    LoaiKhachHang VARCHAR(20) NOT NULL,
    MaKhuVuc INT NOT NULL,
    DiaChi NVARCHAR(300) NOT NULL,
    ViDo DECIMAL(9,6) NOT NULL,
    KinhDo DECIMAL(10,6) NOT NULL
);

DECLARE @CustomerOut TABLE (KyHieuKhachHang VARCHAR(30) PRIMARY KEY, MaKhachHang BIGINT NOT NULL);
DECLARE @CustomerMap TABLE
(
    Seq INT PRIMARY KEY,
    MaKhachHang BIGINT NOT NULL,
    LoaiKhachHang VARCHAR(20) NOT NULL,
    HoTen NVARCHAR(150) NOT NULL,
    SoDienThoai VARCHAR(20) NOT NULL,
    MaKhuVuc INT NOT NULL,
    DiaChi NVARCHAR(300) NOT NULL,
    ViDo DECIMAL(9,6) NOT NULL,
    KinhDo DECIMAL(10,6) NOT NULL
);

;WITH N AS
(
    SELECT TOP (150) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Seq
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
), C AS
(
    SELECT n.Seq, ((n.Seq - 1) % 6) AS AreaIdx,
           CASE WHEN n.Seq <= 30 THEN n.Seq ELSE NULL END AS ShopSeq,
           CASE WHEN n.Seq > 30 THEN n.Seq - 30 ELSE NULL END AS PersonSeq
    FROM N n
)
INSERT INTO @CustomerSeed
(Seq, KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, MaKhuVuc, DiaChi, ViDo, KinhDo)
SELECT
    c.Seq,
    CONCAT('KH-DEMO-261023-', RIGHT('0000' + CONVERT(VARCHAR(4), c.Seq), 4)),
    CASE WHEN c.Seq <= 30 THEN sn.Ten
         ELSE CONCAT(h.Ten, N' ', d.Ten, N' ', t.Ten) END,
    CASE WHEN c.Seq <= 30
         THEN CONCAT('0287300', RIGHT('0000' + CONVERT(VARCHAR(4), c.Seq), 4))
         ELSE CONCAT('097', RIGHT('0000000' + CONVERT(VARCHAR(7), 10000 + c.PersonSeq), 7)) END,
    CASE WHEN c.Seq <= 30
         THEN CONCAT('shop', RIGHT('0000' + CONVERT(VARCHAR(4), c.Seq), 4), '@demo.lastmile.local')
         ELSE CONCAT('khach', RIGHT('0000' + CONVERT(VARCHAR(4), c.PersonSeq), 4), '@demo.lastmile.local') END,
    CASE WHEN c.Seq <= 30 THEN 'BUSINESS' ELSE 'INDIVIDUAL' END,
    a.MaKhuVuc,
    CONCAT(20 + c.Seq, N' ', a.TenDuong),
    CAST(a.ViDoGoc + ((c.Seq % 20) * 0.0001) AS DECIMAL(9,6)),
    CAST(a.KinhDoGoc + ((c.Seq % 20) * 0.0001) AS DECIMAL(10,6))
FROM C c
JOIN @AreaMap a ON a.AreaIdx = c.AreaIdx
LEFT JOIN @ShopNames sn ON sn.Seq = c.ShopSeq
LEFT JOIN @Ho h ON h.Seq = (((c.PersonSeq - 1) % 10) + 1)
LEFT JOIN @Dem d ON d.Seq = ((((c.PersonSeq - 1) / 10) % 8) + 1)
LEFT JOIN @Ten t ON t.Seq = ((((c.PersonSeq - 1) / 80) % 20) + 1);

INSERT INTO dbo.KhachHang(KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, DangHoatDong)
OUTPUT inserted.KyHieuKhachHang, inserted.MaKhachHang INTO @CustomerOut(KyHieuKhachHang, MaKhachHang)
SELECT KyHieuKhachHang, HoTen, SoDienThoai, Email, LoaiKhachHang, 1
FROM @CustomerSeed;

INSERT INTO @CustomerMap(Seq, MaKhachHang, LoaiKhachHang, HoTen, SoDienThoai, MaKhuVuc, DiaChi, ViDo, KinhDo)
SELECT s.Seq, o.MaKhachHang, s.LoaiKhachHang, s.HoTen, s.SoDienThoai, s.MaKhuVuc, s.DiaChi, s.ViDo, s.KinhDo
FROM @CustomerSeed s
JOIN @CustomerOut o ON o.KyHieuKhachHang = s.KyHieuKhachHang;

INSERT INTO dbo.DiaChiKhachHang
(MaKhachHang, NhanDiaChi, TenNguoiLienHe, SoDienThoaiLienHe, DiaChi, MaKhuVuc, ViDo, KinhDo, LaMacDinh, DangHoatDong)
SELECT MaKhachHang, N'Địa chỉ mặc định', HoTen, SoDienThoai, DiaChi, MaKhuVuc, ViDo, KinhDo, 1, 1
FROM @CustomerMap;

/* =============================================================================
   PHẦN 12. TẠO 150 ĐƠN HÀNG, ĐIỂM GIAO NHẬN, CHI TIẾT HÀNG & PHÍ
   ============================================================================= */
PRINT N'13/16 - Tạo 150 đơn hàng bulk, điểm dừng và hàng hóa...';

DECLARE @OrderSeed TABLE
(
    Seq INT PRIMARY KEY,
    KyHieuDonHang VARCHAR(40) NOT NULL,
    MaVanDon VARCHAR(50) NOT NULL,
    MaBuuCuc INT NOT NULL,
    SenderSeq INT NOT NULL,
    ReceiverSeq INT NOT NULL,
    MaNguoiGui BIGINT NOT NULL,
    MaNguoiNhan BIGINT NOT NULL,
    MaLoaiDichVu INT NOT NULL,
    MaTaiKhoanTao BIGINT NOT NULL,
    MaTaiKhoanKho BIGINT NOT NULL,
    MaKho INT NOT NULL,
    GroupNo TINYINT NOT NULL,
    MucDoUuTien TINYINT NOT NULL,
    GiaTriKhaiBao DECIMAL(18,2) NOT NULL,
    TienCOD DECIMAL(18,2) NOT NULL,
    PhiVanChuyen DECIMAL(18,2) NOT NULL
);
DECLARE @BulkOrderOut TABLE (KyHieuDonHang VARCHAR(40) PRIMARY KEY, MaDonHang BIGINT NOT NULL);
DECLARE @BulkOrderMap TABLE
(
    Seq INT PRIMARY KEY,
    MaDonHang BIGINT NOT NULL,
    KyHieuDonHang VARCHAR(40) NOT NULL,
    MaBuuCuc INT NOT NULL,
    SenderSeq INT NOT NULL,
    ReceiverSeq INT NOT NULL,
    MaTaiKhoanTao BIGINT NOT NULL,
    MaTaiKhoanKho BIGINT NOT NULL,
    MaKho INT NOT NULL,
    GroupNo TINYINT NOT NULL,
    PhiVanChuyen DECIMAL(18,2) NOT NULL
);

;WITH N AS
(
    SELECT TOP (150) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Seq
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
), B AS
(
    SELECT n.Seq,
           CASE WHEN (n.Seq - 1) % 3 = 0 THEN @BC_BT WHEN (n.Seq - 1) % 3 = 1 THEN @BC_TP ELSE @BC_Q6 END AS MaBuuCuc,
           CASE WHEN (n.Seq - 1) % 3 = 0 THEN @TK_DPBT WHEN (n.Seq - 1) % 3 = 1 THEN @TK_DPTP ELSE @TK_DPQ6 END AS MaTaiKhoanTao,
           CASE WHEN (n.Seq - 1) % 3 = 0 THEN @TK_KhoBT WHEN (n.Seq - 1) % 3 = 1 THEN @TK_KhoTP ELSE @TK_KhoQ6 END AS MaTaiKhoanKho,
           CASE WHEN (n.Seq - 1) % 3 = 0 THEN @Kho_BT WHEN (n.Seq - 1) % 3 = 1 THEN @Kho_TP ELSE @Kho_Q6 END AS MaKho,
           CASE WHEN n.Seq % 4 = 0 THEN @DV_EXP ELSE @DV_STD END AS MaLoaiDichVu,
           ((n.Seq - 1) / 25) + 1 AS GroupNo,
           ((n.Seq - 1) % 30) + 1 AS SenderSeq,
           31 + ((n.Seq - 1) % 120) AS ReceiverSeq
    FROM N n
)
INSERT INTO @OrderSeed
(Seq, KyHieuDonHang, MaVanDon, MaBuuCuc, SenderSeq, ReceiverSeq, MaNguoiGui, MaNguoiNhan, MaLoaiDichVu,
 MaTaiKhoanTao, MaTaiKhoanKho, MaKho, GroupNo, MucDoUuTien, GiaTriKhaiBao, TienCOD, PhiVanChuyen)
SELECT
    b.Seq,
    CONCAT('DH-HCM-261023-BULK-', RIGHT('0000' + CONVERT(VARCHAR(4), b.Seq), 4)),
    CONCAT('LM261023BULK', RIGHT('000000' + CONVERT(VARCHAR(6), b.Seq), 6)),
    b.MaBuuCuc, b.SenderSeq, b.ReceiverSeq, s.MaKhachHang, r.MaKhachHang, b.MaLoaiDichVu,
    b.MaTaiKhoanTao, b.MaTaiKhoanKho, b.MaKho, b.GroupNo,
    CAST(((b.Seq - 1) % 5) + 1 AS TINYINT),
    CAST(250000 + ((b.Seq * 28731) % 1750000) AS DECIMAL(18,2)),
    CAST(CASE WHEN b.Seq % 4 = 0 THEN 0 ELSE 50000 + ((b.Seq * 13711) % 450000) END AS DECIMAL(18,2)),
    CAST(CASE WHEN b.Seq % 4 = 0 THEN 42000 ELSE 29000 END + ((b.Seq % 5) * 2500) AS DECIMAL(18,2))
FROM B b
JOIN @CustomerMap s ON s.Seq = b.SenderSeq
JOIN @CustomerMap r ON r.Seq = b.ReceiverSeq;

INSERT INTO dbo.DonHang
(KyHieuDonHang, MaVanDon, MaBuuCuc, MaNguoiGui, MaNguoiNhan, MaLoaiDichVu, MaTrangThaiHienTai, MaKhoHienTai,
 ThoiGianSanSang, ThoiGianYeuCauGiao, ThoiGianDuKienGiao, MucDoUuTien, GiaTriKhaiBao, TienCOD, PhiVanChuyen,
 GhiChuDacBiet, MaTaiKhoanTao, MaTaiKhoanCapNhatCuoi)
OUTPUT inserted.KyHieuDonHang, inserted.MaDonHang INTO @BulkOrderOut(KyHieuDonHang, MaDonHang)
SELECT
    s.KyHieuDonHang, s.MaVanDon, s.MaBuuCuc, s.MaNguoiGui, s.MaNguoiNhan, s.MaLoaiDichVu, @TT_NEW, NULL,
    DATEADD(HOUR, -48 - (s.Seq % 72), @Now),
    DATEADD(HOUR, -24 - (s.Seq % 24), @Now),
    DATEADD(HOUR, 2 + (s.Seq % 24), @Now),
    s.MucDoUuTien, s.GiaTriKhaiBao, s.TienCOD, s.PhiVanChuyen,
    CASE s.Seq % 6
      WHEN 0 THEN N'Gọi khách trước khi giao; kiểm tra thông tin người nhận'
      WHEN 1 THEN N'Hàng đóng gói cẩn thận; tránh để nơi ẩm ướt'
      WHEN 2 THEN N'Khách có thể không nghe máy trong giờ làm việc'
      WHEN 3 THEN N'Ưu tiên giao trong khung giờ dự kiến'
      WHEN 4 THEN N'Kiểm tra bao bì khi nhận hàng tại kho'
      ELSE N'Liên hệ khách nếu địa chỉ khó tìm' END,
    s.MaTaiKhoanTao, s.MaTaiKhoanTao
FROM @OrderSeed s;

INSERT INTO @BulkOrderMap(Seq, MaDonHang, KyHieuDonHang, MaBuuCuc, SenderSeq, ReceiverSeq, MaTaiKhoanTao, MaTaiKhoanKho, MaKho, GroupNo, PhiVanChuyen)
SELECT s.Seq, o.MaDonHang, s.KyHieuDonHang, s.MaBuuCuc, s.SenderSeq, s.ReceiverSeq, s.MaTaiKhoanTao, s.MaTaiKhoanKho, s.MaKho, s.GroupNo, s.PhiVanChuyen
FROM @OrderSeed s JOIN @BulkOrderOut o ON o.KyHieuDonHang = s.KyHieuDonHang;

INSERT INTO dbo.DiemGiaoNhan
(MaDonHang, LoaiDiem, TenNguoiLienHe, SoDienThoaiLienHe, DiaChi, MaKhuVuc, ViDo, KinhDo, GhiChu)
SELECT om.MaDonHang, 'PICKUP', c.HoTen, c.SoDienThoai, c.DiaChi, c.MaKhuVuc, c.ViDo, c.KinhDo, N'Điểm lấy hàng của shop gửi'
FROM @BulkOrderMap om JOIN @CustomerMap c ON c.Seq = om.SenderSeq
UNION ALL
SELECT om.MaDonHang, 'DELIVERY', c.HoTen, c.SoDienThoai, c.DiaChi, c.MaKhuVuc, c.ViDo, c.KinhDo, N'Gọi khách trước khi giao nếu cần'
FROM @BulkOrderMap om JOIN @CustomerMap c ON c.Seq = om.ReceiverSeq;

-- SỬA LỖI TỪ KHÓA DÀNH RIÊNG: Đổi LineNo thành DongSo
INSERT INTO dbo.ChiTietDonHang
(MaDonHang, TenHang, LoaiHang, SoLuong, KhoiLuongDonViKg, ChieuDaiCm, ChieuRongCm, ChieuCaoCm, GiaTriHang, HangDeVo, GhiChu)
SELECT
    om.MaDonHang,
    CASE (om.Seq + v.DongSo) % 8
      WHEN 0 THEN N'Tai nghe Bluetooth'
      WHEN 1 THEN N'Áo thun cotton'
      WHEN 2 THEN N'Bình giữ nhiệt'
      WHEN 3 THEN N'Phụ kiện điện thoại'
      WHEN 4 THEN N'Đồ gia dụng nhà bếp'
      WHEN 5 THEN N'Mỹ phẩm chăm sóc cá nhân'
      WHEN 6 THEN N'Sách và văn phòng phẩm'
      ELSE N'Đồ dùng cá nhân' END,
    CASE (om.Seq + v.DongSo) % 5
      WHEN 0 THEN N'Điện tử' WHEN 1 THEN N'Thời trang' WHEN 2 THEN N'Gia dụng'
      WHEN 3 THEN N'Mỹ phẩm' ELSE N'Văn phòng phẩm' END,
    CASE WHEN (om.Seq + v.DongSo) % 5 = 0 THEN 2 ELSE 1 END,
    CAST(0.2 + ((om.Seq * v.DongSo) % 12) * 0.1 AS DECIMAL(10,3)),
    CAST(12 + ((om.Seq * 3 + v.DongSo * 5) % 40) AS DECIMAL(10,2)),
    CAST(8 + ((om.Seq * 5 + v.DongSo * 3) % 28) AS DECIMAL(10,2)),
    CAST(5 + ((om.Seq * 7 + v.DongSo * 2) % 20) AS DECIMAL(10,2)),
    CAST(50000 + ((om.Seq * v.DongSo * 12345) % 250000) AS DECIMAL(18,2)),
    CASE WHEN om.Seq % 7 = 0 THEN 1 ELSE 0 END,
    CASE WHEN om.Seq % 7 = 0 THEN N'Hàng dễ vỡ; thao tác nhẹ tay' ELSE N'Kiện hàng demo; bao bì tiêu chuẩn' END
FROM @BulkOrderMap om
CROSS JOIN (VALUES(1),(2)) v(DongSo);

INSERT INTO dbo.KhoanPhiDonHang(MaDonHang, LoaiKhoanPhi, SoTien, MoTa)
SELECT om.MaDonHang, 'SHIPPING', om.PhiVanChuyen, N'Phí vận chuyển theo loại dịch vụ'
FROM @BulkOrderMap om;

INSERT INTO dbo.KhoanPhiDonHang(MaDonHang, LoaiKhoanPhi, SoTien, MoTa)
SELECT om.MaDonHang, 'SURCHARGE', CAST(5000 + (om.Seq % 4) * 2000 AS DECIMAL(18,2)), N'Phụ phí xử lý/đóng gói đặc biệt'
FROM @BulkOrderMap om WHERE om.Seq % 5 = 0;

INSERT INTO dbo.KhoanPhiDonHang(MaDonHang, LoaiKhoanPhi, SoTien, MoTa)
SELECT om.MaDonHang, 'DISCOUNT', CAST(-3000 AS DECIMAL(18,2)), N'Ưu đãi vận chuyển'
FROM @BulkOrderMap om WHERE om.Seq % 11 = 0;

/* =============================================================================
   PHẦN 13. TỒN KHO & GIAO DỊCH NHẬP KHO CHO 50 ĐƠN BULK
   ============================================================================= */
PRINT N'14/16 - Nhập kho cho 50 đơn bulk (Nhóm 4 và 5)...';

DECLARE @WarehouseTxn TABLE
(
    MaKho INT PRIMARY KEY,
    MaGiaoDichKho BIGINT NOT NULL,
    MaViTriLuuKho BIGINT NOT NULL,
    MaTaiKhoanKho BIGINT NOT NULL
);

DECLARE @WT_BT_BULK BIGINT, @WT_TP_BULK BIGINT, @WT_Q6_BULK BIGINT;

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich, MaKho, LoaiGiaoDich, TrangThaiGiaoDich, MaTaiKhoanThucHien, ThoiGianThucHien, GhiChu)
VALUES
('GD-BULK-261023-BT-IN', @Kho_BT, 'INBOUND', 'COMPLETED', @TK_KhoBT, DATEADD(MINUTE, -60, @Now), N'Nhập lô hàng bulk Bình Tân'),
('GD-BULK-261023-TP-IN', @Kho_TP, 'INBOUND', 'COMPLETED', @TK_KhoTP, DATEADD(MINUTE, -60, @Now), N'Nhập lô hàng bulk Tân Phú'),
('GD-BULK-261023-Q6-IN', @Kho_Q6, 'INBOUND', 'COMPLETED', @TK_KhoQ6, DATEADD(MINUTE, -60, @Now), N'Nhập lô hàng bulk Quận 6');

SELECT @WT_BT_BULK = MaGiaoDichKho FROM dbo.GiaoDichKho WHERE KyHieuGiaoDich = 'GD-BULK-261023-BT-IN';
SELECT @WT_TP_BULK = MaGiaoDichKho FROM dbo.GiaoDichKho WHERE KyHieuGiaoDich = 'GD-BULK-261023-TP-IN';
SELECT @WT_Q6_BULK = MaGiaoDichKho FROM dbo.GiaoDichKho WHERE KyHieuGiaoDich = 'GD-BULK-261023-Q6-IN';

INSERT INTO @WarehouseTxn(MaKho, MaGiaoDichKho, MaViTriLuuKho, MaTaiKhoanKho)
VALUES
(@Kho_BT, @WT_BT_BULK, @VT_BT_A1, @TK_KhoBT),
(@Kho_TP, @WT_TP_BULK, @VT_TP_A1, @TK_KhoTP),
(@Kho_Q6, @WT_Q6_BULK, @VT_Q6_A1, @TK_KhoQ6);

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho, MaDonHang, MaViTriNguon, MaViTriDich, TinhTrangHang, GhiChu)
SELECT wt.MaGiaoDichKho, om.MaDonHang, NULL, wt.MaViTriLuuKho, 'NORMAL', N'Nhập kho bulk; bao bì nguyên vẹn'
FROM @BulkOrderMap om
JOIN @WarehouseTxn wt ON wt.MaKho = om.MaKho
WHERE om.GroupNo IN (4, 5);

INSERT INTO dbo.TonKhoDonHang(MaDonHang, MaKho, MaViTriLuuKho, TrangThaiTonKho, ThoiGianNhapKho, ThoiGianDiChuyenCuoi, MaTaiKhoanCapNhatCuoi)
SELECT om.MaDonHang, wt.MaKho, wt.MaViTriLuuKho, 'STORED', DATEADD(MINUTE, -60, @Now), DATEADD(MINUTE, -30, @Now), wt.MaTaiKhoanKho
FROM @BulkOrderMap om
JOIN @WarehouseTxn wt ON wt.MaKho = om.MaKho
WHERE om.GroupNo IN (4, 5);

UPDATE d
SET MaKhoHienTai = om.MaKho,
    MaTaiKhoanCapNhatCuoi = om.MaTaiKhoanKho,
    ThoiGianCapNhat = @Now
FROM dbo.DonHang d
JOIN @BulkOrderMap om ON om.MaDonHang = d.MaDonHang
WHERE om.GroupNo IN (4, 5);

/* =============================================================================
   PHẦN 14. VẬN HÀNH VÒNG ĐỜI CHO 150 ĐƠN BULK
   ============================================================================= */
PRINT N'15/16 - Chuyển trạng thái 150 đơn bulk qua Stored Procedure...';

DECLARE
    @bIdx INT = 1,
    @bOrderId BIGINT,
    @bGroupNo TINYINT,
    @bCreator BIGINT,
    @bWhAcc BIGINT;

WHILE @bIdx <= 150
BEGIN
    SELECT @bOrderId = MaDonHang, @bGroupNo = GroupNo, @bCreator = MaTaiKhoanTao, @bWhAcc = MaTaiKhoanKho
    FROM @BulkOrderMap WHERE Seq = @bIdx;

    IF @bGroupNo = 6
    BEGIN
        EXEC dbo.sp_ChuyenTrangThaiDonHang
            @MaDonHang = @bOrderId,
            @KyHieuTrangThaiMoi = 'CANCELLED',
            @MaTaiKhoan = @bCreator,
            @LyDo = N'Khách hàng yêu cầu hủy đơn trước khi xử lý tại kho',
            @NguonCapNhat = 'WEB';
    END
    ELSE IF @bGroupNo >= 2
    BEGIN
        EXEC dbo.sp_XacNhanDonHang @MaDonHang = @bOrderId, @MaTaiKhoan = @bCreator;

        IF @bGroupNo >= 3
        BEGIN
            EXEC dbo.sp_ChuyenTrangThaiDonHang
                @MaDonHang = @bOrderId,
                @KyHieuTrangThaiMoi = 'WAITING_INBOUND',
                @MaTaiKhoan = @bWhAcc,
                @LyDo = NULL,
                @NguonCapNhat = 'WEB';
        END;

        IF @bGroupNo >= 4
        BEGIN
            EXEC dbo.sp_ChuyenTrangThaiDonHang
                @MaDonHang = @bOrderId,
                @KyHieuTrangThaiMoi = 'IN_WAREHOUSE',
                @MaTaiKhoan = @bWhAcc,
                @LyDo = NULL,
                @NguonCapNhat = 'WEB';
        END;

        IF @bGroupNo >= 5
        BEGIN
            EXEC dbo.sp_ChuyenTrangThaiDonHang
                @MaDonHang = @bOrderId,
                @KyHieuTrangThaiMoi = 'WAITING_ASSIGNMENT',
                @MaTaiKhoan = @bCreator,
                @LyDo = NULL,
                @NguonCapNhat = 'WEB';
        END;
    END;

    SET @bIdx = @bIdx + 1;
END;

/* =============================================================================
   PHẦN 15. CẢNH BÁO, THÔNG BÁO, NHẬT KÝ AUDIT & 100 ĐIỂM GPS BỔ SUNG
   ============================================================================= */
PRINT N'16/16 - Tạo cảnh báo, thông báo, audit log và 100 điểm GPS...';

INSERT INTO dbo.CanhBaoGiaoHang(MaDonHang, MaChuyenGiao, LoaiCanhBao, MucDoCanhBao, NoiDungCanhBao, TrangThaiCanhBao, ThoiGianPhatHien)
SELECT om.MaDonHang, NULL,
       CASE WHEN om.GroupNo = 3 THEN 'LATE_RISK' ELSE 'NO_SHIPPER' END,
       CASE WHEN om.GroupNo = 5 THEN 'CRITICAL' ELSE 'WARNING' END,
       CASE WHEN om.GroupNo = 3
            THEN CONCAT(N'Đơn ', om.KyHieuDonHang, N' đang chờ tiếp nhận vào kho; cần theo dõi thời gian xử lý.')
            ELSE CONCAT(N'Đơn ', om.KyHieuDonHang, N' đang chờ phân công nhân viên giao hàng.') END,
       'OPEN', DATEADD(MINUTE, -30, @Now)
FROM @BulkOrderMap om
WHERE om.GroupNo IN (3, 5) AND om.Seq % 2 = 0;

INSERT INTO dbo.ThongBao(MaTaiKhoan, LoaiThongBao, TieuDe, NoiDung, LoaiDoiTuongThamChieu, MaDoiTuongThamChieu, DaDoc, ThoiGianTao, ThoiGianDoc)
SELECT om.MaTaiKhoanTao, 'ORDER_STATUS', N'Cập nhật đơn hàng',
       CONCAT(N'Đơn ', om.KyHieuDonHang, N' đã được tạo trong bộ dữ liệu vận hành.'),
       'ORDER', om.MaDonHang, 0, DATEADD(MINUTE, -(om.Seq % 90), @Now), NULL
FROM @BulkOrderMap om;

INSERT INTO dbo.NhatKyHoatDong(MaTaiKhoan, LoaiThaoTac, TenDoiTuong, MaDoiTuong, DuLieuCuJson, DuLieuMoiJson, DiaChiIP, ThongTinThietBi, ThoiGianTao)
SELECT om.MaTaiKhoanTao, 'SEED_INSERT', 'DonHang', om.KyHieuDonHang,
       CONCAT(N'{"status":"NEW","orderCode":"', om.KyHieuDonHang, N'"}'),
       CONCAT(N'{"status":"',
         CASE om.GroupNo WHEN 1 THEN 'NEW' WHEN 2 THEN 'CONFIRMED' WHEN 3 THEN 'WAITING_INBOUND'
              WHEN 4 THEN 'IN_WAREHOUSE' WHEN 5 THEN 'WAITING_ASSIGNMENT' ELSE 'CANCELLED' END,
         N'","orderCode":"', om.KyHieuDonHang, N'"}'),
       '10.30.0.10', N'Bộ dữ liệu thực tế V5', DATEADD(MINUTE, -(om.Seq % 120), @Now)
FROM @BulkOrderMap om;

DECLARE @ShipperMap TABLE
(
    Seq INT PRIMARY KEY,
    MaNhanVienGiaoHang BIGINT NOT NULL,
    MaBuuCuc INT NULL,
    ViDoGoc DECIMAL(9,6) NOT NULL,
    KinhDoGoc DECIMAL(10,6) NOT NULL
);

INSERT INTO @ShipperMap(Seq, MaNhanVienGiaoHang, MaBuuCuc, ViDoGoc, KinhDoGoc)
SELECT ROW_NUMBER() OVER (ORDER BY nv.MaNhanVienGiaoHang), nv.MaNhanVienGiaoHang, tk.MaBuuCuc,
       CASE WHEN tk.MaBuuCuc = @BC_BT THEN 10.810500 WHEN tk.MaBuuCuc = @BC_TP THEN 10.802900 ELSE 10.746900 END,
       CASE WHEN tk.MaBuuCuc = @BC_BT THEN 106.604800 WHEN tk.MaBuuCuc = @BC_TP THEN 106.617900 ELSE 106.635800 END
FROM dbo.NhanVienGiaoHang nv
JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan = nv.MaTaiKhoan
WHERE tk.TenDangNhap IN ('shipper.tuan', 'shipper.bao', 'shipper.phuc', 'shipper.huy', 'shipper.dat');

;WITH N AS
(
    SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Seq
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.LichSuViTriNhanVienGiaoHang(MaNhanVienGiaoHang, ViDo, KinhDo, DoChinhXacMet, ThoiGianGhiNhan)
SELECT s.MaNhanVienGiaoHang,
       CAST(s.ViDoGoc + ((n.Seq % 11) * 0.00017) AS DECIMAL(9,6)),
       CAST(s.KinhDoGoc + ((n.Seq % 13) * 0.00013) AS DECIMAL(10,6)),
       CAST(3.0 + ((n.Seq % 12) * 0.7) AS DECIMAL(8,2)),
       DATEADD(MINUTE, -(1440 + ((100 - n.Seq) * 3)), @Now)
FROM N n
JOIN @ShipperMap s ON s.Seq = ((n.Seq - 1) % 5) + 1;

COMMIT;
PRINT N'===> TOÀN BỘ DỮ LIỆU ĐÃ ĐƯỢC CHÈN VÀ ĐỒNG BỘ THÀNH CÔNG VÀO CSDL! <===';

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK;

    BEGIN TRY
        EXEC sys.sp_set_session_context @key = N'LyDoTrangThai', @value = NULL;
        EXEC sys.sp_set_session_context @key = N'NguonCapNhat', @value = NULL;
    END TRY
    BEGIN CATCH
    END CATCH;

    SELECT
        ERROR_NUMBER() AS MaLoi,
        ERROR_LINE() AS DongLoi,
        ERROR_MESSAGE() AS NoiDungLoi;

    THROW;
END CATCH;
GO

/* =============================================================================
   KIỂM TRA TỔNG QUAN DỮ LIỆU VẬN HÀNH SAU KHI CHẠY XONG
   ============================================================================= */
PRINT N'=== THỐNG KÊ TỔNG QUAN CƠ SỞ DỮ LIỆU SAU KHI NẠP ===';

-- 1. Thống kê số lượng bản ghi trên các bảng chính
SELECT N'KhuVuc' AS TenBang, COUNT_BIG(*) AS TongSoDong FROM dbo.KhuVuc
UNION ALL SELECT N'BuuCuc', COUNT_BIG(*) FROM dbo.BuuCuc
UNION ALL SELECT N'Kho', COUNT_BIG(*) FROM dbo.Kho
UNION ALL SELECT N'ViTriLuuKho', COUNT_BIG(*) FROM dbo.ViTriLuuKho
UNION ALL SELECT N'TaiKhoan', COUNT_BIG(*) FROM dbo.TaiKhoan
UNION ALL SELECT N'NhanVienGiaoHang', COUNT_BIG(*) FROM dbo.NhanVienGiaoHang
UNION ALL SELECT N'PhuongTien', COUNT_BIG(*) FROM dbo.PhuongTien
UNION ALL SELECT N'KhachHang', COUNT_BIG(*) FROM dbo.KhachHang
UNION ALL SELECT N'DiaChiKhachHang', COUNT_BIG(*) FROM dbo.DiaChiKhachHang
UNION ALL SELECT N'DonHang', COUNT_BIG(*) FROM dbo.DonHang
UNION ALL SELECT N'DiemGiaoNhan', COUNT_BIG(*) FROM dbo.DiemGiaoNhan
UNION ALL SELECT N'ChiTietDonHang', COUNT_BIG(*) FROM dbo.ChiTietDonHang
UNION ALL SELECT N'KhoanPhiDonHang', COUNT_BIG(*) FROM dbo.KhoanPhiDonHang
UNION ALL SELECT N'TonKhoDonHang', COUNT_BIG(*) FROM dbo.TonKhoDonHang
UNION ALL SELECT N'GiaoDichKho', COUNT_BIG(*) FROM dbo.GiaoDichKho
UNION ALL SELECT N'ChuyenGiaoHang', COUNT_BIG(*) FROM dbo.ChuyenGiaoHang
UNION ALL SELECT N'PhanCongGiaoHang', COUNT_BIG(*) FROM dbo.PhanCongGiaoHang
UNION ALL SELECT N'LanGiaoHang', COUNT_BIG(*) FROM dbo.LanGiaoHang
UNION ALL SELECT N'BangChungGiaoHang', COUNT_BIG(*) FROM dbo.BangChungGiaoHang
UNION ALL SELECT N'ThuTienCOD', COUNT_BIG(*) FROM dbo.ThuTienCOD
UNION ALL SELECT N'NopTienCOD', COUNT_BIG(*) FROM dbo.NopTienCOD
UNION ALL SELECT N'DoiSoatCOD', COUNT_BIG(*) FROM dbo.DoiSoatCOD
UNION ALL SELECT N'CanhBaoGiaoHang', COUNT_BIG(*) FROM dbo.CanhBaoGiaoHang
UNION ALL SELECT N'ThongBao', COUNT_BIG(*) FROM dbo.ThongBao
UNION ALL SELECT N'NhatKyHoatDong', COUNT_BIG(*) FROM dbo.NhatKyHoatDong
UNION ALL SELECT N'LichSuViTriNhanVienGiaoHang', COUNT_BIG(*) FROM dbo.LichSuViTriNhanVienGiaoHang;

-- 2. Phân bố trạng thái của toàn bộ đơn hàng
SELECT
    tt.ThuTuSapXep,
    tt.KyHieuTrangThai,
    tt.TenTrangThai,
    COUNT_BIG(d.MaDonHang) AS SoLuongDon,
    ISNULL(SUM(d.TienCOD), 0) AS TongTienCOD,
    ISNULL(SUM(d.PhiVanChuyen), 0) AS TongPhiVanChuyen
FROM dbo.TrangThaiDonHang tt
LEFT JOIN dbo.DonHang d ON d.MaTrangThaiHienTai = tt.MaTrangThaiDonHang
GROUP BY tt.ThuTuSapXep, tt.KyHieuTrangThai, tt.TenTrangThai
ORDER BY tt.ThuTuSapXep;

-- 3. Kiểm tra tình trạng chuyến giao hàng
SELECT
    cg.KyHieuChuyenGiao,
    cg.TrangThaiChuyen,
    tk.HoTen AS Shipper,
    pt.BienSo,
    COUNT(ct.MaDonHang) AS SoDonGiao,
    cg.TongQuangDuongKm,
    cg.ThoiGianDuKienPhut
FROM dbo.ChuyenGiaoHang cg
LEFT JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang = cg.MaNhanVienGiaoHang
LEFT JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan = nv.MaTaiKhoan
LEFT JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = cg.MaPhuongTien
LEFT JOIN dbo.ChiTietChuyenGiao ct ON ct.MaChuyenGiao = cg.MaChuyenGiao
GROUP BY cg.KyHieuChuyenGiao, cg.TrangThaiChuyen, tk.HoTen, pt.BienSo, cg.TongQuangDuongKm, cg.ThoiGianDuKienPhut
ORDER BY cg.KyHieuChuyenGiao;

-- 4. Kiểm tra công nợ COD của shipper
SELECT * FROM dbo.vw_CongNoCODNhanVienGiaoHang;
GO