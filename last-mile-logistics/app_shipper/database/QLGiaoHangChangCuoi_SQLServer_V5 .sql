/*
===============================================================================
QLGiaoHangChangCuoi - SQL SERVER 2019/2022
Đề tài: Nền tảng kết nối và quản lý điều phối giao hàng chặng cuối
Phiên bản: V5 FINAL AUDITED - bản chốt sau rà soát toàn vẹn nghiệp vụ

CÁCH CHẠY KHUYẾN NGHỊ TRONG SSMS
1. Kết nối vào SQL Server 2019/2022 bằng SSMS.
2. Mở file này.
3. Nếu chưa có database QLGiaoHangChangCuoi:
      Nhấn F5 để chạy TOÀN BỘ FILE một lần.
4. Nếu muốn học từng phần:
      Chạy tuần tự từ BƯỚC 0 đến BƯỚC 22, không bỏ qua bước trước.
5. Sau khi chạy xong, xem BƯỚC 22 để kiểm tra số bảng, khóa ngoại,
   trigger, stored procedure và view.

LƯU Ý QUAN TRỌNG
- Đây là script KHỞI TẠO database, không phải migration.
- Nếu database đã được khởi tạo, script chủ động dừng để tránh tạo trùng object.
- Không DROP database nếu đang có dữ liệu cần giữ.
- Toàn bộ thời gian mặc định lưu UTC bằng SYSUTCDATETIME().
- Mã trạng thái/kỹ thuật dùng tiếng Anh không dấu để Backend/API xử lý ổn định.

THỨ TỰ LOGIC CỦA FILE
Database
  -> Bảng nền/RBAC
  -> Địa lý/bưu cục/kho
  -> Khách hàng
  -> Shipper/phương tiện
  -> Dịch vụ/phí
  -> Đơn hàng
  -> Kho/bàn giao
  -> Chuyến giao/phân công
  -> Giao hàng/sự cố
  -> COD/đối soát
  -> CSKH/audit
  -> Dữ liệu danh mục
  -> Trigger
  -> View
  -> Index bổ sung
  -> Stored Procedure
  -> Kiểm tra cuối
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF TRY_CONVERT(INT, SERVERPROPERTY('ProductMajorVersion')) < 15
BEGIN
    ;THROW 50000, N'Script yêu cầu SQL Server Database Engine 2019 (15.x) trở lên.', 1;
END;
GO

/*
QUY ƯỚC
- Bảng/cột: tiếng Việt không dấu, PascalCase, schema dbo.
- Mã kỹ thuật: ADMIN, NEW, DELIVERED...; tên hiển thị dùng NVARCHAR.
- Thời gian lưu UTC; Backend/UI chịu trách nhiệm đổi sang múi giờ hiển thị.
*/

/* =============================================================================
   BƯỚC 0. KHỞI TẠO DATABASE
   Tạo database, bật READ_COMMITTED_SNAPSHOT và chặn chạy chồng script.
   ============================================================================= */
IF DB_ID(N'QLGiaoHangChangCuoi') IS NULL
BEGIN
    CREATE DATABASE QLGiaoHangChangCuoi;
END
GO

USE master;
GO

IF EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE name = N'QLGiaoHangChangCuoi'
      AND is_read_committed_snapshot_on = 0
)
BEGIN
    ALTER DATABASE QLGiaoHangChangCuoi
    SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
END;
GO

USE QLGiaoHangChangCuoi;
GO

IF OBJECT_ID(N'dbo.VaiTro', N'U') IS NOT NULL
BEGIN
    ;THROW 50001, N'CSDL QLGiaoHangChangCuoi đã được khởi tạo. Không chạy chồng script này lên cấu trúc hiện có.', 1;
END;
GO

/* =============================================================================
   BƯỚC 1. PHÂN QUYỀN NỀN
   Tạo VaiTro, Quyen, VaiTroQuyen.
   ============================================================================= */
CREATE TABLE dbo.VaiTro (
    MaVaiTro          INT IDENTITY(1,1) CONSTRAINT PK_VaiTro PRIMARY KEY,
    KyHieuVaiTro        VARCHAR(50) NOT NULL,
    TenVaiTro        NVARCHAR(100) NOT NULL,
    MoTa     NVARCHAR(500) NULL,
    DangHoatDong        BIT NOT NULL CONSTRAINT DF_VaiTro_DangHoatDong DEFAULT (1),
    ThoiGianTao       DATETIME2(0) NOT NULL CONSTRAINT DF_VaiTro_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_VaiTro_KyHieuVaiTro UNIQUE (KyHieuVaiTro),
    CONSTRAINT UQ_VaiTro_TenVaiTro UNIQUE (TenVaiTro)
);
GO

CREATE TABLE dbo.Quyen (
    MaQuyen    INT IDENTITY(1,1) CONSTRAINT PK_Quyen PRIMARY KEY,
    KyHieuQuyen  VARCHAR(100) NOT NULL,
    TenQuyen  NVARCHAR(150) NOT NULL,
    MoTa     NVARCHAR(500) NULL,
    CONSTRAINT UQ_Quyen_KyHieu UNIQUE (KyHieuQuyen)
);
GO

CREATE TABLE dbo.VaiTroQuyen (
    MaVaiTro          INT NOT NULL,
    MaQuyen    INT NOT NULL,
    ThoiGianCapQuyen       DATETIME2(0) NOT NULL CONSTRAINT DF_VaiTroQuyen_ThoiGianCapQuyen DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_VaiTroQuyen PRIMARY KEY (MaVaiTro, MaQuyen),
    CONSTRAINT FK_VaiTroQuyen_VaiTro FOREIGN KEY (MaVaiTro)
        REFERENCES dbo.VaiTro(MaVaiTro),
    CONSTRAINT FK_VaiTroQuyen_Quyen FOREIGN KEY (MaQuyen)
        REFERENCES dbo.Quyen(MaQuyen)
);
GO

/* =============================================================================
   BƯỚC 2. ĐỊA LÝ - BƯU CỤC - KHO
   Tạo khu vực, bưu cục, vùng phục vụ, tài khoản, kho và vị trí lưu kho.
   ============================================================================= */
CREATE TABLE dbo.KhuVuc (
    MaKhuVuc          INT IDENTITY(1,1) CONSTRAINT PK_KhuVuc PRIMARY KEY,
    KyHieuKhuVuc        VARCHAR(30) NOT NULL,
    TenKhuVuc        NVARCHAR(150) NOT NULL,
    MaKhuVucCha    INT NULL,
    LoaiKhuVuc        VARCHAR(20) NOT NULL CONSTRAINT DF_KhuVuc_LoaiKhuVuc DEFAULT ('SERVICE_ZONE'),
    DangHoatDong        BIT NOT NULL CONSTRAINT DF_KhuVuc_DangHoatDong DEFAULT (1),
    CONSTRAINT UQ_KhuVuc_KyHieuKhuVuc UNIQUE (KyHieuKhuVuc),
    CONSTRAINT CK_KhuVuc_LoaiKhuVuc CHECK (LoaiKhuVuc IN ('CITY','DISTRICT','WARD','SERVICE_ZONE')),
    CONSTRAINT CK_KhuVuc_KhongTuLamCha CHECK (MaKhuVucCha IS NULL OR MaKhuVucCha <> MaKhuVuc),
    CONSTRAINT FK_KhuVuc_Parent FOREIGN KEY (MaKhuVucCha)
        REFERENCES dbo.KhuVuc(MaKhuVuc)
);
GO

CREATE TABLE dbo.BuuCuc (
    MaBuuCuc        INT IDENTITY(1,1) CONSTRAINT PK_BuuCuc PRIMARY KEY,
    KyHieuBuuCuc      VARCHAR(30) NOT NULL,
    TenBuuCuc      NVARCHAR(150) NOT NULL,
    MaKhuVuc          INT NOT NULL,
    DiaChi     NVARCHAR(300) NOT NULL,
    ViDo        DECIMAL(9,6) NULL,
    KinhDo       DECIMAL(10,6) NULL,
    ToaDoDiaLy      GEOGRAPHY NULL,
    SoDienThoai           VARCHAR(20) NULL,
    Email           VARCHAR(150) NULL,
    DangHoatDong        BIT NOT NULL CONSTRAINT DF_BuuCuc_DangHoatDong DEFAULT (1),
    ThoiGianTao       DATETIME2(0) NOT NULL CONSTRAINT DF_BuuCuc_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_BuuCuc_KyHieuBuuCuc UNIQUE (KyHieuBuuCuc),
    CONSTRAINT CK_BuuCuc_ViDo CHECK (ViDo IS NULL OR ViDo BETWEEN -90 AND 90),
    CONSTRAINT CK_BuuCuc_KinhDo CHECK (KinhDo IS NULL OR KinhDo BETWEEN -180 AND 180),
    CONSTRAINT CK_BuuCuc_CapToaDo CHECK (
        (ViDo IS NULL AND KinhDo IS NULL) OR
        (ViDo IS NOT NULL AND KinhDo IS NOT NULL)
    ),
    CONSTRAINT FK_BuuCuc_KhuVuc FOREIGN KEY (MaKhuVuc)
        REFERENCES dbo.KhuVuc(MaKhuVuc)
);
GO

CREATE TABLE dbo.KhuVucPhucVuBuuCuc (
    MaBuuCuc        INT NOT NULL,
    MaKhuVuc          INT NOT NULL,
    LaChinh       BIT NOT NULL CONSTRAINT DF_KhuVucPhucVuBuuCuc_LaChinh DEFAULT (0),
    CONSTRAINT PK_KhuVucPhucVuBuuCuc PRIMARY KEY (MaBuuCuc, MaKhuVuc),
    CONSTRAINT FK_KhuVucPhucVuBuuCuc_BuuCuc FOREIGN KEY (MaBuuCuc)
        REFERENCES dbo.BuuCuc(MaBuuCuc),
    CONSTRAINT FK_KhuVucPhucVuBuuCuc_KhuVuc FOREIGN KEY (MaKhuVuc)
        REFERENCES dbo.KhuVuc(MaKhuVuc)
);
GO

CREATE UNIQUE INDEX UX_KhuVucPhucVuBuuCuc_MotKhuVucChinh
ON dbo.KhuVucPhucVuBuuCuc(MaBuuCuc)
WHERE LaChinh = 1;
GO

CREATE TABLE dbo.TaiKhoan (
    MaTaiKhoan              BIGINT IDENTITY(1,1) CONSTRAINT PK_TaiKhoan PRIMARY KEY,
    KyHieuTaiKhoan            VARCHAR(30) NOT NULL,
    TenDangNhap            VARCHAR(100) NOT NULL,
    MatKhauBam        VARCHAR(255) NOT NULL,
    HoTen            NVARCHAR(150) NOT NULL,
    SoDienThoai               VARCHAR(20) NULL,
    Email               VARCHAR(150) NULL,
    MaVaiTro              INT NOT NULL,
    MaBuuCuc            INT NULL,
    TrangThaiTaiKhoan       VARCHAR(20) NOT NULL CONSTRAINT DF_TaiKhoan_TrangThai DEFAULT ('ACTIVE'),
    SoLanDangNhapSai    INT NOT NULL CONSTRAINT DF_TaiKhoan_FailedLogin DEFAULT (0),
    KhoaDenLuc         DATETIME2(0) NULL,
    DangNhapCuoiLuc         DATETIME2(0) NULL,
    ThoiGianTao           DATETIME2(0) NOT NULL CONSTRAINT DF_TaiKhoan_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    ThoiGianCapNhat           DATETIME2(0) NOT NULL CONSTRAINT DF_TaiKhoan_ThoiGianCapNhat DEFAULT SYSUTCDATETIME(),
    PhienBan              ROWVERSION,
    CONSTRAINT UQ_TaiKhoan_KyHieuTaiKhoan UNIQUE (KyHieuTaiKhoan),
    CONSTRAINT UQ_TaiKhoan_TenDangNhap UNIQUE (TenDangNhap),
    CONSTRAINT CK_TaiKhoan_TrangThai CHECK (TrangThaiTaiKhoan IN ('ACTIVE','LOCKED','INACTIVE')),
    CONSTRAINT CK_TaiKhoan_FailedLogin CHECK (SoLanDangNhapSai >= 0),
    CONSTRAINT FK_TaiKhoan_VaiTro FOREIGN KEY (MaVaiTro)
        REFERENCES dbo.VaiTro(MaVaiTro),
    CONSTRAINT FK_TaiKhoan_BuuCuc FOREIGN KEY (MaBuuCuc)
        REFERENCES dbo.BuuCuc(MaBuuCuc)
);
GO

CREATE UNIQUE INDEX UX_TaiKhoan_SoDienThoai
ON dbo.TaiKhoan(SoDienThoai)
WHERE SoDienThoai IS NOT NULL;
GO

CREATE UNIQUE INDEX UX_TaiKhoan_Email
ON dbo.TaiKhoan(Email)
WHERE Email IS NOT NULL;
GO

