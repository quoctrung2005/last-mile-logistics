SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'QLGiaoHangChangCuoi'
    THROW 55900,N'Sai database đích. Chọn database API đang dùng trước khi chạy.',1;
IF OBJECT_ID(N'dbo.ShipperPickupIssue',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ShipperPickupIssue(
        IssueId BIGINT IDENTITY PRIMARY KEY,
        AssignmentId BIGINT NOT NULL REFERENCES dbo.PhanCongGiaoHang(MaPhanCongGiaoHang),
        OrderId BIGINT NOT NULL REFERENCES dbo.DonHang(MaDonHang),
        ShipperId BIGINT NOT NULL REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
        WarehouseId INT NOT NULL REFERENCES dbo.Kho(MaKho),
        BranchId INT NOT NULL REFERENCES dbo.BuuCuc(MaBuuCuc),
        Kind VARCHAR(30) NOT NULL CHECK(Kind IN('MISSING','WRONG_LABEL','DAMAGED','WAREHOUSE_UNAVAILABLE','OTHER')),
        Status VARCHAR(20) NOT NULL CHECK(Status IN('OPEN','NEED_MORE','RESOLVED')),
        Revision INT NOT NULL CHECK(Revision>0),
        ReportedAt DATETIME2(0) NOT NULL,
        ClosedAt DATETIME2(0) NULL,
        CONSTRAINT CK_PickupIssue_Closed CHECK((Status='RESOLVED' AND ClosedAt IS NOT NULL) OR (Status IN('OPEN','NEED_MORE') AND ClosedAt IS NULL))
    );
END;
IF OBJECT_ID(N'dbo.ShipperPickupIssueEvent',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ShipperPickupIssueEvent(
        EventId BIGINT IDENTITY PRIMARY KEY,
        IssueId BIGINT NOT NULL REFERENCES dbo.ShipperPickupIssue(IssueId),
        RequestId UNIQUEIDENTIFIER NOT NULL,
        EventType VARCHAR(20) NOT NULL CHECK(EventType IN('REPORT','SUPPLEMENT','REQUEST_INFO','RESOLVE')),
        AuthorAccountId BIGINT NOT NULL REFERENCES dbo.TaiKhoan(MaTaiKhoan),
        Notes NVARCHAR(500) NOT NULL CHECK(LEN(LTRIM(RTRIM(Notes))) BETWEEN 3 AND 500),
        EvidencePath NVARCHAR(1000) NULL,
        ResultStatus VARCHAR(20) NOT NULL CHECK(ResultStatus IN('OPEN','NEED_MORE','RESOLVED')),
        Revision INT NOT NULL CHECK(Revision>0),
        RecordedAt DATETIME2(0) NOT NULL,
        CONSTRAINT CK_PickupIssue_StaffPhoto CHECK(EventType IN('REPORT','SUPPLEMENT') OR EvidencePath IS NULL)
    );
END;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.ShipperPickupIssue') AND name=N'UX_PickupIssue_OpenOrder')
    EXEC(N'CREATE UNIQUE INDEX UX_PickupIssue_OpenOrder ON dbo.ShipperPickupIssue(OrderId) WHERE ClosedAt IS NULL;');
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.ShipperPickupIssue') AND name=N'IX_PickupIssue_Assignment')
    EXEC(N'CREATE INDEX IX_PickupIssue_Assignment ON dbo.ShipperPickupIssue(AssignmentId,IssueId);');
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.ShipperPickupIssueEvent') AND name=N'UX_PickupIssue_Request')
    EXEC(N'CREATE UNIQUE INDEX UX_PickupIssue_Request ON dbo.ShipperPickupIssueEvent(RequestId);');
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.ShipperPickupIssueEvent') AND name=N'UX_PickupIssue_EventRevision')
    EXEC(N'CREATE UNIQUE INDEX UX_PickupIssue_EventRevision ON dbo.ShipperPickupIssueEvent(IssueId,Revision);');
