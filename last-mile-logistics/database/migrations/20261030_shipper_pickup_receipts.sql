SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'QLGiaoHangChangCuoi'
    THROW 55800,N'Sai database đích. Chọn database API đang dùng trước khi chạy.',1;
IF OBJECT_ID(N'dbo.ShipperPickupReceipt',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ShipperPickupReceipt (
        AssignmentId BIGINT NOT NULL CONSTRAINT PK_ShipperPickupReceipt PRIMARY KEY,
        OrderId BIGINT NOT NULL,
        HandoverId BIGINT NOT NULL,
        ShipperId BIGINT NOT NULL,
        WarehouseId INT NOT NULL,
        ConfirmedCode VARCHAR(50) NOT NULL,
        ParcelCondition VARCHAR(30) NULL,
        Notes NVARCHAR(500) NULL,
        Latitude DECIMAL(9,6) NULL,
        Longitude DECIMAL(10,6) NULL,
        AccuracyMeters DECIMAL(9,2) NULL,
        EvidencePath NVARCHAR(1000) NULL,
        ReceivedAt DATETIME2(0) NOT NULL,
        CONSTRAINT FK_PickupReceipt_Assignment FOREIGN KEY(AssignmentId) REFERENCES dbo.PhanCongGiaoHang(MaPhanCongGiaoHang),
        CONSTRAINT FK_PickupReceipt_Order FOREIGN KEY(OrderId) REFERENCES dbo.DonHang(MaDonHang),
        CONSTRAINT FK_PickupReceipt_Handover FOREIGN KEY(HandoverId) REFERENCES dbo.BanGiaoHang(MaBanGiao),
        CONSTRAINT FK_PickupReceipt_Shipper FOREIGN KEY(ShipperId) REFERENCES dbo.NhanVienGiaoHang(MaNhanVienGiaoHang),
        CONSTRAINT FK_PickupReceipt_Warehouse FOREIGN KEY(WarehouseId) REFERENCES dbo.Kho(MaKho),
        CONSTRAINT CK_PickupReceipt_Condition CHECK(ParcelCondition IS NULL OR ParcelCondition IN ('NORMAL','PREEXISTING_DAMAGE')),
        CONSTRAINT CK_PickupReceipt_Damage CHECK(ParcelCondition<>'PREEXISTING_DAMAGE' OR (NULLIF(LTRIM(RTRIM(Notes)),N'') IS NOT NULL AND EvidencePath IS NOT NULL)),
        CONSTRAINT CK_PickupReceipt_Gps CHECK((Latitude IS NULL AND Longitude IS NULL AND AccuracyMeters IS NULL) OR
            (Latitude IS NOT NULL AND Longitude IS NOT NULL AND Latitude BETWEEN -90 AND 90 AND Longitude BETWEEN -180 AND 180 AND (AccuracyMeters IS NULL OR AccuracyMeters BETWEEN 0 AND 100))),
        CONSTRAINT CK_PickupReceipt_WarehouseTime CHECK(ReceivedAt>='2000-01-01')
    );
END;

-- Kiểm tra riêng để chạy lại an toàn, kể cả khi bảng đã có nhưng thiếu index.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID(N'dbo.ShipperPickupReceipt',N'U')
      AND name=N'IX_PickupReceipt_Order'
)
    EXEC(N'CREATE INDEX IX_PickupReceipt_Order ON dbo.ShipperPickupReceipt(OrderId,ReceivedAt);');