CREATE TABLE dbo.TokenLamMoi (
    MaTokenLamMoi      BIGINT IDENTITY(1,1) CONSTRAINT PK_TokenLamMoi PRIMARY KEY,
    MaTaiKhoan              BIGINT NOT NULL,
    GiaTriBamToken           VARCHAR(255) NOT NULL,
    HetHanLuc           DATETIME2(0) NOT NULL,
    ThuHoiLuc           DATETIME2(0) NULL,
    ThoiGianTao           DATETIME2(0) NOT NULL CONSTRAINT DF_TokenLamMoi_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    DiaChiIPTao         VARCHAR(45) NULL,
    TokenThayTheBam VARCHAR(255) NULL,
    CONSTRAINT UQ_TokenLamMoi_GiaTriBamToken UNIQUE (GiaTriBamToken),
    CONSTRAINT CK_TokenLamMoi_Expiry CHECK (HetHanLuc > ThoiGianTao),
    CONSTRAINT CK_TokenLamMoi_ThuHoi CHECK (ThuHoiLuc IS NULL OR ThuHoiLuc >= ThoiGianTao),
    CONSTRAINT FK_TokenLamMoi_TaiKhoan FOREIGN KEY (MaTaiKhoan)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE TABLE dbo.Kho (
    MaKho     INT IDENTITY(1,1) CONSTRAINT PK_Kho PRIMARY KEY,
    KyHieuKho   VARCHAR(30) NOT NULL,
    TenKho   NVARCHAR(150) NOT NULL,
    MaBuuCuc        INT NOT NULL,
    DiaChi     NVARCHAR(300) NULL,
    DangHoatDong        BIT NOT NULL CONSTRAINT DF_Kho_DangHoatDong DEFAULT (1),
    ThoiGianTao       DATETIME2(0) NOT NULL CONSTRAINT DF_Kho_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_Kho_KyHieu UNIQUE (KyHieuKho),
    CONSTRAINT UQ_Kho_MaKho_MaBuuCuc UNIQUE (MaKho, MaBuuCuc),
    CONSTRAINT FK_Kho_BuuCuc FOREIGN KEY (MaBuuCuc)
        REFERENCES dbo.BuuCuc(MaBuuCuc)
);
GO

CREATE TABLE dbo.ViTriLuuKho (
    MaViTriLuuKho BIGINT IDENTITY(1,1) CONSTRAINT PK_ViTriLuuKho PRIMARY KEY,
    MaKho       INT NOT NULL,
    KyHieuViTri      VARCHAR(50) NOT NULL,
    TenKhuLuu          NVARCHAR(100) NULL,
    MaKe         VARCHAR(50) NULL,
    MaO           VARCHAR(50) NULL,
    DangHoatDong          BIT NOT NULL CONSTRAINT DF_ViTriLuuKho_DangHoatDong DEFAULT (1),
    CONSTRAINT UQ_ViTriLuuKho UNIQUE (MaKho, KyHieuViTri),
    CONSTRAINT UQ_ViTriLuuKho_MaViTri_MaKho UNIQUE (MaViTriLuuKho, MaKho),
    CONSTRAINT FK_ViTriLuuKho_Kho FOREIGN KEY (MaKho)
        REFERENCES dbo.Kho(MaKho)
);
GO

/* =============================================================================
   BƯỚC 3. KHÁCH HÀNG
   Tạo khách hàng và sổ địa chỉ.
   ============================================================================= */
CREATE TABLE dbo.KhachHang (
    MaKhachHang      BIGINT IDENTITY(1,1) CONSTRAINT PK_KhachHang PRIMARY KEY,
    KyHieuKhachHang    VARCHAR(30) NOT NULL,
    HoTen        NVARCHAR(150) NOT NULL,
    SoDienThoai           VARCHAR(20) NOT NULL,
    Email           VARCHAR(150) NULL,
    LoaiKhachHang    VARCHAR(20) NOT NULL CONSTRAINT DF_KhachHang_Loai DEFAULT ('INDIVIDUAL'),
    DangHoatDong        BIT NOT NULL CONSTRAINT DF_KhachHang_DangHoatDong DEFAULT (1),
    ThoiGianTao       DATETIME2(0) NOT NULL CONSTRAINT DF_KhachHang_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_KhachHang_KyHieu UNIQUE (KyHieuKhachHang),
    CONSTRAINT CK_KhachHang_Loai CHECK (LoaiKhachHang IN ('INDIVIDUAL','BUSINESS'))
);
GO

CREATE INDEX IX_KhachHang_SoDienThoai ON dbo.KhachHang(SoDienThoai);
GO

CREATE TABLE dbo.DiaChiKhachHang (
    MaDiaChiKhachHang  BIGINT IDENTITY(1,1) CONSTRAINT PK_DiaChiKhachHang PRIMARY KEY,
    MaKhachHang         BIGINT NOT NULL,
    NhanDiaChi       NVARCHAR(100) NULL,
    TenNguoiLienHe        NVARCHAR(150) NULL,
    SoDienThoaiLienHe       VARCHAR(20) NULL,
    DiaChi        NVARCHAR(300) NOT NULL,
    MaKhuVuc             INT NULL,
    ViDo           DECIMAL(9,6) NULL,
    KinhDo          DECIMAL(10,6) NULL,
    ToaDoDiaLy        GEOGRAPHY NULL,
    LaMacDinh          BIT NOT NULL CONSTRAINT DF_DiaChiKhachHang_LaMacDinh DEFAULT (0),
    DangHoatDong           BIT NOT NULL CONSTRAINT DF_DiaChiKhachHang_DangHoatDong DEFAULT (1),
    CONSTRAINT CK_DiaChiKhachHang_Lat CHECK (ViDo IS NULL OR ViDo BETWEEN -90 AND 90),
    CONSTRAINT CK_DiaChiKhachHang_Lng CHECK (KinhDo IS NULL OR KinhDo BETWEEN -180 AND 180),
    CONSTRAINT CK_DiaChiKhachHang_CapToaDo CHECK (
        (ViDo IS NULL AND KinhDo IS NULL) OR
        (ViDo IS NOT NULL AND KinhDo IS NOT NULL)
    ),
    CONSTRAINT FK_DiaChiKhachHang_KhachHang FOREIGN KEY (MaKhachHang)
        REFERENCES dbo.KhachHang(MaKhachHang),
    CONSTRAINT FK_DiaChiKhachHang_KhuVuc FOREIGN KEY (MaKhuVuc)
        REFERENCES dbo.KhuVuc(MaKhuVuc)
);
GO

CREATE UNIQUE INDEX UX_DiaChiKhachHang_MacDinh
ON dbo.DiaChiKhachHang(MaKhachHang)
WHERE LaMacDinh = 1 AND DangHoatDong = 1;
GO

/* =============================================================================
   BƯỚC 4. SHIPPER - PHƯƠNG TIỆN
   Tạo hồ sơ shipper, phương tiện, phân xe, khu vực phục vụ và lịch sử GPS.
   ============================================================================= */
CREATE TABLE dbo.NhanVienGiaoHang (
    MaNhanVienGiaoHang           BIGINT IDENTITY(1,1) CONSTRAINT PK_NhanVienGiaoHang PRIMARY KEY,
    MaTaiKhoan              BIGINT NOT NULL,
    MaNhanVien        VARCHAR(30) NOT NULL,
    CCCD                VARCHAR(20) NULL,
    SoBangLai     VARCHAR(50) NULL,
    NgayHetHanBangLai DATE NULL,
    TrangThaiSanSang  VARCHAR(20) NOT NULL CONSTRAINT DF_NhanVienGiaoHang_Availability DEFAULT ('OFFLINE'),
    ViDoHienTai     DECIMAL(9,6) NULL,
    KinhDoHienTai    DECIMAL(10,6) NULL,
    ToaDoHienTai      GEOGRAPHY NULL,
    ThoiGianCapNhatViTri   DATETIME2(0) NULL,
    DangHoatDong            BIT NOT NULL CONSTRAINT DF_NhanVienGiaoHang_DangHoatDong DEFAULT (1),
    CONSTRAINT UQ_NhanVienGiaoHang_TaiKhoan UNIQUE (MaTaiKhoan),
    CONSTRAINT UQ_NhanVienGiaoHang_MaNhanVien UNIQUE (MaNhanVien),
    CONSTRAINT CK_NhanVienGiaoHang_Availability CHECK (TrangThaiSanSang IN ('AVAILABLE','DELIVERING','BREAK','OFFLINE')),
    CONSTRAINT CK_NhanVienGiaoHang_Lat CHECK (ViDoHienTai IS NULL OR ViDoHienTai BETWEEN -90 AND 90),
    CONSTRAINT CK_NhanVienGiaoHang_Lng CHECK (KinhDoHienTai IS NULL OR KinhDoHienTai BETWEEN -180 AND 180),
    CONSTRAINT CK_NhanVienGiaoHang_CapToaDo CHECK (
        (ViDoHienTai IS NULL AND KinhDoHienTai IS NULL) OR
        (ViDoHienTai IS NOT NULL AND KinhDoHienTai IS NOT NULL)
    ),
    CONSTRAINT FK_NhanVienGiaoHang_TaiKhoan FOREIGN KEY (MaTaiKhoan)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE UNIQUE INDEX UX_NhanVienGiaoHang_CCCD
ON dbo.NhanVienGiaoHang(CCCD)
WHERE CCCD IS NOT NULL;
GO

CREATE TABLE dbo.PhuongTien (
    MaPhuongTien        BIGINT IDENTITY(1,1) CONSTRAINT PK_PhuongTien PRIMARY KEY,
    KyHieuPhuongTien      VARCHAR(30) NOT NULL,
    BienSo     NVARCHAR(20) NOT NULL,
    LoaiXe      VARCHAR(30) NOT NULL,
    KhoiLuongDenKg      DECIMAL(10,2) NOT NULL,
    TheTichToiDaM3      DECIMAL(10,3) NULL,
    TrangThaiPhuongTien    VARCHAR(20) NOT NULL CONSTRAINT DF_PhuongTien_TrangThai DEFAULT ('AVAILABLE'),
    DangHoatDong         BIT NOT NULL CONSTRAINT DF_PhuongTien_DangHoatDong DEFAULT (1),
    CONSTRAINT UQ_PhuongTien_KyHieu UNIQUE (KyHieuPhuongTien),
    CONSTRAINT UQ_PhuongTien_BienSo UNIQUE (BienSo),
    CONSTRAINT CK_PhuongTien_KhoiLuong CHECK (KhoiLuongDenKg > 0),
    CONSTRAINT CK_PhuongTien_Volume CHECK (TheTichToiDaM3 IS NULL OR TheTichToiDaM3 > 0),
    CONSTRAINT CK_PhuongTien_TrangThai CHECK (TrangThaiPhuongTien IN ('AVAILABLE','IN_USE','MAINTENANCE','INACTIVE'))
);
GO

CREATE TABLE dbo.PhanCongPhuongTien (
    MaPhanCongPhuongTien BIGINT IDENTITY(1,1) CONSTRAINT PK_PhanCongPhuongTien PRIMARY KEY,
    MaNhanVienGiaoHang       BIGINT NOT NULL,
    MaPhuongTien       BIGINT NOT NULL,
    ThoiGianPhanCong      DATETIME2(0) NOT NULL CONSTRAINT DF_SVA_ThoiGianPhanCong DEFAULT SYSUTCDATETIME(),
    ThoiGianKetThuc         DATETIME2(0) NULL,
    MaTaiKhoanPhanCong BIGINT NULL,
    GhiChu            NVARCHAR(500) NULL,
    CONSTRAINT CK_SVA_ThoiGian CHECK (ThoiGianKetThuc IS NULL OR ThoiGianKetThuc >= ThoiGianPhanCong),
    CONSTRAINT FK_SVA_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
    CONSTRAINT FK_SVA_PhuongTien FOREIGN KEY (MaPhuongTien)
        REFERENCES dbo.PhuongTien(MaPhuongTien),
    CONSTRAINT FK_SVA_AssignedBy FOREIGN KEY (MaTaiKhoanPhanCong)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE UNIQUE INDEX UX_SVA_ActiveShipper
ON dbo.PhanCongPhuongTien(MaNhanVienGiaoHang)
WHERE ThoiGianKetThuc IS NULL;
GO

CREATE UNIQUE INDEX UX_SVA_ActiveVehicle
ON dbo.PhanCongPhuongTien(MaPhuongTien)
WHERE ThoiGianKetThuc IS NULL;
GO

CREATE TABLE dbo.KhuVucNhanVienGiaoHang (
    MaNhanVienGiaoHang       BIGINT NOT NULL,
    MaKhuVuc          INT NOT NULL,
    LaChinh       BIT NOT NULL CONSTRAINT DF_KhuVucNhanVienGiaoHang_LaChinh DEFAULT (0),
    CONSTRAINT PK_KhuVucNhanVienGiaoHang PRIMARY KEY (MaNhanVienGiaoHang, MaKhuVuc),
    CONSTRAINT FK_KhuVucNhanVienGiaoHang_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
    CONSTRAINT FK_KhuVucNhanVienGiaoHang_KhuVuc FOREIGN KEY (MaKhuVuc)
        REFERENCES dbo.KhuVuc(MaKhuVuc)
);
GO

CREATE UNIQUE INDEX UX_KhuVucNhanVienGiaoHang_MotKhuVucChinh
ON dbo.KhuVucNhanVienGiaoHang(MaNhanVienGiaoHang)
WHERE LaChinh = 1;
GO

CREATE TABLE dbo.LichSuViTriNhanVienGiaoHang (
    MaLichSuViTri BIGINT IDENTITY(1,1) CONSTRAINT PK_LichSuViTriNhanVienGiaoHang PRIMARY KEY,
    MaNhanVienGiaoHang       BIGINT NOT NULL,
    ViDo        DECIMAL(9,6) NOT NULL,
    KinhDo       DECIMAL(10,6) NOT NULL,
    DoChinhXacMet  DECIMAL(8,2) NULL,
    ThoiGianGhiNhan      DATETIME2(0) NOT NULL CONSTRAINT DF_ShipperLocation_ThoiGianGhiNhan DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_ShipperLocation_Lat CHECK (ViDo BETWEEN -90 AND 90),
    CONSTRAINT CK_ShipperLocation_Lng CHECK (KinhDo BETWEEN -180 AND 180),
    CONSTRAINT CK_ShipperLocation_Accuracy CHECK (DoChinhXacMet IS NULL OR DoChinhXacMet >= 0),
    CONSTRAINT FK_ShipperLocation_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang)
);
GO

CREATE INDEX IX_ShipperLocation_NhanVienGiaoHang_ThoiGian
ON dbo.LichSuViTriNhanVienGiaoHang(MaNhanVienGiaoHang, ThoiGianGhiNhan DESC);
GO

CREATE INDEX IX_LichSuViTri_ThoiGianGhiNhan
ON dbo.LichSuViTriNhanVienGiaoHang(ThoiGianGhiNhan)
INCLUDE (MaNhanVienGiaoHang);
GO

/* =============================================================================
   BƯỚC 5. DỊCH VỤ - CẤU HÌNH PHÍ
   Tạo loại dịch vụ và quy tắc tính phí.
   ============================================================================= */
CREATE TABLE dbo.LoaiDichVu (
    MaLoaiDichVu    INT IDENTITY(1,1) CONSTRAINT PK_LoaiDichVu PRIMARY KEY,
    KyHieuDichVu      VARCHAR(30) NOT NULL,
    TenDichVu      NVARCHAR(100) NOT NULL,
    MoTa      NVARCHAR(500) NULL,
    DangHoatDong         BIT NOT NULL CONSTRAINT DF_LoaiDichVu_DangHoatDong DEFAULT (1),
    CONSTRAINT UQ_LoaiDichVu_KyHieu UNIQUE (KyHieuDichVu)
);
GO

CREATE TABLE dbo.QuyTacTinhPhi (
    MaQuyTacTinhPhi       BIGINT IDENTITY(1,1) CONSTRAINT PK_QuyTacTinhPhi PRIMARY KEY,
    MaLoaiDichVu    INT NOT NULL,
    MaKhuVuc           INT NULL,
    KhoangCachTuKm    DECIMAL(10,2) NULL,
    KhoangCachDenKm    DECIMAL(10,2) NULL,
    KhoiLuongTuKg      DECIMAL(10,2) NULL,
    KhoiLuongDenKg      DECIMAL(10,2) NULL,
    PhiCoBan          DECIMAL(18,2) NOT NULL,
    PhiMoiKm         DECIMAL(18,2) NOT NULL CONSTRAINT DF_Rate_PhiMoiKm DEFAULT (0),
    PhiMoiKg         DECIMAL(18,2) NOT NULL CONSTRAINT DF_Rate_PhiMoiKg DEFAULT (0),
    HieuLucTu    DATETIME2(0) NOT NULL,
    HieuLucDen      DATETIME2(0) NULL,
    DangHoatDong         BIT NOT NULL CONSTRAINT DF_Rate_DangHoatDong DEFAULT (1),
    CONSTRAINT CK_Rate_Distance CHECK (
        (KhoangCachTuKm IS NULL OR KhoangCachTuKm >= 0) AND
        (KhoangCachDenKm IS NULL OR KhoangCachDenKm >= 0) AND
        (KhoangCachTuKm IS NULL OR KhoangCachDenKm IS NULL OR KhoangCachDenKm >= KhoangCachTuKm)
    ),
    CONSTRAINT CK_Rate_KhoiLuong CHECK (
        (KhoiLuongTuKg IS NULL OR KhoiLuongTuKg >= 0) AND
        (KhoiLuongDenKg IS NULL OR KhoiLuongDenKg >= 0) AND
        (KhoiLuongTuKg IS NULL OR KhoiLuongDenKg IS NULL OR KhoiLuongDenKg >= KhoiLuongTuKg)
    ),
    CONSTRAINT CK_Rate_Fee CHECK (PhiCoBan >= 0 AND PhiMoiKm >= 0 AND PhiMoiKg >= 0),
    CONSTRAINT CK_Rate_Effective CHECK (HieuLucDen IS NULL OR HieuLucDen > HieuLucTu),
    CONSTRAINT FK_Rate_Service FOREIGN KEY (MaLoaiDichVu)
        REFERENCES dbo.LoaiDichVu(MaLoaiDichVu),
    CONSTRAINT FK_Rate_KhuVuc FOREIGN KEY (MaKhuVuc)
        REFERENCES dbo.KhuVuc(MaKhuVuc)
);
GO

/* =============================================================================
   BƯỚC 6. ĐƠN HÀNG - TRẠNG THÁI
   Tạo state machine, đơn hàng, điểm lấy/giao, chi tiết và khoản phí.
   ============================================================================= */
CREATE TABLE dbo.TrangThaiDonHang (
    MaTrangThaiDonHang    SMALLINT IDENTITY(1,1) CONSTRAINT PK_TrangThaiDonHang PRIMARY KEY,
    KyHieuTrangThai       VARCHAR(40) NOT NULL,
    TenTrangThai       NVARCHAR(100) NOT NULL,
    LaTrangThaiKetThuc       BIT NOT NULL CONSTRAINT DF_TrangThaiDonHang_LaTrangThaiKetThuc DEFAULT (0),
    ThuTuSapXep        SMALLINT NOT NULL,
    CONSTRAINT UQ_TrangThaiDonHang_KyHieu UNIQUE (KyHieuTrangThai),
    CONSTRAINT UQ_TrangThaiDonHang_Sort UNIQUE (ThuTuSapXep)
);
GO

CREATE TABLE dbo.ChuyenTrangThaiDonHang (
    MaTrangThaiCu     SMALLINT NOT NULL,
    MaTrangThaiMoi       SMALLINT NOT NULL,
    BatBuocLyDo   BIT NOT NULL CONSTRAINT DF_StatusTransition_BatBuocLyDo DEFAULT (0),
    CONSTRAINT PK_ChuyenTrangThaiDonHang PRIMARY KEY (MaTrangThaiCu, MaTrangThaiMoi),
    CONSTRAINT CK_StatusTransition_NoSelf CHECK (MaTrangThaiCu <> MaTrangThaiMoi),
    CONSTRAINT FK_StatusTransition_From FOREIGN KEY (MaTrangThaiCu)
        REFERENCES dbo.TrangThaiDonHang(MaTrangThaiDonHang),
    CONSTRAINT FK_StatusTransition_To FOREIGN KEY (MaTrangThaiMoi)
        REFERENCES dbo.TrangThaiDonHang(MaTrangThaiDonHang)
);
GO

CREATE TABLE dbo.DonHang (
    MaDonHang              BIGINT IDENTITY(1,1) CONSTRAINT PK_DonHang PRIMARY KEY,
    KyHieuDonHang            VARCHAR(40) NOT NULL,
    MaVanDon       VARCHAR(50) NOT NULL,
    MaBuuCuc             INT NOT NULL,
    MaNguoiGui     BIGINT NOT NULL,
    MaNguoiNhan   BIGINT NOT NULL,
    MaLoaiDichVu        INT NOT NULL,
    MaTrangThaiHienTai      SMALLINT NOT NULL,
    MaKhoHienTai   INT NULL,
    ThoiGianSanSang              DATETIME2(0) NULL,
    ThoiGianYeuCauGiao  DATETIME2(0) NULL,
    ThoiGianDuKienGiao   DATETIME2(0) NULL,
    MucDoUuTien        TINYINT NOT NULL CONSTRAINT DF_DonHang_MucDoUuTien DEFAULT (3),
    TongKhoiLuongKg        DECIMAL(12,3) NOT NULL CONSTRAINT DF_DonHang_TongKhoiLuong DEFAULT (0),
    GiaTriKhaiBao        DECIMAL(18,2) NOT NULL CONSTRAINT DF_DonHang_GiaTriKhaiBao DEFAULT (0),
    TienCOD            DECIMAL(18,2) NOT NULL CONSTRAINT DF_DonHang_COD DEFAULT (0),
    PhiVanChuyen          DECIMAL(18,2) NOT NULL CONSTRAINT DF_DonHang_PhiVanChuyen DEFAULT (0),
    GhiChuDacBiet          NVARCHAR(1000) NULL,
    MaTaiKhoanTao      BIGINT NOT NULL,
    MaTaiKhoanCapNhatCuoi BIGINT NULL,
    ThoiGianTao            DATETIME2(0) NOT NULL CONSTRAINT DF_DonHang_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    ThoiGianCapNhat            DATETIME2(0) NOT NULL CONSTRAINT DF_DonHang_ThoiGianCapNhat DEFAULT SYSUTCDATETIME(),
    PhienBan               ROWVERSION,
    CONSTRAINT UQ_DonHang_KyHieuDonHang UNIQUE (KyHieuDonHang),
    CONSTRAINT UQ_DonHang_Tracking UNIQUE (MaVanDon),
    CONSTRAINT CK_DonHang_MucDoUuTien CHECK (MucDoUuTien BETWEEN 1 AND 5),
    CONSTRAINT CK_DonHang_KhoiLuong CHECK (TongKhoiLuongKg >= 0),
    CONSTRAINT CK_DonHang_Money CHECK (GiaTriKhaiBao >= 0 AND TienCOD >= 0 AND PhiVanChuyen >= 0),
    CONSTRAINT CK_DonHang_DeliveryTime CHECK (
        (ThoiGianYeuCauGiao IS NULL OR ThoiGianSanSang IS NULL OR ThoiGianYeuCauGiao >= ThoiGianSanSang)
        AND
        (ThoiGianDuKienGiao IS NULL OR ThoiGianSanSang IS NULL OR ThoiGianDuKienGiao >= ThoiGianSanSang)
    ),
    CONSTRAINT FK_DonHang_BuuCuc FOREIGN KEY (MaBuuCuc)
        REFERENCES dbo.BuuCuc(MaBuuCuc),
    CONSTRAINT FK_DonHang_Sender FOREIGN KEY (MaNguoiGui)
        REFERENCES dbo.KhachHang(MaKhachHang),
    CONSTRAINT FK_DonHang_Receiver FOREIGN KEY (MaNguoiNhan)
        REFERENCES dbo.KhachHang(MaKhachHang),
    CONSTRAINT FK_DonHang_Service FOREIGN KEY (MaLoaiDichVu)
        REFERENCES dbo.LoaiDichVu(MaLoaiDichVu),
    CONSTRAINT FK_DonHang_TrangThai FOREIGN KEY (MaTrangThaiHienTai)
        REFERENCES dbo.TrangThaiDonHang(MaTrangThaiDonHang),
    CONSTRAINT FK_DonHang_Kho_BuuCuc FOREIGN KEY (MaKhoHienTai, MaBuuCuc)
        REFERENCES dbo.Kho(MaKho, MaBuuCuc),
    CONSTRAINT FK_DonHang_CreatedBy FOREIGN KEY (MaTaiKhoanTao)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan),
    CONSTRAINT FK_DonHang_ModifiedBy FOREIGN KEY (MaTaiKhoanCapNhatCuoi)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE INDEX IX_DonHang_BuuCuc_TrangThai
ON dbo.DonHang(MaBuuCuc, MaTrangThaiHienTai, ThoiGianYeuCauGiao)
INCLUDE (KyHieuDonHang, MaVanDon, TongKhoiLuongKg, TienCOD);
GO

CREATE INDEX IX_DonHang_Receiver
ON dbo.DonHang(MaNguoiNhan, ThoiGianTao DESC);
GO

CREATE TABLE dbo.DiemGiaoNhan (
    MaDiemGiaoNhan      BIGINT IDENTITY(1,1) CONSTRAINT PK_DiemGiaoNhan PRIMARY KEY,
    MaDonHang          BIGINT NOT NULL,
    LoaiDiem         VARCHAR(10) NOT NULL,
    TenNguoiLienHe      NVARCHAR(150) NOT NULL,
    SoDienThoaiLienHe     VARCHAR(20) NOT NULL,
    DiaChi      NVARCHAR(300) NOT NULL,
    MaKhuVuc           INT NULL,
    ViDo         DECIMAL(9,6) NULL,
    KinhDo        DECIMAL(10,6) NULL,
    ToaDoDiaLy       GEOGRAPHY NULL,
    GhiChu             NVARCHAR(500) NULL,
    CONSTRAINT UQ_DiemGiaoNhan_Loai UNIQUE (MaDonHang, LoaiDiem),
    CONSTRAINT UQ_DiemGiaoNhan_MaDiem_MaDon UNIQUE (MaDiemGiaoNhan, MaDonHang),
    CONSTRAINT CK_DiemGiaoNhan_Loai CHECK (LoaiDiem IN ('PICKUP','DELIVERY')),
    CONSTRAINT CK_DiemGiaoNhan_Lat CHECK (ViDo IS NULL OR ViDo BETWEEN -90 AND 90),
    CONSTRAINT CK_DiemGiaoNhan_Lng CHECK (KinhDo IS NULL OR KinhDo BETWEEN -180 AND 180),
    CONSTRAINT CK_DiemGiaoNhan_CapToaDo CHECK (
        (ViDo IS NULL AND KinhDo IS NULL) OR
        (ViDo IS NOT NULL AND KinhDo IS NOT NULL)
    ),
    CONSTRAINT FK_DiemGiaoNhan_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_DiemGiaoNhan_KhuVuc FOREIGN KEY (MaKhuVuc)
        REFERENCES dbo.KhuVuc(MaKhuVuc)
);
GO

CREATE INDEX IX_DiemGiaoNhan_KhuVuc_Loai ON dbo.DiemGiaoNhan(MaKhuVuc, LoaiDiem);
GO

CREATE TABLE dbo.ChiTietDonHang (
    MaChiTietDonHang      BIGINT IDENTITY(1,1) CONSTRAINT PK_ChiTietDonHang PRIMARY KEY,
    MaDonHang          BIGINT NOT NULL,
    TenHang         NVARCHAR(200) NOT NULL,
    LoaiHang     NVARCHAR(100) NULL,
    SoLuong         INT NOT NULL,
    KhoiLuongDonViKg     DECIMAL(10,3) NOT NULL,
    ChieuDaiCm         DECIMAL(10,2) NULL,
    ChieuRongCm          DECIMAL(10,2) NULL,
    ChieuCaoCm         DECIMAL(10,2) NULL,
    GiaTriHang        DECIMAL(18,2) NOT NULL CONSTRAINT DF_ChiTietDonHang_Value DEFAULT (0),
    HangDeVo        BIT NOT NULL CONSTRAINT DF_ChiTietDonHang_HangDeVo DEFAULT (0),
    GhiChu             NVARCHAR(500) NULL,
    CONSTRAINT CK_ChiTietDonHang_SoLuong CHECK (SoLuong > 0),
    CONSTRAINT CK_ChiTietDonHang_KhoiLuong CHECK (KhoiLuongDonViKg > 0),
    CONSTRAINT CK_ChiTietDonHang_Dimensions CHECK (
        (ChieuDaiCm IS NULL AND ChieuRongCm IS NULL AND ChieuCaoCm IS NULL)
        OR
        (ChieuDaiCm > 0 AND ChieuRongCm > 0 AND ChieuCaoCm > 0)
    ),
    CONSTRAINT CK_ChiTietDonHang_Value CHECK (GiaTriHang >= 0),
    CONSTRAINT FK_ChiTietDonHang_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang)
);
GO

CREATE TABLE dbo.KhoanPhiDonHang (
    MaKhoanPhi    BIGINT IDENTITY(1,1) CONSTRAINT PK_KhoanPhiDonHang PRIMARY KEY,
    MaDonHang          BIGINT NOT NULL,
    LoaiKhoanPhi       VARCHAR(30) NOT NULL,
    SoTien           DECIMAL(18,2) NOT NULL,
    MoTa      NVARCHAR(300) NULL,
    ThoiGianTao        DATETIME2(0) NOT NULL CONSTRAINT DF_KhoanPhiDonHang_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_KhoanPhiDonHang_Loai CHECK (LoaiKhoanPhi IN ('SHIPPING','RETURN','SURCHARGE','DISCOUNT','OTHER')),
    CONSTRAINT CK_KhoanPhiDonHang_SoTien CHECK (
        (LoaiKhoanPhi = 'DISCOUNT' AND SoTien <= 0) OR
        (LoaiKhoanPhi <> 'DISCOUNT' AND SoTien >= 0)
    ),
    CONSTRAINT FK_KhoanPhiDonHang_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang)
);
GO

/* =============================================================================
   BƯỚC 7. KHO - GIAO DỊCH KHO - BÀN GIAO
   Theo dõi đơn trong kho, nhập/xuất/di chuyển và bàn giao cho shipper.
   ============================================================================= */
