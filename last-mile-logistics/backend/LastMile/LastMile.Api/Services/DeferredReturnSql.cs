namespace LastMile.Api.Services;

// A return parcel remains in the driver's custody/load, but does not keep the
// delivery trip open once all its delivery work has been resolved.
internal static class DeferredReturnSql
{
    // Alias c is the trip being evaluated. Empty/unstarted trips remain blocking.
    public const string DeliveryFinishedTrip = """
        c.TrangThaiChuyen = 'IN_PROGRESS'
        AND EXISTS (SELECT 1 FROM dbo.ChiTietChuyenGiao ct WHERE ct.MaChuyenGiao=c.MaChuyenGiao)
        AND NOT EXISTS (SELECT 1 FROM dbo.PhanCongGiaoHang pc
            WHERE pc.MaChuyenGiao=c.MaChuyenGiao AND pc.ThoiGianKetThuc IS NULL)
        AND NOT EXISTS (
            SELECT 1 FROM dbo.ChiTietChuyenGiao ct
            JOIN dbo.DonHang d ON d.MaDonHang=ct.MaDonHang
            JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
            WHERE ct.MaChuyenGiao=c.MaChuyenGiao
              AND NOT (tt.KyHieuTrangThai IN ('DELIVERED','RETURNED','COMPLETED','CANCELLED')
                OR (tt.KyHieuTrangThai='RETURNING' AND EXISTS (
                    SELECT 1 FROM dbo.YeuCauGiaoLaiHoacHoan yc WHERE yc.MaDonHang=d.MaDonHang
                      AND yc.LoaiYeuCau='RETURN' AND yc.TrangThaiYeuCau='IN_PROGRESS'))))
        AND NOT EXISTS (SELECT 1 FROM dbo.ChiTietChuyenGiao ct
            JOIN dbo.YeuCauGiaoLaiHoacHoan yc ON yc.MaDonHang=ct.MaDonHang
            WHERE ct.MaChuyenGiao=c.MaChuyenGiao AND yc.TrangThaiYeuCau IN ('PENDING','APPROVED','IN_PROGRESS')
              AND NOT (yc.LoaiYeuCau='RETURN' AND yc.TrangThaiYeuCau='IN_PROGRESS'))
        """;

    public static string HeldOrders(bool locked)
    {
        var hint=locked ? "WITH(UPDLOCK,HOLDLOCK)" : "";
        return $$"""
            SELECT d.MaDonHang, d.TongKhoiLuongKg, latest.MaNhanVienGiaoHang, latest.MaPhuongTien
            FROM dbo.DonHang d {{hint}}
            JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
            CROSS APPLY (SELECT TOP(1) pc.MaNhanVienGiaoHang,pc.MaPhuongTien,pc.TrangThaiPhanCong
                FROM dbo.PhanCongGiaoHang pc {{hint}} WHERE pc.MaDonHang=d.MaDonHang
                ORDER BY pc.MaPhanCongGiaoHang DESC) latest
            WHERE tt.KyHieuTrangThai='RETURNING' AND latest.TrangThaiPhanCong='ATTEMPT_FAILED'
              AND EXISTS (SELECT 1 FROM dbo.YeuCauGiaoLaiHoacHoan yc {{hint}}
                WHERE yc.MaDonHang=d.MaDonHang AND yc.LoaiYeuCau='RETURN' AND yc.TrangThaiYeuCau='IN_PROGRESS')
            """;
    }

    // Used inside the same transaction as the last successful delivery/return-start.
    public static string Reconcile => $$"""
        UPDATE c SET TrangThaiChuyen='COMPLETED', ThoiGianKetThucThucTe=SYSUTCDATETIME()
        FROM dbo.ChuyenGiaoHang c WITH(UPDLOCK,HOLDLOCK)
        WHERE c.MaNhanVienGiaoHang=@ShipperId AND ({{DeliveryFinishedTrip}});
        UPDATE nv SET TrangThaiSanSang='AVAILABLE'
        FROM dbo.NhanVienGiaoHang nv WITH(UPDLOCK,HOLDLOCK)
        WHERE nv.MaNhanVienGiaoHang=@ShipperId AND nv.TrangThaiSanSang='DELIVERING'
          AND NOT EXISTS (SELECT 1 FROM dbo.PhanCongGiaoHang pc WITH(UPDLOCK,HOLDLOCK)
              WHERE pc.MaNhanVienGiaoHang=@ShipperId AND pc.ThoiGianKetThuc IS NULL)
          AND NOT EXISTS (SELECT 1 FROM dbo.ChuyenGiaoHang c WITH(UPDLOCK,HOLDLOCK)
              WHERE c.MaNhanVienGiaoHang=@ShipperId AND c.TrangThaiChuyen NOT IN ('COMPLETED','CANCELLED'));
        """;
}
