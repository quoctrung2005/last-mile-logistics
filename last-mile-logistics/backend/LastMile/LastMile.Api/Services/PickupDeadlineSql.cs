namespace LastMile.Api.Services;

internal static class PickupDeadlineSql
{
    // Old databases remain readable until the additive migration is applied.
    public const string Read = "TRY_CONVERT(DATETIME2(0),JSON_VALUE((SELECT pc.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'$.HanDenLayHang'),126)";
    public const string SaveOnCreate = """
        IF @PickupDueAt IS NOT NULL
        BEGIN
            IF COL_LENGTH(N'dbo.PhanCongGiaoHang',N'HanDenLayHang') IS NULL
                THROW 55700,N'Chưa chạy migration 20261030_assignment_pickup_deadline.sql.',1;
            IF @PickupDueAt<=SYSUTCDATETIME() OR EXISTS(SELECT 1 FROM dbo.DonHang
                WHERE MaDonHang=@OrderId AND ThoiGianDuKienGiao IS NOT NULL AND ThoiGianDuKienGiao<@PickupDueAt)
                THROW 51204,N'Hạn đến lấy hàng phải trong tương lai và không sau hạn giao của đơn.',1;
            EXEC sp_executesql N'UPDATE dbo.PhanCongGiaoHang SET HanDenLayHang=@due WHERE MaPhanCongGiaoHang=@assignment;',
                N'@due DATETIME2(0),@assignment BIGINT',@PickupDueAt,@AssignmentId;
        END;
        """;
}