CREATE TABLE dbo.TonKhoDonHang (
    MaDonHang              BIGINT CONSTRAINT PK_TonKhoDonHang PRIMARY KEY,
    MaKho          INT NOT NULL,
    MaViTriLuuKho    BIGINT NULL,
    TrangThaiTonKho      VARCHAR(20) NOT NULL,
    ThoiGianNhapKho           DATETIME2(0) NOT NULL,
    ThoiGianDiChuyenCuoi          DATETIME2(0) NULL,
    MaTaiKhoanCapNhatCuoi  BIGINT NOT NULL,
    CONSTRAINT CK_TonKhoDonHang_TrangThai CHECK (TrangThaiTonKho IN ('RECEIVED','STORED','ALLOCATED','HANDED_OVER','RETURNED')),
    CONSTRAINT CK_TonKhoDonHang_ThoiGian CHECK (ThoiGianDiChuyenCuoi IS NULL OR ThoiGianDiChuyenCuoi >= ThoiGianNhapKho),
    CONSTRAINT CK_TonKhoDonHang_ViTri CHECK (TrangThaiTonKho <> 'STORED' OR MaViTriLuuKho IS NOT NULL),
    CONSTRAINT FK_TonKhoDonHang_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_TonKhoDonHang_Kho FOREIGN KEY (MaKho)
        REFERENCES dbo.Kho(MaKho),
    CONSTRAINT FK_TonKhoDonHang_ViTri_Kho FOREIGN KEY (MaViTriLuuKho, MaKho)
        REFERENCES dbo.ViTriLuuKho(MaViTriLuuKho, MaKho),
    CONSTRAINT FK_TonKhoDonHang_TaiKhoan FOREIGN KEY (MaTaiKhoanCapNhatCuoi)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE INDEX IX_TonKhoDonHang_Kho_ViTri
ON dbo.TonKhoDonHang(MaKho, MaViTriLuuKho, TrangThaiTonKho);
GO

CREATE TABLE dbo.GiaoDichKho (
    MaGiaoDichKho BIGINT IDENTITY(1,1) CONSTRAINT PK_GiaoDichKho PRIMARY KEY,
    KyHieuGiaoDich        VARCHAR(40) NOT NULL,
    MaKho            INT NOT NULL,
    LoaiGiaoDich        VARCHAR(20) NOT NULL,
    TrangThaiGiaoDich      VARCHAR(20) NOT NULL CONSTRAINT DF_WT_TrangThai DEFAULT ('COMPLETED'),
    MaTaiKhoanThucHien      BIGINT NOT NULL,
    ThoiGianThucHien            DATETIME2(0) NOT NULL CONSTRAINT DF_WT_ThoiGianThucHien DEFAULT SYSUTCDATETIME(),
    GhiChu                   NVARCHAR(500) NULL,
    CONSTRAINT UQ_GiaoDichKho_KyHieu UNIQUE (KyHieuGiaoDich),
    CONSTRAINT CK_GiaoDichKho_Loai CHECK (LoaiGiaoDich IN ('INBOUND','MOVE','OUTBOUND','RETURN_IN')),
    CONSTRAINT CK_GiaoDichKho_TrangThai CHECK (TrangThaiGiaoDich IN ('PENDING','COMPLETED','CANCELLED')),
    CONSTRAINT FK_GiaoDichKho_Kho FOREIGN KEY (MaKho)
        REFERENCES dbo.Kho(MaKho),
    CONSTRAINT FK_GiaoDichKho_TaiKhoan FOREIGN KEY (MaTaiKhoanThucHien)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE TABLE dbo.ChiTietGiaoDichKho (
    MaGiaoDichKho BIGINT NOT NULL,
    MaDonHang                 BIGINT NOT NULL,
    MaViTriNguon   BIGINT NULL,
    MaViTriDich     BIGINT NULL,
    TinhTrangHang           VARCHAR(20) NOT NULL CONSTRAINT DF_WTD_Condition DEFAULT ('NORMAL'),
    GhiChu                    NVARCHAR(500) NULL,
    CONSTRAINT PK_ChiTietGiaoDichKho PRIMARY KEY (MaGiaoDichKho, MaDonHang),
    CONSTRAINT CK_WTD_Condition CHECK (TinhTrangHang IN ('NORMAL','DAMAGED','MISSING','OTHER')),
    CONSTRAINT FK_WTD_Header FOREIGN KEY (MaGiaoDichKho)
        REFERENCES dbo.GiaoDichKho(MaGiaoDichKho),
    CONSTRAINT FK_WTD_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_WTD_FromLocation FOREIGN KEY (MaViTriNguon)
        REFERENCES dbo.ViTriLuuKho(MaViTriLuuKho),
    CONSTRAINT FK_WTD_ToLocation FOREIGN KEY (MaViTriDich)
        REFERENCES dbo.ViTriLuuKho(MaViTriLuuKho)
);
GO

CREATE TABLE dbo.BanGiaoHang (
    MaBanGiao          BIGINT IDENTITY(1,1) CONSTRAINT PK_BanGiaoHang PRIMARY KEY,
    KyHieuBanGiao        VARCHAR(40) NOT NULL,
    MaKho         INT NOT NULL,
    MaNhanVienGiaoHang           BIGINT NOT NULL,
    MaTaiKhoanBanGiao  BIGINT NOT NULL,
    TrangThaiBanGiao      VARCHAR(20) NOT NULL CONSTRAINT DF_BanGiaoHang_TrangThai DEFAULT ('PENDING'),
    ThoiGianBanGiao        DATETIME2(0) NULL,
    ThoiGianNhanVienXacNhan  DATETIME2(0) NULL,
    GhiChu                NVARCHAR(500) NULL,
    CONSTRAINT UQ_BanGiaoHang_KyHieu UNIQUE (KyHieuBanGiao),
    CONSTRAINT CK_BanGiaoHang_TrangThai CHECK (TrangThaiBanGiao IN ('PENDING','CONFIRMED','REJECTED','CANCELLED')),
    CONSTRAINT CK_BanGiaoHang_ThoiGian CHECK (
        (ThoiGianNhanVienXacNhan IS NULL OR ThoiGianBanGiao IS NULL OR ThoiGianNhanVienXacNhan >= ThoiGianBanGiao)
        AND
        (TrangThaiBanGiao <> 'CONFIRMED'
         OR (ThoiGianBanGiao IS NOT NULL AND ThoiGianNhanVienXacNhan IS NOT NULL))
    ),
    CONSTRAINT FK_BanGiaoHang_Kho FOREIGN KEY (MaKho)
        REFERENCES dbo.Kho(MaKho),
    CONSTRAINT FK_BanGiaoHang_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
    CONSTRAINT FK_BanGiaoHang_TaiKhoan FOREIGN KEY (MaTaiKhoanBanGiao)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE TABLE dbo.ChiTietBanGiaoHang (
    MaBanGiao      BIGINT NOT NULL,
    MaDonHang         BIGINT NOT NULL,
    SoLuong        INT NOT NULL CONSTRAINT DF_ChiTietBanGiaoHang_SoLuong DEFAULT (1),
    GhiChuTinhTrang   NVARCHAR(500) NULL,
    CONSTRAINT PK_ChiTietBanGiaoHang PRIMARY KEY (MaBanGiao, MaDonHang),
    CONSTRAINT CK_ChiTietBanGiaoHang_SoLuong CHECK (SoLuong > 0),
    CONSTRAINT FK_ChiTietBanGiaoHang_BanGiaoHang FOREIGN KEY (MaBanGiao)
        REFERENCES dbo.BanGiaoHang(MaBanGiao),
    CONSTRAINT FK_ChiTietBanGiaoHang_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang)
);
GO

/* =============================================================================
   BƯỚC 8. CHUYẾN GIAO - TUYẾN - PHÂN CÔNG
   Tạo chuyến, gom đơn, điểm dừng tuyến và phân công giao hàng.
   ============================================================================= */
CREATE TABLE dbo.ChuyenGiaoHang (
    MaChuyenGiao               BIGINT IDENTITY(1,1) CONSTRAINT PK_ChuyenGiaoHang PRIMARY KEY,
    KyHieuChuyenGiao             VARCHAR(40) NOT NULL,
    MaBuuCuc             INT NOT NULL,
    MaKho          INT NOT NULL,
    MaNhanVienGiaoHang            BIGINT NULL,
    MaPhuongTien            BIGINT NULL,
    TrangThaiChuyen           VARCHAR(20) NOT NULL CONSTRAINT DF_ChuyenGiao_TrangThai DEFAULT ('PLANNED'),
    PhuongPhapToiUu   VARCHAR(20) NULL,
    TongQuangDuongKm      DECIMAL(10,2) NULL,
    ThoiGianDuKienPhut INT NULL,
    ThoiGianBatDauDuKien       DATETIME2(0) NULL,
    ThoiGianBatDauThucTe        DATETIME2(0) NULL,
    ThoiGianKetThucThucTe          DATETIME2(0) NULL,
    MaTaiKhoanTao      BIGINT NOT NULL,
    ThoiGianTao            DATETIME2(0) NOT NULL CONSTRAINT DF_ChuyenGiao_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_ChuyenGiaoHang_KyHieu UNIQUE (KyHieuChuyenGiao),
    CONSTRAINT CK_ChuyenGiao_TrangThai CHECK (TrangThaiChuyen IN ('PLANNED','ASSIGNED','ACCEPTED','IN_PROGRESS','COMPLETED','CANCELLED')),
    CONSTRAINT CK_ChuyenGiao_Method CHECK (PhuongPhapToiUu IS NULL OR PhuongPhapToiUu IN ('VRP','DIJKSTRA','ASTAR','MANUAL')),
    CONSTRAINT CK_ChuyenGiao_Distance CHECK (TongQuangDuongKm IS NULL OR TongQuangDuongKm >= 0),
    CONSTRAINT CK_ChuyenGiao_Duration CHECK (ThoiGianDuKienPhut IS NULL OR ThoiGianDuKienPhut >= 0),
    CONSTRAINT CK_ChuyenGiao_ThoiGian CHECK (
        (ThoiGianBatDauThucTe IS NULL OR ThoiGianBatDauDuKien IS NULL OR ThoiGianBatDauThucTe >= DATEADD(DAY,-1,ThoiGianBatDauDuKien))
        AND (ThoiGianKetThucThucTe IS NULL OR ThoiGianBatDauThucTe IS NULL OR ThoiGianKetThucThucTe >= ThoiGianBatDauThucTe)
    ),
    CONSTRAINT FK_ChuyenGiao_BuuCuc FOREIGN KEY (MaBuuCuc)
        REFERENCES dbo.BuuCuc(MaBuuCuc),
    CONSTRAINT FK_ChuyenGiao_Kho_BuuCuc FOREIGN KEY (MaKho, MaBuuCuc)
        REFERENCES dbo.Kho(MaKho, MaBuuCuc),
    CONSTRAINT FK_ChuyenGiao_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
    CONSTRAINT FK_ChuyenGiao_PhuongTien FOREIGN KEY (MaPhuongTien)
        REFERENCES dbo.PhuongTien(MaPhuongTien),
    CONSTRAINT FK_ChuyenGiao_CreatedBy FOREIGN KEY (MaTaiKhoanTao)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE INDEX IX_ChuyenGiao_NhanVienGiaoHang_TrangThai
ON dbo.ChuyenGiaoHang(MaNhanVienGiaoHang, TrangThaiChuyen, ThoiGianBatDauDuKien);
GO

CREATE TABLE dbo.ChiTietChuyenGiao (
    MaChuyenGiao           BIGINT NOT NULL,
    MaDonHang          BIGINT NOT NULL,
    ThuTuDuKien  INT NOT NULL,
    ThoiGianDenDuKien DATETIME2(0) NULL,
    ThoiGianDenThucTe    DATETIME2(0) NULL,
    CONSTRAINT PK_ChiTietChuyenGiao PRIMARY KEY (MaChuyenGiao, MaDonHang),
    CONSTRAINT UQ_ChiTietChuyenGiao_ThuTu UNIQUE (MaChuyenGiao, ThuTuDuKien),
    CONSTRAINT CK_ChiTietChuyenGiao_ThuTu CHECK (ThuTuDuKien > 0),
    CONSTRAINT FK_ChiTietChuyenGiao_ChuyenGiao FOREIGN KEY (MaChuyenGiao)
        REFERENCES dbo.ChuyenGiaoHang(MaChuyenGiao),
    CONSTRAINT FK_ChiTietChuyenGiao_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang)
);
GO

CREATE INDEX IX_ChiTietChuyenGiao_DonHang ON dbo.ChiTietChuyenGiao(MaDonHang);
GO

CREATE TABLE dbo.DiemDungTuyen (
    MaDiemDung        BIGINT IDENTITY(1,1) CONSTRAINT PK_DiemDungTuyen PRIMARY KEY,
    MaChuyenGiao             BIGINT NOT NULL,
    MaDonHang            BIGINT NULL,
    MaDiemGiaoNhan        BIGINT NULL,
    ThuTuDiemDung       INT NOT NULL,
    LoaiDiem           VARCHAR(20) NOT NULL,
    ViDo           DECIMAL(9,6) NOT NULL,
    KinhDo          DECIMAL(10,6) NOT NULL,
    ToaDoDiaLy       GEOGRAPHY NULL,
    ThoiGianDenDuKien DATETIME2(0) NULL,
    ThoiGianDenThucTe    DATETIME2(0) NULL,
    KhoangCachTuDiemTruocKm DECIMAL(10,2) NULL,
    ThoiGianTuDiemTruocPhut INT NULL,
    CONSTRAINT UQ_DiemDungTuyen_ThuTu UNIQUE (MaChuyenGiao, ThuTuDiemDung),
    CONSTRAINT CK_DiemDungTuyen_ThuTu CHECK (ThuTuDiemDung > 0),
    CONSTRAINT CK_DiemDungTuyen_Loai CHECK (LoaiDiem IN ('BRANCH','PICKUP','DELIVERY','RETURN')),
    CONSTRAINT CK_DiemDungTuyen_Lat CHECK (ViDo BETWEEN -90 AND 90),
    CONSTRAINT CK_DiemDungTuyen_Lng CHECK (KinhDo BETWEEN -180 AND 180),
    CONSTRAINT CK_DiemDungTuyen_Distance CHECK (KhoangCachTuDiemTruocKm IS NULL OR KhoangCachTuDiemTruocKm >= 0),
    CONSTRAINT CK_DiemDungTuyen_Duration CHECK (ThoiGianTuDiemTruocPhut IS NULL OR ThoiGianTuDiemTruocPhut >= 0),
    CONSTRAINT CK_DiemDungTuyen_ThamChieu CHECK (
        (LoaiDiem = 'BRANCH' AND MaDonHang IS NULL AND MaDiemGiaoNhan IS NULL)
        OR
        (LoaiDiem IN ('PICKUP','DELIVERY') AND MaDonHang IS NOT NULL AND MaDiemGiaoNhan IS NOT NULL)
        OR
        (LoaiDiem = 'RETURN' AND MaDonHang IS NOT NULL)
    ),
    CONSTRAINT FK_DiemDungTuyen_ChuyenGiao FOREIGN KEY (MaChuyenGiao)
        REFERENCES dbo.ChuyenGiaoHang(MaChuyenGiao),
    CONSTRAINT FK_DiemDungTuyen_Chuyen_DonHang FOREIGN KEY (MaChuyenGiao, MaDonHang)
        REFERENCES dbo.ChiTietChuyenGiao(MaChuyenGiao, MaDonHang),
    CONSTRAINT FK_DiemDungTuyen_DiemGiaoNhan_DonHang FOREIGN KEY (MaDiemGiaoNhan, MaDonHang)
        REFERENCES dbo.DiemGiaoNhan(MaDiemGiaoNhan, MaDonHang)
);
GO

CREATE TABLE dbo.PhanCongGiaoHang (
    MaPhanCongGiaoHang      BIGINT IDENTITY(1,1) CONSTRAINT PK_PhanCongGiaoHang PRIMARY KEY,
    MaDonHang           BIGINT NOT NULL,
    MaChuyenGiao            BIGINT NULL,
    MaNhanVienGiaoHang         BIGINT NOT NULL,
    MaPhuongTien         BIGINT NULL,
    MaTaiKhoanPhanCong  BIGINT NOT NULL,
    ThoiGianPhanCong        DATETIME2(0) NOT NULL CONSTRAINT DF_Assignment_ThoiGianPhanCong DEFAULT SYSUTCDATETIME(),
    ThoiGianChapNhan        DATETIME2(0) NULL,
    ThoiGianKetThuc           DATETIME2(0) NULL,
    TrangThaiPhanCong  VARCHAR(20) NOT NULL CONSTRAINT DF_Assignment_TrangThai DEFAULT ('PENDING'),
    BoQuaQuyTacKhuVuc  BIT NOT NULL CONSTRAINT DF_Assignment_Override DEFAULT (0),
    LyDoBoQua    NVARCHAR(500) NULL,
    CONSTRAINT CK_Assignment_TrangThai CHECK (TrangThaiPhanCong IN ('PENDING','ACCEPTED','IN_PROGRESS','COMPLETED','ATTEMPT_FAILED','REJECTED','CANCELLED','REASSIGNED')),
    CONSTRAINT CK_Assignment_ThoiGian CHECK (
        (ThoiGianChapNhan IS NULL OR ThoiGianChapNhan >= ThoiGianPhanCong)
        AND
        (ThoiGianKetThuc IS NULL OR ThoiGianKetThuc >= COALESCE(ThoiGianChapNhan, ThoiGianPhanCong))
    ),
    CONSTRAINT CK_Assignment_TrangThaiThoiGian CHECK (
        (TrangThaiPhanCong = 'PENDING' AND ThoiGianChapNhan IS NULL AND ThoiGianKetThuc IS NULL)
        OR (TrangThaiPhanCong IN ('ACCEPTED','IN_PROGRESS') AND ThoiGianChapNhan IS NOT NULL AND ThoiGianKetThuc IS NULL)
        OR (TrangThaiPhanCong IN ('COMPLETED','ATTEMPT_FAILED') AND ThoiGianChapNhan IS NOT NULL AND ThoiGianKetThuc IS NOT NULL)
        OR (TrangThaiPhanCong IN ('REJECTED','CANCELLED','REASSIGNED') AND ThoiGianKetThuc IS NOT NULL)
    ),
    CONSTRAINT CK_Assignment_Override CHECK (
        BoQuaQuyTacKhuVuc = 0 OR
        (BoQuaQuyTacKhuVuc = 1 AND NULLIF(LTRIM(RTRIM(LyDoBoQua)), N'') IS NOT NULL)
    ),
    CONSTRAINT UQ_PhanCongGiaoHang_MaPhanCong_MaDon UNIQUE (MaPhanCongGiaoHang, MaDonHang),
    CONSTRAINT FK_Assignment_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_Assignment_ChuyenGiao FOREIGN KEY (MaChuyenGiao)
        REFERENCES dbo.ChuyenGiaoHang(MaChuyenGiao),
    CONSTRAINT FK_Assignment_Chuyen_DonHang FOREIGN KEY (MaChuyenGiao, MaDonHang)
        REFERENCES dbo.ChiTietChuyenGiao(MaChuyenGiao, MaDonHang),
    CONSTRAINT FK_Assignment_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
    CONSTRAINT FK_Assignment_PhuongTien FOREIGN KEY (MaPhuongTien)
        REFERENCES dbo.PhuongTien(MaPhuongTien),
    CONSTRAINT FK_Assignment_TaiKhoan FOREIGN KEY (MaTaiKhoanPhanCong)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

-- Mỗi đơn chỉ được có một phân công hiện hành.
CREATE UNIQUE INDEX UX_PhanCongGiaoHang_OneCurrent
ON dbo.PhanCongGiaoHang(MaDonHang)
WHERE ThoiGianKetThuc IS NULL;
GO

CREATE INDEX IX_Assignment_NhanVienGiaoHang_TrangThai
ON dbo.PhanCongGiaoHang(MaNhanVienGiaoHang, TrangThaiPhanCong, ThoiGianPhanCong DESC);
GO

/* =============================================================================
   BƯỚC 9. GIAO HÀNG - LỊCH SỬ - SỰ CỐ
   Lưu lịch sử trạng thái, lần giao, bằng chứng, thất bại, giao lại/hoàn và cảnh báo.
   ============================================================================= */
CREATE TABLE dbo.LichSuTrangThaiDonHang (
    MaLichSuTrangThai BIGINT IDENTITY(1,1) CONSTRAINT PK_LichSuTrangThaiDonHang PRIMARY KEY,
    MaDonHang          BIGINT NOT NULL,
    MaTrangThaiCu     SMALLINT NULL,
    MaTrangThaiMoi       SMALLINT NOT NULL,
    MaTaiKhoanThayDoi  BIGINT NULL,
    ThoiGianThayDoi        DATETIME2(0) NOT NULL CONSTRAINT DF_StatusHistory_ThoiGianThayDoi DEFAULT SYSUTCDATETIME(),
    LyDo           NVARCHAR(500) NULL,
    NguonCapNhat     VARCHAR(20) NOT NULL CONSTRAINT DF_StatusHistory_Source DEFAULT ('WEB'),
    CONSTRAINT CK_StatusHistory_Source CHECK (NguonCapNhat IN ('WEB','MOBILE','SYSTEM','API')),
    CONSTRAINT FK_StatusHistory_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_StatusHistory_From FOREIGN KEY (MaTrangThaiCu)
        REFERENCES dbo.TrangThaiDonHang(MaTrangThaiDonHang),
    CONSTRAINT FK_StatusHistory_To FOREIGN KEY (MaTrangThaiMoi)
        REFERENCES dbo.TrangThaiDonHang(MaTrangThaiDonHang),
    CONSTRAINT FK_StatusHistory_TaiKhoan FOREIGN KEY (MaTaiKhoanThayDoi)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE INDEX IX_StatusHistory_DonHang_ThoiGian
ON dbo.LichSuTrangThaiDonHang(MaDonHang, ThoiGianThayDoi DESC);
GO

CREATE TABLE dbo.LyDoGiaoThatBai (
    MaLyDoGiaoThatBai  INT IDENTITY(1,1) CONSTRAINT PK_LyDoGiaoThatBai PRIMARY KEY,
    KyHieuLyDo       VARCHAR(40) NOT NULL,
    TenLyDo       NVARCHAR(150) NOT NULL,
    BatBuocMinhChung BIT NOT NULL CONSTRAINT DF_LyDoGiaoThatBai_Evidence DEFAULT (0),
    DangHoatDong         BIT NOT NULL CONSTRAINT DF_LyDoGiaoThatBai_DangHoatDong DEFAULT (1),
    CONSTRAINT UQ_LyDoGiaoThatBai_KyHieu UNIQUE (KyHieuLyDo)
);
GO

CREATE TABLE dbo.LanGiaoHang (
    MaLanGiaoHang BIGINT IDENTITY(1,1) CONSTRAINT PK_LanGiaoHang PRIMARY KEY,
    MaDonHang          BIGINT NOT NULL,
    MaPhanCongGiaoHang     BIGINT NOT NULL,
    SoLanThu        INT NOT NULL,
    ThoiGianThuGiao      DATETIME2(0) NOT NULL CONSTRAINT DF_LanGiaoHang_ThoiGian DEFAULT SYSUTCDATETIME(),
    KetQua           VARCHAR(20) NOT NULL,
    MaLyDoGiaoThatBai  INT NULL,
    GhiChu             NVARCHAR(1000) NULL,
    ThoiGianGiaoLaiDuKien      DATETIME2(0) NULL,
    MaTaiKhoanGhiNhan BIGINT NOT NULL,
    CONSTRAINT UQ_LanGiaoHang UNIQUE (MaDonHang, SoLanThu),
    CONSTRAINT UQ_LanGiaoHang_MaLan_MaDon UNIQUE (MaLanGiaoHang, MaDonHang),
    CONSTRAINT CK_LanGiaoHang_No CHECK (SoLanThu > 0),
    CONSTRAINT CK_LanGiaoHang_KetQua CHECK (KetQua IN ('SUCCESS','FAILED')),
    CONSTRAINT CK_LanGiaoHang_Failure CHECK (
        (KetQua = 'SUCCESS' AND MaLyDoGiaoThatBai IS NULL) OR
        (KetQua = 'FAILED' AND MaLyDoGiaoThatBai IS NOT NULL)
    ),
    CONSTRAINT CK_LanGiaoHang_Retry CHECK (ThoiGianGiaoLaiDuKien IS NULL OR ThoiGianGiaoLaiDuKien >= ThoiGianThuGiao),
    CONSTRAINT FK_LanGiaoHang_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_LanGiaoHang_PhanCong_DonHang FOREIGN KEY (MaPhanCongGiaoHang, MaDonHang)
        REFERENCES dbo.PhanCongGiaoHang(MaPhanCongGiaoHang, MaDonHang),
    CONSTRAINT FK_LanGiaoHang_LyDoGiaoThatBai FOREIGN KEY (MaLyDoGiaoThatBai)
        REFERENCES dbo.LyDoGiaoThatBai(MaLyDoGiaoThatBai),
    CONSTRAINT FK_LanGiaoHang_TaiKhoan FOREIGN KEY (MaTaiKhoanGhiNhan)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE UNIQUE INDEX UX_LanGiaoHang_MotLanThanhCong
ON dbo.LanGiaoHang(MaDonHang)
WHERE KetQua = 'SUCCESS';
GO

CREATE TABLE dbo.BangChungGiaoHang (
    MaBangChung   BIGINT IDENTITY(1,1) CONSTRAINT PK_BangChungGiaoHang PRIMARY KEY,
    MaDonHang           BIGINT NOT NULL,
    MaLanGiaoHang BIGINT NOT NULL,
    LoaiBangChung         VARCHAR(30) NOT NULL,
    DuongDanTep           NVARCHAR(1000) NULL,
    MaXacNhanBam VARCHAR(255) NULL,
    TenNguoiNhan     NVARCHAR(150) NULL,
    ThoiGianGhiNhan        DATETIME2(0) NOT NULL CONSTRAINT DF_BangChungGiaoHang_ThoiGianGhiNhan DEFAULT SYSUTCDATETIME(),
    ViDo          DECIMAL(9,6) NULL,
    KinhDo         DECIMAL(10,6) NULL,
    MaTaiKhoanTaiLen  BIGINT NOT NULL,
    CONSTRAINT CK_BangChungGiaoHang_Loai CHECK (LoaiBangChung IN ('PHOTO','SIGNATURE','OTP','RECEIVER_CONFIRMATION')),
    CONSTRAINT CK_BangChungGiaoHang_NoiDung CHECK (
        (LoaiBangChung IN ('PHOTO','SIGNATURE') AND NULLIF(LTRIM(RTRIM(DuongDanTep)), N'') IS NOT NULL)
        OR (LoaiBangChung = 'OTP' AND NULLIF(LTRIM(RTRIM(MaXacNhanBam)), '') IS NOT NULL)
        OR (LoaiBangChung = 'RECEIVER_CONFIRMATION' AND NULLIF(LTRIM(RTRIM(TenNguoiNhan)), N'') IS NOT NULL)
    ),
    CONSTRAINT CK_BangChungGiaoHang_Lat CHECK (ViDo IS NULL OR ViDo BETWEEN -90 AND 90),
    CONSTRAINT CK_BangChungGiaoHang_Lng CHECK (KinhDo IS NULL OR KinhDo BETWEEN -180 AND 180),
    CONSTRAINT CK_BangChungGiaoHang_CapToaDo CHECK (
        (ViDo IS NULL AND KinhDo IS NULL) OR
        (ViDo IS NOT NULL AND KinhDo IS NOT NULL)
    ),
    CONSTRAINT FK_BangChungGiaoHang_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_BangChungGiaoHang_LanGiao_DonHang FOREIGN KEY (MaLanGiaoHang, MaDonHang)
        REFERENCES dbo.LanGiaoHang(MaLanGiaoHang, MaDonHang),
    CONSTRAINT FK_BangChungGiaoHang_TaiKhoan FOREIGN KEY (MaTaiKhoanTaiLen)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE TABLE dbo.YeuCauGiaoLaiHoacHoan (
    MaYeuCauGiaoLaiHoacHoan    BIGINT IDENTITY(1,1) CONSTRAINT PK_YeuCauGiaoLaiHoacHoan PRIMARY KEY,
    MaDonHang            BIGINT NOT NULL,
    LoaiYeuCau        VARCHAR(20) NOT NULL,
    TrangThaiYeuCau       VARCHAR(20) NOT NULL CONSTRAINT DF_YeuCauGiaoLaiHoacHoan_TrangThai DEFAULT ('PENDING'),
    MaBuuCucHoan     INT NULL,
    LyDo             NVARCHAR(500) NOT NULL,
    MaTaiKhoanYeuCau  BIGINT NOT NULL,
    ThoiGianYeuCau        DATETIME2(0) NOT NULL CONSTRAINT DF_YeuCauGiaoLaiHoacHoan_ThoiGianYeuCau DEFAULT SYSUTCDATETIME(),
    ThoiGianHoanTat        DATETIME2(0) NULL,
    CONSTRAINT CK_YeuCauGiaoLaiHoacHoan_Loai CHECK (LoaiYeuCau IN ('RETRY','RECALL','RETURN')),
    CONSTRAINT CK_YeuCauGiaoLaiHoacHoan_TrangThai CHECK (TrangThaiYeuCau IN ('PENDING','APPROVED','IN_PROGRESS','COMPLETED','CANCELLED')),
    CONSTRAINT CK_YeuCauGiaoLaiHoacHoan_ThoiGian CHECK (
        (ThoiGianHoanTat IS NULL OR ThoiGianHoanTat >= ThoiGianYeuCau)
        AND (TrangThaiYeuCau <> 'COMPLETED' OR ThoiGianHoanTat IS NOT NULL)
    ),
    CONSTRAINT CK_YeuCauGiaoLaiHoacHoan_BuuCucHoan CHECK (
        LoaiYeuCau <> 'RETURN' OR MaBuuCucHoan IS NOT NULL
    ),
    CONSTRAINT FK_YeuCauGiaoLaiHoacHoan_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_YeuCauGiaoLaiHoacHoan_BuuCuc FOREIGN KEY (MaBuuCucHoan)
        REFERENCES dbo.BuuCuc(MaBuuCuc),
    CONSTRAINT FK_YeuCauGiaoLaiHoacHoan_TaiKhoan FOREIGN KEY (MaTaiKhoanYeuCau)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE TABLE dbo.CanhBaoGiaoHang (
    MaCanhBao          BIGINT IDENTITY(1,1) CONSTRAINT PK_CanhBaoGiaoHang PRIMARY KEY,
    MaDonHang          BIGINT NULL,
    MaChuyenGiao           BIGINT NULL,
    LoaiCanhBao        VARCHAR(30) NOT NULL,
    MucDoCanhBao         VARCHAR(10) NOT NULL,
    NoiDungCanhBao          NVARCHAR(1000) NOT NULL,
    TrangThaiCanhBao      VARCHAR(20) NOT NULL CONSTRAINT DF_CanhBaoGiaoHang_TrangThai DEFAULT ('OPEN'),
    ThoiGianPhatHien       DATETIME2(0) NOT NULL CONSTRAINT DF_CanhBaoGiaoHang_ThoiGianPhatHien DEFAULT SYSUTCDATETIME(),
    ThoiGianXuLy       DATETIME2(0) NULL,
    MaTaiKhoanXuLy BIGINT NULL,
    CONSTRAINT CK_CanhBaoGiaoHang_Target CHECK (MaDonHang IS NOT NULL OR MaChuyenGiao IS NOT NULL),
    CONSTRAINT CK_CanhBaoGiaoHang_Loai CHECK (LoaiCanhBao IN ('LATE_RISK','OVERLOAD','OFF_ROUTE','NO_GPS','NO_SHIPPER','SYNC_ERROR','OTHER')),
    CONSTRAINT CK_CanhBaoGiaoHang_MucDoCanhBao CHECK (MucDoCanhBao IN ('INFO','WARNING','CRITICAL')),
    CONSTRAINT CK_CanhBaoGiaoHang_TrangThai CHECK (TrangThaiCanhBao IN ('OPEN','ACKNOWLEDGED','RESOLVED','IGNORED')),
    CONSTRAINT CK_CanhBaoGiaoHang_ThoiGian CHECK (ThoiGianXuLy IS NULL OR ThoiGianXuLy >= ThoiGianPhatHien),
    CONSTRAINT FK_CanhBaoGiaoHang_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_CanhBaoGiaoHang_ChuyenGiao FOREIGN KEY (MaChuyenGiao)
        REFERENCES dbo.ChuyenGiaoHang(MaChuyenGiao),
    CONSTRAINT FK_CanhBaoGiaoHang_ResolvedBy FOREIGN KEY (MaTaiKhoanXuLy)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

/* =============================================================================
   BƯỚC 10. COD - NỘP TIỀN - ĐỐI SOÁT
   Theo dõi thu COD, nộp tiền và đối soát.
   ============================================================================= */
CREATE TABLE dbo.ThuTienCOD (
    MaThuTienCOD   BIGINT IDENTITY(1,1) CONSTRAINT PK_ThuTienCOD PRIMARY KEY,
    MaDonHang           BIGINT NOT NULL,
    MaLanGiaoHang BIGINT NOT NULL,
    MaNhanVienGiaoHang         BIGINT NOT NULL,
    SoTienPhaiThu    DECIMAL(18,2) NOT NULL,
    SoTienThucThu   DECIMAL(18,2) NOT NULL,
    SoTienChenhLech  AS (SoTienThucThu - SoTienPhaiThu) PERSISTED,
    TrangThaiThuTien  VARCHAR(20) NOT NULL CONSTRAINT DF_ThuTienCOD_TrangThai DEFAULT ('COLLECTED'),
    ThoiGianThuTien       DATETIME2(0) NOT NULL CONSTRAINT DF_ThuTienCOD_ThoiGianThuTien DEFAULT SYSUTCDATETIME(),
    GhiChu              NVARCHAR(500) NULL,
    CONSTRAINT UQ_ThuTienCOD_DonHang UNIQUE (MaDonHang),
    CONSTRAINT CK_ThuTienCOD_SoTien CHECK (
        SoTienPhaiThu > 0
        AND SoTienThucThu >= 0
        AND SoTienThucThu <= SoTienPhaiThu
    ),
    CONSTRAINT CK_ThuTienCOD_TrangThai CHECK (TrangThaiThuTien IN ('COLLECTED','PARTIAL','WAIVED','REVERSED')),
    CONSTRAINT CK_ThuTienCOD_TrangThaiSoTien CHECK (
        (TrangThaiThuTien = 'COLLECTED' AND SoTienThucThu = SoTienPhaiThu)
        OR (TrangThaiThuTien = 'PARTIAL' AND SoTienThucThu < SoTienPhaiThu)
        OR (TrangThaiThuTien = 'WAIVED' AND SoTienThucThu = 0)
        OR TrangThaiThuTien = 'REVERSED'
    ),
    CONSTRAINT FK_ThuTienCOD_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_ThuTienCOD_LanGiao_DonHang FOREIGN KEY (MaLanGiaoHang, MaDonHang)
        REFERENCES dbo.LanGiaoHang(MaLanGiaoHang, MaDonHang),
    CONSTRAINT FK_ThuTienCOD_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang)
);
GO

CREATE INDEX IX_ThuTienCOD_NhanVienGiaoHang_ThoiGian
ON dbo.ThuTienCOD(MaNhanVienGiaoHang, ThoiGianThuTien DESC);
GO

CREATE TABLE dbo.NopTienCOD (
    MaNopTienCOD       BIGINT IDENTITY(1,1) CONSTRAINT PK_NopTienCOD PRIMARY KEY,
    KyHieuNopTien        VARCHAR(40) NOT NULL,
    MaNhanVienGiaoHang          BIGINT NOT NULL,
    MaBuuCuc           INT NOT NULL,
    SoTienNop    DECIMAL(18,2) NOT NULL,
    PhuongThucNop      VARCHAR(20) NOT NULL,
    TrangThaiNop      VARCHAR(20) NOT NULL CONSTRAINT DF_NopTienCOD_TrangThai DEFAULT ('PENDING'),
    ThoiGianNop        DATETIME2(0) NOT NULL CONSTRAINT DF_NopTienCOD_ThoiGianNop DEFAULT SYSUTCDATETIME(),
    ThoiGianXacNhan        DATETIME2(0) NULL,
    MaTaiKhoanXacNhan  BIGINT NULL,
    MaThamChieuNgoai  VARCHAR(100) NULL,
    GhiChu               NVARCHAR(500) NULL,
    CONSTRAINT UQ_NopTienCOD_KyHieu UNIQUE (KyHieuNopTien),
    CONSTRAINT CK_NopTienCOD_SoTien CHECK (SoTienNop > 0),
    CONSTRAINT CK_NopTienCOD_Method CHECK (PhuongThucNop IN ('CASH','BANK_TRANSFER','OTHER')),
    CONSTRAINT CK_NopTienCOD_TrangThai CHECK (TrangThaiNop IN ('PENDING','CONFIRMED','REJECTED','CANCELLED')),
    CONSTRAINT CK_NopTienCOD_ThoiGian CHECK (ThoiGianXacNhan IS NULL OR ThoiGianXacNhan >= ThoiGianNop),
    CONSTRAINT CK_NopTienCOD_XacNhan CHECK (
        TrangThaiNop <> 'CONFIRMED'
        OR (ThoiGianXacNhan IS NOT NULL AND MaTaiKhoanXacNhan IS NOT NULL)
    ),
    CONSTRAINT FK_NopTienCOD_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
    CONSTRAINT FK_NopTienCOD_BuuCuc FOREIGN KEY (MaBuuCuc)
        REFERENCES dbo.BuuCuc(MaBuuCuc),
    CONSTRAINT FK_NopTienCOD_ConfirmedBy FOREIGN KEY (MaTaiKhoanXacNhan)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE UNIQUE INDEX UX_NopTienCOD_MaThamChieuNgoai
ON dbo.NopTienCOD(MaThamChieuNgoai)
WHERE MaThamChieuNgoai IS NOT NULL;
GO

CREATE TABLE dbo.ChiTietNopTienCOD (
    MaNopTienCOD     BIGINT NOT NULL,
    MaDonHang          BIGINT NOT NULL,
    SoTienPhanBo  DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_ChiTietNopTienCOD PRIMARY KEY (MaNopTienCOD, MaDonHang),
    CONSTRAINT CK_ChiTietNopTienCOD_SoTien CHECK (SoTienPhanBo > 0),
    CONSTRAINT FK_ChiTietNopTienCOD_Deposit FOREIGN KEY (MaNopTienCOD)
        REFERENCES dbo.NopTienCOD(MaNopTienCOD),
    CONSTRAINT FK_ChiTietNopTienCOD_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang)
);
GO

CREATE TABLE dbo.DoiSoatCOD (
    MaDoiSoatCOD   BIGINT IDENTITY(1,1) CONSTRAINT PK_DoiSoatCOD PRIMARY KEY,
    KyHieuDoiSoat VARCHAR(40) NOT NULL,
    MaBuuCuc            INT NOT NULL,
    MaNhanVienGiaoHang           BIGINT NOT NULL,
    TuThoiGian          DATETIME2(0) NOT NULL,
    DenThoiGian            DATETIME2(0) NOT NULL,
    TongTienPhaiThu       DECIMAL(18,2) NOT NULL CONSTRAINT DF_Recon_Expected DEFAULT (0),
    TongTienDaThu      DECIMAL(18,2) NOT NULL CONSTRAINT DF_Recon_Collected DEFAULT (0),
    TongTienDaNop      DECIMAL(18,2) NOT NULL CONSTRAINT DF_Recon_Deposited DEFAULT (0),
    SoTienChenhLech    AS (TongTienDaNop - TongTienPhaiThu) PERSISTED,
    TrangThaiDoiSoat VARCHAR(20) NOT NULL CONSTRAINT DF_Recon_TrangThai DEFAULT ('DRAFT'),
    MaTaiKhoanXacNhan   BIGINT NULL,
    ThoiGianXacNhan         DATETIME2(0) NULL,
    ThoiGianKhoa            DATETIME2(0) NULL,
    GhiChu                NVARCHAR(1000) NULL,
    CONSTRAINT UQ_DoiSoatCOD_KyHieu UNIQUE (KyHieuDoiSoat),
    CONSTRAINT CK_Recon_Period CHECK (DenThoiGian > TuThoiGian),
    CONSTRAINT CK_Recon_Amounts CHECK (
        TongTienPhaiThu >= 0
        AND TongTienDaThu >= 0
        AND TongTienDaNop >= 0
        AND TongTienDaThu <= TongTienPhaiThu
    ),
    CONSTRAINT CK_Recon_TrangThai CHECK (TrangThaiDoiSoat IN ('DRAFT','REVIEW','CONFIRMED','DIFFERENCE','LOCKED','CANCELLED')),
    CONSTRAINT CK_Recon_XacNhan CHECK (
        TrangThaiDoiSoat NOT IN ('CONFIRMED','DIFFERENCE','LOCKED')
        OR (MaTaiKhoanXacNhan IS NOT NULL AND ThoiGianXacNhan IS NOT NULL)
    ),
    CONSTRAINT CK_Recon_Khoa CHECK (
        TrangThaiDoiSoat <> 'LOCKED' OR ThoiGianKhoa IS NOT NULL
    ),
    CONSTRAINT FK_Recon_BuuCuc FOREIGN KEY (MaBuuCuc)
        REFERENCES dbo.BuuCuc(MaBuuCuc),
    CONSTRAINT FK_Recon_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
    CONSTRAINT FK_Recon_ConfirmedBy FOREIGN KEY (MaTaiKhoanXacNhan)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE TABLE dbo.ChiTietDoiSoatCOD (
    MaDoiSoatCOD   BIGINT NOT NULL,
    MaDonHang             BIGINT NOT NULL,
    SoTienPhaiThu      DECIMAL(18,2) NOT NULL,
    SoTienDaThu     DECIMAL(18,2) NOT NULL,
    SoTienDaNop     DECIMAL(18,2) NOT NULL,
    SoTienChenhLech    AS (SoTienDaNop - SoTienPhaiThu) PERSISTED,
    TrangThaiKetQua        VARCHAR(20) NOT NULL,
    GhiChuXuLy      NVARCHAR(500) NULL,
    CONSTRAINT PK_ChiTietDoiSoatCOD PRIMARY KEY (MaDoiSoatCOD, MaDonHang),
    CONSTRAINT CK_ReconDetail_Amounts CHECK (
        SoTienPhaiThu >= 0
        AND SoTienDaThu >= 0
        AND SoTienDaNop >= 0
        AND SoTienDaThu <= SoTienPhaiThu
    ),
    CONSTRAINT CK_ReconDetail_TrangThai CHECK (TrangThaiKetQua IN ('MATCHED','SHORT','OVER','PENDING_RESOLUTION','RESOLVED')),
    CONSTRAINT FK_ReconDetail_Recon FOREIGN KEY (MaDoiSoatCOD)
        REFERENCES dbo.DoiSoatCOD(MaDoiSoatCOD),
    CONSTRAINT FK_ReconDetail_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang)
);
GO

/* =============================================================================
   BƯỚC 11. ĐÁNH GIÁ - KHIẾU NẠI
   Lưu đánh giá và quy trình xử lý khiếu nại.
   ============================================================================= */
CREATE TABLE dbo.DanhGia (
    MaDanhGia         BIGINT IDENTITY(1,1) CONSTRAINT PK_DanhGia PRIMARY KEY,
    MaDonHang          BIGINT NOT NULL,
    MaKhachHang       BIGINT NOT NULL,
    MaNhanVienGiaoHang        BIGINT NULL,
    SoSao            TINYINT NOT NULL,
    NhanXet          NVARCHAR(1000) NULL,
    ThoiGianTao        DATETIME2(0) NOT NULL CONSTRAINT DF_DanhGia_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    ThoiGianCapNhat        DATETIME2(0) NULL,
    CONSTRAINT UQ_DanhGia_DonHang UNIQUE (MaDonHang),
    CONSTRAINT CK_DanhGia_SoSao CHECK (SoSao BETWEEN 1 AND 5),
    CONSTRAINT CK_DanhGia_ThoiGian CHECK (ThoiGianCapNhat IS NULL OR ThoiGianCapNhat >= ThoiGianTao),
    CONSTRAINT FK_DanhGia_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_DanhGia_KhachHang FOREIGN KEY (MaKhachHang)
        REFERENCES dbo.KhachHang(MaKhachHang),
    CONSTRAINT FK_DanhGia_NhanVienGiaoHang FOREIGN KEY (MaNhanVienGiaoHang)
        REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang)
);
GO

CREATE TABLE dbo.KhieuNai (
    MaKhieuNai       BIGINT IDENTITY(1,1) CONSTRAINT PK_KhieuNai PRIMARY KEY,
    KyHieuKhieuNai     VARCHAR(40) NOT NULL,
    MaDonHang           BIGINT NOT NULL,
    MaKhachHang        BIGINT NULL,
    LoaiKhieuNai     VARCHAR(30) NOT NULL,
    TieuDe             NVARCHAR(200) NOT NULL,
    NoiDung           NVARCHAR(2000) NOT NULL,
    TrangThaiKhieuNai   VARCHAR(20) NOT NULL CONSTRAINT DF_KhieuNai_TrangThai DEFAULT ('OPEN'),
    MucDoUuTien          VARCHAR(10) NOT NULL CONSTRAINT DF_KhieuNai_MucDoUuTien DEFAULT ('NORMAL'),
    MaTaiKhoanXuLy  BIGINT NULL,
    KetQuaXuLy        NVARCHAR(2000) NULL,
    ThoiGianTao         DATETIME2(0) NOT NULL CONSTRAINT DF_KhieuNai_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    ThoiGianXuLy        DATETIME2(0) NULL,
    CONSTRAINT UQ_KhieuNai_KyHieu UNIQUE (KyHieuKhieuNai),
    CONSTRAINT CK_KhieuNai_Loai CHECK (LoaiKhieuNai IN ('LATE','LOST','DAMAGED','WRONG_RECIPIENT','COD','SERVICE_ATTITUDE','OTHER')),
    CONSTRAINT CK_KhieuNai_TrangThai CHECK (TrangThaiKhieuNai IN ('OPEN','IN_PROGRESS','WAITING_INFO','RESOLVED','REJECTED','CLOSED')),
    CONSTRAINT CK_KhieuNai_MucDoUuTien CHECK (MucDoUuTien IN ('LOW','NORMAL','HIGH','URGENT')),
    CONSTRAINT CK_KhieuNai_ThoiGian CHECK (ThoiGianXuLy IS NULL OR ThoiGianXuLy >= ThoiGianTao),
    CONSTRAINT CK_KhieuNai_KetThuc CHECK (
        TrangThaiKhieuNai NOT IN ('RESOLVED','REJECTED','CLOSED')
        OR (ThoiGianXuLy IS NOT NULL AND NULLIF(LTRIM(RTRIM(KetQuaXuLy)), N'') IS NOT NULL)
    ),
    CONSTRAINT FK_KhieuNai_DonHang FOREIGN KEY (MaDonHang)
        REFERENCES dbo.DonHang(MaDonHang),
    CONSTRAINT FK_KhieuNai_KhachHang FOREIGN KEY (MaKhachHang)
        REFERENCES dbo.KhachHang(MaKhachHang),
    CONSTRAINT FK_KhieuNai_Assignee FOREIGN KEY (MaTaiKhoanXuLy)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE TABLE dbo.LichSuKhieuNai (
    MaLichSuKhieuNai BIGINT IDENTITY(1,1) CONSTRAINT PK_LichSuKhieuNai PRIMARY KEY,
    MaKhieuNai       BIGINT NOT NULL,
    TrangThaiCu        VARCHAR(20) NULL,
    TrangThaiMoi          VARCHAR(20) NOT NULL,
    MaTaiKhoanThucHien    BIGINT NOT NULL,
    ThoiGianThucHien          DATETIME2(0) NOT NULL CONSTRAINT DF_LichSuKhieuNai_ThoiGianThucHien DEFAULT SYSUTCDATETIME(),
    GhiChu              NVARCHAR(1000) NULL,
    CONSTRAINT CK_LichSuKhieuNai_TrangThai CHECK (
        (TrangThaiCu IS NULL OR TrangThaiCu IN ('OPEN','IN_PROGRESS','WAITING_INFO','RESOLVED','REJECTED','CLOSED'))
        AND TrangThaiMoi IN ('OPEN','IN_PROGRESS','WAITING_INFO','RESOLVED','REJECTED','CLOSED')
        AND (TrangThaiCu IS NULL OR TrangThaiCu <> TrangThaiMoi)
    ),
    CONSTRAINT FK_LichSuKhieuNai_KhieuNai FOREIGN KEY (MaKhieuNai)
        REFERENCES dbo.KhieuNai(MaKhieuNai),
    CONSTRAINT FK_LichSuKhieuNai_TaiKhoan FOREIGN KEY (MaTaiKhoanThucHien)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

/* =============================================================================
   BƯỚC 12. THÔNG BÁO - NHẬT KÝ HỆ THỐNG
   Lưu thông báo và audit log.
   ============================================================================= */
CREATE TABLE dbo.ThongBao (
    MaThongBao   BIGINT IDENTITY(1,1) CONSTRAINT PK_ThongBao PRIMARY KEY,
    MaTaiKhoan           BIGINT NOT NULL,
    LoaiThongBao VARCHAR(30) NOT NULL,
    TieuDe            NVARCHAR(200) NOT NULL,
    NoiDung          NVARCHAR(1000) NOT NULL,
    LoaiDoiTuongThamChieu    VARCHAR(30) NULL,
    MaDoiTuongThamChieu      BIGINT NULL,
    DaDoc           BIT NOT NULL CONSTRAINT DF_ThongBao_DaDoc DEFAULT (0),
    ThoiGianTao        DATETIME2(0) NOT NULL CONSTRAINT DF_ThongBao_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    ThoiGianDoc           DATETIME2(0) NULL,
    CONSTRAINT CK_ThongBao_DaDoc CHECK (
        ((DaDoc = 0 AND ThoiGianDoc IS NULL) OR
         (DaDoc = 1 AND ThoiGianDoc IS NOT NULL))
        AND (ThoiGianDoc IS NULL OR ThoiGianDoc >= ThoiGianTao)
    ),
    CONSTRAINT FK_ThongBao_TaiKhoan FOREIGN KEY (MaTaiKhoan)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE INDEX IX_ThongBao_TaiKhoan_Unread
ON dbo.ThongBao(MaTaiKhoan, DaDoc, ThoiGianTao DESC);
GO

CREATE TABLE dbo.NhatKyHoatDong (
    MaNhatKy       BIGINT IDENTITY(1,1) CONSTRAINT PK_NhatKyHoatDong PRIMARY KEY,
    MaTaiKhoan           BIGINT NULL,
    LoaiThaoTac       VARCHAR(50) NOT NULL,
    TenDoiTuong       VARCHAR(100) NOT NULL,
    MaDoiTuong         VARCHAR(100) NULL,
    DuLieuCuJson      NVARCHAR(MAX) NULL,
    DuLieuMoiJson      NVARCHAR(MAX) NULL,
    DiaChiIP        VARCHAR(45) NULL,
    ThongTinThietBi        NVARCHAR(500) NULL,
    ThoiGianTao        DATETIME2(0) NOT NULL CONSTRAINT DF_NhatKyHoatDong_ThoiGianTao DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_NhatKyHoatDong_OldJson CHECK (DuLieuCuJson IS NULL OR ISJSON(DuLieuCuJson) = 1),
    CONSTRAINT CK_NhatKyHoatDong_NewJson CHECK (DuLieuMoiJson IS NULL OR ISJSON(DuLieuMoiJson) = 1),
    CONSTRAINT FK_NhatKyHoatDong_TaiKhoan FOREIGN KEY (MaTaiKhoan)
        REFERENCES dbo.TaiKhoan(MaTaiKhoan)
);
GO

CREATE INDEX IX_NhatKyHoatDong_DoiTuong_ThoiGian
ON dbo.NhatKyHoatDong(TenDoiTuong, MaDoiTuong, ThoiGianTao DESC);
GO

/* =============================================================================
   BƯỚC 13. DỮ LIỆU DANH MỤC BAN ĐẦU
   Nạp role, service, trạng thái, luồng trạng thái và lý do thất bại cần thiết.
   ============================================================================= */
INSERT INTO dbo.VaiTro(KyHieuVaiTro, TenVaiTro, MoTa)
SELECT v.KyHieuVaiTro, v.TenVaiTro, v.MoTa
FROM (VALUES
    ('ADMIN',             N'Quản trị viên',        N'Quản trị hệ thống và phân quyền'),
    ('BRANCH_MANAGER',    N'Quản lý bưu cục',     N'Quản lý vận hành bưu cục'),
    ('DISPATCHER',        N'Điều phối viên',       N'Gom đơn, phân công, giám sát giao hàng'),
    ('WAREHOUSE_STAFF',   N'Nhân viên kho',        N'Nhập kho, kiểm kê, xuất kho, bàn giao'),
    ('ACCOUNTANT',        N'Kế toán/Đối soát',     N'Quản lý COD và công nợ'),
    ('SHIPPER',           N'Nhân viên giao hàng',  N'Thực hiện giao hàng trên ứng dụng Mobile')
) v(KyHieuVaiTro, TenVaiTro, MoTa)
WHERE NOT EXISTS (SELECT 1 FROM dbo.VaiTro r WHERE r.KyHieuVaiTro = v.KyHieuVaiTro);
GO

INSERT INTO dbo.Quyen(KyHieuQuyen, TenQuyen, MoTa)
SELECT v.KyHieuQuyen, v.TenQuyen, v.MoTa
FROM (VALUES
    ('TAIKHOAN_XEM',              N'Xem tài khoản',                         N'Tra cứu danh sách và thông tin tài khoản'),
    ('TAIKHOAN_QUANLY',           N'Quản lý tài khoản',                    N'Tạo, sửa, khóa hoặc ngừng hoạt động tài khoản'),
    ('PHANQUYEN_QUANLY',          N'Quản lý phân quyền',                   N'Quản lý vai trò và quyền truy cập'),
    ('BUUCUC_QUANLY',             N'Quản lý bưu cục',                     N'Quản lý bưu cục và khu vực phục vụ'),
    ('KHO_XEM',                   N'Xem dữ liệu kho',                      N'Tra cứu hàng tồn và vị trí lưu kho'),
    ('KHO_NHAP',                  N'Nhập kho',                             N'Xác nhận hàng hóa nhập kho'),
    ('KHO_XUAT',                  N'Xuất kho và bàn giao',                 N'Xuất kho và bàn giao hàng cho nhân viên giao hàng'),
    ('KHO_KIEMKE',                N'Kiểm kê kho',                          N'Kiểm tra và cập nhật tình trạng hàng tồn'),
    ('DONHANG_XEM',               N'Xem đơn hàng',                         N'Tra cứu thông tin và lịch sử đơn hàng'),
    ('DONHANG_TAO',               N'Tạo đơn hàng',                         N'Tạo mới đơn giao hàng'),
    ('DONHANG_CAPNHAT',           N'Cập nhật đơn hàng',                    N'Cập nhật thông tin đơn hàng theo quyền'),
    ('DONHANG_HUY',               N'Hủy đơn hàng',                         N'Thực hiện hoặc phê duyệt hủy đơn theo quy trình'),
    ('DIEUPHOI_GOMDON',           N'Gom nhóm đơn hàng',                    N'Gom các đơn đủ điều kiện thành chuyến giao'),
    ('DIEUPHOI_PHANCONG',         N'Phân công nhân viên giao hàng',        N'Phân công, đổi người giao hoặc tái điều phối'),
    ('DIEUPHOI_TOIUUTUYEN',       N'Tối ưu tuyến giao',                    N'Tạo và điều chỉnh tuyến giao hàng'),
    ('DIEUPHOI_GIAMSAT',          N'Giám sát giao hàng',                   N'Theo dõi chuyến, trạng thái và cảnh báo'),
    ('NHIEMVU_XEM',               N'Xem nhiệm vụ giao hàng',               N'Nhân viên giao hàng xem chuyến và đơn được phân công'),
    ('NHIEMVU_CAPNHAT',           N'Cập nhật tiến độ giao hàng',           N'Xác nhận nhận hàng và cập nhật trạng thái giao'),
    ('BANGCHUNG_TAO',             N'Gửi bằng chứng giao hàng',             N'Tải ảnh, chữ ký hoặc xác nhận giao hàng'),
    ('COD_THUTIEN',               N'Ghi nhận thu tiền COD',                N'Ghi nhận tiền COD thực thu theo đơn'),
    ('COD_NOPTIEN',               N'Nộp tiền COD',                         N'Ghi nhận giao dịch nộp tiền COD'),
    ('COD_DOISOAT',               N'Đối soát COD',                         N'Đối chiếu COD và quản lý công nợ'),
    ('KHIEUNAI_XEM',              N'Xem khiếu nại',                        N'Tra cứu khiếu nại và dữ liệu tra soát'),
    ('KHIEUNAI_XULY',             N'Xử lý khiếu nại',                      N'Cập nhật trạng thái và kết quả giải quyết khiếu nại'),
    ('BAOCAO_XEM',                N'Xem báo cáo thống kê',                 N'Xem các chỉ số vận hành, doanh thu, COD và hiệu suất'),
    ('NHATKY_XEM',                N'Xem nhật ký hoạt động',                N'Tra cứu lịch sử thao tác phục vụ kiểm tra'),
    ('BANGGIA_QUANLY',            N'Quản lý cấu hình phí',                 N'Thiết lập quy tắc tính phí vận chuyển')
) v(KyHieuQuyen, TenQuyen, MoTa)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Quyen q WHERE q.KyHieuQuyen = v.KyHieuQuyen
);
GO

;WITH PQ(KyHieuVaiTro, KyHieuQuyen) AS (
    SELECT * FROM (VALUES
        ('ADMIN','TAIKHOAN_XEM'),('ADMIN','TAIKHOAN_QUANLY'),('ADMIN','PHANQUYEN_QUANLY'),
        ('ADMIN','BUUCUC_QUANLY'),('ADMIN','KHO_XEM'),('ADMIN','KHO_NHAP'),('ADMIN','KHO_XUAT'),('ADMIN','KHO_KIEMKE'),
        ('ADMIN','DONHANG_XEM'),('ADMIN','DONHANG_TAO'),('ADMIN','DONHANG_CAPNHAT'),('ADMIN','DONHANG_HUY'),
        ('ADMIN','DIEUPHOI_GOMDON'),('ADMIN','DIEUPHOI_PHANCONG'),('ADMIN','DIEUPHOI_TOIUUTUYEN'),('ADMIN','DIEUPHOI_GIAMSAT'),
        ('ADMIN','COD_DOISOAT'),('ADMIN','KHIEUNAI_XEM'),('ADMIN','KHIEUNAI_XULY'),('ADMIN','BAOCAO_XEM'),
        ('ADMIN','NHATKY_XEM'),('ADMIN','BANGGIA_QUANLY'),

        ('BRANCH_MANAGER','TAIKHOAN_XEM'),('BRANCH_MANAGER','BUUCUC_QUANLY'),
        ('BRANCH_MANAGER','KHO_XEM'),('BRANCH_MANAGER','KHO_NHAP'),('BRANCH_MANAGER','KHO_XUAT'),('BRANCH_MANAGER','KHO_KIEMKE'),
        ('BRANCH_MANAGER','DONHANG_XEM'),('BRANCH_MANAGER','DONHANG_CAPNHAT'),('BRANCH_MANAGER','DONHANG_HUY'),
        ('BRANCH_MANAGER','DIEUPHOI_GIAMSAT'),('BRANCH_MANAGER','COD_DOISOAT'),
        ('BRANCH_MANAGER','KHIEUNAI_XEM'),('BRANCH_MANAGER','KHIEUNAI_XULY'),('BRANCH_MANAGER','BAOCAO_XEM'),

        ('DISPATCHER','KHO_XEM'),('DISPATCHER','KHO_NHAP'),('DISPATCHER','KHO_XUAT'),
        ('DISPATCHER','DONHANG_XEM'),('DISPATCHER','DONHANG_TAO'),('DISPATCHER','DONHANG_CAPNHAT'),
        ('DISPATCHER','DIEUPHOI_GOMDON'),('DISPATCHER','DIEUPHOI_PHANCONG'),
        ('DISPATCHER','DIEUPHOI_TOIUUTUYEN'),('DISPATCHER','DIEUPHOI_GIAMSAT'),
        ('DISPATCHER','KHIEUNAI_XEM'),

        ('WAREHOUSE_STAFF','KHO_XEM'),('WAREHOUSE_STAFF','KHO_NHAP'),
        ('WAREHOUSE_STAFF','KHO_XUAT'),('WAREHOUSE_STAFF','KHO_KIEMKE'),('WAREHOUSE_STAFF','DONHANG_XEM'),

        ('ACCOUNTANT','DONHANG_XEM'),('ACCOUNTANT','COD_DOISOAT'),
        ('ACCOUNTANT','BAOCAO_XEM'),('ACCOUNTANT','KHIEUNAI_XEM'),

        ('SHIPPER','NHIEMVU_XEM'),('SHIPPER','NHIEMVU_CAPNHAT'),
        ('SHIPPER','BANGCHUNG_TAO'),('SHIPPER','COD_THUTIEN'),('SHIPPER','COD_NOPTIEN')
    ) x(KyHieuVaiTro, KyHieuQuyen)
)
INSERT INTO dbo.VaiTroQuyen(MaVaiTro, MaQuyen)
SELECT vt.MaVaiTro, q.MaQuyen
FROM PQ
JOIN dbo.VaiTro vt ON vt.KyHieuVaiTro = PQ.KyHieuVaiTro
JOIN dbo.Quyen q ON q.KyHieuQuyen = PQ.KyHieuQuyen
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.VaiTroQuyen vq
    WHERE vq.MaVaiTro = vt.MaVaiTro
      AND vq.MaQuyen = q.MaQuyen
);
GO

INSERT INTO dbo.LoaiDichVu(KyHieuDichVu, TenDichVu, MoTa)
SELECT v.KyHieuDichVu, v.TenDichVu, v.MoTa
FROM (VALUES
    ('STANDARD', N'Giao tiêu chuẩn', N'Dịch vụ giao hàng tiêu chuẩn'),
    ('EXPRESS',  N'Giao nhanh',      N'Dịch vụ giao hàng ưu tiên')
) v(KyHieuDichVu, TenDichVu, MoTa)
WHERE NOT EXISTS (SELECT 1 FROM dbo.LoaiDichVu s WHERE s.KyHieuDichVu = v.KyHieuDichVu);
GO

INSERT INTO dbo.LyDoGiaoThatBai(KyHieuLyDo, TenLyDo, BatBuocMinhChung)
SELECT v.KyHieuLyDo, v.TenLyDo, v.BatBuocMinhChung
FROM (VALUES
    ('NO_ANSWER',       N'Không liên lạc được người nhận', 0),
    ('RECIPIENT_ABSENT',N'Người nhận vắng mặt',            0),
    ('WRONG_ADDRESS',   N'Sai địa chỉ',                    1),
    ('RECIPIENT_REFUSED',N'Người nhận từ chối nhận',       0),
    ('DAMAGED',         N'Hàng hóa hư hỏng',               1),
    ('OTHER',           N'Nguyên nhân khác',               0)
) v(KyHieuLyDo, TenLyDo, BatBuocMinhChung)
WHERE NOT EXISTS (SELECT 1 FROM dbo.LyDoGiaoThatBai f WHERE f.KyHieuLyDo = v.KyHieuLyDo);
GO

INSERT INTO dbo.TrangThaiDonHang(KyHieuTrangThai, TenTrangThai, LaTrangThaiKetThuc, ThuTuSapXep)
SELECT v.KyHieuTrangThai, v.TenTrangThai, v.LaTrangThaiKetThuc, v.ThuTuSapXep
FROM (VALUES
    ('NEW',               N'Mới tạo',                    0,  10),
    ('CONFIRMED',         N'Đã tiếp nhận',               0,  20),
    ('WAITING_INBOUND',   N'Chờ nhập kho',               0,  30),
    ('IN_WAREHOUSE',      N'Đã nhập kho',                0,  40),
    ('WAITING_ASSIGNMENT',N'Chờ phân công',              0,  50),
    ('ASSIGNED',          N'Đã phân công',               0,  60),
    ('HANDED_OVER',       N'Đã xuất kho/Bàn giao',       0,  70),
    ('EN_ROUTE_PICKUP',   N'Đang đến lấy hàng',          0,  80),
    ('PICKED_UP',         N'Đã lấy hàng',                0,  90),
    ('IN_DELIVERY',       N'Đang giao',                  0, 100),
    ('DELIVERED',         N'Giao thành công',            0, 110),
    ('FAILED',            N'Giao thất bại',              0, 120),
    ('RETRY_WAITING',     N'Chờ giao lại',               0, 130),
    ('RETURNING',         N'Chuyển hoàn',                0, 140),
    ('RETURNED',          N'Đã hoàn hàng',               0, 150),
    ('COMPLETED',         N'Hoàn tất',                   1, 160),
    ('CANCELLED',         N'Đã hủy',                     1, 170)
) v(KyHieuTrangThai, TenTrangThai, LaTrangThaiKetThuc, ThuTuSapXep)
WHERE NOT EXISTS (SELECT 1 FROM dbo.TrangThaiDonHang s WHERE s.KyHieuTrangThai = v.KyHieuTrangThai);
GO

;WITH T(KyHieuTrangThaiCu, KyHieuTrangThaiMoi, BatBuocLyDo) AS (
    SELECT * FROM (VALUES
        ('NEW','CONFIRMED',0),
        ('NEW','CANCELLED',1),
        ('CONFIRMED','WAITING_INBOUND',0),
        ('CONFIRMED','WAITING_ASSIGNMENT',0),
        ('CONFIRMED','CANCELLED',1),
        ('WAITING_INBOUND','IN_WAREHOUSE',0),
        ('WAITING_INBOUND','CANCELLED',1),
        ('IN_WAREHOUSE','WAITING_ASSIGNMENT',0),
        ('IN_WAREHOUSE','CANCELLED',1),
        ('WAITING_ASSIGNMENT','ASSIGNED',0),
        ('WAITING_ASSIGNMENT','CANCELLED',1),
        ('ASSIGNED','HANDED_OVER',0),
        ('ASSIGNED','WAITING_ASSIGNMENT',1),
        ('ASSIGNED','CANCELLED',1),
        ('HANDED_OVER','EN_ROUTE_PICKUP',0),
        ('HANDED_OVER','PICKED_UP',0),
        ('EN_ROUTE_PICKUP','PICKED_UP',0),
        ('PICKED_UP','IN_DELIVERY',0),
        ('IN_DELIVERY','DELIVERED',0),
        ('IN_DELIVERY','FAILED',1),
        ('FAILED','RETRY_WAITING',1),
        ('FAILED','RETURNING',1),
        ('RETRY_WAITING','ASSIGNED',0),
        ('RETRY_WAITING','IN_DELIVERY',0),
        ('RETRY_WAITING','RETURNING',1),
        ('RETURNING','RETURNED',0),
        ('RETURNED','COMPLETED',0),
        ('DELIVERED','COMPLETED',0)
    ) x(KyHieuTrangThaiCu, KyHieuTrangThaiMoi, BatBuocLyDo)
)
INSERT INTO dbo.ChuyenTrangThaiDonHang(MaTrangThaiCu, MaTrangThaiMoi, BatBuocLyDo)
SELECT f.MaTrangThaiDonHang, t2.MaTrangThaiDonHang, T.BatBuocLyDo
FROM T
JOIN dbo.TrangThaiDonHang f  ON f.KyHieuTrangThai = T.KyHieuTrangThaiCu
JOIN dbo.TrangThaiDonHang t2 ON t2.KyHieuTrangThai = T.KyHieuTrangThaiMoi
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.ChuyenTrangThaiDonHang z
    WHERE z.MaTrangThaiCu = f.MaTrangThaiDonHang
      AND z.MaTrangThaiMoi = t2.MaTrangThaiDonHang
);
GO

/* =============================================================================
   BƯỚC 14. TRIGGER ĐỒNG BỘ TỌA ĐỘ
   Đồng bộ ViDo/KinhDo sang GEOGRAPHY.
   ============================================================================= */
CREATE OR ALTER TRIGGER dbo.TR_BuuCuc_DongBoToaDoDiaLy
ON dbo.BuuCuc
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(ViDo) OR UPDATE(KinhDo)) RETURN;

    UPDATE b
    SET ToaDoDiaLy = CASE
        WHEN i.ViDo IS NOT NULL AND i.KinhDo IS NOT NULL
        THEN geography::Point(CONVERT(float, i.ViDo), CONVERT(float, i.KinhDo), 4326)
        ELSE NULL END
    FROM dbo.BuuCuc b
    JOIN inserted i ON i.MaBuuCuc = b.MaBuuCuc;
END;
GO

CREATE OR ALTER TRIGGER dbo.TR_DiaChiKhachHang_DongBoToaDoDiaLy
ON dbo.DiaChiKhachHang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(ViDo) OR UPDATE(KinhDo)) RETURN;

    UPDATE d
    SET ToaDoDiaLy = CASE
        WHEN i.ViDo IS NOT NULL AND i.KinhDo IS NOT NULL
        THEN geography::Point(CONVERT(float, i.ViDo), CONVERT(float, i.KinhDo), 4326)
        ELSE NULL END
    FROM dbo.DiaChiKhachHang d
    JOIN inserted i ON i.MaDiaChiKhachHang = d.MaDiaChiKhachHang;
END;
GO

CREATE OR ALTER TRIGGER dbo.TR_NhanVienGiaoHang_DongBoToaDoHienTai
ON dbo.NhanVienGiaoHang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(ViDoHienTai) OR UPDATE(KinhDoHienTai)) RETURN;

    UPDATE nv
    SET ToaDoHienTai = CASE
        WHEN i.ViDoHienTai IS NOT NULL AND i.KinhDoHienTai IS NOT NULL
        THEN geography::Point(CONVERT(float, i.ViDoHienTai), CONVERT(float, i.KinhDoHienTai), 4326)
        ELSE NULL END
    FROM dbo.NhanVienGiaoHang nv
    JOIN inserted i ON i.MaNhanVienGiaoHang = nv.MaNhanVienGiaoHang;
END;
GO

CREATE OR ALTER TRIGGER dbo.TR_DiemGiaoNhan_DongBoToaDoDiaLy
ON dbo.DiemGiaoNhan
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(ViDo) OR UPDATE(KinhDo)) RETURN;

    UPDATE d
    SET ToaDoDiaLy = CASE
        WHEN i.ViDo IS NOT NULL AND i.KinhDo IS NOT NULL
        THEN geography::Point(CONVERT(float, i.ViDo), CONVERT(float, i.KinhDo), 4326)
        ELSE NULL END
    FROM dbo.DiemGiaoNhan d
    JOIN inserted i ON i.MaDiemGiaoNhan = d.MaDiemGiaoNhan;
END;
GO

CREATE OR ALTER TRIGGER dbo.TR_DiemDungTuyen_DongBoToaDoDiaLy
ON dbo.DiemDungTuyen
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT (UPDATE(ViDo) OR UPDATE(KinhDo)) RETURN;

    UPDATE d
    SET ToaDoDiaLy = CASE
        WHEN i.ViDo IS NOT NULL AND i.KinhDo IS NOT NULL
        THEN geography::Point(CONVERT(float, i.ViDo), CONVERT(float, i.KinhDo), 4326)
        ELSE NULL END
    FROM dbo.DiemDungTuyen d
    JOIN inserted i ON i.MaDiemDung = d.MaDiemDung;
END;
GO

CREATE SPATIAL INDEX SIX_BuuCuc_ToaDoDiaLy ON dbo.BuuCuc(ToaDoDiaLy);
GO
CREATE SPATIAL INDEX SIX_NhanVienGiaoHang_ToaDoHienTai ON dbo.NhanVienGiaoHang(ToaDoHienTai);
GO
CREATE SPATIAL INDEX SIX_DiemGiaoNhan_ToaDoDiaLy ON dbo.DiemGiaoNhan(ToaDoDiaLy);
GO

/* =============================================================================
   BƯỚC 15. TRIGGER VÒNG ĐỜI ĐƠN
   Chặn chuyển trạng thái sai và tự ghi lịch sử trạng thái.
   ============================================================================= */
CREATE OR ALTER TRIGGER dbo.TR_DonHang_KiemTraToanVenTrangThai
ON dbo.DonHang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LyDoTrangThai NVARCHAR(500) =
        NULLIF(LTRIM(RTRIM(TRY_CONVERT(NVARCHAR(500), SESSION_CONTEXT(N'LyDoTrangThai')))), N'');

    DECLARE @NguonCapNhat VARCHAR(20) =
        UPPER(COALESCE(TRY_CONVERT(VARCHAR(20), SESSION_CONTEXT(N'NguonCapNhat')), 'SYSTEM'));

    IF @NguonCapNhat NOT IN ('WEB','MOBILE','SYSTEM','API')
        SET @NguonCapNhat = 'SYSTEM';

    IF EXISTS (
        SELECT 1
        FROM inserted i
        LEFT JOIN deleted d ON d.MaDonHang=i.MaDonHang
        JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang = i.MaTrangThaiHienTai
        WHERE d.MaDonHang IS NULL
          AND tt.KyHieuTrangThai <> 'NEW'
    )
    BEGIN
        ;THROW 51000, N'Đơn hàng mới tạo bắt buộc phải ở trạng thái NEW.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.MaDonHang=i.MaDonHang
        WHERE i.MaTrangThaiHienTai<>d.MaTrangThaiHienTai
          AND NOT EXISTS (
              SELECT 1
              FROM dbo.ChuyenTrangThaiDonHang t
              WHERE t.MaTrangThaiCu=d.MaTrangThaiHienTai
                AND t.MaTrangThaiMoi=i.MaTrangThaiHienTai
          )
    )
    BEGIN
        ;THROW 51001, N'Chuyển trạng thái đơn hàng không hợp lệ theo vòng đời nghiệp vụ.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.MaDonHang=i.MaDonHang
        JOIN dbo.ChuyenTrangThaiDonHang t
          ON t.MaTrangThaiCu=d.MaTrangThaiHienTai
         AND t.MaTrangThaiMoi=i.MaTrangThaiHienTai
        WHERE i.MaTrangThaiHienTai<>d.MaTrangThaiHienTai
          AND t.BatBuocLyDo=1
          AND @LyDoTrangThai IS NULL
    )
    BEGIN
        ;THROW 51006, N'Chuyển trạng thái này bắt buộc phải có lý do.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.MaDonHang=i.MaDonHang
        JOIN dbo.TrangThaiDonHang ns ON ns.MaTrangThaiDonHang=i.MaTrangThaiHienTai
        WHERE i.MaTrangThaiHienTai<>d.MaTrangThaiHienTai
          AND ns.KyHieuTrangThai<>'CANCELLED'
          AND (
              (SELECT COUNT(*) FROM dbo.DiemGiaoNhan s WHERE s.MaDonHang=i.MaDonHang AND s.LoaiDiem='PICKUP')<>1
              OR (SELECT COUNT(*) FROM dbo.DiemGiaoNhan s WHERE s.MaDonHang=i.MaDonHang AND s.LoaiDiem='DELIVERY')<>1
              OR NOT EXISTS (SELECT 1 FROM dbo.ChiTietDonHang ct WHERE ct.MaDonHang=i.MaDonHang)
          )
    )
    BEGIN
        ;THROW 51002, N'Đơn hàng phải có đúng 1 điểm lấy, 1 điểm giao và ít nhất 1 chi tiết hàng hóa.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.MaDonHang=i.MaDonHang
        JOIN dbo.TrangThaiDonHang ns ON ns.MaTrangThaiDonHang=i.MaTrangThaiHienTai
        WHERE i.MaTrangThaiHienTai<>d.MaTrangThaiHienTai
          AND ns.KyHieuTrangThai='DELIVERED'
          AND NOT EXISTS (
              SELECT 1
              FROM dbo.LanGiaoHang lg
              JOIN dbo.BangChungGiaoHang bc
                ON bc.MaLanGiaoHang=lg.MaLanGiaoHang
               AND bc.MaDonHang=lg.MaDonHang
              WHERE lg.MaDonHang=i.MaDonHang
                AND lg.KetQua='SUCCESS'
          )
    )
    BEGIN
        ;THROW 51003, N'Đơn giao thành công phải có lần giao SUCCESS và bằng chứng tương ứng.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.MaDonHang=i.MaDonHang
        JOIN dbo.TrangThaiDonHang ns ON ns.MaTrangThaiDonHang=i.MaTrangThaiHienTai
        WHERE i.MaTrangThaiHienTai<>d.MaTrangThaiHienTai
          AND ns.KyHieuTrangThai='DELIVERED'
          AND i.TienCOD>0
          AND NOT EXISTS (
              SELECT 1
              FROM dbo.ThuTienCOD c
              JOIN dbo.LanGiaoHang lg
                ON lg.MaLanGiaoHang=c.MaLanGiaoHang
               AND lg.MaDonHang=c.MaDonHang
              JOIN dbo.PhanCongGiaoHang pc
                ON pc.MaPhanCongGiaoHang=lg.MaPhanCongGiaoHang
               AND pc.MaDonHang=lg.MaDonHang
              WHERE c.MaDonHang=i.MaDonHang
                AND lg.KetQua='SUCCESS'
                AND c.MaNhanVienGiaoHang=pc.MaNhanVienGiaoHang
                AND c.TrangThaiThuTien='COLLECTED'
                AND c.SoTienPhaiThu=i.TienCOD
                AND c.SoTienThucThu=i.TienCOD
          )
    )
    BEGIN
        ;THROW 51004, N'Đơn có COD phải ghi nhận tiền thực thu gắn với lần giao SUCCESS.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.MaDonHang=i.MaDonHang
        JOIN dbo.TrangThaiDonHang ns ON ns.MaTrangThaiDonHang=i.MaTrangThaiHienTai
        WHERE i.MaTrangThaiHienTai<>d.MaTrangThaiHienTai
          AND ns.KyHieuTrangThai='ASSIGNED'
          AND (SELECT COUNT(*) FROM dbo.PhanCongGiaoHang a
               WHERE a.MaDonHang=i.MaDonHang AND a.ThoiGianKetThuc IS NULL)<>1
    )
    BEGIN
        ;THROW 51005, N'Đơn ở trạng thái Đã phân công phải có đúng một phân công hiện hành.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.MaDonHang=i.MaDonHang
        JOIN dbo.TrangThaiDonHang ns ON ns.MaTrangThaiDonHang=i.MaTrangThaiHienTai
        WHERE i.MaTrangThaiHienTai<>d.MaTrangThaiHienTai
          AND ns.KyHieuTrangThai='IN_DELIVERY'
          AND (
              SELECT COUNT(*)
              FROM dbo.PhanCongGiaoHang a
              WHERE a.MaDonHang=i.MaDonHang
                AND a.ThoiGianKetThuc IS NULL
                AND a.TrangThaiPhanCong IN ('ACCEPTED','IN_PROGRESS')
          )<>1
    )
    BEGIN
        ;THROW 51055, N'Đơn đang giao phải có đúng một phân công hiện hành ở trạng thái ACCEPTED hoặc IN_PROGRESS.', 1;
    END;

    INSERT INTO dbo.LichSuTrangThaiDonHang
        (MaDonHang,MaTrangThaiCu,MaTrangThaiMoi,MaTaiKhoanThayDoi,ThoiGianThayDoi,LyDo,NguonCapNhat)
    SELECT
        i.MaDonHang,
        d.MaTrangThaiHienTai,
        i.MaTrangThaiHienTai,
        COALESCE(i.MaTaiKhoanCapNhatCuoi,i.MaTaiKhoanTao),
        SYSUTCDATETIME(),
        CASE WHEN d.MaDonHang IS NULL THEN NULL ELSE @LyDoTrangThai END,
        CASE WHEN d.MaDonHang IS NULL THEN 'SYSTEM' ELSE @NguonCapNhat END
    FROM inserted i
    LEFT JOIN deleted d ON d.MaDonHang=i.MaDonHang
    WHERE d.MaDonHang IS NULL
       OR i.MaTrangThaiHienTai<>d.MaTrangThaiHienTai;
