-- Run against the application database before deploying the session-aware API.
-- Existing access tokens (no sid) and refresh tokens (MaPhien IS NULL) require
-- a fresh login. Re-running this migration does not revoke newly issued sessions.
SET XACT_ABORT ON;
BEGIN TRAN;

IF OBJECT_ID(N'dbo.PhienDangNhap', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PhienDangNhap (
        MaPhien UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_PhienDangNhap PRIMARY KEY,
        MaTaiKhoan BIGINT NOT NULL,
        ThoiGianTao DATETIME2(0) NOT NULL,
        HetHanLuc DATETIME2(0) NOT NULL,
        ThuHoiLuc DATETIME2(0) NULL,
        CONSTRAINT UQ_PhienDangNhap_Phien_TaiKhoan UNIQUE (MaPhien, MaTaiKhoan),
        CONSTRAINT FK_PhienDangNhap_TaiKhoan FOREIGN KEY (MaTaiKhoan) REFERENCES dbo.TaiKhoan(MaTaiKhoan),
        CONSTRAINT CK_PhienDangNhap_Expiry CHECK (HetHanLuc > ThoiGianTao),
        CONSTRAINT CK_PhienDangNhap_ThuHoi CHECK (ThuHoiLuc IS NULL OR ThuHoiLuc >= ThoiGianTao)
    );
END;

IF COL_LENGTH(N'dbo.TokenLamMoi', N'MaPhien') IS NULL
    ALTER TABLE dbo.TokenLamMoi ADD MaPhien UNIQUEIDENTIFIER NULL;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_TokenLamMoi_PhienDangNhap')
    EXEC(N'ALTER TABLE dbo.TokenLamMoi WITH CHECK ADD CONSTRAINT FK_TokenLamMoi_PhienDangNhap
        FOREIGN KEY (MaPhien, MaTaiKhoan) REFERENCES dbo.PhienDangNhap(MaPhien, MaTaiKhoan);');

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.PhienDangNhap') AND name = N'IX_PhienDangNhap_TaiKhoan')
    CREATE INDEX IX_PhienDangNhap_TaiKhoan ON dbo.PhienDangNhap(MaTaiKhoan, MaPhien) INCLUDE (ThuHoiLuc, HetHanLuc);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.TokenLamMoi') AND name = N'IX_TokenLamMoi_Phien')
    EXEC(N'CREATE INDEX IX_TokenLamMoi_Phien ON dbo.TokenLamMoi(MaPhien, MaTaiKhoan) INCLUDE (ThuHoiLuc);');

COMMIT;
