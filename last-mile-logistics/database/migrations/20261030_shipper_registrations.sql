-- Additive migration. No existing account, vehicle, order or stock is changed.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'QLGiaoHangChangCuoi'
    THROW 57500, N'Sai database đích cho hồ sơ đăng ký tài xế.', 1;
BEGIN TRAN;
IF OBJECT_ID(N'dbo.ShipperRegistration',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ShipperRegistration (
        Id UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_ShipperRegistration PRIMARY KEY,
        TokenHash VARCHAR(64) NOT NULL,
        Username VARCHAR(100) NOT NULL, PasswordHash VARCHAR(255) NULL,
        FullName NVARCHAR(150) NOT NULL, Phone VARCHAR(20) NOT NULL, Email VARCHAR(150) NOT NULL,
        BirthDate DATE NULL, IdentityNumber VARCHAR(20) NOT NULL,
        LicenseNumber VARCHAR(50) NOT NULL, LicenseExpiresAt DATE NOT NULL,
        BranchId INT NOT NULL REFERENCES dbo.BuuCuc(MaBuuCuc),
        AreaId INT NOT NULL REFERENCES dbo.KhuVuc(MaKhuVuc),
        VehicleType VARCHAR(30) NOT NULL, LicensePlate NVARCHAR(20) NOT NULL,
        Status VARCHAR(20) NOT NULL CONSTRAINT DF_SR_Status DEFAULT 'PENDING',
        SubmittedAt DATETIME2(0) NOT NULL CONSTRAINT DF_SR_Submitted DEFAULT SYSUTCDATETIME(),
        UpdatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_SR_Updated DEFAULT SYSUTCDATETIME(),
        ReviewedAt DATETIME2(0) NULL, ReviewedBy BIGINT NULL REFERENCES dbo.TaiKhoan(MaTaiKhoan),
        ReviewReason NVARCHAR(500) NULL, ClosedAt DATETIME2(0) NULL,
        AccountId BIGINT NULL REFERENCES dbo.TaiKhoan(MaTaiKhoan),
        ShipperId BIGINT NULL REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
        Version ROWVERSION NOT NULL,
        CONSTRAINT CK_SR_Status CHECK(Status IN ('PENDING','NEEDS_INFO','APPROVED','REJECTED')),
        CONSTRAINT CK_SR_Closure CHECK((Status IN ('PENDING','NEEDS_INFO') AND ClosedAt IS NULL)
            OR (Status IN ('APPROVED','REJECTED') AND ClosedAt IS NOT NULL)),
        CONSTRAINT CK_SR_Vehicle CHECK(VehicleType IN ('MOTORBIKE','VAN','TRUCK'))
    );
    CREATE UNIQUE INDEX UX_SR_OpenUsername ON dbo.ShipperRegistration(Username) WHERE ClosedAt IS NULL;
    CREATE UNIQUE INDEX UX_SR_OpenPhone ON dbo.ShipperRegistration(Phone) WHERE ClosedAt IS NULL;
    CREATE UNIQUE INDEX UX_SR_OpenEmail ON dbo.ShipperRegistration(Email) WHERE ClosedAt IS NULL;
    CREATE UNIQUE INDEX UX_SR_OpenIdentity ON dbo.ShipperRegistration(IdentityNumber) WHERE ClosedAt IS NULL;
    CREATE INDEX IX_SR_Status_Submitted ON dbo.ShipperRegistration(Status,SubmittedAt DESC);
END;
IF OBJECT_ID(N'dbo.ShipperRegistrationDocument',N'U') IS NULL
    CREATE TABLE dbo.ShipperRegistrationDocument (
        RegistrationId UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.ShipperRegistration(Id),
        Kind VARCHAR(20) NOT NULL, ContentType VARCHAR(30) NOT NULL, Bytes VARBINARY(MAX) NOT NULL,
        CONSTRAINT PK_ShipperRegistrationDocument PRIMARY KEY(RegistrationId,Kind),
        CONSTRAINT CK_SRD_Kind CHECK(Kind IN ('IDENTITY_FRONT','IDENTITY_BACK','LICENSE','PORTRAIT')),
        CONSTRAINT CK_SRD_Size CHECK(DATALENGTH(Bytes)>0 AND DATALENGTH(Bytes)<=5242880)
    );
IF OBJECT_ID(N'dbo.ShipperRegistrationEvent',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ShipperRegistrationEvent (
        Id BIGINT IDENTITY PRIMARY KEY, RegistrationId UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.ShipperRegistration(Id),
        CommandId UNIQUEIDENTIFIER NULL, Status VARCHAR(20) NOT NULL,
        Reason NVARCHAR(500) NULL, ActorId BIGINT NULL REFERENCES dbo.TaiKhoan(MaTaiKhoan),
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE UNIQUE INDEX UX_SRE_Command ON dbo.ShipperRegistrationEvent(CommandId) WHERE CommandId IS NOT NULL;
END;
COMMIT;