END;
GO

/* =============================================================================
   BƯỚC 16. TRIGGER ĐÁNH GIÁ
   Chỉ cho đánh giá đúng đơn, đúng khách hàng và shipper.
   ============================================================================= */
CREATE OR ALTER TRIGGER dbo.TR_DanhGia_ChiDonDaHoanTat
ON dbo.DanhGia
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted r
        JOIN dbo.DonHang d ON d.MaDonHang = r.MaDonHang
        JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
        WHERE tt.KyHieuTrangThai NOT IN ('DELIVERED','COMPLETED')
           OR r.MaKhachHang NOT IN (d.MaNguoiGui, d.MaNguoiNhan)
           OR (
                r.MaNhanVienGiaoHang IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM dbo.LanGiaoHang lg
                    JOIN dbo.PhanCongGiaoHang pc ON pc.MaPhanCongGiaoHang = lg.MaPhanCongGiaoHang
                    WHERE lg.MaDonHang = r.MaDonHang
                      AND lg.KetQua = 'SUCCESS'
                      AND pc.MaNhanVienGiaoHang = r.MaNhanVienGiaoHang
                )
           )
    )
    BEGIN
        ;THROW 51020, N'Đánh giá chỉ hợp lệ cho đơn đã giao; khách hàng và nhân viên giao hàng phải thuộc đúng đơn.', 1;
    END;
