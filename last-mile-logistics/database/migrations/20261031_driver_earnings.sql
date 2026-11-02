-- Migration: Driver Earnings & Wage Rules (Module Tiền công & Ví thu nhập tài xế)
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'QLGiaoHangChangCuoi'
    THROW 55800, N'Sai database đích. Chọn QLGiaoHangChangCuoi trước khi chạy.', 1;

-- 1. Bảng Cấu hình tiền công tài xế
IF OBJECT_ID(N'dbo.CauHinhTienCong', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CauHinhTienCong (
        MaCauHinh INT IDENTITY(1,1) CONSTRAINT PK_CauHinhTienCong PRIMARY KEY,
        TenCauHinh NVARCHAR(100) NOT NULL,
        TienCongGiaoThanhCong DECIMAL(18,2) NOT NULL CONSTRAINT DF_CauHinh_GiaoThanhCong DEFAULT (15000),
        PhuCapGiaoLai DECIMAL(18,2) NOT NULL CONSTRAINT DF_CauHinh_PhuCapGiaoLai DEFAULT (5000),
        TienCongChuyenHoan DECIMAL(18,2) NOT NULL CONSTRAINT DF_CauHinh_ChuyenHoan DEFAULT (8000),
        DangHoatDong BIT NOT NULL CONSTRAINT DF_CauHinh_DangHoatDong DEFAULT (1),
        ThoiGianTao DATETIME2(0) NOT NULL CONSTRAINT DF_CauHinh_ThoiGianTao DEFAULT SYSUTCDATETIME()
    );

    INSERT INTO dbo.CauHinhTienCong (TenCauHinh, TienCongGiaoThanhCong, PhuCapGiaoLai, TienCongChuyenHoan, DangHoatDong)
    VALUES (N'Bảng thù lao giao hàng tiêu chuẩn', 15000, 5000, 8000, 1);
END;

-- 2. Bảng Thu nhập tài xế (Driver Earnings)
IF OBJECT_ID(N'dbo.ThuNhapTaiXe', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ThuNhapTaiXe (
        MaThuNhap BIGINT IDENTITY(1,1) CONSTRAINT PK_ThuNhapTaiXe PRIMARY KEY,
        MaNhanVienGiaoHang BIGINT NOT NULL CONSTRAINT FK_ThuNhap_NhanVien REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
        MaDonHang BIGINT NOT NULL CONSTRAINT FK_ThuNhap_DonHang REFERENCES dbo.DonHang(MaDonHang),
        MaPhanCongGiaoHang BIGINT NULL CONSTRAINT FK_ThuNhap_PhanCong REFERENCES dbo.PhanCongGiaoHang(MaPhanCongGiaoHang),
        LoaiThuNhap VARCHAR(30) NOT NULL, -- 'DELIVERY_SUCCESS', 'RETRY_BONUS', 'RETURN_COMPLETED', 'BONUS'
        SoTien DECIMAL(18,2) NOT NULL CONSTRAINT CK_ThuNhap_SoTien CHECK (SoTien > 0),
        TrangThai VARCHAR(20) NOT NULL CONSTRAINT DF_ThuNhap_TrangThai DEFAULT ('PENDING'), -- 'PENDING', 'APPROVED', 'PAID'
        KyDoiSoat VARCHAR(20) NULL,
        ThoiGianGhiNhan DATETIME2(0) NOT NULL CONSTRAINT DF_ThuNhap_ThoiGian DEFAULT SYSUTCDATETIME(),
        ThoiGianDuyet DATETIME2(0) NULL,
        ThoiGianThanhToan DATETIME2(0) NULL,
        GhiChu NVARCHAR(300) NULL,
        CONSTRAINT UQ_ThuNhap_DonHang_Loai UNIQUE (MaDonHang, LoaiThuNhap),
        CONSTRAINT CK_ThuNhap_Loai CHECK (LoaiThuNhap IN ('DELIVERY_SUCCESS', 'RETRY_BONUS', 'RETURN_COMPLETED', 'BONUS')),
        CONSTRAINT CK_ThuNhap_TrangThai CHECK (TrangThai IN ('PENDING', 'APPROVED', 'PAID'))
    );

    CREATE INDEX IX_ThuNhap_Shipper_Date 
    ON dbo.ThuNhapTaiXe(MaNhanVienGiaoHang, ThoiGianGhiNhan) 
    INCLUDE (SoTien, TrangThai, LoaiThuNhap);
END;

-- 3. Khởi tạo dữ liệu thu nhập cho các đơn đã giao thành công / hoàn tất trong quá khứ
-- Giao thành công: 15.000đ
INSERT INTO dbo.ThuNhapTaiXe (MaNhanVienGiaoHang, MaDonHang, MaPhanCongGiaoHang, LoaiThuNhap, SoTien, TrangThai, ThoiGianGhiNhan, GhiChu)
SELECT 
    pc.MaNhanVienGiaoHang,
    l.MaDonHang,
    l.MaPhanCongGiaoHang,
    'DELIVERY_SUCCESS',
    15000,
    'APPROVED',
    l.ThoiGianThuGiao,
    N'Thù lao giao hàng thành công đơn ' + d.KyHieuDonHang
FROM dbo.LanGiaoHang l
JOIN dbo.PhanCongGiaoHang pc ON pc.MaPhanCongGiaoHang = l.MaPhanCongGiaoHang
JOIN dbo.DonHang d ON d.MaDonHang = l.MaDonHang
WHERE l.KetQua = 'SUCCESS'
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ThuNhapTaiXe tn 
      WHERE tn.MaDonHang = l.MaDonHang AND tn.LoaiThuNhap = 'DELIVERY_SUCCESS'
  );

-- Phụ cấp giao lại lần 2+: 5.000đ
INSERT INTO dbo.ThuNhapTaiXe (MaNhanVienGiaoHang, MaDonHang, MaPhanCongGiaoHang, LoaiThuNhap, SoTien, TrangThai, ThoiGianGhiNhan, GhiChu)
SELECT 
    pc.MaNhanVienGiaoHang,
    l.MaDonHang,
    l.MaPhanCongGiaoHang,
    'RETRY_BONUS',
    5000,
    'APPROVED',
    l.ThoiGianThuGiao,
    N'Phụ cấp giao lại thành công (lần ' + CAST(l.SoLanThu AS NVARCHAR(10)) + N') đơn ' + d.KyHieuDonHang
FROM dbo.LanGiaoHang l
JOIN dbo.PhanCongGiaoHang pc ON pc.MaPhanCongGiaoHang = l.MaPhanCongGiaoHang
JOIN dbo.DonHang d ON d.MaDonHang = l.MaDonHang
WHERE l.KetQua = 'SUCCESS' AND l.SoLanThu >= 2
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ThuNhapTaiXe tn 
      WHERE tn.MaDonHang = l.MaDonHang AND tn.LoaiThuNhap = 'RETRY_BONUS'
  );

