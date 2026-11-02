-- Read-only SSMS verification. No DDL, application writes, procedures or tokens.
-- Select the API database QLGiaoHangChangCuoi before running this file.
SET NOCOUNT ON;
IF DB_NAME() <> N'QLGiaoHangChangCuoi'
    THROW 55300, N'Sai database đích. Chọn QLGiaoHangChangCuoi trước khi kiểm tra.', 1;

SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ServerName')) AS serverName,
       DB_NAME() AS databaseName;

SELECT N'dbo.' + expected.tableName AS tableName,
       CONVERT(bit, CASE WHEN t.object_id IS NOT NULL THEN 1 ELSE 0 END) AS tableExists,
       c.name AS versionColumn, TYPE_NAME(c.system_type_id) AS typeName,
       c.max_length AS bytes, c.is_nullable AS nullable,
       CONVERT(bit, CASE WHEN c.name = N'PhienBan' AND c.system_type_id = 189
                        AND c.max_length = 8 AND c.is_nullable = 0 THEN 1 ELSE 0 END) AS schemaReady
FROM (VALUES (N'NhanVienGiaoHang'), (N'PhuongTien')) expected(tableName)
LEFT JOIN sys.tables t ON t.name = expected.tableName AND t.schema_id = SCHEMA_ID(N'dbo')
LEFT JOIN sys.columns c ON c.object_id = t.object_id
    AND (c.name = N'PhienBan' OR c.system_type_id = 189)
ORDER BY expected.tableName, c.column_id;

-- Column inspection is metadata only, so missing PhienBan does not prevent this
-- script compiling. Existing differently-named rowversions are displayed too.
