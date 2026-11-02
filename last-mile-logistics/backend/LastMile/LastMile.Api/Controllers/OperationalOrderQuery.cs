namespace LastMile.Api.Controllers;

// Shared by operational totals and their destination list. Never filter these by creation date.
internal static class OperationalOrderQuery
{
    internal static readonly string[] Groups = ["waitingInbound", "inWarehouse", "waitingAssignment", "waitingHandover", "inDelivery", "failedNeedsAction", "overdue"];
    internal const string WaitingInbound = "tt.KyHieuTrangThai IN ('CONFIRMED','WAITING_INBOUND') AND d.MaKhoHienTai IS NULL AND NOT EXISTS(SELECT 1 FROM dbo.TonKhoDonHang stock WHERE stock.MaDonHang=d.MaDonHang)";
    internal const string WaitingAssignment = "tt.KyHieuTrangThai='WAITING_ASSIGNMENT'";
    internal const string InWarehouse = "tt.KyHieuTrangThai='IN_WAREHOUSE'";
    internal const string WaitingHandover = "tt.KyHieuTrangThai='ASSIGNED'";
    internal const string InDelivery = "tt.KyHieuTrangThai='IN_DELIVERY'";
    internal const string FailedNeedsAction = """
        tt.KyHieuTrangThai='FAILED' AND EXISTS(
            SELECT 1 FROM dbo.LanGiaoHang failed
            WHERE failed.MaDonHang=d.MaDonHang AND failed.KetQua='FAILED'
              AND NOT EXISTS(SELECT 1 FROM dbo.LanGiaoHang newer WHERE newer.MaDonHang=d.MaDonHang AND newer.SoLanThu>failed.SoLanThu)
              AND NOT EXISTS(SELECT 1 FROM dbo.YeuCauGiaoLaiHoacHoan resolution
                  WHERE resolution.MaDonHang=d.MaDonHang
                    AND (resolution.TrangThaiYeuCau IN ('PENDING','APPROVED','IN_PROGRESS')
                      OR (resolution.TrangThaiYeuCau='COMPLETED' AND resolution.ThoiGianYeuCau>=failed.ThoiGianThuGiao))))
        """;
    internal static string Overdue => $"d.ThoiGianDuKienGiao IS NOT NULL AND d.ThoiGianDuKienGiao<SYSUTCDATETIME() AND (tt.KyHieuTrangThai IN ('CONFIRMED','WAITING_INBOUND','IN_WAREHOUSE','WAITING_ASSIGNMENT','ASSIGNED','HANDED_OVER','EN_ROUTE_PICKUP','PICKED_UP','IN_DELIVERY','RETRY_WAITING') OR ({FailedNeedsAction}))";
    internal static string Predicate(string group) => group switch
    {
        "waitingInbound" => WaitingInbound, "inWarehouse" => InWarehouse, "waitingAssignment" => WaitingAssignment, "waitingHandover" => WaitingHandover,
        "inDelivery" => InDelivery, "failedNeedsAction" => FailedNeedsAction,
        "overdue" => Overdue,
        _ => throw new ArgumentOutOfRangeException(nameof(group))
    };
    internal static string FilterSql => "(@OperationalGroup IS NULL OR " + string.Join(" OR ", Groups.Select(g => $"(@OperationalGroup='{g}' AND ({Predicate(g)}))")) + ")";
}
