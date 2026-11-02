-- REVIEW ONLY. Run the additive migration first if depot columns are missing.
-- No verified coordinates are available yet. Fill the four NULL inputs below
-- and set @CoordinatesConfirmed=1 ONLY after independent verification.
-- Never substitute sample, branch or device coordinates without confirmation.
SET XACT_ABORT ON;
DECLARE @ExpectedDatabase SYSNAME = N'QLGiaoHangChangCuoi';
DECLARE @WarehouseCode VARCHAR(30) = 'KHO-TP-PL';
DECLARE @Latitude DECIMAL(9,6) = NULL;
DECLARE @Longitude DECIMAL(10,6) = NULL;
DECLARE @Source NVARCHAR(300) = NULL;
DECLARE @AdminAccountId BIGINT = NULL;
DECLARE @CoordinatesConfirmed BIT = 0;
-- Original snapshot from the read-only diagnosis; review again if it changes.
DECLARE @ExpectedLatitude DECIMAL(9,6) = NULL;
DECLARE @ExpectedLongitude DECIMAL(10,6) = NULL;
DECLARE @ExpectedSource NVARCHAR(300) = NULL;
IF DB_NAME()<>@ExpectedDatabase THROW 54810,N'Sai database. Dừng và kiểm tra kết nối.',1;
IF COL_LENGTH('dbo.Kho','ViDo') IS NULL OR COL_LENGTH('dbo.Kho','KinhDo') IS NULL OR COL_LENGTH('dbo.Kho','NguonToaDo') IS NULL
    THROW 54810,N'Chưa có schema tọa độ kho. Xem migration 20261017_dispatch_planning.sql.',1;
IF @CoordinatesConfirmed<>1 OR @Latitude IS NULL OR @Longitude IS NULL OR NULLIF(LTRIM(RTRIM(@Source)),N'') IS NULL OR @AdminAccountId IS NULL
    THROW 54810,N'Cần tọa độ kho thực tế, nguồn xác minh, mã tài khoản admin và xác nhận trước khi chạy.',1;
IF @Latitude NOT BETWEEN -90 AND 90 OR @Longitude NOT BETWEEN -180 AND 180 OR (@Latitude=0 AND @Longitude=0)
    THROW 54810,N'Tọa độ kho không hợp lệ.',1;
BEGIN TRY
    BEGIN TRANSACTION;
    IF NOT EXISTS(SELECT 1 FROM dbo.TaiKhoan t WITH(HOLDLOCK)
      JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro JOIN dbo.VaiTroQuyen p ON p.MaVaiTro=v.MaVaiTro
      JOIN dbo.Quyen q ON q.MaQuyen=p.MaQuyen
      WHERE t.MaTaiKhoan=@AdminAccountId AND t.TrangThaiTaiKhoan='ACTIVE' AND v.DangHoatDong=1 AND v.KyHieuVaiTro='ADMIN' AND q.KyHieuQuyen='BUUCUC_QUANLY')
        THROW 54810,N'Cần tài khoản admin hoạt động có quyền quản lý bưu cục để ghi nhật ký.',1;
    DECLARE @Id INT,@Old NVARCHAR(MAX),@Lat DECIMAL(9,6),@Lon DECIMAL(10,6),@CurrentSource NVARCHAR(300);
    SELECT @Id=k.MaKho,@Lat=k.ViDo,@Lon=k.KinhDo,@CurrentSource=k.NguonToaDo,
      @Old=(SELECT k.MaKho id,k.ViDo latitude,k.KinhDo longitude,k.NguonToaDo coordinateSource FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER)
    FROM dbo.Kho k WITH(UPDLOCK,HOLDLOCK) JOIN dbo.BuuCuc b WITH(HOLDLOCK) ON b.MaBuuCuc=k.MaBuuCuc
    WHERE k.KyHieuKho=@WarehouseCode AND k.DangHoatDong=1 AND b.DangHoatDong=1;
    IF @Id IS NULL THROW 54810,N'Không tìm thấy kho hoạt động.',1;
    IF (@Lat<>@ExpectedLatitude OR (@Lat IS NULL AND @ExpectedLatitude IS NOT NULL) OR (@Lat IS NOT NULL AND @ExpectedLatitude IS NULL))
      OR (@Lon<>@ExpectedLongitude OR (@Lon IS NULL AND @ExpectedLongitude IS NOT NULL) OR (@Lon IS NOT NULL AND @ExpectedLongitude IS NULL))
      OR (@CurrentSource COLLATE Latin1_General_100_BIN2<>@ExpectedSource COLLATE Latin1_General_100_BIN2 OR (@CurrentSource IS NULL AND @ExpectedSource IS NOT NULL) OR (@CurrentSource IS NOT NULL AND @ExpectedSource IS NULL))
        THROW 54810,N'Tọa độ đã thay đổi sau chẩn đoán. Đọc lại dữ liệu trước khi cập nhật.',1;
    UPDATE dbo.Kho SET ViDo=@Latitude,KinhDo=@Longitude,NguonToaDo=LTRIM(RTRIM(@Source)) WHERE MaKho=@Id;
    INSERT dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuCuJson,DuLieuMoiJson)
    VALUES(@AdminAccountId,'UPDATE_WAREHOUSE_DEPOT','Kho',CONVERT(VARCHAR(100),@Id),@Old,
      (SELECT @Id id,@Latitude latitude,@Longitude longitude,LTRIM(RTRIM(@Source)) coordinateSource FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    COMMIT;
    SELECT MaKho,KyHieuKho,TenKho,ViDo,KinhDo,NguonToaDo FROM dbo.Kho WHERE MaKho=@Id;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    THROW;
END CATCH;
-- Then choose "Tải lại tọa độ kho" in Optimization and calculate a new proposal.
