-- Run explicitly in the application database BEFORE deploying these APIs.
-- This script is not executed by the application. Existing data is preserved.
-- Confirm the database below against the API's effective configuration first.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @ExpectedDatabase SYSNAME = N'QLGiaoHangChangCuoi';
IF DB_NAME() <> @ExpectedDatabase
    THROW 55300, N'Sai database đích. Chọn database API đang kết nối trước khi chạy migration.', 1;
BEGIN TRY
    BEGIN TRAN;
    IF OBJECT_ID(N'dbo.NhanVienGiaoHang', N'U') IS NULL
       OR OBJECT_ID(N'dbo.PhuongTien', N'U') IS NULL
        THROW 55301, N'Thiếu bảng shipper hoặc phương tiện. Hãy kiểm tra database đích.', 1;

    -- SQL Server permits one rowversion per table. Do not silently add a second
    -- version or rename an existing differently-named column used elsewhere.
    IF EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id IN (OBJECT_ID(N'dbo.NhanVienGiaoHang'), OBJECT_ID(N'dbo.PhuongTien'))
          AND system_type_id = 189 AND name <> N'PhienBan'
    )
        THROW 55303, N'Bảng đã có ROWVERSION mang tên khác. Cần đối chiếu schema, không tự thêm hoặc đổi tên cột.', 1;

    IF COL_LENGTH(N'dbo.NhanVienGiaoHang', N'PhienBan') IS NULL
        ALTER TABLE dbo.NhanVienGiaoHang ADD PhienBan ROWVERSION NOT NULL;
    IF COL_LENGTH(N'dbo.PhuongTien', N'PhienBan') IS NULL
        ALTER TABLE dbo.PhuongTien ADD PhienBan ROWVERSION NOT NULL;

    IF EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id IN (OBJECT_ID(N'dbo.NhanVienGiaoHang'), OBJECT_ID(N'dbo.PhuongTien'))
          AND name = N'PhienBan'
          AND (system_type_id <> 189 OR max_length <> 8 OR is_nullable <> 0)
    )
        THROW 55302, N'PhienBan phải là ROWVERSION 8 byte NOT NULL. Hãy kiểm tra schema.', 1;
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
END CATCH;

-- Metadata only: no same-batch compilation dependency on a newly-added column.
SELECT DB_NAME() AS databaseName, s.name AS schemaName, t.name AS tableName,
    c.name AS columnName, TYPE_NAME(c.system_type_id) AS typeName,
    c.max_length AS bytes, c.is_nullable AS nullable
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = N'dbo' AND t.name IN (N'NhanVienGiaoHang', N'PhuongTien')
  AND c.name = N'PhienBan';
