using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class OptimizeTripRequest
{
    [Range(1, 120)]
    public int AverageSpeedKmH { get; set; } = 25;

    [Range(0, 60)]
    public int ServiceMinutesPerStop { get; set; } = 5;

    public bool ReturnToBranch { get; set; } = true;
}

[ApiController]
[Authorize]
[Route("api/v1/trips")]
public class TripOptimizationController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public TripOptimizationController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{id:long}/optimize")]
    public async Task<IActionResult> Optimize(
        long id,
        OptimizeTripRequest request,
        CancellationToken cancellationToken)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã chuyến không hợp lệ." });

        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @AccountBranch INT,
                    @BranchId INT,
                    @TripStatus VARCHAR(20),
                    @ShipperId BIGINT,
                    @VehicleId BIGINT,
                    @StartLat DECIMAL(9,6),
                    @StartLng DECIMAL(10,6),
                    @StartTime DATETIME2(0),
                    @StartPoint GEOGRAPHY,
                    @CurrentPoint GEOGRAPHY,
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @RoleId = tk.MaVaiTro,
                    @AccountBranch = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @AccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @Role IS NULL
                    THROW 54101,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DIEUPHOI_TOIUUTUYEN'
                )
                    THROW 54102,
                        N'Bạn không có quyền tối ưu tuyến.', 1;

                SELECT
                    @BranchId = cg.MaBuuCuc,
                    @TripStatus = cg.TrangThaiChuyen,
                    @ShipperId = cg.MaNhanVienGiaoHang,
                    @VehicleId = cg.MaPhuongTien,
                    @StartTime = cg.ThoiGianBatDauDuKien
                FROM dbo.ChuyenGiaoHang cg WITH (UPDLOCK, HOLDLOCK)
                WHERE cg.MaChuyenGiao = @TripId;

                IF @TripStatus IS NULL
                    THROW 54103,
                        N'Không tìm thấy chuyến giao.', 1;

                IF @Role <> 'ADMIN'
                   AND (
                       @AccountBranch IS NULL
                       OR @AccountBranch <> @BranchId
                   )
                    THROW 54103,
                        N'Không tìm thấy chuyến giao.', 1;

                IF @TripStatus NOT IN (
                    'PLANNED', 'ASSIGNED', 'ACCEPTED'
                )
                    THROW 54104,
                        N'Chỉ được tối ưu chuyến chưa bắt đầu.', 1;

                SELECT
                    @StartLat = bc.ViDo,
                    @StartLng = bc.KinhDo
                FROM dbo.BuuCuc bc WITH (HOLDLOCK)
                WHERE bc.MaBuuCuc = @BranchId
                  AND bc.DangHoatDong = 1;

                IF @StartLat IS NULL OR @StartLng IS NULL
                    THROW 54105,
                        N'Bưu cục chưa có tọa độ hợp lệ.', 1;

                SELECT @OldJson = (
                    SELECT
                        cg.MaChuyenGiao AS id,
                        cg.PhuongPhapToiUu AS method,
                        cg.TongQuangDuongKm AS distanceKm,
                        cg.ThoiGianDuKienPhut AS durationMinutes,
                        JSON_QUERY((
                            SELECT
                                ct.MaDonHang AS orderId,
                                ct.ThuTuDuKien AS sequence
                            FROM dbo.ChiTietChuyenGiao ct
                            WHERE ct.MaChuyenGiao = @TripId
                            ORDER BY ct.ThuTuDuKien
                            FOR JSON PATH
                        )) AS orders
                    FROM dbo.ChuyenGiaoHang cg
                    WHERE cg.MaChuyenGiao = @TripId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                CREATE TABLE #Orders (
                    OrderId BIGINT NOT NULL PRIMARY KEY,
                    OrderStatus VARCHAR(30) NOT NULL
                );

                INSERT INTO #Orders (OrderId, OrderStatus)
                SELECT
                    d.MaDonHang,
                    tt.KyHieuTrangThai
                FROM dbo.ChiTietChuyenGiao ct WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                    ON d.MaDonHang = ct.MaDonHang
                JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE ct.MaChuyenGiao = @TripId;

                DECLARE @OrderCount INT = (
                    SELECT COUNT(*) FROM #Orders
                );

                IF @OrderCount < 1 OR @OrderCount > 100
                    THROW 54104,
                        N'Chuyến phải có từ 1 đến 100 đơn hàng.', 1;

                IF @TripStatus = 'PLANNED'
                BEGIN
                    IF EXISTS (
                        SELECT 1 FROM #Orders
                        WHERE OrderStatus <> 'WAITING_ASSIGNMENT'
                    )
                        THROW 54104,
                            N'Đơn của chuyến nháp phải ở WAITING_ASSIGNMENT.', 1;
                END
                ELSE
                BEGIN
                    IF EXISTS (
                        SELECT 1 FROM #Orders
                        WHERE OrderStatus <> 'ASSIGNED'
                    )
                        THROW 54104,
                            N'Không được tối ưu sau khi đã bàn giao hàng.', 1;
                END;

                SELECT
                    pc.MaDonHang AS OrderId,
                    pc.MaNhanVienGiaoHang AS ShipperId,
                    pc.MaPhuongTien AS VehicleId,
                    pc.TrangThaiPhanCong AS AssignmentStatus
                INTO #Assignments
                FROM dbo.PhanCongGiaoHang pc WITH (UPDLOCK, HOLDLOCK)
                JOIN #Orders o ON o.OrderId = pc.MaDonHang
                WHERE pc.MaChuyenGiao = @TripId
                  AND pc.ThoiGianKetThuc IS NULL;

                IF @TripStatus = 'PLANNED'
                BEGIN
                    IF EXISTS (
                        SELECT 1
                        FROM dbo.PhanCongGiaoHang pc
                            WITH (UPDLOCK, HOLDLOCK)
                        JOIN #Orders o ON o.OrderId = pc.MaDonHang
                        WHERE pc.ThoiGianKetThuc IS NULL
                    )
                        THROW 54104,
                            N'Đơn của chuyến nháp đã có phân công hoạt động.', 1;
                END
                ELSE
                BEGIN
                    IF @ShipperId IS NULL
                       OR @VehicleId IS NULL
                       OR (
                           SELECT COUNT(*) FROM #Assignments
                       ) <> @OrderCount
                       OR EXISTS (
                           SELECT 1 FROM #Assignments
                           WHERE ShipperId <> @ShipperId
                              OR VehicleId IS NULL
                              OR VehicleId <> @VehicleId
                              OR AssignmentStatus
                                  NOT IN ('PENDING', 'ACCEPTED')
                       )
                        THROW 54104,
                            N'Phân công của chuyến đã thay đổi. Hãy tải lại.', 1;
                END;

                CREATE TABLE #Points (
                    OrderId BIGINT NOT NULL PRIMARY KEY,
                    DeliveryPointId BIGINT NOT NULL,
                    Latitude DECIMAL(9,6) NULL,
                    Longitude DECIMAL(10,6) NULL,
                    GeoPoint GEOGRAPHY NULL,
                    Sequence INT NULL,
                    DistanceKm DECIMAL(10,2) NULL,
                    TravelMinutes INT NULL,
                    ArrivalAt DATETIME2(0) NULL
                );

                INSERT INTO #Points (
                    OrderId, DeliveryPointId, Latitude, Longitude
                )
                SELECT
                    gn.MaDonHang,
                    gn.MaDiemGiaoNhan,
                    gn.ViDo,
                    gn.KinhDo
                FROM dbo.DiemGiaoNhan gn WITH (HOLDLOCK)
                JOIN #Orders o ON o.OrderId = gn.MaDonHang
                WHERE gn.LoaiDiem = 'DELIVERY';

                IF (
                    SELECT COUNT(*) FROM #Points
                ) <> @OrderCount
                   OR EXISTS (
                       SELECT 1 FROM #Points
                       WHERE Latitude IS NULL OR Longitude IS NULL
                   )
                    THROW 54105,
                        N'Mỗi đơn phải có điểm giao với đầy đủ tọa độ.', 1;

                UPDATE #Points
                SET GeoPoint = geography::Point(
                    Latitude, Longitude, 4326
                );

                SET @StartPoint = geography::Point(
                    @StartLat, @StartLng, 4326
                );

                SET @CurrentPoint = @StartPoint;

                DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

                IF @StartTime IS NULL OR @StartTime < @Now
                    SET @StartTime = @Now;

                DECLARE
                    @Sequence INT = 0,
                    @NextOrderId BIGINT,
                    @NextPoint GEOGRAPHY,
                    @DistanceMeters FLOAT,
                    @TravelMinutes INT,
                    @ElapsedMinutes INT = 0,
                    @TotalMeters FLOAT = 0;

                -- Chọn điểm chưa thăm gần điểm hiện tại nhất.
                WHILE EXISTS (
                    SELECT 1 FROM #Points WHERE Sequence IS NULL
                )
                BEGIN
                    SELECT TOP (1)
                        @NextOrderId = OrderId,
                        @NextPoint = GeoPoint,
                        @DistanceMeters =
                            @CurrentPoint.STDistance(GeoPoint)
                    FROM #Points
                    WHERE Sequence IS NULL
                    ORDER BY
                        @CurrentPoint.STDistance(GeoPoint),
                        OrderId;

                    SET @Sequence += 1;

                    SET @TravelMinutes = CONVERT(
                        INT,
                        CEILING(
                            @DistanceMeters / 1000.0
                            / @Speed * 60.0
                        )
                    );

                    SET @ElapsedMinutes += @TravelMinutes;
                    SET @TotalMeters += @DistanceMeters;

                    UPDATE #Points
                    SET Sequence = @Sequence,
                        DistanceKm = CONVERT(
                            DECIMAL(10,2), @DistanceMeters / 1000.0
                        ),
                        TravelMinutes = @TravelMinutes,
                        ArrivalAt = DATEADD(
                            MINUTE, @ElapsedMinutes, @StartTime
                        )
                    WHERE OrderId = @NextOrderId;

                    SET @ElapsedMinutes += @ServiceMinutes;
                    SET @CurrentPoint = @NextPoint;
                END;

                DECLARE
                    @ReturnDistanceKm DECIMAL(10,2) = NULL,
                    @ReturnMinutes INT = NULL;

                IF @ReturnToBranch = 1
                BEGIN
                    SET @DistanceMeters =
                        @CurrentPoint.STDistance(@StartPoint);

                    SET @ReturnDistanceKm = CONVERT(
                        DECIMAL(10,2), @DistanceMeters / 1000.0
                    );

                    SET @ReturnMinutes = CONVERT(
                        INT,
                        CEILING(
                            @DistanceMeters / 1000.0
                            / @Speed * 60.0
                        )
                    );

                    SET @TotalMeters += @DistanceMeters;
                    SET @ElapsedMinutes += @ReturnMinutes;
                END;

                -- Đưa thứ tự cũ sang vùng tạm để tránh trùng
                -- unique index khi đổi thứ tự các đơn.
                DECLARE @Offset BIGINT = (
                    SELECT CONVERT(BIGINT, MAX(ThuTuDuKien))
                           + @OrderCount + 1
                    FROM dbo.ChiTietChuyenGiao
                    WHERE MaChuyenGiao = @TripId
                );

                IF @Offset + @OrderCount > 2147483647
                    THROW 54104,
                        N'Thứ tự hiện tại quá lớn để sắp xếp lại.', 1;

                UPDATE ct
                SET ThuTuDuKien = CONVERT(
                    INT, @Offset + p.Sequence
                )
                FROM dbo.ChiTietChuyenGiao ct
                JOIN #Points p ON p.OrderId = ct.MaDonHang
                WHERE ct.MaChuyenGiao = @TripId;

                UPDATE ct
                SET ThuTuDuKien = p.Sequence,
                    ThoiGianDenDuKien = p.ArrivalAt
                FROM dbo.ChiTietChuyenGiao ct
                JOIN #Points p ON p.OrderId = ct.MaDonHang
                WHERE ct.MaChuyenGiao = @TripId;

                DELETE FROM dbo.DiemDungTuyen
                WHERE MaChuyenGiao = @TripId;

                INSERT INTO dbo.DiemDungTuyen (
                    MaChuyenGiao,
                    ThuTuDiemDung,
                    LoaiDiem,
                    ViDo,
                    KinhDo,
                    ThoiGianDenDuKien,
                    KhoangCachTuDiemTruocKm,
                    ThoiGianTuDiemTruocPhut
                )
                VALUES (
                    @TripId, 1, 'BRANCH',
                    @StartLat, @StartLng, @StartTime, 0, 0
                );

                INSERT INTO dbo.DiemDungTuyen (
                    MaChuyenGiao,
                    MaDonHang,
                    MaDiemGiaoNhan,
                    ThuTuDiemDung,
                    LoaiDiem,
                    ViDo,
                    KinhDo,
                    ThoiGianDenDuKien,
                    KhoangCachTuDiemTruocKm,
                    ThoiGianTuDiemTruocPhut
                )
                SELECT
                    @TripId,
                    OrderId,
                    DeliveryPointId,
                    Sequence + 1,
                    'DELIVERY',
                    Latitude,
                    Longitude,
                    ArrivalAt,
                    DistanceKm,
                    TravelMinutes
                FROM #Points;

                IF @ReturnToBranch = 1
                BEGIN
                    INSERT INTO dbo.DiemDungTuyen (
                        MaChuyenGiao,
                        ThuTuDiemDung,
                        LoaiDiem,
                        ViDo,
                        KinhDo,
                        ThoiGianDenDuKien,
                        KhoangCachTuDiemTruocKm,
                        ThoiGianTuDiemTruocPhut
                    )
                    VALUES (
                        @TripId,
                        @OrderCount + 2,
                        'BRANCH',
                        @StartLat,
                        @StartLng,
                        DATEADD(
                            MINUTE, @ElapsedMinutes, @StartTime
                        ),
                        @ReturnDistanceKm,
                        @ReturnMinutes
                    );
                END;

                UPDATE dbo.ChuyenGiaoHang
                SET PhuongPhapToiUu = 'NEAREST_NEIGHBOR',
                    TongQuangDuongKm = CONVERT(
                        DECIMAL(10,2), @TotalMeters / 1000.0
                    ),
                    ThoiGianDuKienPhut = @ElapsedMinutes
                WHERE MaChuyenGiao = @TripId;

                SELECT @Result = (
                    SELECT
                        cg.MaChuyenGiao AS id,
                        cg.KyHieuChuyenGiao AS tripCode,
                        cg.TrangThaiChuyen AS status,
                        'NEAREST_NEIGHBOR' AS algorithm,
                        'GEOGRAPHIC_ESTIMATE' AS distanceSource,
                        cg.TongQuangDuongKm AS estimatedDistanceKm,
                        cg.ThoiGianDuKienPhut AS estimatedDurationMinutes,
                        @Speed AS averageSpeedKmH,
                        @ServiceMinutes AS serviceMinutesPerStop,
                        @ReturnToBranch AS returnToBranch,
                        @StartTime AS estimatedStartAt,
                        JSON_QUERY((
                            SELECT
                                p.OrderId AS orderId,
                                p.Sequence AS sequence,
                                p.DistanceKm AS distanceFromPreviousKm,
                                p.TravelMinutes AS travelMinutes,
                                p.ArrivalAt AS estimatedArrivalAt
                            FROM #Points p
                            ORDER BY p.Sequence
                            FOR JSON PATH
                        )) AS orders,
                        N'Đã sắp xếp tuyến theo điểm giao gần nhất.'
                            AS message
                    FROM dbo.ChuyenGiaoHang cg
                    WHERE cg.MaChuyenGiao = @TripId
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
                    'OPTIMIZE_TRIP',
                    'ChuyenGiaoHang',
                    CONVERT(VARCHAR(100), @TripId),
                    @OldJson,
                    @Result
                );

                COMMIT;
                SELECT @Result;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0
                    ROLLBACK;
                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@TripId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Speed", SqlDbType.Int).Value =
            request.AverageSpeedKmH;

        command.Parameters.Add(
            "@ServiceMinutes", SqlDbType.Int).Value =
            request.ServiceMinutesPerStop;

        command.Parameters.Add(
            "@ReturnToBranch", SqlDbType.Bit).Value =
            request.ReturnToBranch;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 54101)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54102)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54103)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54105)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (
            ex.Number >= 51000 && ex.Number <= 54104)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy tải lại và thử lại."
            });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627 or 547)
        {
            return Conflict(new
            {
                message = "Dữ liệu tuyến đã thay đổi hoặc không còn phù hợp. Hãy tải lại."
            });
        }
    }
}