END;
GO

/* =============================================================================
   BƯỚC 17. TRIGGER NĂNG LỰC CHUYẾN GIAO
   Kiểm tra tải trọng và thể tích phương tiện.
   ============================================================================= */
CREATE OR ALTER TRIGGER dbo.TR_ChiTietChuyenGiao_KiemTraTaiTrong
ON dbo.ChiTietChuyenGiao
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra tổng khối lượng của chuyến.
    IF EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT MaChuyenGiao FROM inserted) x
        JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao = x.MaChuyenGiao
        JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = cg.MaPhuongTien
        CROSS APPLY (
            SELECT SUM(dh.TongKhoiLuongKg) AS TongKhoiLuong
            FROM dbo.ChiTietChuyenGiao ct
            JOIN dbo.DonHang dh ON dh.MaDonHang = ct.MaDonHang
            WHERE ct.MaChuyenGiao = cg.MaChuyenGiao
        ) w
        WHERE w.TongKhoiLuong > pt.KhoiLuongDenKg
    )
    BEGIN
        ;THROW 51030, N'Tổng tải trọng đơn hàng trong chuyến vượt quá tải trọng cho phép của phương tiện.', 1;
    END;

    -- Nếu xe có giới hạn thể tích, kiểm tra đủ kích thước và tổng thể tích hàng.
    IF EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT MaChuyenGiao FROM inserted) x
        JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao = x.MaChuyenGiao
        JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = cg.MaPhuongTien
        WHERE pt.TheTichToiDaM3 IS NOT NULL
          AND EXISTS (
              SELECT 1
              FROM dbo.ChiTietChuyenGiao ct
              JOIN dbo.ChiTietDonHang dhct ON dhct.MaDonHang = ct.MaDonHang
              WHERE ct.MaChuyenGiao = cg.MaChuyenGiao
                AND (dhct.ChieuDaiCm IS NULL OR dhct.ChieuRongCm IS NULL OR dhct.ChieuCaoCm IS NULL)
          )
    )
    BEGIN
        ;THROW 51032, N'Phải có đầy đủ kích thước hàng hóa để kiểm tra giới hạn thể tích phương tiện.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT MaChuyenGiao FROM inserted) x
        JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao = x.MaChuyenGiao
        JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = cg.MaPhuongTien
        CROSS APPLY (
            SELECT SUM(
                CAST(cth.SoLuong AS DECIMAL(18,6))
                * cth.ChieuDaiCm * cth.ChieuRongCm * cth.ChieuCaoCm / 1000000.0
            ) AS TongTheTichM3
            FROM dbo.ChiTietChuyenGiao ct
            JOIN dbo.ChiTietDonHang cth ON cth.MaDonHang = ct.MaDonHang
            WHERE ct.MaChuyenGiao = cg.MaChuyenGiao
        ) v
        WHERE pt.TheTichToiDaM3 IS NOT NULL
          AND ISNULL(v.TongTheTichM3,0) > pt.TheTichToiDaM3
    )
    BEGIN
        ;THROW 51033, N'Tổng thể tích hàng hóa trong chuyến vượt quá thể tích cho phép của phương tiện.', 1;
    END;
