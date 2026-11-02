namespace LastMile.Api.Services;

internal static class ShipperPickupSql
{
    private const string Scope = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;



                DECLARE
                    @Now DATETIME2(0) = SYSUTCDATETIME(),
                    @PickupReceiptJson NVARCHAR(MAX),
                    @OrderId BIGINT, @WarehouseId INT,
                    @TripId BIGINT, @TrackingNumber VARCHAR(50), @ExpectedCode VARCHAR(50),
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @AccountBranchId INT,
                    @OrderBranchId INT,
                    @OrderWarehouseId INT,
                    @OrderStatus VARCHAR(40),
                    @ShipperId BIGINT,
                    @VehicleId BIGINT,
                    @AssignmentStatus VARCHAR(20),
                    @AssignmentEndedAt DATETIME2(0),
                    @StockWarehouseId INT,
                    @LocationId BIGINT,
                    @StockStatus VARCHAR(20),
                    @MaxWeight DECIMAL(10,2),
                    @MaxVolume DECIMAL(10,3),
                    @TotalWeight DECIMAL(28,3),
                    @TotalVolume DECIMAL(28,6),
                    @MissingDimensions INT,
                    @TransactionId BIGINT,
                    @HandoverId BIGINT,
                    @TransactionCode VARCHAR(40),
                    @HandoverCode VARCHAR(40),
                    @OldJson NVARCHAR(MAX),
                    @NewJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @RoleId = tk.MaVaiTro,
                    @AccountBranchId = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk
                INNER JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @AccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= @Now
                  );

                IF @Role IS NULL
                    THROW 51501,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF @Role <> 'SHIPPER' OR @AccountBranchId IS NULL
                    THROW 51502, N'Chức năng này chỉ dành cho tài xế thuộc bưu cục.', 1;

                IF NOT EXISTS (SELECT 1 FROM dbo.BuuCuc WHERE MaBuuCuc = @AccountBranchId AND DangHoatDong = 1)
                    THROW 51502, N'Bưu cục của tài xế không còn hoạt động.', 1;

                IF NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen
                    WHERE vq.MaVaiTro=@RoleId AND q.KyHieuQuyen='NHIEMVU_CAPNHAT')
                    THROW 51502,N'Bạn không còn quyền xác nhận nhận kiện.',1;

                SELECT @OrderId = pc.MaDonHang
                FROM dbo.PhanCongGiaoHang pc
                JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang = pc.MaNhanVienGiaoHang
                WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                  AND nv.MaTaiKhoan = @AccountId AND nv.DangHoatDong = 1;
                IF @OrderId IS NULL
                    THROW 51503, N'Không tìm thấy nhiệm vụ của bạn.', 1;

                SELECT
                    @OrderBranchId = d.MaBuuCuc,
                    @OrderWarehouseId = d.MaKhoHienTai,
                    @WarehouseId = d.MaKhoHienTai,
                    @TrackingNumber = d.MaVanDon, @ExpectedCode = d.KyHieuDonHang,
                    @OrderStatus = tt.KyHieuTrangThai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (
                      @Role = 'ADMIN'
                      OR d.MaBuuCuc = @AccountBranchId
                  );

                IF @OrderBranchId IS NULL
                    THROW 51503,
                        N'Không tìm thấy đơn hàng.',
                        1;

                IF @ConfirmedCode NOT IN (@TrackingNumber, @ExpectedCode)
                    THROW 51504, N'Mã kiện không khớp với nhiệm vụ. Hãy kiểm tra lại nhãn kiện.', 1;
 """;
    public static string Preflight => Scope + "\nSELECT @OrderId;";
    public static string Write => Scope + "\n" + $$"""
                {{PickupReceiptSql.Load}}
                -- Replay is allowed only for this still-current assignment and an actual confirmed receipt.
                IF @OrderStatus = 'IN_DELIVERY' AND EXISTS (
                    SELECT 1 FROM dbo.PhanCongGiaoHang pc
                    JOIN dbo.ChiTietBanGiaoHang ct ON ct.MaDonHang = pc.MaDonHang
                    JOIN dbo.BanGiaoHang bg ON bg.MaBanGiao = ct.MaBanGiao
                    WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                      AND pc.ThoiGianKetThuc IS NULL AND pc.TrangThaiPhanCong = 'IN_PROGRESS'
                      AND bg.MaNhanVienGiaoHang = pc.MaNhanVienGiaoHang
                      AND bg.TrangThaiBanGiao = 'CONFIRMED'
                      AND bg.ThoiGianNhanVienXacNhan >= pc.ThoiGianChapNhan
                )
                BEGIN
                    SET @Result = (SELECT TOP(1) @OrderId AS orderId, @AssignmentId AS assignmentId,
                        pc.MaNhanVienGiaoHang AS shipperId, 'IN_DELIVERY' AS orderStatus,
                        'CONFIRMED' AS handoverStatus, bg.MaBanGiao AS handoverId,
                        JSON_QUERY(@PickupReceiptJson) AS pickupReceipt,
                        bg.ThoiGianNhanVienXacNhan AS handedOverAt, CAST(1 AS BIT) AS alreadyReceived
                        FROM dbo.PhanCongGiaoHang pc
                        JOIN dbo.ChiTietBanGiaoHang ct ON ct.MaDonHang = pc.MaDonHang
                        JOIN dbo.BanGiaoHang bg ON bg.MaBanGiao = ct.MaBanGiao
                        WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                          AND bg.MaNhanVienGiaoHang = pc.MaNhanVienGiaoHang AND bg.TrangThaiBanGiao = 'CONFIRMED'
                          AND bg.ThoiGianNhanVienXacNhan >= pc.ThoiGianChapNhan
                        ORDER BY bg.ThoiGianNhanVienXacNhan, bg.MaBanGiao
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    
                    SELECT @Result AS Result;
                    RETURN;
                END;

                IF (@ParcelCondition IS NOT NULL OR @Latitude IS NOT NULL OR @EvidencePath IS NOT NULL)
                    AND OBJECT_ID(N'dbo.ShipperPickupReceipt',N'U') IS NULL
                    THROW 55800,N'Chưa chạy migration 20261030_shipper_pickup_receipts.sql.',1;
                {{PickupIssueSql.AssertClear()}}
                IF @OrderStatus <> 'ASSIGNED'
                    THROW 51504, N'Đơn không còn chờ nhận tại kho. Hãy tải lại nhiệm vụ.', 1;

                IF @OrderWarehouseId IS NULL
                   OR @OrderWarehouseId <> @WarehouseId
                    THROW 51504,
                        N'Kho yêu cầu không khớp kho hiện tại của đơn.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.Kho k
                    INNER JOIN dbo.BuuCuc b
                        ON b.MaBuuCuc = k.MaBuuCuc
                    WHERE k.MaKho = @WarehouseId
                      AND k.MaBuuCuc = @OrderBranchId
                      AND k.DangHoatDong = 1
                      AND b.DangHoatDong = 1
                )
                    THROW 51504,
                        N'Kho hoặc bưu cục không còn hoạt động.',
                        1;

                SELECT
                    @ShipperId = pc.MaNhanVienGiaoHang,
                    @VehicleId = pc.MaPhuongTien,
                    @AssignmentStatus = pc.TrangThaiPhanCong,
                    @TripId = pc.MaChuyenGiao,
                    @AssignmentEndedAt = pc.ThoiGianKetThuc
                FROM dbo.PhanCongGiaoHang pc
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                  AND pc.MaDonHang = @OrderId;

                IF @ShipperId IS NULL
                    THROW 51503,
                        N'Không tìm thấy phân công của đơn.',
                        1;

                IF @AssignmentEndedAt IS NOT NULL
                   OR @AssignmentStatus <> 'ACCEPTED'
                    THROW 51504,
                        N'Shipper phải nhận nhiệm vụ trước khi xuất kho.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.NhanVienGiaoHang nv
                        WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.TaiKhoan tk
                        ON tk.MaTaiKhoan = nv.MaTaiKhoan
                    INNER JOIN dbo.VaiTro vt
                        ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE nv.MaNhanVienGiaoHang = @ShipperId
                      AND nv.DangHoatDong = 1
                      AND nv.TrangThaiSanSang IN (
                          'AVAILABLE', 'DELIVERING'
                      )
                      AND (
                          nv.NgayHetHanBangLai IS NULL
                          OR nv.NgayHetHanBangLai >= {{VietnamDate.SqlDate("@Now")}}
                      )
                      AND tk.MaBuuCuc = @OrderBranchId
                      AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                      AND (
                          tk.KhoaDenLuc IS NULL
                          OR tk.KhoaDenLuc <= @Now
                      )
                      AND vt.KyHieuVaiTro = 'SHIPPER'
                      AND vt.DangHoatDong = 1
                )
                    THROW 51504,
                        N'Shipper không còn đủ điều kiện nhận bàn giao.',
                        1;

                SELECT
                    @MaxWeight = KhoiLuongDenKg,
                    @MaxVolume = TheTichToiDaM3
                FROM dbo.PhuongTien WITH (UPDLOCK, HOLDLOCK)
                WHERE MaPhuongTien = @VehicleId
                  AND DangHoatDong = 1
                  AND TrangThaiPhuongTien IN ('AVAILABLE', 'IN_USE');

                IF @MaxWeight IS NULL
                    THROW 51504,
                        N'Phương tiện không còn phù hợp.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongPhuongTien
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaNhanVienGiaoHang = @ShipperId
                      AND MaPhuongTien = @VehicleId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 51504,
                        N'Phương tiện không còn được phân cho shipper.',
                        1;

                SELECT pc.MaDonHang INTO #PickupVehicleOrders
                FROM dbo.PhanCongGiaoHang pc WITH(UPDLOCK,HOLDLOCK)
                WHERE pc.MaPhuongTien=@VehicleId AND pc.ThoiGianKetThuc IS NULL;
                INSERT #PickupVehicleOrders(MaDonHang)
                SELECT held.MaDonHang FROM ({{DeferredReturnSql.HeldOrders(true)}}) held
                WHERE held.MaPhuongTien=@VehicleId AND NOT EXISTS(SELECT 1 FROM #PickupVehicleOrders x WHERE x.MaDonHang=held.MaDonHang);
                SELECT @TotalWeight = SUM(d.TongKhoiLuongKg)
                FROM #PickupVehicleOrders pc
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = pc.MaDonHang
                ;

                IF @TotalWeight > @MaxWeight
                    THROW 51504,
                        N'Các đơn đang phân công vượt tải trọng xe.',
                        1;

                IF @MaxVolume IS NOT NULL
                BEGIN
                    SELECT
                        @MissingDimensions = COALESCE(MAX(
                            CASE
                                WHEN ct.ChieuDaiCm IS NULL
                                  OR ct.ChieuRongCm IS NULL
                                  OR ct.ChieuCaoCm IS NULL
                                THEN 1 ELSE 0
                            END
                        ), 0),
                        @TotalVolume = COALESCE(SUM(
                            CAST(ct.SoLuong AS DECIMAL(18,6))
                            * ct.ChieuDaiCm
                            * ct.ChieuRongCm
                            * ct.ChieuCaoCm / 1000000.0
                        ), 0)
                    FROM #PickupVehicleOrders pc
                    LEFT JOIN dbo.ChiTietDonHang ct
                        ON ct.MaDonHang = pc.MaDonHang
                    ;

                    IF @MissingDimensions = 1
                       OR @TotalVolume > @MaxVolume
                        THROW 51504,
                            N'Không đủ dữ liệu kích thước hoặc hàng vượt thể tích xe.',
                            1;
                END;

                SELECT
                    @StockWarehouseId = t.MaKho,
                    @LocationId = t.MaViTriLuuKho,
                    @StockStatus = t.TrangThaiTonKho
                FROM dbo.TonKhoDonHang t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.MaDonHang = @OrderId;

                IF @StockWarehouseId IS NULL
                   OR @StockWarehouseId <> @WarehouseId
                   OR @StockStatus NOT IN ('STORED', 'ALLOCATED')
                   OR @LocationId IS NULL
                    THROW 51504,
                        N'Đơn không còn trong tồn kho phù hợp để xuất.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.ViTriLuuKho
                    WHERE MaViTriLuuKho = @LocationId
                      AND MaKho = @WarehouseId
                      AND DangHoatDong = 1
                )
                    THROW 51504,
                        N'Vị trí lưu kho không còn hoạt động.',
                        1;

                IF @TripId IS NOT NULL AND NOT EXISTS (
                    SELECT 1 FROM dbo.ChuyenGiaoHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaChuyenGiao = @TripId AND MaNhanVienGiaoHang = @ShipperId
                      AND MaPhuongTien = @VehicleId AND MaKho = @WarehouseId
                      AND TrangThaiChuyen IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS')
                      AND (ThoiGianBatDauDuKien IS NULL OR @Now >= ThoiGianBatDauDuKien)
                )
                    THROW 51504, N'Chuyến đã thay đổi hoặc chưa đến giờ xuất phát. Hãy liên hệ điều phối.', 1;

                SET @OldJson = (
                    SELECT
                        @OrderId AS orderId,
                        @OrderStatus AS orderStatus,
                        @WarehouseId AS warehouseId,
                        @LocationId AS locationId,
                        @StockStatus AS stockStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                SET @Now = SYSUTCDATETIME();

                SET @TransactionCode =
                    'XK-' + REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');

                SET @HandoverCode =
                    'BG-' + REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');

                INSERT INTO dbo.GiaoDichKho (
                    KyHieuGiaoDich, MaKho, LoaiGiaoDich,
                    TrangThaiGiaoDich, MaTaiKhoanThucHien,
                    ThoiGianThucHien, GhiChu
                )
                VALUES (
                    @TransactionCode, @WarehouseId, 'OUTBOUND',
                    'COMPLETED', @AccountId, @Now, @Notes
                );

                SET @TransactionId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.ChiTietGiaoDichKho (
                    MaGiaoDichKho, MaDonHang,
                    MaViTriNguon, MaViTriDich,
                    TinhTrangHang, GhiChu
                )
                VALUES (
                    @TransactionId, @OrderId,
                    @LocationId, NULL, 'NORMAL', @Notes
                );

                INSERT INTO dbo.BanGiaoHang (
                    KyHieuBanGiao, MaKho,
                    MaNhanVienGiaoHang, MaTaiKhoanBanGiao,
                    TrangThaiBanGiao, ThoiGianBanGiao, GhiChu
                )
                VALUES (
                    @HandoverCode, @WarehouseId,
                    @ShipperId, @AccountId,
                    'PENDING', @Now, @Notes
                );

                SET @HandoverId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                -- Phải thêm chi tiết bàn giao khi hàng còn trong kho
                -- để đáp ứng trigger kiểm tra bàn giao.
                -- Một dòng tương ứng một đơn được bàn giao.
                INSERT INTO dbo.ChiTietBanGiaoHang (
                    MaBanGiao, MaDonHang, SoLuong, GhiChuTinhTrang
                )
                VALUES (
                    @HandoverId, @OrderId, 1, @Notes
                );

                UPDATE dbo.TonKhoDonHang
                SET TrangThaiTonKho = 'HANDED_OVER',
                    MaViTriLuuKho = NULL,
                    ThoiGianDiChuyenCuoi = @Now,
                    MaTaiKhoanCapNhatCuoi = @AccountId
                WHERE MaDonHang = @OrderId;

                UPDATE dbo.DonHang
                SET MaKhoHienTai = NULL,
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = @Now
                WHERE MaDonHang = @OrderId;

                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'HANDED_OVER',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = @Notes,
                    @NguonCapNhat = 'API';

                UPDATE dbo.BanGiaoHang
                SET TrangThaiBanGiao = 'CONFIRMED', ThoiGianNhanVienXacNhan = @Now
                WHERE MaBanGiao = @HandoverId;
                UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong = 'IN_PROGRESS'
                WHERE MaPhanCongGiaoHang = @AssignmentId;
                EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'PICKED_UP', @MaTaiKhoan = @AccountId,
                    @LyDo = N'Tài xế kiểm tra và xác nhận nhận kiện.', @NguonCapNhat = 'MOBILE';
                EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'IN_DELIVERY', @MaTaiKhoan = @AccountId,
                    @LyDo = N'Tự bắt đầu giao sau khi nhận kiện.', @NguonCapNhat = 'MOBILE';
                UPDATE dbo.NhanVienGiaoHang SET TrangThaiSanSang = 'DELIVERING'
                WHERE MaNhanVienGiaoHang = @ShipperId;
                UPDATE dbo.PhuongTien SET TrangThaiPhuongTien = 'IN_USE'
                WHERE MaPhuongTien = @VehicleId;
                IF @TripId IS NOT NULL
                    UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen = 'IN_PROGRESS',
                        ThoiGianBatDauThucTe = COALESCE(ThoiGianBatDauThucTe, @Now)
                    WHERE MaChuyenGiao = @TripId;

                {{PickupReceiptSql.Save}}
                SET @PickupReceiptJson=NULL;
                {{PickupReceiptSql.Load}}
                SET @NewJson = (
                    SELECT
                        @OrderId AS orderId,
                        'IN_DELIVERY' AS orderStatus,
                        @TransactionId AS transactionId,
                        @HandoverId AS handoverId,
                        @ShipperId AS shipperId,
                        @AssignmentId AS assignmentId,
                        'CONFIRMED' AS handoverStatus,
                        JSON_QUERY(@PickupReceiptJson) AS pickupReceipt
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan, LoaiThaoTac,
                    TenDoiTuong, MaDoiTuong,
                    DuLieuCuJson, DuLieuMoiJson
                )
                VALUES (
                    @AccountId, 'SHIPPER_PICKUP',
                    'DonHang', CONVERT(VARCHAR(100), @OrderId),
                    @OldJson, @NewJson
                );

                SET @Result = (
                    SELECT
                        @TransactionId AS transactionId,
                        @TransactionCode AS transactionCode,
                        @HandoverId AS handoverId,
                        @HandoverCode AS handoverCode,
                        @OrderId AS orderId,
                        @WarehouseId AS warehouseId,
                        @AssignmentId AS assignmentId,
                        @ShipperId AS shipperId,
                        @VehicleId AS vehicleId,
                        'IN_DELIVERY' AS orderStatus,
                        'CONFIRMED' AS handoverStatus,
                        @Now AS handedOverAt,
                        CAST(0 AS BIT) AS alreadyReceived,
                        JSON_QUERY(@PickupReceiptJson) AS pickupReceipt,
                        N'Đã nhận kiện, xuất kho và bắt đầu giao.'
                            AS message
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );



                SELECT @Result AS Result;

 """;
}
