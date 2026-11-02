namespace LastMile.Api.Services;

internal static class PickupReceiptReadSql
{
    public const string Authorize = """
        SET NOCOUNT ON;
        DECLARE @Role VARCHAR(50),@RoleId INT,@Branch INT,@OwnShipper BIGINT;
        SELECT @Role=vt.KyHieuVaiTro,@RoleId=tk.MaVaiTro,@Branch=tk.MaBuuCuc
        FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro
        WHERE tk.MaTaiKhoan=@Account AND tk.TrangThaiTaiKhoan='ACTIVE' AND vt.DangHoatDong=1
          AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc<=SYSUTCDATETIME());
        IF @Role IS NULL THROW 55801,N'Tài khoản không còn hoạt động.',1;
        IF NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen
            WHERE vq.MaVaiTro=@RoleId AND ((@Role='SHIPPER' AND q.KyHieuQuyen='NHIEMVU_XEM')
              OR (@Role<>'SHIPPER' AND q.KyHieuQuyen IN ('DONHANG_XEM','KHO_XEM'))))
            THROW 55802,N'Bạn không có quyền xem biên nhận nhận kiện.',1;
        SELECT @OwnShipper=MaNhanVienGiaoHang FROM dbo.NhanVienGiaoHang
            WHERE MaTaiKhoan=@Account AND DangHoatDong=1;
        IF NOT EXISTS(SELECT 1 FROM dbo.DonHang d WHERE d.MaDonHang=@Order
            AND (@Role='ADMIN' OR (@Role<>'SHIPPER' AND d.MaBuuCuc=@Branch) OR
              (@Role='SHIPPER' AND d.MaBuuCuc=@Branch AND @OwnShipper IS NOT NULL
                AND EXISTS(SELECT 1 FROM dbo.BuuCuc b WHERE b.MaBuuCuc=@Branch AND b.DangHoatDong=1)
                AND EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang pc WHERE pc.MaDonHang=d.MaDonHang
                    AND pc.MaNhanVienGiaoHang=@OwnShipper AND (@Assignment IS NULL OR pc.MaPhanCongGiaoHang=@Assignment)))))
            THROW 55803,N'Không tìm thấy biên nhận trong phạm vi của bạn.',1;
        """;
    public static string Rows => $$"""
        SELECT {{PickupReceiptSql.Columns}} FROM dbo.ShipperPickupReceipt r
        JOIN dbo.Kho k ON k.MaKho=r.WarehouseId
        WHERE r.OrderId=@Order AND (@Assignment IS NULL OR r.AssignmentId=@Assignment)
          AND (@Role<>'SHIPPER' OR r.ShipperId=@OwnShipper)
        ORDER BY r.ReceivedAt DESC,r.AssignmentId DESC
        FOR JSON PATH,INCLUDE_NULL_VALUES;
        """;
}