-- Chuyển hoàn về kho hoàn tất: 8.000đ
INSERT INTO dbo.ThuNhapTaiXe (MaNhanVienGiaoHang, MaDonHang, MaPhanCongGiaoHang, LoaiThuNhap, SoTien, TrangThai, ThoiGianGhiNhan, GhiChu)
SELECT 
    pc.MaNhanVienGiaoHang,
    y.MaDonHang,
    pc.MaPhanCongGiaoHang,
    'RETURN_COMPLETED',
    8000,
    'APPROVED',
    COALESCE(y.ThoiGianHoanTat, y.ThoiGianYeuCau, SYSUTCDATETIME()),
    N'Thù lao hoàn tất thủ tục trả hàng hoàn đơn ' + d.KyHieuDonHang
FROM dbo.YeuCauGiaoLaiHoacHoan y
JOIN dbo.DonHang d ON d.MaDonHang = y.MaDonHang
OUTER APPLY (
    SELECT TOP 1 p.MaNhanVienGiaoHang, p.MaPhanCongGiaoHang
    FROM dbo.PhanCongGiaoHang p
    WHERE p.MaDonHang = y.MaDonHang
    ORDER BY p.MaPhanCongGiaoHang DESC
) pc
WHERE y.LoaiYeuCau = 'RETURN' 
  AND y.TrangThaiYeuCau IN ('COMPLETED', 'APPROVED')
  AND pc.MaNhanVienGiaoHang IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ThuNhapTaiXe tn 
      WHERE tn.MaDonHang = y.MaDonHang AND tn.LoaiThuNhap = 'RETURN_COMPLETED'
  );
