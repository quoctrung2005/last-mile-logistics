/* Vị trí chờ xử lý cho đơn quá hạn được khách xác nhận hủy.
   Không tự hủy đơn, không giả lập cuộc gọi CSKH hoặc chuyển hàng.
*/
USE QLGiaoHangChangCuoi;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
BEGIN TRAN;
INSERT dbo.ViTriLuuKho(MaKho,KyHieuViTri,TenKhuLuu,MaKe,MaO,DangHoatDong)
SELECT k.MaKho,'CHO-XU-LY',N'Hàng chờ xử lý / khách hủy','HOLD','01',1
FROM dbo.Kho k WITH(UPDLOCK,HOLDLOCK)
WHERE k.DangHoatDong=1 AND NOT EXISTS(SELECT 1 FROM dbo.ViTriLuuKho v WHERE v.MaKho=k.MaKho AND v.KyHieuViTri='CHO-XU-LY');
COMMIT;
GO
