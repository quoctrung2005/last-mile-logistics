namespace LastMile.Api.Services;

// The read preview and the locked write must evaluate the same rules.
internal static class ShipperAvailabilitySql
{
    public static string Evaluate(bool locked)
    {
        var hint = locked ? "WITH (UPDLOCK, HOLDLOCK)" : "";
        return $$"""
            DECLARE @HasWork BIT = 0, @HasDeliveryWork BIT = 0,
                @ReadyBlockedReason NVARCHAR(300) = NULL,
                @StopBlockedReason NVARCHAR(300) = NULL, @PendingReturnCount INT=0;

            IF EXISTS (SELECT 1 FROM dbo.PhanCongGiaoHang {{hint}}
                WHERE MaNhanVienGiaoHang = @ShipperId AND ThoiGianKetThuc IS NULL)
                OR EXISTS (SELECT 1 FROM dbo.ChuyenGiaoHang c {{hint}}
                WHERE c.MaNhanVienGiaoHang = @ShipperId
                    AND c.TrangThaiChuyen IN ('ASSIGNED','ACCEPTED','IN_PROGRESS')
                    AND NOT ({{DeferredReturnSql.DeliveryFinishedTrip}}))
                SET @HasWork = 1;

            IF EXISTS (
                SELECT 1 FROM dbo.PhanCongGiaoHang pc {{hint}}
                JOIN dbo.DonHang d {{hint}} ON d.MaDonHang = pc.MaDonHang
                JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE pc.MaNhanVienGiaoHang = @ShipperId AND pc.ThoiGianKetThuc IS NULL
                  AND tt.KyHieuTrangThai IN ('HANDED_OVER','EN_ROUTE_PICKUP','PICKED_UP',
                      'IN_DELIVERY','FAILED','RETRY_WAITING'))
                OR EXISTS (SELECT 1 FROM dbo.ChuyenGiaoHang c {{hint}}
                WHERE c.MaNhanVienGiaoHang = @ShipperId AND c.TrangThaiChuyen = 'IN_PROGRESS'
                    AND NOT ({{DeferredReturnSql.DeliveryFinishedTrip}}))
                SET @HasDeliveryWork = 1;

            -- A return can remain the driver's responsibility after the assignment closes.
            SELECT @PendingReturnCount=COUNT(*) FROM ({{DeferredReturnSql.HeldOrders(locked)}}) held
                WHERE held.MaNhanVienGiaoHang=@ShipperId;
            IF @PendingReturnCount>0 SET @HasWork=1;

            IF NOT EXISTS (SELECT 1 FROM dbo.VaiTroQuyen vq
                JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @RoleId AND q.KyHieuQuyen = 'NHIEMVU_CAPNHAT')
            BEGIN
                SET @ReadyBlockedReason = N'Bạn chưa có quyền đổi trạng thái. Liên hệ quản trị viên.';
                SET @StopBlockedReason = @ReadyBlockedReason;
            END
            ELSE
            BEGIN
                IF @HasWork = 1
                    SET @StopBlockedReason = CASE WHEN @PendingReturnCount>0
                        THEN N'Bạn còn kiện hoàn chờ trả kho cuối ca. Có thể tiếp tục nhận chuyến mới; kho xác nhận nhận lại trước khi kết thúc ca.'
                        ELSE N'Bạn còn nhiệm vụ hoặc chuyến chưa kết thúc. Hoàn tất hoặc liên hệ điều phối trước khi chuyển ngoại tuyến.' END;
                IF @HasDeliveryWork = 1
                    SET @ReadyBlockedReason = N'Bạn còn hàng đang giao. Tiếp tục xử lý trong mục Nhiệm vụ.';
                ELSE IF EXISTS (SELECT 1 FROM dbo.NhanVienGiaoHang {{hint}}
                    WHERE MaNhanVienGiaoHang = @ShipperId
                        AND NgayHetHanBangLai < {{VietnamDate.SqlDate("SYSUTCDATETIME()")}})
                    SET @ReadyBlockedReason = N'Bằng lái đã hết hạn. Liên hệ quản lý cập nhật hồ sơ trước khi nhận việc.';
                ELSE IF NOT EXISTS (SELECT 1 FROM dbo.PhanCongPhuongTien pc {{hint}}
                    JOIN dbo.PhuongTien pt {{hint}} ON pt.MaPhuongTien = pc.MaPhuongTien
                    WHERE pc.MaNhanVienGiaoHang = @ShipperId AND pc.ThoiGianKetThuc IS NULL
                        AND pt.DangHoatDong = 1 AND pt.TrangThaiPhuongTien IN ('AVAILABLE','IN_USE'))
                    SET @ReadyBlockedReason = N'Chưa có phương tiện hoạt động được phân công. Liên hệ quản lý phương tiện.';
            END;
            """;
    }

    public const string Fields = """
        @HasWork AS hasActiveWork, @HasDeliveryWork AS hasDeliveryWork,
        @PendingReturnCount AS pendingReturnCount,
        CONVERT(BIT, CASE WHEN @ReadyBlockedReason IS NULL THEN 1 ELSE 0 END) AS canSetAvailable,
        CONVERT(BIT, CASE WHEN @StopBlockedReason IS NULL THEN 1 ELSE 0 END) AS canSetOffline,
        @ReadyBlockedReason AS availableBlockedReason, @StopBlockedReason AS stopBlockedReason
        """;
}
