-- Run in the application database before deploying version-aware customer APIs.
-- Adds independent rowversions; existing customer/address data is preserved.
SET XACT_ABORT ON;
BEGIN TRAN;
IF COL_LENGTH(N'dbo.KhachHang', N'PhienBan') IS NULL
    ALTER TABLE dbo.KhachHang ADD PhienBan ROWVERSION NOT NULL;
IF COL_LENGTH(N'dbo.DiaChiKhachHang', N'PhienBan') IS NULL
    ALTER TABLE dbo.DiaChiKhachHang ADD PhienBan ROWVERSION NOT NULL;
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id IN (OBJECT_ID(N'dbo.KhachHang'), OBJECT_ID(N'dbo.DiaChiKhachHang'))
      AND name = N'PhienBan' AND (system_type_id <> 189 OR max_length <> 8)
)
    THROW 54901, N'PhienBan phải là ROWVERSION 8 byte. Hãy kiểm tra schema trước khi triển khai.', 1;
COMMIT;
