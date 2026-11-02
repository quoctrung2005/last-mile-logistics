using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/reports")]
public class ReportsDashboardController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public ReportsDashboardController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("dashboard")]
    public async Task<IActionResult> Dashboard(
        [FromQuery] DateOnly? from = null,
        [FromQuery] DateOnly? to = null,

        [FromQuery]
        [Range(1, int.MaxValue)]
        int? branchId = null,

        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        // Ngày báo cáo theo giờ Việt Nam, UTC+7.
        var vietnamOffset = TimeSpan.FromHours(7);

        var today = DateOnly.FromDateTime(
            DateTimeOffset.UtcNow.ToOffset(vietnamOffset).DateTime);

        var minimumDate = new DateOnly(1900, 1, 1);
        var maximumDate = new DateOnly(9999, 12, 30);

        var toDate = to ?? today;

        // Kiểm tra trước khi gọi AddDays hoặc chuyển sang UTC.
        if (toDate < minimumDate || toDate > maximumDate)
        {
            return BadRequest(new
            {
                message = "Ngày to phải từ 1900-01-01 đến 9999-12-30."
            });
        }

        var defaultFromDate = toDate.AddDays(-29);

        if (defaultFromDate < minimumDate)
            defaultFromDate = minimumDate;

        var fromDate = from ?? defaultFromDate;

        if (fromDate < minimumDate || fromDate > maximumDate)
        {
            return BadRequest(new
            {
                message = "Ngày from phải từ 1900-01-01 đến 9999-12-30."
            });
        }

        if (fromDate > toDate)
        {
            return BadRequest(new
            {
                message = "Ngày from không được sau ngày to."
            });
        }

        if (toDate.DayNumber - fromDate.DayNumber > 365)
        {
            return BadRequest(new
            {
                message = "Mỗi lần xem báo cáo tối đa 366 ngày."
            });
        }

        var fromUtc = new DateTimeOffset(
            fromDate.ToDateTime(TimeOnly.MinValue),
            vietnamOffset).UtcDateTime;

        // Bao gồm toàn bộ ngày to.
        var toUtcExclusive = new DateTimeOffset(
            toDate.AddDays(1).ToDateTime(TimeOnly.MinValue),
            vietnamOffset).UtcDateTime;

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @ActorRole VARCHAR(50),
                @ActorRoleId INT,
                @ActorBranchId INT,
                @ScopeBranchId INT = @BranchId,
                @Result NVARCHAR(MAX);

            SELECT
                @ActorRole = vt.KyHieuVaiTro,
                @ActorRoleId = tk.MaVaiTro,
                @ActorBranchId = tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @ActorId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
              );

            IF @ActorRole IS NULL
                THROW 57401,
                    N'Tài khoản không còn hợp lệ.', 1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vq
                JOIN dbo.Quyen q
                    ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @ActorRoleId
                  AND q.KyHieuQuyen = 'BAOCAO_XEM'
            )
                THROW 57402,
                    N'Bạn không có quyền xem báo cáo.', 1;

            IF @ActorRole <> 'ADMIN'
            BEGIN
                IF @ActorBranchId IS NULL
                   OR (
                       @BranchId IS NOT NULL
                       AND @BranchId <> @ActorBranchId
                   )
                    THROW 57402,
                        N'Bạn chỉ được xem báo cáo của bưu cục mình.', 1;

                SET @ScopeBranchId = @ActorBranchId;
            END;

            IF @ScopeBranchId IS NOT NULL
               AND NOT EXISTS (
                   SELECT 1
                   FROM dbo.BuuCuc
                   WHERE MaBuuCuc = @ScopeBranchId
               )
                THROW 57403,
                    N'Không tìm thấy bưu cục.', 1;

            -- Toàn bộ đơn thuộc phạm vi được phép xem.
            SELECT
                d.MaDonHang AS OrderId,
                d.MaBuuCuc AS BranchId,
                d.ThoiGianTao AS CreatedAt,
                d.PhiVanChuyen AS ShippingFee,
                d.TienCOD AS CodAmount,
                tt.KyHieuTrangThai AS Status,
                tt.TenTrangThai AS StatusName
            INTO #ScopedOrders
            FROM dbo.DonHang d
            JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang =
                   d.MaTrangThaiHienTai
            WHERE @ScopeBranchId IS NULL
               OR d.MaBuuCuc = @ScopeBranchId;

            CREATE UNIQUE CLUSTERED INDEX IX_ScopedOrders
            ON #ScopedOrders(OrderId);

            -- Đơn được tạo trong kỳ báo cáo.
            SELECT *
            INTO #PeriodOrders
            FROM #ScopedOrders
            WHERE CreatedAt >= @FromUtc
              AND CreatedAt < @ToUtcExclusive;

            -- Các lần giao xảy ra trong kỳ.
            SELECT
                lg.MaLanGiaoHang AS AttemptId,
                lg.MaDonHang AS OrderId,
                lg.KetQua AS Result
            INTO #PeriodAttempts
            FROM dbo.LanGiaoHang lg
            JOIN #ScopedOrders d
                ON d.OrderId = lg.MaDonHang
            WHERE lg.ThoiGianThuGiao >= @FromUtc
              AND lg.ThoiGianThuGiao < @ToUtcExclusive;

            -- COD được ghi nhận thu trong kỳ.
            -- Tiền nộp được cộng theo phân bổ của chính các đơn này,
            -- không cộng trực tiếp cả phiếu nộp để tránh đếm trùng.
            SELECT
                c.MaDonHang AS OrderId,
                c.SoTienPhaiThu AS ExpectedAmount,
                c.SoTienThucThu AS CollectedAmount,
                ISNULL(p.ConfirmedAmount, 0) AS ConfirmedDepositAmount,
                ISNULL(p.PendingAmount, 0) AS PendingDepositAmount
            INTO #PeriodCod
            FROM dbo.ThuTienCOD c
            JOIN #ScopedOrders d
                ON d.OrderId = c.MaDonHang
            OUTER APPLY (
                SELECT
                    SUM(CASE
                        WHEN nt.TrangThaiNop = 'CONFIRMED'
                            THEN ct.SoTienPhanBo
                        ELSE 0
                    END) AS ConfirmedAmount,

                    SUM(CASE
                        WHEN nt.TrangThaiNop = 'PENDING'
                            THEN ct.SoTienPhanBo
                        ELSE 0
                    END) AS PendingAmount
                FROM dbo.ChiTietNopTienCOD ct
                JOIN dbo.NopTienCOD nt
                    ON nt.MaNopTienCOD = ct.MaNopTienCOD
                WHERE ct.MaDonHang = c.MaDonHang
            ) p
            WHERE c.TrangThaiThuTien <> 'REVERSED'
              AND c.ThoiGianThuTien >= @FromUtc
              AND c.ThoiGianThuTien < @ToUtcExclusive;

            -- Hàng thực tế đang nằm trong kho tại thời điểm xem.
            SELECT
                tk.MaDonHang AS OrderId,
                tk.TrangThaiTonKho AS Status
            INTO #Inventory
            FROM dbo.TonKhoDonHang tk
            JOIN dbo.Kho k
                ON k.MaKho = tk.MaKho
            WHERE (
                @ScopeBranchId IS NULL
                OR k.MaBuuCuc = @ScopeBranchId
            )
              AND tk.TrangThaiTonKho IN (
                  'RECEIVED', 'STORED', 'ALLOCATED', 'RETURNED'
              );

            -- Chuyến giao được tạo trong kỳ.
            SELECT
                MaChuyenGiao AS TripId,
                TrangThaiChuyen AS Status
            INTO #PeriodTrips
            FROM dbo.ChuyenGiaoHang
            WHERE (
                @ScopeBranchId IS NULL
                OR MaBuuCuc = @ScopeBranchId
            )
              AND ThoiGianTao >= @FromUtc
              AND ThoiGianTao < @ToUtcExclusive;

            -- Lịch đầy đủ, bao gồm ngày không có đơn.
            DECLARE @Days TABLE (
                ReportDate DATE NOT NULL PRIMARY KEY
            );

            DECLARE @Day DATE = @FromDate;

            WHILE @Day <= @ToDate
            BEGIN
                INSERT INTO @Days (ReportDate) VALUES (@Day);
                SET @Day = DATEADD(DAY, 1, @Day);
            END;

            SELECT @Result = (
                SELECT
                    @FromDate AS [from],
                    @ToDate AS [to],
                    'Asia/Ho_Chi_Minh' AS timeZone,
                    @ScopeBranchId AS branchId,
                    SYSUTCDATETIME() AS generatedAtUtc,

                    JSON_QUERY((
                        SELECT
                            COUNT_BIG(*) AS createdCount,
                            COUNT_BIG(CASE
                                WHEN Status = 'COMPLETED' THEN 1
                            END) AS completedCount,
                            COUNT_BIG(CASE
                                WHEN Status = 'CANCELLED' THEN 1
                            END) AS cancelledCount,

                            COALESCE(SUM(CASE
                                WHEN Status <> 'CANCELLED'
                                    THEN ShippingFee
                                ELSE 0
                            END), 0) AS recordedShippingFees

                        FROM #PeriodOrders
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )) AS orders,

                    JSON_QUERY((
                        SELECT
                            Status AS status,
                            StatusName AS statusName,
                            COUNT_BIG(*) AS orderCount
                        FROM #PeriodOrders
                        GROUP BY Status, StatusName
                        ORDER BY Status
                        FOR JSON PATH
                    )) AS ordersByStatus,

                    JSON_QUERY((
                        SELECT
                            COUNT_BIG(*) AS attemptCount,

                            COUNT_BIG(CASE
                                WHEN Result = 'SUCCESS' THEN 1
                            END) AS successfulAttemptCount,

                            COUNT_BIG(CASE
                                WHEN Result = 'FAILED' THEN 1
                            END) AS failedAttemptCount,

                            CONVERT(DECIMAL(5,2), COALESCE(
                                100.0 * COUNT_BIG(CASE
                                    WHEN Result = 'SUCCESS' THEN 1
                                END)
                                / NULLIF(COUNT_BIG(*), 0),
                                0
                            )) AS attemptSuccessRatePercent

                        FROM #PeriodAttempts
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )) AS delivery,

                    JSON_QUERY((
                        SELECT
                            COUNT_BIG(*) AS currentOrderCount,

                            COUNT_BIG(CASE
                                WHEN Status = 'RECEIVED' THEN 1
                            END) AS receivedCount,

                            COUNT_BIG(CASE
                                WHEN Status = 'STORED' THEN 1
                            END) AS storedCount,

                            COUNT_BIG(CASE
                                WHEN Status = 'ALLOCATED' THEN 1
                            END) AS allocatedCount,

                            COUNT_BIG(CASE
                                WHEN Status = 'RETURNED' THEN 1
                            END) AS returnedCount

                        FROM #Inventory
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )) AS inventory,

                    JSON_QUERY((
                        SELECT
                            COUNT_BIG(*) AS createdCount,

                            COUNT_BIG(CASE
                                WHEN Status = 'COMPLETED' THEN 1
                            END) AS completedCount,

                            COUNT_BIG(CASE
                                WHEN Status = 'CANCELLED' THEN 1
                            END) AS cancelledCount,

                            COUNT_BIG(CASE
                                WHEN Status NOT IN (
                                    'COMPLETED', 'CANCELLED'
                                ) THEN 1
                            END) AS openCount

                        FROM #PeriodTrips
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )) AS trips,

                    JSON_QUERY((
                        SELECT
                            COUNT_BIG(*) AS collectionCount,

                            COALESCE(SUM(ExpectedAmount), 0)
                                AS expectedAmount,

                            COALESCE(SUM(CollectedAmount), 0)
                                AS collectedAmount,

                            COALESCE(SUM(
                                ConfirmedDepositAmount
                            ), 0) AS confirmedDepositAmount,

                            COALESCE(SUM(
                                PendingDepositAmount
                            ), 0) AS pendingDepositAmount,

                            COALESCE(SUM(
                                CollectedAmount
                                - ConfirmedDepositAmount
                            ), 0) AS netBalanceAmount,

                            COALESCE(SUM(CASE
                                WHEN CollectedAmount
                                     > ConfirmedDepositAmount
                                THEN CollectedAmount
                                     - ConfirmedDepositAmount
                                ELSE 0
                            END), 0) AS outstandingAmount,

                            COALESCE(SUM(CASE
                                WHEN ConfirmedDepositAmount
                                     > CollectedAmount
                                THEN ConfirmedDepositAmount
                                     - CollectedAmount
                                ELSE 0
                            END), 0) AS overpaidAmount,

                            COALESCE(SUM(CASE
                                WHEN CollectedAmount
                                     > ConfirmedDepositAmount
                                       + PendingDepositAmount
                                THEN CollectedAmount
                                     - ConfirmedDepositAmount
                                     - PendingDepositAmount
                                ELSE 0
                            END), 0) AS availableToDepositAmount

                        FROM #PeriodCod
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )) AS cod,

                    JSON_QUERY((
                        SELECT
                            CONVERT(
                                VARCHAR(10), day.ReportDate, 23
                            ) AS [date],

                            COUNT_BIG(d.OrderId) AS createdOrderCount,

                            COALESCE(SUM(CASE
                                WHEN d.Status <> 'CANCELLED'
                                    THEN d.ShippingFee
                                ELSE 0
                            END), 0) AS recordedShippingFees

                        FROM @Days day
                        LEFT JOIN #PeriodOrders d
                            ON CONVERT(
                                DATE, DATEADD(HOUR, 7, d.CreatedAt)
                            ) = day.ReportDate
                        GROUP BY day.ReportDate
                        ORDER BY day.ReportDate
                        FOR JSON PATH
                    )) AS dailyOrders

                FOR JSON PATH,
                    INCLUDE_NULL_VALUES,
                    WITHOUT_ARRAY_WRAPPER
            );

            SELECT @Result;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = actorId;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
            (object?)branchId ?? DBNull.Value;

        command.Parameters.Add(
            "@FromDate", SqlDbType.Date).Value =
            fromDate.ToDateTime(TimeOnly.MinValue);

        command.Parameters.Add(
            "@ToDate", SqlDbType.Date).Value =
            toDate.ToDateTime(TimeOnly.MinValue);

        var fromParameter = command.Parameters.Add(
            "@FromUtc", SqlDbType.DateTime2);

        fromParameter.Scale = 0;
        fromParameter.Value = fromUtc;

        var toParameter = command.Parameters.Add(
            "@ToUtcExclusive", SqlDbType.DateTime2);

        toParameter.Scale = 0;
        toParameter.Value = toUtcExclusive;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 57401)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57402)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57403)
        {
            return NotFound(new { message = ex.Message });
        }
    }
}