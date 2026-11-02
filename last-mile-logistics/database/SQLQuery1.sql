USE QLGiaoHangChangCuoi;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRAN;

    IF COL_LENGTH('dbo.NhanVienGiaoHang', 'PhienBan') IS NULL
        ALTER TABLE dbo.NhanVienGiaoHang
        ADD PhienBan ROWVERSION NOT NULL;

    IF COL_LENGTH('dbo.PhuongTien', 'PhienBan') IS NULL
        ALTER TABLE dbo.PhuongTien
        ADD PhienBan ROWVERSION NOT NULL;

    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
END CATCH;
GO

SELECT TOP (5) MaNhanVienGiaoHang, PhienBan
FROM dbo.NhanVienGiaoHang;

SELECT TOP (5) MaPhuongTien, PhienBan
FROM dbo.PhuongTien;