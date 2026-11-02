namespace LastMile.Api.Services;

internal static class PickupReceiptSql
{
    public const string Columns = """
        r.AssignmentId assignmentId,r.OrderId orderId,r.HandoverId handoverId,
        r.ShipperId shipperId,r.WarehouseId warehouseId,k.TenKho warehouseName,
        r.ConfirmedCode confirmedCode,r.ParcelCondition parcelCondition,r.Notes notes,
        r.Latitude latitude,r.Longitude longitude,r.AccuracyMeters accuracyMeters,
        CONVERT(BIT,CASE WHEN r.EvidencePath IS NULL THEN 0 ELSE 1 END) hasEvidence,r.ReceivedAt receivedAt
        """;
    public static string Load => $$"""
        IF OBJECT_ID(N'dbo.ShipperPickupReceipt',N'U') IS NOT NULL
            EXEC sp_executesql N'SELECT @receipt=(SELECT {{Columns}} FROM dbo.ShipperPickupReceipt r
                JOIN dbo.Kho k ON k.MaKho=r.WarehouseId WHERE r.AssignmentId=@assignment
                FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);',
                N'@assignment BIGINT,@receipt NVARCHAR(MAX) OUTPUT',@AssignmentId,@PickupReceiptJson OUTPUT;
        """;
    public const string Save = """
        IF OBJECT_ID(N'dbo.ShipperPickupReceipt',N'U') IS NOT NULL
            EXEC sp_executesql N'INSERT dbo.ShipperPickupReceipt
                (AssignmentId,OrderId,HandoverId,ShipperId,WarehouseId,ConfirmedCode,ParcelCondition,Notes,Latitude,Longitude,AccuracyMeters,EvidencePath,ReceivedAt)
                VALUES(@assignment,@order,@handover,@shipper,@warehouse,@code,@condition,@notes,@lat,@lng,@accuracy,@photo,@received);',
                N'@assignment BIGINT,@order BIGINT,@handover BIGINT,@shipper BIGINT,@warehouse INT,@code VARCHAR(50),@condition VARCHAR(30),@notes NVARCHAR(500),@lat DECIMAL(9,6),@lng DECIMAL(10,6),@accuracy DECIMAL(9,2),@photo NVARCHAR(1000),@received DATETIME2(0)',
                @AssignmentId,@OrderId,@HandoverId,@ShipperId,@WarehouseId,@ConfirmedCode,@ParcelCondition,@Notes,@Latitude,@Longitude,@AccuracyMeters,@EvidencePath,@Now;
        """;
}