END;
GO

CREATE OR ALTER TRIGGER dbo.TR_ChuyenGiaoHang_KiemTraTaiTrong
ON dbo.ChuyenGiaoHang
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(MaPhuongTien) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = i.MaPhuongTien
        CROSS APPLY (
            SELECT ISNULL(SUM(dh.TongKhoiLuongKg),0) AS TongKhoiLuong
            FROM dbo.ChiTietChuyenGiao ct
            JOIN dbo.DonHang dh ON dh.MaDonHang = ct.MaDonHang
            WHERE ct.MaChuyenGiao = i.MaChuyenGiao
        ) w
        WHERE w.TongKhoiLuong > pt.KhoiLuongDenKg
    )
    BEGIN
        ;THROW 51031, N'Phương tiện mới không đủ tải trọng cho chuyến.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = i.MaPhuongTien
        WHERE pt.TheTichToiDaM3 IS NOT NULL
          AND EXISTS (
              SELECT 1
              FROM dbo.ChiTietChuyenGiao ct
              JOIN dbo.ChiTietDonHang cth ON cth.MaDonHang = ct.MaDonHang
              WHERE ct.MaChuyenGiao = i.MaChuyenGiao
                AND (cth.ChieuDaiCm IS NULL OR cth.ChieuRongCm IS NULL OR cth.ChieuCaoCm IS NULL)
          )
    )
    BEGIN
        ;THROW 51034, N'Không thể kiểm tra thể tích vì có kiện hàng thiếu kích thước.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = i.MaPhuongTien
        CROSS APPLY (
            SELECT SUM(
                CAST(cth.SoLuong AS DECIMAL(18,6))
                * cth.ChieuDaiCm * cth.ChieuRongCm * cth.ChieuCaoCm / 1000000.0
            ) AS TongTheTichM3
            FROM dbo.ChiTietChuyenGiao ct
            JOIN dbo.ChiTietDonHang cth ON cth.MaDonHang = ct.MaDonHang
            WHERE ct.MaChuyenGiao = i.MaChuyenGiao
        ) v
        WHERE pt.TheTichToiDaM3 IS NOT NULL
          AND ISNULL(v.TongTheTichM3,0) > pt.TheTichToiDaM3
    )
    BEGIN
        ;THROW 51035, N'Phương tiện mới không đủ thể tích cho chuyến.', 1;
    END;
END;
GO


/* =============================================================================
   BƯỚC 18. TRIGGER TOÀN VẸN BỔ SUNG
   Bảo vệ các quy tắc xuyên bảng: vai trò, khối lượng, kho, chuyến, phí.
   ============================================================================= */

-- Hồ sơ nhân viên giao hàng chỉ được gắn với tài khoản SHIPPER.
CREATE OR ALTER TRIGGER dbo.TR_NhanVienGiaoHang_KiemTraVaiTro
ON dbo.NhanVienGiaoHang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan = i.MaTaiKhoan
        JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
        WHERE vt.KyHieuVaiTro <> 'SHIPPER'
    )
    BEGIN
        ;THROW 51040, N'Tài khoản gắn với nhân viên giao hàng phải có vai trò SHIPPER.', 1;
    END;
END;
GO

-- Đồng bộ tổng khối lượng đơn từ các dòng ChiTietDonHang.
CREATE OR ALTER TRIGGER dbo.TR_ChiTietDonHang_DongBoTongKhoiLuong
ON dbo.ChiTietDonHang
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH DonBiAnhHuong AS (
        SELECT MaDonHang FROM inserted
        UNION
        SELECT MaDonHang FROM deleted
    ),
    Tong AS (
        SELECT
            d.MaDonHang,
            CAST(ISNULL(SUM(CAST(ct.SoLuong AS DECIMAL(18,3)) * ct.KhoiLuongDonViKg), 0)
                 AS DECIMAL(12,3)) AS TongKhoiLuong
        FROM DonBiAnhHuong d
        LEFT JOIN dbo.ChiTietDonHang ct ON ct.MaDonHang = d.MaDonHang
        GROUP BY d.MaDonHang
    )
    UPDATE dh
    SET dh.TongKhoiLuongKg = t.TongKhoiLuong,
        dh.ThoiGianCapNhat = SYSUTCDATETIME()
    FROM dbo.DonHang dh
    JOIN Tong t ON t.MaDonHang = dh.MaDonHang;
END;
GO

-- Chặn cập nhật tổng khối lượng không khớp chi tiết đơn.
CREATE OR ALTER TRIGGER dbo.TR_DonHang_KiemTraTongKhoiLuong
ON dbo.DonHang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(TongKhoiLuongKg) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        OUTER APPLY (
            SELECT CAST(ISNULL(SUM(CAST(ct.SoLuong AS DECIMAL(18,3)) * ct.KhoiLuongDonViKg), 0)
                        AS DECIMAL(12,3)) AS TongChiTiet
            FROM dbo.ChiTietDonHang ct
            WHERE ct.MaDonHang = i.MaDonHang
        ) x
        WHERE i.TongKhoiLuongKg <> x.TongChiTiet
    )
    BEGIN
        ;THROW 51041, N'Tổng khối lượng đơn phải bằng tổng SoLuong × KhoiLuongDonViKg của chi tiết đơn.', 1;
    END;
END;
GO

-- Sau khi đổi khối lượng, chuyến đang hoạt động vẫn phải nằm trong tải trọng xe.
CREATE OR ALTER TRIGGER dbo.TR_DonHang_KiemTraTaiTrongSauCapNhatKhoiLuong
ON dbo.DonHang
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(TongKhoiLuongKg) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.ChiTietChuyenGiao ct ON ct.MaDonHang=i.MaDonHang
        JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao=ct.MaChuyenGiao
        JOIN dbo.PhuongTien pt ON pt.MaPhuongTien=cg.MaPhuongTien
        CROSS APPLY (
            SELECT SUM(dh.TongKhoiLuongKg) TongKhoiLuong
            FROM dbo.ChiTietChuyenGiao ct2
            JOIN dbo.DonHang dh ON dh.MaDonHang=ct2.MaDonHang
            WHERE ct2.MaChuyenGiao=cg.MaChuyenGiao
        ) w
        WHERE cg.TrangThaiChuyen NOT IN ('COMPLETED','CANCELLED')
          AND w.TongKhoiLuong>pt.KhoiLuongDenKg
    )
    BEGIN
        ;THROW 51042, N'Cập nhật hàng hóa làm chuyến giao vượt tải trọng phương tiện.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.ChiTietChuyenGiao ct ON ct.MaDonHang=i.MaDonHang
        JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao=ct.MaChuyenGiao
        JOIN dbo.PhuongTien pt ON pt.MaPhuongTien=cg.MaPhuongTien
        WHERE cg.TrangThaiChuyen NOT IN ('COMPLETED','CANCELLED')
          AND pt.TheTichToiDaM3 IS NOT NULL
          AND EXISTS (
              SELECT 1
              FROM dbo.ChiTietChuyenGiao ct2
              JOIN dbo.ChiTietDonHang h ON h.MaDonHang=ct2.MaDonHang
              WHERE ct2.MaChuyenGiao=cg.MaChuyenGiao
                AND (h.ChieuDaiCm IS NULL OR h.ChieuRongCm IS NULL OR h.ChieuCaoCm IS NULL)
          )
    )
    BEGIN
        ;THROW 51053, N'Cập nhật hàng hóa làm chuyến thiếu dữ liệu kích thước để kiểm tra thể tích.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.ChiTietChuyenGiao ct ON ct.MaDonHang=i.MaDonHang
        JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao=ct.MaChuyenGiao
        JOIN dbo.PhuongTien pt ON pt.MaPhuongTien=cg.MaPhuongTien
        CROSS APPLY (
            SELECT SUM(
                CAST(h.SoLuong AS DECIMAL(18,6))*h.ChieuDaiCm*h.ChieuRongCm*h.ChieuCaoCm/1000000.0
            ) TongTheTichM3
            FROM dbo.ChiTietChuyenGiao ct2
            JOIN dbo.ChiTietDonHang h ON h.MaDonHang=ct2.MaDonHang
            WHERE ct2.MaChuyenGiao=cg.MaChuyenGiao
        ) v
        WHERE cg.TrangThaiChuyen NOT IN ('COMPLETED','CANCELLED')
          AND pt.TheTichToiDaM3 IS NOT NULL
          AND ISNULL(v.TongTheTichM3,0)>pt.TheTichToiDaM3
    )
    BEGIN
        ;THROW 51054, N'Cập nhật hàng hóa làm chuyến giao vượt thể tích cho phép của phương tiện.', 1;
    END;
END;
GO

-- Phân công gắn chuyến phải khớp shipper và phương tiện.
CREATE OR ALTER TRIGGER dbo.TR_PhanCongGiaoHang_KiemTraChuyen
ON dbo.PhanCongGiaoHang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao = i.MaChuyenGiao
        WHERE i.MaChuyenGiao IS NOT NULL
          AND (
              cg.MaNhanVienGiaoHang IS NULL
              OR cg.MaNhanVienGiaoHang <> i.MaNhanVienGiaoHang
              OR (cg.MaPhuongTien IS NULL AND i.MaPhuongTien IS NOT NULL)
              OR (cg.MaPhuongTien IS NOT NULL AND ISNULL(i.MaPhuongTien,-1) <> cg.MaPhuongTien)
          )
    )
    BEGIN
        ;THROW 51043, N'Phân công đơn phải khớp nhân viên giao hàng và phương tiện của chuyến.', 1;
    END;
END;
GO

-- Không cho đổi shipper/xe nếu làm lệch các phân công hiện hành.
CREATE OR ALTER TRIGGER dbo.TR_ChuyenGiaoHang_KiemTraPhanCong
ON dbo.ChuyenGiaoHang
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT (UPDATE(MaNhanVienGiaoHang) OR UPDATE(MaPhuongTien)) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.PhanCongGiaoHang pc ON pc.MaChuyenGiao = i.MaChuyenGiao
        WHERE pc.ThoiGianKetThuc IS NULL
          AND (
              i.MaNhanVienGiaoHang IS NULL
              OR pc.MaNhanVienGiaoHang <> i.MaNhanVienGiaoHang
              OR (i.MaPhuongTien IS NULL AND pc.MaPhuongTien IS NOT NULL)
              OR (i.MaPhuongTien IS NOT NULL AND ISNULL(pc.MaPhuongTien,-1) <> i.MaPhuongTien)
          )
    )
    BEGIN
        ;THROW 51044, N'Không thể đổi shipper/phương tiện của chuyến khi còn phân công hiện hành không khớp.', 1;
    END;
END;
GO

-- Vị trí nguồn/đích phải thuộc đúng kho của giao dịch.
CREATE OR ALTER TRIGGER dbo.TR_ChiTietGiaoDichKho_KiemTraViTri
ON dbo.ChiTietGiaoDichKho
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.GiaoDichKho gd ON gd.MaGiaoDichKho = i.MaGiaoDichKho
        LEFT JOIN dbo.ViTriLuuKho vn ON vn.MaViTriLuuKho = i.MaViTriNguon
        LEFT JOIN dbo.ViTriLuuKho vd ON vd.MaViTriLuuKho = i.MaViTriDich
        WHERE (i.MaViTriNguon IS NOT NULL AND vn.MaKho <> gd.MaKho)
           OR (i.MaViTriDich IS NOT NULL AND vd.MaKho <> gd.MaKho)
           OR (gd.LoaiGiaoDich = 'INBOUND' AND (i.MaViTriNguon IS NOT NULL OR i.MaViTriDich IS NULL))
           OR (gd.LoaiGiaoDich = 'MOVE' AND (i.MaViTriNguon IS NULL OR i.MaViTriDich IS NULL OR i.MaViTriNguon = i.MaViTriDich))
           OR (gd.LoaiGiaoDich = 'OUTBOUND' AND (i.MaViTriNguon IS NULL OR i.MaViTriDich IS NOT NULL))
           OR (gd.LoaiGiaoDich = 'RETURN_IN' AND (i.MaViTriNguon IS NOT NULL OR i.MaViTriDich IS NULL))
    )
    BEGIN
        ;THROW 51045, N'Vị trí kho không phù hợp với kho hoặc loại giao dịch kho.', 1;
    END;
END;
GO

-- Chỉ bàn giao đơn ở đúng kho cho đúng shipper được phân công.
CREATE OR ALTER TRIGGER dbo.TR_ChiTietBanGiaoHang_KiemTra
ON dbo.ChiTietBanGiaoHang
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.BanGiaoHang bg ON bg.MaBanGiao = i.MaBanGiao
        LEFT JOIN dbo.TonKhoDonHang tk ON tk.MaDonHang = i.MaDonHang
        WHERE tk.MaDonHang IS NULL
           OR tk.MaKho <> bg.MaKho
           OR tk.TrangThaiTonKho NOT IN ('RECEIVED','STORED','ALLOCATED')
           OR NOT EXISTS (
                SELECT 1
                FROM dbo.PhanCongGiaoHang pc
                WHERE pc.MaDonHang = i.MaDonHang
                  AND pc.MaNhanVienGiaoHang = bg.MaNhanVienGiaoHang
                  AND pc.ThoiGianKetThuc IS NULL
                  AND pc.TrangThaiPhanCong IN ('PENDING','ACCEPTED','IN_PROGRESS')
           )
    )
    BEGIN
        ;THROW 51046, N'Đơn bàn giao phải nằm tại đúng kho và được phân công cho đúng nhân viên giao hàng.', 1;
    END;
END;
GO

