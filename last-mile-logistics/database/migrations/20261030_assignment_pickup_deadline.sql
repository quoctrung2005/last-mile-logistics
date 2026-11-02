-- Additive; existing assignments keep an unknown pickup deadline.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'QLGiaoHangChangCuoi'
    THROW 55700,N'Sai database đích. Chọn database API đang dùng trước khi chạy.',1;
IF OBJECT_ID(N'dbo.PhanCongGiaoHang',N'U') IS NULL
    THROW 55700,N'Thiếu bảng phân công giao hàng.',1;
IF COL_LENGTH(N'dbo.PhanCongGiaoHang',N'HanDenLayHang') IS NULL
    ALTER TABLE dbo.PhanCongGiaoHang ADD HanDenLayHang DATETIME2(0) NULL;
