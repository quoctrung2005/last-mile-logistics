namespace LastMile.Api.Services;

internal static class DeliverySuccessSql
{
    public const string Scope = """

                SET NOCOUNT ON; SET XACT_ABORT ON;
                DECLARE @Now DATETIME2(0)=SYSUTCDATETIME(),@Role VARCHAR(50),@RoleId INT,
                    @AccountBranchId INT,@ShipperId BIGINT,@OrderStatus VARCHAR(40),
                    @ExpectedCod DECIMAL(18,2),@AssignmentId BIGINT,@ExistingReceipt NVARCHAR(MAX);
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
                    THROW 51801,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF @Role <> 'SHIPPER'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vtq
                       INNER JOIN dbo.Quyen q
                           ON q.MaQuyen = vtq.MaQuyen
                       WHERE vtq.MaVaiTro = @RoleId
                         AND q.KyHieuQuyen = @Permission
                   )
                    THROW 51802,
                        N'API này dành cho shipper ghi nhận kết quả giao hàng.',
                        1;

                SELECT @ShipperId = MaNhanVienGiaoHang
                FROM dbo.NhanVienGiaoHang
                WHERE MaTaiKhoan = @AccountId
                  AND DangHoatDong = 1;

                IF @ShipperId IS NULL
                    THROW 51802,
                        N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                        1;


                IF NOT EXISTS (SELECT 1 FROM dbo.BuuCuc WHERE MaBuuCuc=@AccountBranchId AND DangHoatDong=1)
                    THROW 51802, N'Bưu cục của tài xế không còn hoạt động.', 1;

                SELECT @OrderStatus=tt.KyHieuTrangThai,@ExpectedCod=d.TienCOD
                FROM dbo.DonHang d WITH(UPDLOCK,HOLDLOCK)
                JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
                WHERE d.MaDonHang=@OrderId AND d.MaBuuCuc=@AccountBranchId;
                SELECT @AssignmentId=pc.MaPhanCongGiaoHang
                FROM dbo.PhanCongGiaoHang pc WITH(UPDLOCK,HOLDLOCK)
                WHERE pc.MaDonHang=@OrderId AND pc.MaNhanVienGiaoHang=@ShipperId
                  AND (@ExpectedAssignment IS NULL OR pc.MaPhanCongGiaoHang=@ExpectedAssignment)
                  AND NOT EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang newer
                    WHERE newer.MaDonHang=pc.MaDonHang AND newer.MaPhanCongGiaoHang>pc.MaPhanCongGiaoHang);
                IF @OrderStatus IS NULL OR @AssignmentId IS NULL
                    THROW 51803,N'Không tìm thấy nhiệm vụ hiện tại của bạn.',1;
                IF @ExpectedAssignment IS NOT NULL AND @OrderStatus='DELIVERED'
                    SELECT TOP(1) @ExistingReceipt=JSON_MODIFY(
                        JSON_MODIFY(log.DuLieuMoiJson,'$.alreadyDelivered',CAST(1 AS BIT)),
                        '$.hasEvidence',CAST(CASE WHEN JSON_VALUE(log.DuLieuMoiJson,'$.evidenceType')='PHOTO' THEN 1 ELSE 0 END AS BIT))
                    FROM dbo.NhatKyHoatDong log
                    WHERE log.LoaiThaoTac='DELIVERY_SUCCESS' AND log.MaTaiKhoan=@AccountId
                      AND log.MaDoiTuong=CONVERT(VARCHAR(100),@OrderId)
                      AND JSON_VALUE(log.DuLieuMoiJson,'$.assignmentId')=CONVERT(VARCHAR(30),@AssignmentId)
                      AND EXISTS(SELECT 1 FROM dbo.LanGiaoHang lg WHERE lg.MaDonHang=@OrderId
                        AND lg.MaPhanCongGiaoHang=@AssignmentId AND lg.KetQua='SUCCESS')
                    ORDER BY log.MaNhatKy DESC;

        """;
    public static string Write => Scope + $$"""

                IF @ExistingReceipt IS NOT NULL BEGIN SELECT @ExistingReceipt AS Result; RETURN; END;
                IF @OrderStatus<>'IN_DELIVERY' OR NOT EXISTS (
                    SELECT 1 FROM dbo.PhanCongGiaoHang pc
                    WHERE pc.MaPhanCongGiaoHang=@AssignmentId AND pc.TrangThaiPhanCong='IN_PROGRESS'
                      AND pc.ThoiGianKetThuc IS NULL
                      AND (pc.MaChuyenGiao IS NULL OR EXISTS(SELECT 1 FROM dbo.ChuyenGiaoHang trip
                        WHERE trip.MaChuyenGiao=pc.MaChuyenGiao AND trip.MaNhanVienGiaoHang=@ShipperId
                          AND trip.MaPhuongTien=pc.MaPhuongTien AND trip.TrangThaiChuyen='IN_PROGRESS')))
                    THROW 51804,N'Nhiệm vụ không còn ở bước giao hàng hiện tại. Hãy tải lại.',1;
                DECLARE @DeliveryAttemptId BIGINT,@EvidenceId BIGINT,@OldJson NVARCHAR(MAX),@Result NVARCHAR(MAX);
                IF @ActualCodAmount <> @ExpectedCod
                    THROW 51805,
                        N'Số tiền COD thực thu phải bằng đúng tiền COD của đơn. Đơn không COD nhập 0.',
                        1;

                SET @OldJson = (
                    SELECT
                        @OrderId AS orderId,
                        @AssignmentId AS assignmentId,
                        @OrderStatus AS orderStatus,
                        @ExpectedCod AS codAmount
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                -- Procedure tạo lần giao, bằng chứng, COD,
                -- đổi trạng thái đơn và kết thúc phân công.
                EXEC dbo.sp_XacNhanGiaoHangThanhCong
                    @MaDonHang = @OrderId,
                    @MaNhanVienGiaoHang = @ShipperId,
                    @MaTaiKhoan = @AccountId,
                    @LoaiBangChung = @EvidenceType,
                    @DuongDanTep = @EvidencePath,
                    @MaXacNhanBam = NULL,
                    @TenNguoiNhan = @ReceiverName,
                    @ViDo = @Latitude,
                    @KinhDo = @Longitude,
                    @SoTienThucThu = @ActualCodAmount,
                    @GhiChuCOD = @CodNotes;
                
                UPDATE dbo.YeuCauGiaoLaiHoacHoan
                SET TrangThaiYeuCau = 'COMPLETED',
                    ThoiGianHoanTat = SYSUTCDATETIME()
                WHERE MaDonHang = @OrderId
                  AND LoaiYeuCau = 'RETRY'
                  AND TrangThaiYeuCau = 'IN_PROGRESS';

                SELECT @DeliveryAttemptId = MaLanGiaoHang
                FROM dbo.LanGiaoHang
                WHERE MaDonHang = @OrderId
                  AND MaPhanCongGiaoHang = @AssignmentId
                  AND KetQua = 'SUCCESS';

                UPDATE dbo.LanGiaoHang SET GhiChu=@Notes WHERE MaLanGiaoHang=@DeliveryAttemptId;

                SELECT TOP (1) @EvidenceId = MaBangChung
                FROM dbo.BangChungGiaoHang
                WHERE MaDonHang = @OrderId
                  AND MaLanGiaoHang = @DeliveryAttemptId
                ORDER BY MaBangChung DESC;

                {{DeferredReturnSql.Reconcile}}

                -- Ghi nhận thù lao tài xế vào dbo.ThuNhapTaiXe theo chiết khấu cước & loại phương tiện
                DECLARE @CommissionRate DECIMAL(5,2) = 80.00,
                        @MinWage DECIMAL(18,2) = 15000,
                        @VanAllowance DECIMAL(18,2) = 20000,
                        @TruckAllowance DECIMAL(18,2) = 50000,
                        @RetryBonus DECIMAL(18,2) = 5000;

                SELECT TOP 1 
                    @CommissionRate = COALESCE(TiLeChietKhauPhanTram, 80.00),
                    @MinWage = COALESCE(TienCongToiThieu, 15000),
                    @VanAllowance = COALESCE(PhuCapXeVan, 20000),
                    @TruckAllowance = COALESCE(PhuCapXeTai, 50000),
                    @RetryBonus = COALESCE(PhuCapGiaoLai, 5000)
                FROM dbo.CauHinhTienCong 
                WHERE DangHoatDong = 1 
                ORDER BY MaCauHinh DESC;

                DECLARE @OrderShippingFee DECIMAL(18,2) = 0,
                        @VehicleType VARCHAR(30) = NULL,
                        @CalculatedWage DECIMAL(18,2) = 0,
                        @VehicleExtra DECIMAL(18,2) = 0;

                SELECT 
                    @OrderShippingFee = COALESCE(d.PhiVanChuyen, 0),
                    @VehicleType = pt.LoaiXe
                FROM dbo.DonHang d
                LEFT JOIN dbo.PhanCongGiaoHang pc ON pc.MaPhanCongGiaoHang = @AssignmentId
                LEFT JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = pc.MaPhuongTien
                WHERE d.MaDonHang = @OrderId;

                IF @VehicleType IN ('VAN', 'XE_VAN', 'BA_GAC')
                    SET @VehicleExtra = @VanAllowance;
                ELSE IF @VehicleType IN ('TRUCK', 'TRUCK_LIGHT', 'TRUCK_HEAVY', 'XE_TAI')
                    SET @VehicleExtra = @TruckAllowance;
                ELSE
                    SET @VehicleExtra = 0;

                -- Tính thù lao: max(cước * % chiết khấu, thù lao tối thiểu) + phụ cấp xe
                IF @OrderShippingFee > 0 AND (@OrderShippingFee * (@CommissionRate / 100.0)) > @MinWage
                    SET @CalculatedWage = ROUND(@OrderShippingFee * (@CommissionRate / 100.0) + @VehicleExtra, 0);
                ELSE
                    SET @CalculatedWage = ROUND(@MinWage + @VehicleExtra, 0);

                IF NOT EXISTS (SELECT 1 FROM dbo.ThuNhapTaiXe WHERE MaDonHang = @OrderId AND LoaiThuNhap = 'DELIVERY_SUCCESS')
                BEGIN
                    INSERT INTO dbo.ThuNhapTaiXe (
                        MaNhanVienGiaoHang, MaDonHang, MaPhanCongGiaoHang, LoaiThuNhap, SoTien, CuocDonHang, TiLeChietKhau, TrangThai, ThoiGianGhiNhan, GhiChu
                    )
                    SELECT 
                        @ShipperId, @OrderId, @AssignmentId, 'DELIVERY_SUCCESS', @CalculatedWage, @OrderShippingFee, @CommissionRate, 'APPROVED', @Now,
                        N'Thù lao ' + CONVERT(VARCHAR(10), CAST(@CommissionRate AS INT)) + N'% cước đơn ' + d.KyHieuDonHang + 
                        N' (Cước: ' + FORMAT(@OrderShippingFee, 'N0', 'vi-VN') + N' đ)' + 
                        CASE WHEN @VehicleExtra > 0 THEN N' + Phụ cấp xe: ' + FORMAT(@VehicleExtra, 'N0', 'vi-VN') + N' đ' ELSE N'' END
                    FROM dbo.DonHang d WHERE d.MaDonHang = @OrderId;
                END;

                IF EXISTS (SELECT 1 FROM dbo.LanGiaoHang WHERE MaLanGiaoHang = @DeliveryAttemptId AND SoLanThu >= 2)
                   AND NOT EXISTS (SELECT 1 FROM dbo.ThuNhapTaiXe WHERE MaDonHang = @OrderId AND LoaiThuNhap = 'RETRY_BONUS')
                BEGIN
                    INSERT INTO dbo.ThuNhapTaiXe (
                        MaNhanVienGiaoHang, MaDonHang, MaPhanCongGiaoHang, LoaiThuNhap, SoTien, CuocDonHang, TiLeChietKhau, TrangThai, ThoiGianGhiNhan, GhiChu
                    )
                    SELECT 
                        @ShipperId, @OrderId, @AssignmentId, 'RETRY_BONUS', @RetryBonus, @OrderShippingFee, NULL, 'APPROVED', @Now,
                        N'Phụ cấp giao lại thành công đơn ' + d.KyHieuDonHang
                    FROM dbo.DonHang d WHERE d.MaDonHang = @OrderId;
                END;

                SET @Result = (
                    SELECT
                        d.MaDonHang AS orderId,
                        d.KyHieuDonHang AS orderCode,
                        d.MaVanDon AS trackingNumber,
                        @AssignmentId AS assignmentId,
                        @DeliveryAttemptId AS deliveryAttemptId,
                        @EvidenceId AS evidenceId,
                        @ShipperId AS shipperId,
                        @ReceiverName AS receiverName,
                        @EvidenceType AS evidenceType,
                        CAST(CASE WHEN @EvidencePath IS NULL THEN 0 ELSE 1 END AS BIT) AS hasEvidence,
                        CAST(0 AS BIT) AS alreadyDelivered,
                        tt.KyHieuTrangThai AS orderStatus,
                        pc.TrangThaiPhanCong AS assignmentStatus,
                        d.TienCOD AS codAmount,
                        @ActualCodAmount AS actualCodAmount,
                        CASE
                            WHEN d.TienCOD > 0 THEN 'COLLECTED'
                            ELSE 'NOT_REQUIRED'
                        END AS codStatus,
                        lg.ThoiGianThuGiao AS deliveredAt,
                        d.PhienBan AS version,
                        N'Đã ghi nhận giao hàng thành công.'
                            AS message
                    FROM dbo.DonHang d
                    INNER JOIN dbo.TrangThaiDonHang tt
                        ON tt.MaTrangThaiDonHang =
                           d.MaTrangThaiHienTai
                    INNER JOIN dbo.PhanCongGiaoHang pc
                        ON pc.MaPhanCongGiaoHang = @AssignmentId
                    INNER JOIN dbo.LanGiaoHang lg
                        ON lg.MaLanGiaoHang = @DeliveryAttemptId
                    WHERE d.MaDonHang = @OrderId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan,
                    LoaiThaoTac,
                    TenDoiTuong,
                    MaDoiTuong,
                    DuLieuCuJson,
                    DuLieuMoiJson
                )
                VALUES (
                    @AccountId,
                    'DELIVERY_SUCCESS',
                    'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    @OldJson,
                    @Result
                );


                SELECT @Result AS Result;
        """;
}
