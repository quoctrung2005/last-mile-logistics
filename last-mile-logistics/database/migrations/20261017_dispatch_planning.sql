-- Additive migration. Run against the selected QLGiaoHangChangCuoi database; never recreates existing data.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF COL_LENGTH('dbo.Kho','ViDo') IS NULL
    ALTER TABLE dbo.Kho ADD ViDo DECIMAL(9,6) NULL;
IF COL_LENGTH('dbo.Kho','KinhDo') IS NULL
    ALTER TABLE dbo.Kho ADD KinhDo DECIMAL(10,6) NULL;
IF COL_LENGTH('dbo.Kho','NguonToaDo') IS NULL
    ALTER TABLE dbo.Kho ADD NguonToaDo NVARCHAR(300) NULL;
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_Kho_DepotCoordinates')
    EXEC(N'ALTER TABLE dbo.Kho ADD CONSTRAINT CK_Kho_DepotCoordinates CHECK
        ((ViDo IS NULL AND KinhDo IS NULL) OR (ViDo IS NOT NULL AND KinhDo IS NOT NULL AND ViDo BETWEEN -90 AND 90 AND KinhDo BETWEEN -180 AND 180))');
IF OBJECT_ID('dbo.DispatchRoutePlan','U') IS NULL
BEGIN
    CREATE TABLE dbo.DispatchRoutePlan(
        Id UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_DispatchRoutePlan PRIMARY KEY,
        AccountId BIGINT NOT NULL REFERENCES dbo.TaiKhoan(MaTaiKhoan),
        WarehouseId INT NOT NULL REFERENCES dbo.Kho(MaKho),
        RequestJson NVARCHAR(MAX) NOT NULL CHECK(ISJSON(RequestJson)=1),
        SnapshotHash CHAR(64) NOT NULL,
        GraphVersion VARCHAR(64) NOT NULL,
        ResultJson NVARCHAR(MAX) NOT NULL CHECK(ISJSON(ResultJson)=1),
        ExpiresAt DATETIME2(0) NOT NULL,
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        ConfirmedJson NVARCHAR(MAX) NULL CHECK(ConfirmedJson IS NULL OR ISJSON(ConfirmedJson)=1)
    );
    CREATE INDEX IX_DispatchRoutePlan_Expiry ON dbo.DispatchRoutePlan(ExpiresAt);
END;
IF OBJECT_ID('dbo.TripRouteGeometry','U') IS NULL
    CREATE TABLE dbo.TripRouteGeometry(
        TripId BIGINT NOT NULL CONSTRAINT PK_TripRouteGeometry PRIMARY KEY REFERENCES dbo.ChuyenGiaoHang(MaChuyenGiao),
        GraphVersion VARCHAR(64) NOT NULL,
        RouteJson NVARCHAR(MAX) NOT NULL CHECK(ISJSON(RouteJson)=1),
        SettingsJson NVARCHAR(MAX) NOT NULL CHECK(ISJSON(SettingsJson)=1)
    );
COMMIT;
GO