-- Không cho quy tắc phí đang hoạt động bị chồng lấn.
CREATE OR ALTER TRIGGER dbo.TR_QuyTacTinhPhi_KhongChongLap
ON dbo.QuyTacTinhPhi
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.QuyTacTinhPhi q
          ON q.MaQuyTacTinhPhi <> i.MaQuyTacTinhPhi
         AND q.MaLoaiDichVu = i.MaLoaiDichVu
         AND ISNULL(q.MaKhuVuc,-1) = ISNULL(i.MaKhuVuc,-1)
         AND q.DangHoatDong = 1
         AND i.DangHoatDong = 1
         AND q.HieuLucTu < ISNULL(i.HieuLucDen, CONVERT(DATETIME2(0),'9999-12-31'))
         AND i.HieuLucTu < ISNULL(q.HieuLucDen, CONVERT(DATETIME2(0),'9999-12-31'))
         AND ISNULL(q.KhoangCachTuKm,0) <= ISNULL(i.KhoangCachDenKm,999999999)
         AND ISNULL(i.KhoangCachTuKm,0) <= ISNULL(q.KhoangCachDenKm,999999999)
         AND ISNULL(q.KhoiLuongTuKg,0) <= ISNULL(i.KhoiLuongDenKg,999999999)
         AND ISNULL(i.KhoiLuongTuKg,0) <= ISNULL(q.KhoiLuongDenKg,999999999)
    )
    BEGIN
        ;THROW 51047, N'Quy tắc tính phí bị chồng lấn với một quy tắc đang hoạt động.', 1;
    END;
END;
GO


-- Không cho xóa/chuyển hết chi tiết hàng sau khi đơn đã rời NEW.
CREATE OR ALTER TRIGGER dbo.TR_ChiTietDonHang_BaoVeDonDaXuLy
ON dbo.ChiTietDonHang
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM (SELECT MaDonHang FROM deleted UNION SELECT MaDonHang FROM inserted) a
        JOIN dbo.DonHang d ON d.MaDonHang=a.MaDonHang
        JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
        WHERE tt.KyHieuTrangThai NOT IN ('NEW','CANCELLED')
          AND NOT EXISTS (SELECT 1 FROM dbo.ChiTietDonHang ct WHERE ct.MaDonHang=a.MaDonHang)
    )
    BEGIN
        ;THROW 51048, N'Không được xóa toàn bộ chi tiết hàng khi đơn đã bước vào quy trình xử lý.', 1;
    END;
END;
GO

-- Sau khi đơn rời NEW phải luôn còn đúng một PICKUP và một DELIVERY.
CREATE OR ALTER TRIGGER dbo.TR_DiemGiaoNhan_BaoVeDonDaXuLy
ON dbo.DiemGiaoNhan
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM (SELECT MaDonHang FROM deleted UNION SELECT MaDonHang FROM inserted) a
        JOIN dbo.DonHang d ON d.MaDonHang=a.MaDonHang
        JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
        WHERE tt.KyHieuTrangThai NOT IN ('NEW','CANCELLED')
          AND (
              (SELECT COUNT(*) FROM dbo.DiemGiaoNhan p WHERE p.MaDonHang=a.MaDonHang AND p.LoaiDiem='PICKUP')<>1
              OR
              (SELECT COUNT(*) FROM dbo.DiemGiaoNhan p WHERE p.MaDonHang=a.MaDonHang AND p.LoaiDiem='DELIVERY')<>1
          )
    )
    BEGIN
        ;THROW 51049, N'Đơn đã xử lý phải luôn có đúng một điểm lấy và một điểm giao.', 1;
    END;
END;
GO

-- Một đơn chỉ được nằm trong một chuyến chưa kết thúc tại một thời điểm.
CREATE OR ALTER TRIGGER dbo.TR_ChiTietChuyenGiao_MotChuyenHoatDong
ON dbo.ChiTietChuyenGiao
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao=i.MaChuyenGiao
        WHERE cg.TrangThaiChuyen IN ('COMPLETED','CANCELLED')
    )
    BEGIN
        ;THROW 51050, N'Không được thêm đơn vào chuyến đã hoàn tất hoặc đã hủy.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.ChiTietChuyenGiao ct
          ON ct.MaDonHang=i.MaDonHang
         AND ct.MaChuyenGiao<>i.MaChuyenGiao
        JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao=ct.MaChuyenGiao
        WHERE cg.TrangThaiChuyen NOT IN ('COMPLETED','CANCELLED')
    )
    BEGIN
        ;THROW 51051, N'Một đơn không được thuộc đồng thời nhiều chuyến giao đang hoạt động.', 1;
    END;
END;
GO

-- Nếu khiếu nại do khách hàng tạo thì khách đó phải thuộc đúng đơn.
CREATE OR ALTER TRIGGER dbo.TR_KhieuNai_KiemTraKhachHang
ON dbo.KhieuNai
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted k
        JOIN dbo.DonHang d ON d.MaDonHang=k.MaDonHang
        WHERE k.MaKhachHang IS NOT NULL
          AND k.MaKhachHang NOT IN (d.MaNguoiGui,d.MaNguoiNhan)
    )
    BEGIN
        ;THROW 51052, N'Khách hàng khiếu nại phải là người gửi hoặc người nhận của đơn.', 1;
    END;
END;
GO

/* =============================================================================
   BƯỚC 19. VIEW TRA CỨU - BÁO CÁO
   Tạo view tổng hợp vận hành và công nợ COD.
   ============================================================================= */
CREATE OR ALTER VIEW dbo.vw_TongHopVanHanhDonHang
AS
SELECT
    o.MaDonHang,
    o.KyHieuDonHang,
    o.MaVanDon,
    b.KyHieuBuuCuc,
    b.TenBuuCuc,
    s.KyHieuTrangThai,
    s.TenTrangThai,
    sender.HoTen AS TenNguoiGui,
    sender.SoDienThoai AS SoDienThoaiNguoiGui,
    receiver.HoTen AS TenNguoiNhan,
    receiver.SoDienThoai AS SoDienThoaiNguoiNhan,
    o.TongKhoiLuongKg,
    o.TienCOD,
    o.PhiVanChuyen,
    o.ThoiGianYeuCauGiao,
    o.ThoiGianDuKienGiao,
    o.ThoiGianTao,
    curA.MaNhanVienGiaoHang,
    shipUser.HoTen AS TenNhanVienGiaoHangHienTai,
    curA.TrangThaiPhanCong
FROM dbo.DonHang o
JOIN dbo.BuuCuc b ON b.MaBuuCuc = o.MaBuuCuc
JOIN dbo.TrangThaiDonHang s ON s.MaTrangThaiDonHang = o.MaTrangThaiHienTai
JOIN dbo.KhachHang sender ON sender.MaKhachHang = o.MaNguoiGui
JOIN dbo.KhachHang receiver ON receiver.MaKhachHang = o.MaNguoiNhan
OUTER APPLY (
    SELECT TOP (1) a.MaNhanVienGiaoHang, a.TrangThaiPhanCong
    FROM dbo.PhanCongGiaoHang a
    WHERE a.MaDonHang = o.MaDonHang
      AND a.ThoiGianKetThuc IS NULL
    ORDER BY a.ThoiGianPhanCong DESC
) curA
LEFT JOIN dbo.NhanVienGiaoHang sh ON sh.MaNhanVienGiaoHang = curA.MaNhanVienGiaoHang
LEFT JOIN dbo.TaiKhoan shipUser ON shipUser.MaTaiKhoan = sh.MaTaiKhoan;
GO

CREATE OR ALTER VIEW dbo.vw_CongNoCODNhanVienGiaoHang
AS
WITH TongThu AS
(
    SELECT MaNhanVienGiaoHang, SUM(SoTienThucThu) AS TongTienDaThu
    FROM dbo.ThuTienCOD
    WHERE TrangThaiThuTien IN ('COLLECTED','PARTIAL')
    GROUP BY MaNhanVienGiaoHang
),
TongNop AS
(
    SELECT MaNhanVienGiaoHang, SUM(SoTienNop) AS TongTienDaNopDaXacNhan
    FROM dbo.NopTienCOD
    WHERE TrangThaiNop='CONFIRMED'
    GROUP BY MaNhanVienGiaoHang
)
SELECT
    nv.MaNhanVienGiaoHang,
    tk.HoTen AS TenNhanVienGiaoHang,
    ISNULL(t.TongTienDaThu,0) AS TongTienDaThu,
    ISNULL(n.TongTienDaNopDaXacNhan,0) AS TongTienDaNopDaXacNhan,
    ISNULL(t.TongTienDaThu,0)-ISNULL(n.TongTienDaNopDaXacNhan,0) AS CongNoCODConLai
FROM dbo.NhanVienGiaoHang nv
JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan=nv.MaTaiKhoan
LEFT JOIN TongThu t ON t.MaNhanVienGiaoHang=nv.MaNhanVienGiaoHang
LEFT JOIN TongNop n ON n.MaNhanVienGiaoHang=nv.MaNhanVienGiaoHang;
GO

/* =============================================================================
   BƯỚC 20. INDEX BỔ SUNG
   Tối ưu các truy vấn nghiệp vụ thường xuyên.
   ============================================================================= */
CREATE INDEX IX_ThuTienCOD_CongNo
ON dbo.ThuTienCOD(MaNhanVienGiaoHang, TrangThaiThuTien)
INCLUDE (SoTienThucThu);
GO

CREATE INDEX IX_NopTienCOD_CongNo
ON dbo.NopTienCOD(MaNhanVienGiaoHang, TrangThaiNop)
INCLUDE (SoTienNop);
GO

CREATE INDEX IX_DonHang_TrangThai_Ready_MucDoUuTien
ON dbo.DonHang(MaTrangThaiHienTai, ThoiGianSanSang, MucDoUuTien)
INCLUDE (MaBuuCuc, TongKhoiLuongKg, ThoiGianYeuCauGiao, TienCOD);
GO

CREATE INDEX IX_BanGiaoHang_NhanVienGiaoHang_TrangThai
ON dbo.BanGiaoHang(MaNhanVienGiaoHang, TrangThaiBanGiao, ThoiGianBanGiao DESC);
GO

CREATE INDEX IX_LanGiaoHang_DonHang_ThoiGian
ON dbo.LanGiaoHang(MaDonHang, ThoiGianThuGiao DESC);
GO

CREATE INDEX IX_KhieuNai_DonHang_TrangThai
ON dbo.KhieuNai(MaDonHang, TrangThaiKhieuNai, ThoiGianTao DESC);
GO

CREATE INDEX IX_KhuVuc_MaKhuVucCha
ON dbo.KhuVuc(MaKhuVucCha)
WHERE MaKhuVucCha IS NOT NULL;
GO

CREATE INDEX IX_TokenLamMoi_TaiKhoan_HetHan
ON dbo.TokenLamMoi(MaTaiKhoan, HetHanLuc)
INCLUDE (ThuHoiLuc);
GO

CREATE INDEX IX_ChiTietDonHang_DonHang
ON dbo.ChiTietDonHang(MaDonHang);
GO

CREATE INDEX IX_KhoanPhiDonHang_DonHang
ON dbo.KhoanPhiDonHang(MaDonHang, ThoiGianTao DESC);
GO

CREATE INDEX IX_BangChungGiaoHang_DonHang_LanGiao
ON dbo.BangChungGiaoHang(MaDonHang, MaLanGiaoHang);
GO

CREATE INDEX IX_YeuCauGiaoLai_DonHang_TrangThai
ON dbo.YeuCauGiaoLaiHoacHoan(MaDonHang, TrangThaiYeuCau, ThoiGianYeuCau DESC);
GO

CREATE INDEX IX_ChiTietNopTienCOD_DonHang
ON dbo.ChiTietNopTienCOD(MaDonHang)
INCLUDE (MaNopTienCOD, SoTienPhanBo);
GO

CREATE INDEX IX_ChiTietDoiSoatCOD_DonHang
ON dbo.ChiTietDoiSoatCOD(MaDonHang, MaDoiSoatCOD);
GO

CREATE INDEX IX_LichSuKhieuNai_KhieuNai_ThoiGian
ON dbo.LichSuKhieuNai(MaKhieuNai, ThoiGianThucHien DESC);
GO

CREATE INDEX IX_NhatKyHoatDong_TaiKhoan_ThoiGian
ON dbo.NhatKyHoatDong(MaTaiKhoan, ThoiGianTao DESC)
WHERE MaTaiKhoan IS NOT NULL;
GO

/* =============================================================================
   BƯỚC 21. STORED PROCEDURE NGHIỆP VỤ
   Đóng gói các flow quan trọng trong transaction.
   ============================================================================= */
-- Dùng cho các chuyển trạng thái thông thường; trigger sẽ kiểm tra state machine và ghi lịch sử.
CREATE OR ALTER PROCEDURE dbo.sp_ChuyenTrangThaiDonHang
    @MaDonHang BIGINT,
    @KyHieuTrangThaiMoi VARCHAR(40),
    @MaTaiKhoan BIGINT,
    @LyDo NVARCHAR(500)=NULL,
    @NguonCapNhat VARCHAR(20)='API'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @MaTrangThaiMoi SMALLINT,
            @KyHieuTrangThaiCu VARCHAR(40);

    SET @NguonCapNhat=UPPER(COALESCE(@NguonCapNhat,'API'));

    IF @NguonCapNhat NOT IN ('WEB','MOBILE','SYSTEM','API')
    BEGIN
        ;THROW 51100, N'Nguồn cập nhật trạng thái không hợp lệ.', 1;
    END;

    IF @KyHieuTrangThaiMoi IN ('DELIVERED','FAILED')
    BEGIN
        ;THROW 51103, N'DELIVERED/FAILED phải đi qua stored procedure giao thành công hoặc giao thất bại chuyên dụng.', 1;
    END;

    SELECT @MaTrangThaiMoi=MaTrangThaiDonHang
    FROM dbo.TrangThaiDonHang
    WHERE KyHieuTrangThai=@KyHieuTrangThaiMoi;

    IF @MaTrangThaiMoi IS NULL
    BEGIN
        ;THROW 51101, N'Không tìm thấy trạng thái đích.', 1;
    END;

    BEGIN TRY
        BEGIN TRAN;

        SELECT @KyHieuTrangThaiCu=tt.KyHieuTrangThai
        FROM dbo.DonHang d WITH (UPDLOCK,HOLDLOCK)
        JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
        WHERE d.MaDonHang=@MaDonHang;

        IF @KyHieuTrangThaiCu IS NULL
        BEGIN
            ;THROW 51102, N'Không tìm thấy đơn hàng.', 1;
        END;

        IF @KyHieuTrangThaiCu=@KyHieuTrangThaiMoi
        BEGIN
            ;THROW 51102, N'Đơn đã ở trạng thái đích.', 1;
        END;

        IF @KyHieuTrangThaiMoi='WAITING_ASSIGNMENT'
        BEGIN
            UPDATE dbo.PhanCongGiaoHang
            SET TrangThaiPhanCong='REASSIGNED',
                ThoiGianKetThuc=SYSUTCDATETIME()
            WHERE MaDonHang=@MaDonHang AND ThoiGianKetThuc IS NULL;
        END;

        IF @KyHieuTrangThaiMoi='RETURNING'
        BEGIN
            UPDATE dbo.PhanCongGiaoHang
            SET TrangThaiPhanCong=
                    CASE WHEN TrangThaiPhanCong IN ('ACCEPTED','IN_PROGRESS')
                         THEN 'ATTEMPT_FAILED' ELSE 'CANCELLED' END,
                ThoiGianKetThuc=SYSUTCDATETIME()
            WHERE MaDonHang=@MaDonHang AND ThoiGianKetThuc IS NULL;
        END;

        IF @KyHieuTrangThaiMoi='CANCELLED'
        BEGIN
            UPDATE dbo.PhanCongGiaoHang
            SET TrangThaiPhanCong='CANCELLED',
                ThoiGianKetThuc=SYSUTCDATETIME()
            WHERE MaDonHang=@MaDonHang AND ThoiGianKetThuc IS NULL;
        END;

        EXEC sys.sp_set_session_context @key=N'LyDoTrangThai',@value=@LyDo;
        EXEC sys.sp_set_session_context @key=N'NguonCapNhat',@value=@NguonCapNhat;

        UPDATE dbo.DonHang
        SET MaTrangThaiHienTai=@MaTrangThaiMoi,
            MaTaiKhoanCapNhatCuoi=@MaTaiKhoan,
            ThoiGianCapNhat=SYSUTCDATETIME()
        WHERE MaDonHang=@MaDonHang;

        EXEC sys.sp_set_session_context @key=N'LyDoTrangThai',@value=NULL;
        EXEC sys.sp_set_session_context @key=N'NguonCapNhat',@value=NULL;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        BEGIN TRY
            EXEC sys.sp_set_session_context @key=N'LyDoTrangThai',@value=NULL;
            EXEC sys.sp_set_session_context @key=N'NguonCapNhat',@value=NULL;
        END TRY
        BEGIN CATCH
        END CATCH;
        ;THROW;
    END CATCH;
END;
GO

-- Dùng khi xác nhận đơn NEW sau khi đã có điểm lấy, điểm giao và chi tiết hàng.
CREATE OR ALTER PROCEDURE dbo.sp_XacNhanDonHang
    @MaDonHang BIGINT,
    @MaTaiKhoan BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.DonHang d
        JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
        WHERE d.MaDonHang = @MaDonHang
          AND tt.KyHieuTrangThai = 'NEW'
    )
    BEGIN
        ;THROW 51110, N'Không tìm thấy đơn hàng ở trạng thái NEW để xác nhận.', 1;
    END;

    EXEC dbo.sp_ChuyenTrangThaiDonHang
        @MaDonHang = @MaDonHang,
        @KyHieuTrangThaiMoi = 'CONFIRMED',
        @MaTaiKhoan = @MaTaiKhoan,
        @LyDo = NULL,
        @NguonCapNhat = 'API';
END;
GO

-- Mobile shipper gọi procedure này khi giao thành công; bằng chứng, COD và trạng thái được xử lý trong cùng transaction.
CREATE OR ALTER PROCEDURE dbo.sp_XacNhanGiaoHangThanhCong
    @MaDonHang BIGINT,
    @MaNhanVienGiaoHang BIGINT,
    @MaTaiKhoan BIGINT,
    @LoaiBangChung VARCHAR(30),
    @DuongDanTep NVARCHAR(1000)=NULL,
    @MaXacNhanBam VARCHAR(255)=NULL,
    @TenNguoiNhan NVARCHAR(150)=NULL,
    @ViDo DECIMAL(9,6)=NULL,
    @KinhDo DECIMAL(10,6)=NULL,
    @SoTienThucThu DECIMAL(18,2)=NULL,
    @GhiChuCOD NVARCHAR(500)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TienCOD DECIMAL(18,2),
            @TrangThai VARCHAR(40),
            @MaPhanCong BIGINT,
            @MaLanGiaoHang BIGINT,
            @SoLanThu INT,
            @MaDelivered SMALLINT;

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.NhanVienGiaoHang
            WHERE MaNhanVienGiaoHang = @MaNhanVienGiaoHang
              AND MaTaiKhoan = @MaTaiKhoan
              AND DangHoatDong = 1
        )
        BEGIN
            ;THROW 51120, N'Tài khoản không khớp nhân viên giao hàng.', 1;
        END;

        SELECT @TienCOD=d.TienCOD, @TrangThai=tt.KyHieuTrangThai
        FROM dbo.DonHang d WITH (UPDLOCK,HOLDLOCK)
        JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
        WHERE d.MaDonHang=@MaDonHang;

        IF @TrangThai IS NULL
        BEGIN
            ;THROW 51121, N'Không tìm thấy đơn hàng.', 1;
        END;

        IF @TrangThai <> 'IN_DELIVERY'
        BEGIN
            ;THROW 51122, N'Chỉ đơn IN_DELIVERY mới được xác nhận giao thành công.', 1;
        END;

        SELECT @MaPhanCong=pc.MaPhanCongGiaoHang
        FROM dbo.PhanCongGiaoHang pc WITH (UPDLOCK,HOLDLOCK)
        WHERE pc.MaDonHang=@MaDonHang
          AND pc.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
          AND pc.ThoiGianKetThuc IS NULL
          AND pc.TrangThaiPhanCong IN ('ACCEPTED','IN_PROGRESS');

        IF @MaPhanCong IS NULL
        BEGIN
            ;THROW 51123, N'Nhân viên giao hàng không phải người đang được phân công đơn này.', 1;
        END;

        IF @LoaiBangChung NOT IN ('PHOTO','SIGNATURE','OTP','RECEIVER_CONFIRMATION')
        BEGIN
            ;THROW 51124, N'Loại bằng chứng không hợp lệ.', 1;
        END;

        IF @DuongDanTep IS NULL AND @MaXacNhanBam IS NULL AND @TenNguoiNhan IS NULL
        BEGIN
            ;THROW 51125, N'Phải có ít nhất một nội dung bằng chứng.', 1;
        END;

        IF (@ViDo IS NULL AND @KinhDo IS NOT NULL)
           OR (@ViDo IS NOT NULL AND @KinhDo IS NULL)
           OR (@ViDo IS NOT NULL AND @ViDo NOT BETWEEN -90 AND 90)
           OR (@KinhDo IS NOT NULL AND @KinhDo NOT BETWEEN -180 AND 180)
        BEGIN
            ;THROW 51126, N'Tọa độ bằng chứng không hợp lệ.', 1;
        END;

        IF EXISTS (
            SELECT 1 FROM dbo.LanGiaoHang
            WHERE MaDonHang=@MaDonHang AND KetQua='SUCCESS'
        )
        BEGIN
            ;THROW 51127, N'Đơn đã có lần giao thành công.', 1;
        END;

        IF @TienCOD > 0 AND (@SoTienThucThu IS NULL OR @SoTienThucThu <> @TienCOD)
        BEGIN
            ;THROW 51128, N'Đơn COD chỉ được xác nhận giao thành công khi đã thu đủ đúng số tiền COD.', 1;
        END;

        IF @TienCOD = 0 AND ISNULL(@SoTienThucThu,0) <> 0
        BEGIN
            ;THROW 51129, N'Đơn không COD không được ghi nhận tiền COD.', 1;
        END;

        SELECT @SoLanThu=ISNULL(MAX(SoLanThu),0)+1
        FROM dbo.LanGiaoHang WITH (UPDLOCK,HOLDLOCK)
        WHERE MaDonHang=@MaDonHang;

        INSERT INTO dbo.LanGiaoHang
        (MaDonHang,MaPhanCongGiaoHang,SoLanThu,ThoiGianThuGiao,KetQua,
         MaLyDoGiaoThatBai,GhiChu,ThoiGianGiaoLaiDuKien,MaTaiKhoanGhiNhan)
        VALUES
        (@MaDonHang,@MaPhanCong,@SoLanThu,SYSUTCDATETIME(),'SUCCESS',
         NULL,NULL,NULL,@MaTaiKhoan);

        SET @MaLanGiaoHang=SCOPE_IDENTITY();

        INSERT INTO dbo.BangChungGiaoHang
        (MaDonHang,MaLanGiaoHang,LoaiBangChung,DuongDanTep,MaXacNhanBam,
         TenNguoiNhan,ViDo,KinhDo,MaTaiKhoanTaiLen)
        VALUES
        (@MaDonHang,@MaLanGiaoHang,@LoaiBangChung,@DuongDanTep,@MaXacNhanBam,
         @TenNguoiNhan,@ViDo,@KinhDo,@MaTaiKhoan);

        IF @TienCOD > 0
        BEGIN
            INSERT INTO dbo.ThuTienCOD
            (MaDonHang,MaLanGiaoHang,MaNhanVienGiaoHang,SoTienPhaiThu,
             SoTienThucThu,TrangThaiThuTien,GhiChu)
            VALUES
            (@MaDonHang,@MaLanGiaoHang,@MaNhanVienGiaoHang,@TienCOD,
             @SoTienThucThu,'COLLECTED',@GhiChuCOD);
        END;

        SELECT @MaDelivered=MaTrangThaiDonHang
        FROM dbo.TrangThaiDonHang
        WHERE KyHieuTrangThai='DELIVERED';

        IF @MaDelivered IS NULL
        BEGIN
            ;THROW 51130, N'Không tìm thấy trạng thái DELIVERED.', 1;
        END;

        EXEC sys.sp_set_session_context @key=N'LyDoTrangThai',@value=NULL;
        EXEC sys.sp_set_session_context @key=N'NguonCapNhat',@value='MOBILE';

        UPDATE dbo.DonHang
        SET MaTrangThaiHienTai=@MaDelivered,
            MaTaiKhoanCapNhatCuoi=@MaTaiKhoan,
            ThoiGianCapNhat=SYSUTCDATETIME()
        WHERE MaDonHang=@MaDonHang;

        UPDATE dbo.PhanCongGiaoHang
        SET TrangThaiPhanCong='COMPLETED',
            ThoiGianKetThuc=SYSUTCDATETIME()
        WHERE MaPhanCongGiaoHang=@MaPhanCong;

        EXEC sys.sp_set_session_context @key=N'LyDoTrangThai',@value=NULL;
        EXEC sys.sp_set_session_context @key=N'NguonCapNhat',@value=NULL;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        BEGIN TRY
            EXEC sys.sp_set_session_context @key=N'LyDoTrangThai',@value=NULL;
            EXEC sys.sp_set_session_context @key=N'NguonCapNhat',@value=NULL;
        END TRY
        BEGIN CATCH
        END CATCH;
        ;THROW;
    END CATCH;
