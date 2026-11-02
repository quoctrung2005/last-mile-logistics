-- Migration: 20261031_incident_chat.sql
-- Kênh Chat trao đổi và xử lý sự cố giữa Shipper và Điều phối viên / Quản trị viên

IF OBJECT_ID('dbo.TinNhanSuCo', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TinNhanSuCo (
        MaTinNhan BIGINT IDENTITY(1,1) PRIMARY KEY,
        MaCanhBao BIGINT NULL,
        MaDonHang BIGINT NULL,
        MaChuyenGiao BIGINT NULL,
        MaTaiKhoanGui BIGINT NOT NULL,
        VaiTroNguoiGui VARCHAR(30) NOT NULL, -- 'SHIPPER', 'DISPATCHER', 'ADMIN', 'SYSTEM'
        TenNguoiGui NVARCHAR(100) NOT NULL,
        NoiDung NVARCHAR(2000) NOT NULL,
        HinhAnhMinhChung NVARCHAR(500) NULL,
        ThoiGianGui DATETIME2(0) NOT NULL CONSTRAINT DF_TinNhanSuCo_ThoiGianGui DEFAULT SYSUTCDATETIME(),
        DaDoc BIT NOT NULL CONSTRAINT DF_TinNhanSuCo_DaDoc DEFAULT 0,
        CONSTRAINT FK_TinNhanSuCo_CanhBao FOREIGN KEY (MaCanhBao) REFERENCES dbo.CanhBaoGiaoHang(MaCanhBao) ON DELETE SET NULL,
        CONSTRAINT FK_TinNhanSuCo_DonHang FOREIGN KEY (MaDonHang) REFERENCES dbo.DonHang(MaDonHang) ON DELETE SET NULL,
        CONSTRAINT FK_TinNhanSuCo_ChuyenGiao FOREIGN KEY (MaChuyenGiao) REFERENCES dbo.ChuyenGiaoHang(MaChuyenGiao) ON DELETE SET NULL,
        CONSTRAINT FK_TinNhanSuCo_TaiKhoan FOREIGN KEY (MaTaiKhoanGui) REFERENCES dbo.TaiKhoan(MaTaiKhoan)
    );

    CREATE INDEX IX_TinNhanSuCo_CanhBao ON dbo.TinNhanSuCo(MaCanhBao, ThoiGianGui);
    CREATE INDEX IX_TinNhanSuCo_DonHang ON dbo.TinNhanSuCo(MaDonHang, ThoiGianGui);
    CREATE INDEX IX_TinNhanSuCo_ChuyenGiao ON dbo.TinNhanSuCo(MaChuyenGiao, ThoiGianGui);
    CREATE INDEX IX_TinNhanSuCo_TaiKhoan ON dbo.TinNhanSuCo(MaTaiKhoanGui, ThoiGianGui);

    PRINT 'Đã tạo bảng dbo.TinNhanSuCo thành công.';
END
ELSE
BEGIN
    PRINT 'Bảng dbo.TinNhanSuCo đã tồn tại.';
END
GO