END;
GO


-- FLOW: giao thất bại -> lưu lần giao/minh chứng -> FAILED -> đóng phân công.
CREATE OR ALTER PROCEDURE dbo.sp_XacNhanGiaoHangThatBai
    @MaDonHang BIGINT,
    @MaNhanVienGiaoHang BIGINT,
    @MaTaiKhoan BIGINT,
    @MaLyDoGiaoThatBai INT,
    @GhiChu NVARCHAR(1000)=NULL,
    @ThoiGianGiaoLaiDuKien DATETIME2(0)=NULL,
    @DuongDanTepMinhChung NVARCHAR(1000)=NULL,
    @ViDo DECIMAL(9,6)=NULL,
    @KinhDo DECIMAL(10,6)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TrangThai VARCHAR(40),
            @MaPhanCong BIGINT,
            @MaLanGiaoHang BIGINT,
            @SoLanThu INT,
            @BatBuocMinhChung BIT,
            @TenLyDo NVARCHAR(150),
            @MaFailed SMALLINT,
            @LyDoLichSu NVARCHAR(500);

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (
            SELECT 1 FROM dbo.NhanVienGiaoHang
            WHERE MaNhanVienGiaoHang=@MaNhanVienGiaoHang
              AND MaTaiKhoan=@MaTaiKhoan
              AND DangHoatDong=1
        )
        BEGIN
            ;THROW 51140, N'Tài khoản không khớp nhân viên giao hàng.', 1;
        END;

        SELECT @TrangThai=tt.KyHieuTrangThai
        FROM dbo.DonHang d WITH (UPDLOCK,HOLDLOCK)
        JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
        WHERE d.MaDonHang=@MaDonHang;

        IF @TrangThai IS NULL
        BEGIN
            ;THROW 51141, N'Không tìm thấy đơn hàng.', 1;
        END;

        IF @TrangThai<>'IN_DELIVERY'
        BEGIN
            ;THROW 51142, N'Chỉ đơn IN_DELIVERY mới được xác nhận giao thất bại.', 1;
        END;

        SELECT @BatBuocMinhChung=BatBuocMinhChung,@TenLyDo=TenLyDo
        FROM dbo.LyDoGiaoThatBai
        WHERE MaLyDoGiaoThatBai=@MaLyDoGiaoThatBai
          AND DangHoatDong=1;

        IF @BatBuocMinhChung IS NULL
        BEGIN
            ;THROW 51143, N'Lý do giao thất bại không hợp lệ.', 1;
        END;

        IF @BatBuocMinhChung=1 AND NULLIF(LTRIM(RTRIM(@DuongDanTepMinhChung)),N'') IS NULL
        BEGIN
            ;THROW 51144, N'Lý do này bắt buộc phải có ảnh minh chứng.', 1;
        END;

        IF (@ViDo IS NULL AND @KinhDo IS NOT NULL)
           OR (@ViDo IS NOT NULL AND @KinhDo IS NULL)
           OR (@ViDo IS NOT NULL AND @ViDo NOT BETWEEN -90 AND 90)
           OR (@KinhDo IS NOT NULL AND @KinhDo NOT BETWEEN -180 AND 180)
        BEGIN
            ;THROW 51145, N'Tọa độ minh chứng không hợp lệ.', 1;
        END;

        SELECT @MaPhanCong=pc.MaPhanCongGiaoHang
        FROM dbo.PhanCongGiaoHang pc WITH (UPDLOCK,HOLDLOCK)
        WHERE pc.MaDonHang=@MaDonHang
          AND pc.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
          AND pc.ThoiGianKetThuc IS NULL
          AND pc.TrangThaiPhanCong IN ('ACCEPTED','IN_PROGRESS');

        IF @MaPhanCong IS NULL
        BEGIN
            ;THROW 51146, N'Nhân viên giao hàng không phải người đang được phân công đơn này.', 1;
        END;

        SELECT @SoLanThu=ISNULL(MAX(SoLanThu),0)+1
        FROM dbo.LanGiaoHang WITH (UPDLOCK,HOLDLOCK)
        WHERE MaDonHang=@MaDonHang;

        INSERT INTO dbo.LanGiaoHang
        (MaDonHang,MaPhanCongGiaoHang,SoLanThu,ThoiGianThuGiao,KetQua,
         MaLyDoGiaoThatBai,GhiChu,ThoiGianGiaoLaiDuKien,MaTaiKhoanGhiNhan)
        VALUES
        (@MaDonHang,@MaPhanCong,@SoLanThu,SYSUTCDATETIME(),'FAILED',
         @MaLyDoGiaoThatBai,@GhiChu,@ThoiGianGiaoLaiDuKien,@MaTaiKhoan);

        SET @MaLanGiaoHang=SCOPE_IDENTITY();

        IF NULLIF(LTRIM(RTRIM(@DuongDanTepMinhChung)),N'') IS NOT NULL
        BEGIN
            INSERT INTO dbo.BangChungGiaoHang
            (MaDonHang,MaLanGiaoHang,LoaiBangChung,DuongDanTep,
             MaXacNhanBam,TenNguoiNhan,ViDo,KinhDo,MaTaiKhoanTaiLen)
            VALUES
            (@MaDonHang,@MaLanGiaoHang,'PHOTO',@DuongDanTepMinhChung,
             NULL,NULL,@ViDo,@KinhDo,@MaTaiKhoan);
        END;

        SELECT @MaFailed=MaTrangThaiDonHang
        FROM dbo.TrangThaiDonHang
        WHERE KyHieuTrangThai='FAILED';

        SET @LyDoLichSu=LEFT(
            CONCAT(@TenLyDo,
                   CASE WHEN NULLIF(LTRIM(RTRIM(@GhiChu)),N'') IS NULL
                        THEN N'' ELSE N' - '+@GhiChu END),500);

        EXEC sys.sp_set_session_context @key=N'LyDoTrangThai',@value=@LyDoLichSu;
        EXEC sys.sp_set_session_context @key=N'NguonCapNhat',@value='MOBILE';

        UPDATE dbo.DonHang
        SET MaTrangThaiHienTai=@MaFailed,
            MaTaiKhoanCapNhatCuoi=@MaTaiKhoan,
            ThoiGianCapNhat=SYSUTCDATETIME()
        WHERE MaDonHang=@MaDonHang;

        /* Giữ assignment hiện hành để cùng shipper có thể RETRY_WAITING -> IN_DELIVERY.
           Nếu chuyển RETURNING/WAITING_ASSIGNMENT/CANCELLED, procedure chuyển trạng thái sẽ đóng assignment. */
        UPDATE dbo.PhanCongGiaoHang
        SET TrangThaiPhanCong='IN_PROGRESS'
        WHERE MaPhanCongGiaoHang=@MaPhanCong;

        EXEC sys.sp_set_session_context @key=N'LyDoTrangThai',@value=NULL;
        EXEC sys.sp_set_session_context @key=N'NguonCapNhat',@value=NULL;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        BEGIN TRY
            EXEC sys.sp_set_session_context @key=N'LyDoTrangThai',@value=NULL;
            EXEC sys.sp_set_session_context @key=N'NguonCapNhat',@value=NULL;
        END TRY
        BEGIN CATCH
        END CATCH;
        ;THROW;
    END CATCH;
END;
GO

-- FLOW: xác nhận nộp COD; tổng phân bổ phải khớp phiếu và không vượt tiền đã thu.
CREATE OR ALTER PROCEDURE dbo.sp_XacNhanNopTienCOD
    @MaNopTienCOD BIGINT,
    @MaTaiKhoanXacNhan BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @MaNhanVienGiaoHang BIGINT,
            @MaBuuCuc INT,
            @SoTienNop DECIMAL(18,2),
            @TrangThai VARCHAR(20),
            @TongChiTiet DECIMAL(18,2),
            @SoDongKhoa INT;

    BEGIN TRY
        BEGIN TRAN;

        SELECT @MaNhanVienGiaoHang=MaNhanVienGiaoHang,
               @MaBuuCuc=MaBuuCuc,
               @SoTienNop=SoTienNop,
               @TrangThai=TrangThaiNop
        FROM dbo.NopTienCOD WITH (UPDLOCK,HOLDLOCK)
        WHERE MaNopTienCOD=@MaNopTienCOD;

        IF @TrangThai IS NULL
        BEGIN
            ;THROW 51170, N'Không tìm thấy phiếu nộp COD.', 1;
        END;

        IF @TrangThai<>'PENDING'
        BEGIN
            ;THROW 51171, N'Chỉ phiếu PENDING mới được xác nhận.', 1;
        END;

        SELECT @TongChiTiet=ISNULL(SUM(SoTienPhanBo),0)
        FROM dbo.ChiTietNopTienCOD WITH (UPDLOCK,HOLDLOCK)
        WHERE MaNopTienCOD=@MaNopTienCOD;

        IF @TongChiTiet<>@SoTienNop
        BEGIN
            ;THROW 51172, N'Tổng tiền phân bổ chi tiết phải bằng số tiền nộp trên phiếu.', 1;
        END;

        IF EXISTS (
            SELECT 1
            FROM dbo.ChiTietNopTienCOD ct
            JOIN dbo.DonHang d ON d.MaDonHang=ct.MaDonHang
            WHERE ct.MaNopTienCOD=@MaNopTienCOD
              AND d.MaBuuCuc<>@MaBuuCuc
        )
        BEGIN
            ;THROW 51175, N'Phiếu nộp COD chỉ được phân bổ cho đơn thuộc cùng bưu cục.', 1;
        END;

        SELECT @SoDongKhoa=COUNT(*)
        FROM dbo.ThuTienCOD thu WITH (UPDLOCK,HOLDLOCK)
        JOIN dbo.ChiTietNopTienCOD ct ON ct.MaDonHang=thu.MaDonHang
        WHERE ct.MaNopTienCOD=@MaNopTienCOD
          AND thu.MaNhanVienGiaoHang=@MaNhanVienGiaoHang;

        IF EXISTS (
            SELECT 1
            FROM dbo.ChiTietNopTienCOD ct
            LEFT JOIN dbo.ThuTienCOD thu
              ON thu.MaDonHang=ct.MaDonHang
             AND thu.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
             AND thu.TrangThaiThuTien IN ('COLLECTED','PARTIAL')
            WHERE ct.MaNopTienCOD=@MaNopTienCOD
              AND thu.MaThuTienCOD IS NULL
        )
        BEGIN
            ;THROW 51173, N'Có đơn không thuộc tiền COD đã thu của nhân viên giao hàng này.', 1;
        END;

        IF EXISTS (
            SELECT 1
            FROM dbo.ChiTietNopTienCOD ct
            JOIN dbo.ThuTienCOD thu ON thu.MaDonHang=ct.MaDonHang
            OUTER APPLY (
                SELECT ISNULL(SUM(ct2.SoTienPhanBo),0) AS DaNopTruoc
                FROM dbo.ChiTietNopTienCOD ct2
                JOIN dbo.NopTienCOD n2 ON n2.MaNopTienCOD=ct2.MaNopTienCOD
                WHERE ct2.MaDonHang=ct.MaDonHang
                  AND n2.TrangThaiNop='CONFIRMED'
            ) x
            WHERE ct.MaNopTienCOD=@MaNopTienCOD
              AND x.DaNopTruoc+ct.SoTienPhanBo>thu.SoTienThucThu
        )
        BEGIN
            ;THROW 51174, N'Số tiền nộp phân bổ vượt số tiền COD thực thu của một hoặc nhiều đơn.', 1;
        END;

        UPDATE dbo.NopTienCOD
        SET TrangThaiNop='CONFIRMED',
            ThoiGianXacNhan=SYSUTCDATETIME(),
            MaTaiKhoanXacNhan=@MaTaiKhoanXacNhan
        WHERE MaNopTienCOD=@MaNopTienCOD;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        ;THROW;
    END CATCH;
END;
GO

-- FLOW: xác nhận đối soát; tổng tiền được tính lại từ chi tiết ở phía server.
CREATE OR ALTER PROCEDURE dbo.sp_XacNhanDoiSoatCOD
    @MaDoiSoatCOD BIGINT,
    @MaTaiKhoanXacNhan BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TrangThai VARCHAR(20),
            @MaBuuCuc INT,
            @MaNhanVienGiaoHang BIGINT,
            @TuThoiGian DATETIME2(0),
            @DenThoiGian DATETIME2(0),
            @TongPhaiThu DECIMAL(18,2),
            @TongDaThu DECIMAL(18,2),
            @TongDaNop DECIMAL(18,2),
            @SoDongKhoa INT;

    BEGIN TRY
        BEGIN TRAN;

        SELECT @TrangThai=TrangThaiDoiSoat,
               @MaBuuCuc=MaBuuCuc,
               @MaNhanVienGiaoHang=MaNhanVienGiaoHang,
               @TuThoiGian=TuThoiGian,
               @DenThoiGian=DenThoiGian
        FROM dbo.DoiSoatCOD WITH (UPDLOCK,HOLDLOCK)
        WHERE MaDoiSoatCOD=@MaDoiSoatCOD;

        IF @TrangThai IS NULL
        BEGIN
            ;THROW 51180, N'Không tìm thấy phiên đối soát COD.', 1;
        END;

        IF @TrangThai NOT IN ('DRAFT','REVIEW','DIFFERENCE')
        BEGIN
            ;THROW 51181, N'Trạng thái đối soát hiện tại không cho phép xác nhận lại.', 1;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.ThuTienCOD thu
            JOIN dbo.DonHang d ON d.MaDonHang=thu.MaDonHang
            WHERE thu.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
              AND d.MaBuuCuc=@MaBuuCuc
              AND thu.TrangThaiThuTien IN ('COLLECTED','PARTIAL')
              AND thu.ThoiGianThuTien>=@TuThoiGian
              AND thu.ThoiGianThuTien<@DenThoiGian
        )
        BEGIN
            ;THROW 51182, N'Không có dữ liệu COD phù hợp trong kỳ đối soát.', 1;
        END;

        /* Khóa các bản ghi COD thuộc kỳ trước khi kiểm tra trùng phiên đối soát. */
        SELECT @SoDongKhoa=COUNT(*)
        FROM dbo.ThuTienCOD thu WITH (UPDLOCK,HOLDLOCK)
        JOIN dbo.DonHang d ON d.MaDonHang=thu.MaDonHang
        WHERE thu.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
          AND d.MaBuuCuc=@MaBuuCuc
          AND thu.TrangThaiThuTien IN ('COLLECTED','PARTIAL')
          AND thu.ThoiGianThuTien>=@TuThoiGian
          AND thu.ThoiGianThuTien<@DenThoiGian;

        IF EXISTS (
            SELECT 1
            FROM dbo.ThuTienCOD thu
            JOIN dbo.DonHang d ON d.MaDonHang=thu.MaDonHang
            JOIN dbo.ChiTietDoiSoatCOD ct ON ct.MaDonHang=thu.MaDonHang
            JOIN dbo.DoiSoatCOD ds ON ds.MaDoiSoatCOD=ct.MaDoiSoatCOD
            WHERE thu.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
              AND d.MaBuuCuc=@MaBuuCuc
              AND thu.TrangThaiThuTien IN ('COLLECTED','PARTIAL')
              AND thu.ThoiGianThuTien>=@TuThoiGian
              AND thu.ThoiGianThuTien<@DenThoiGian
              AND ct.MaDoiSoatCOD<>@MaDoiSoatCOD
              AND ds.TrangThaiDoiSoat<>'CANCELLED'
        )
        BEGIN
            ;THROW 51183, N'Có đơn COD đã thuộc một phiên đối soát khác chưa hủy.', 1;
        END;

        INSERT INTO dbo.ChiTietDoiSoatCOD
        (MaDoiSoatCOD,MaDonHang,SoTienPhaiThu,SoTienDaThu,SoTienDaNop,TrangThaiKetQua,GhiChuXuLy)
        SELECT @MaDoiSoatCOD,thu.MaDonHang,0,0,0,'PENDING_RESOLUTION',NULL
        FROM dbo.ThuTienCOD thu WITH (UPDLOCK,HOLDLOCK)
        JOIN dbo.DonHang d ON d.MaDonHang=thu.MaDonHang
        WHERE thu.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
          AND d.MaBuuCuc=@MaBuuCuc
          AND thu.TrangThaiThuTien IN ('COLLECTED','PARTIAL')
          AND thu.ThoiGianThuTien>=@TuThoiGian
          AND thu.ThoiGianThuTien<@DenThoiGian
          AND NOT EXISTS (
              SELECT 1 FROM dbo.ChiTietDoiSoatCOD x
              WHERE x.MaDoiSoatCOD=@MaDoiSoatCOD
                AND x.MaDonHang=thu.MaDonHang
          );

        IF EXISTS (
            SELECT 1
            FROM dbo.ChiTietDoiSoatCOD ct
            LEFT JOIN dbo.ThuTienCOD thu
              ON thu.MaDonHang=ct.MaDonHang
             AND thu.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
             AND thu.TrangThaiThuTien IN ('COLLECTED','PARTIAL')
             AND thu.ThoiGianThuTien>=@TuThoiGian
             AND thu.ThoiGianThuTien<@DenThoiGian
            LEFT JOIN dbo.DonHang d ON d.MaDonHang=ct.MaDonHang
            WHERE ct.MaDoiSoatCOD=@MaDoiSoatCOD
              AND (thu.MaThuTienCOD IS NULL OR d.MaBuuCuc<>@MaBuuCuc)
        )
        BEGIN
            ;THROW 51184, N'Chi tiết đối soát chứa đơn không thuộc kỳ, shipper hoặc bưu cục của phiên đối soát.', 1;
        END;

        UPDATE ct
        SET ct.SoTienPhaiThu=thu.SoTienPhaiThu,
            ct.SoTienDaThu=thu.SoTienThucThu,
            ct.SoTienDaNop=ISNULL(nop.SoTienDaNop,0),
            ct.TrangThaiKetQua=
                CASE
                    WHEN ISNULL(nop.SoTienDaNop,0)=thu.SoTienThucThu THEN 'MATCHED'
                    WHEN ISNULL(nop.SoTienDaNop,0)<thu.SoTienThucThu THEN 'SHORT'
                    ELSE 'OVER'
                END
        FROM dbo.ChiTietDoiSoatCOD ct
        JOIN dbo.ThuTienCOD thu WITH (UPDLOCK,HOLDLOCK)
          ON thu.MaDonHang=ct.MaDonHang
         AND thu.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
        OUTER APPLY (
            SELECT SUM(cn.SoTienPhanBo) SoTienDaNop
            FROM dbo.ChiTietNopTienCOD cn
            JOIN dbo.NopTienCOD n ON n.MaNopTienCOD=cn.MaNopTienCOD
            WHERE cn.MaDonHang=ct.MaDonHang
              AND n.MaNhanVienGiaoHang=@MaNhanVienGiaoHang
              AND n.MaBuuCuc=@MaBuuCuc
              AND n.TrangThaiNop='CONFIRMED'
        ) nop
        WHERE ct.MaDoiSoatCOD=@MaDoiSoatCOD;

        SELECT @TongPhaiThu=ISNULL(SUM(SoTienPhaiThu),0),
               @TongDaThu=ISNULL(SUM(SoTienDaThu),0),
               @TongDaNop=ISNULL(SUM(SoTienDaNop),0)
        FROM dbo.ChiTietDoiSoatCOD
        WHERE MaDoiSoatCOD=@MaDoiSoatCOD;

        UPDATE dbo.DoiSoatCOD
        SET TongTienPhaiThu=@TongPhaiThu,
            TongTienDaThu=@TongDaThu,
            TongTienDaNop=@TongDaNop,
            TrangThaiDoiSoat=
                CASE WHEN @TongDaThu=@TongPhaiThu AND @TongDaNop=@TongDaThu
                     THEN 'CONFIRMED' ELSE 'DIFFERENCE' END,
            MaTaiKhoanXacNhan=@MaTaiKhoanXacNhan,
            ThoiGianXacNhan=SYSUTCDATETIME()
        WHERE MaDoiSoatCOD=@MaDoiSoatCOD;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        ;THROW;
    END CATCH;
END;
GO

-- Procedure bảo trì: xóa lịch sử GPS cũ theo lô; nên chạy bằng job/scheduler định kỳ.
CREATE OR ALTER PROCEDURE dbo.sp_DonDepLichSuViTriNhanVienGiaoHang
    @SoNgayLuu INT = 30,
    @KichThuocLo INT = 10000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SoNgayLuu < 1
    BEGIN
        ;THROW 51160, N'Số ngày lưu dữ liệu GPS phải lớn hơn hoặc bằng 1.', 1;
    END;
    
    IF @KichThuocLo < 100 OR @KichThuocLo > 100000
    BEGIN
        ;THROW 51161, N'Kích thước lô phải nằm trong khoảng 100 đến 100000.', 1;
    END;

    DECLARE @MocThoiGian DATETIME2(0) = DATEADD(DAY, -@SoNgayLuu, SYSUTCDATETIME());
    DECLARE @SoDongXoa INT = 1;

    WHILE @SoDongXoa > 0
    BEGIN
        DELETE TOP (@KichThuocLo)
        FROM dbo.LichSuViTriNhanVienGiaoHang
        WHERE ThoiGianGhiNhan < @MocThoiGian;

        SET @SoDongXoa = @@ROWCOUNT;
    END;
END;
GO

/* =============================================================================
   BƯỚC 22. KIỂM TRA SAU KHI KHỞI TẠO
   Chạy các SELECT này sau cùng để xác nhận cấu trúc đã được tạo.
   ============================================================================= */
SELECT
    s.name AS TenSchema,
    t.name AS TenBang
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE s.name='dbo'
ORDER BY t.name;

SELECT COUNT(*) AS SoBang
FROM sys.tables
WHERE schema_id=SCHEMA_ID(N'dbo');

SELECT COUNT(*) AS SoKhoaNgoai
FROM sys.foreign_keys
WHERE parent_object_id IN (
    SELECT object_id FROM sys.tables WHERE schema_id=SCHEMA_ID(N'dbo')
);

SELECT COUNT(*) AS SoTrigger
FROM sys.triggers
WHERE parent_class_desc='OBJECT_OR_COLUMN';

SELECT COUNT(*) AS SoStoredProcedure
FROM sys.procedures
WHERE schema_id=SCHEMA_ID(N'dbo');

SELECT COUNT(*) AS SoView
FROM sys.views
WHERE schema_id=SCHEMA_ID(N'dbo');

SELECT name AS TenStoredProcedure
FROM sys.procedures
WHERE schema_id=SCHEMA_ID(N'dbo')
ORDER BY name;

SELECT name AS TenTrigger, OBJECT_NAME(parent_id) AS Bang
FROM sys.triggers
WHERE parent_class_desc='OBJECT_OR_COLUMN'
ORDER BY name;
GO