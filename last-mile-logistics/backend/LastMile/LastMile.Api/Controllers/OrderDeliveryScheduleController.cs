using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class UpdateOrderDeliveryScheduleRequest
{
    [Required, StringLength(16)]
    public string ExpectedVersion { get; set; } = "";

    public DateTimeOffset? RequestedDeliveryAt { get; set; }

    [Required]
    public DateTimeOffset? ExpectedDeliveryAt { get; set; }

    [Required, StringLength(500)]
    public string Reason { get; set; } = "";
}

[Authorize]
[ApiController]
[Route("api/v1/orders")]
public class OrderDeliveryScheduleController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<OrderDeliveryScheduleController> _logger;

    public OrderDeliveryScheduleController(
        IConfiguration configuration,
        ILogger<OrderDeliveryScheduleController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPut("{id:long}/delivery-schedule")]
    public async Task<IActionResult> UpdateSchedule(
        long id,
        UpdateOrderDeliveryScheduleRequest request,
        CancellationToken cancellationToken)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã đơn phải lớn hơn 0." });

        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId)
            || accountId <= 0)
        {
            return Unauthorized();
        }

        if (string.IsNullOrWhiteSpace(request.Reason))
        {
            return BadRequest(new
            {
                message = "Phải nhập lý do điều chỉnh lịch giao."
            });
        }

        if (string.IsNullOrWhiteSpace(request.ExpectedVersion))
        {
            return BadRequest(new
            {
                message = "Phải gửi phiên bản dữ liệu của đơn."
            });
        }

        byte[] expectedVersion;

        try
        {
            expectedVersion =
                Convert.FromBase64String(request.ExpectedVersion);
        }
        catch (FormatException)
        {
            return BadRequest(new
            {
                message = "ExpectedVersion phải là chuỗi Base64 hợp lệ."
            });
        }

        if (expectedVersion.Length != 8)
        {
            return BadRequest(new
            {
                message = "Phiên bản dữ liệu không hợp lệ."
            });
        }

        if (!request.ExpectedDeliveryAt.HasValue)
        {
            return BadRequest(new
            {
                message = "Phải nhập hạn giao hàng."
            });
        }

        DateTime? requestedUtc =
            request.RequestedDeliveryAt.HasValue
                ? ToUtcSeconds(request.RequestedDeliveryAt.Value)
                : null;

        var expectedUtc =
            ToUtcSeconds(request.ExpectedDeliveryAt.Value);

        if (requestedUtc.HasValue && expectedUtc < requestedUtc.Value)
        {
            return BadRequest(new
            {
                message = "Hạn giao không được trước thời điểm yêu cầu giao."
            });
        }

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Allowed BIT = 0,
                    @IsAdmin BIT = 0,
                    @AccountBranchId INT;

                SELECT
                    @Allowed = 1,
                    @IsAdmin = CASE
                        WHEN vt.KyHieuVaiTro = 'ADMIN' THEN 1 ELSE 0
                    END,
                    @AccountBranchId = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @AccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  )
                  AND EXISTS (
                      SELECT 1
                      FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                      JOIN dbo.Quyen q WITH (HOLDLOCK)
                          ON q.MaQuyen = vq.MaQuyen
                      WHERE vq.MaVaiTro = tk.MaVaiTro
                        AND q.KyHieuQuyen = 'DONHANG_CAPNHAT'
                  );

                IF @Allowed = 0
                   OR (@IsAdmin = 0 AND @AccountBranchId IS NULL)
                    THROW 52501, N'Không có quyền cập nhật lịch giao.', 1;

                DECLARE
                    @Status VARCHAR(40),
                    @CurrentVersion BINARY(8),
                    @ReadyAt DATETIME2(0),
                    @OldRequestedAt DATETIME2(0),
                    @OldExpectedAt DATETIME2(0);

                SELECT
                    @Status = tt.KyHieuTrangThai,
                    @CurrentVersion = d.PhienBan,
                    @ReadyAt = d.ThoiGianSanSang,
                    @OldRequestedAt = d.ThoiGianYeuCauGiao,
                    @OldExpectedAt = d.ThoiGianDuKienGiao
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.TrangThaiDonHang tt WITH (HOLDLOCK)
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (
                      @IsAdmin = 1
                      OR d.MaBuuCuc = @AccountBranchId
                  );

                IF @Status IS NULL
                    THROW 52502,
                        N'Không tìm thấy đơn trong phạm vi được xem.', 1;

                IF @CurrentVersion IS NULL
                   OR @CurrentVersion <> @ExpectedVersion
                    THROW 52503,
                        N'Đơn đã thay đổi. Hãy tải lại chi tiết trước khi sửa lịch.', 1;

                IF @Status <> 'IN_WAREHOUSE'
                    THROW 52503,
                        N'API này chỉ sửa lịch giao cho đơn IN_WAREHOUSE.', 1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 52503,
                        N'Đơn đã có phân công đang hoạt động. Hãy kiểm tra lại phân công.', 1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.ChiTietChuyenGiao ct WITH (UPDLOCK, HOLDLOCK)
                    JOIN dbo.ChuyenGiaoHang cg WITH (HOLDLOCK)
                        ON cg.MaChuyenGiao = ct.MaChuyenGiao
                    WHERE ct.MaDonHang = @OrderId
                      AND cg.TrangThaiChuyen NOT IN (
                          'COMPLETED', 'CANCELLED'
                      )
                )
                    THROW 52503,
                        N'Đơn đang thuộc chuyến giao chưa kết thúc.', 1;

                DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

                IF @ReadyAt > @Now
                    THROW 52503,
                        N'Thời gian sẵn sàng đang nằm trong tương lai. Hãy kiểm tra dữ liệu đơn.', 1;

                IF @ExpectedAt IS NULL OR @ExpectedAt <= @Now
                    THROW 52504,
                        N'Hạn giao mới phải nằm trong tương lai.', 1;

                IF @RequestedAt IS NOT NULL
                   AND @RequestedAt <= @Now
                   AND (
                       @OldRequestedAt IS NULL
                       OR @RequestedAt <> @OldRequestedAt
                   )
                    THROW 52504,
                        N'Thời điểm yêu cầu giao mới phải nằm trong tương lai.', 1;

                IF @RequestedAt IS NOT NULL
                   AND @ExpectedAt < @RequestedAt
                    THROW 52504,
                        N'Hạn giao không được trước thời điểm yêu cầu giao.', 1;

                -- Khi chưa có mốc sẵn sàng, dùng thời điểm hiện tại
                -- để kiểm tra lịch trước thao tác ready-for-dispatch.
                DECLARE @ReadyBoundary DATETIME2(0) =
                    COALESCE(@ReadyAt, @Now);

                IF @ExpectedAt < @ReadyBoundary
                   OR (
                       @RequestedAt IS NOT NULL
                       AND @RequestedAt < @ReadyBoundary
                   )
                    THROW 52504,
                        N'Lịch giao không được trước thời gian hàng sẵn sàng.', 1;

                DECLARE @OldData NVARCHAR(MAX) = (
                    SELECT
                        @Status AS status,
                        @CurrentVersion AS version,
                        CASE WHEN @OldRequestedAt IS NOT NULL
                            THEN CONVERT(VARCHAR(33), @OldRequestedAt, 126) + 'Z'
                        END AS requestedDeliveryAt,
                        CASE WHEN @OldExpectedAt IS NOT NULL
                            THEN CONVERT(VARCHAR(33), @OldExpectedAt, 126) + 'Z'
                        END AS expectedDeliveryAt
                    FOR JSON PATH, INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                UPDATE dbo.DonHang
                SET ThoiGianYeuCauGiao = @RequestedAt,
                    ThoiGianDuKienGiao = @ExpectedAt,
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = @Now
                WHERE MaDonHang = @OrderId
                  AND PhienBan = @ExpectedVersion;

                IF @@ROWCOUNT <> 1
                    THROW 52503,
                        N'Đơn đã thay đổi. Hãy tải lại chi tiết.', 1;

                DECLARE @NewData NVARCHAR(MAX);

                SELECT @NewData = (
                    SELECT
                        d.MaDonHang AS id,
                        @Status AS status,
                        d.PhienBan AS version,
                        CASE WHEN d.ThoiGianYeuCauGiao IS NOT NULL
                            THEN CONVERT(
                                VARCHAR(33), d.ThoiGianYeuCauGiao, 126
                            ) + 'Z'
                        END AS requestedDeliveryAt,
                        CONVERT(
                            VARCHAR(33), d.ThoiGianDuKienGiao, 126
                        ) + 'Z' AS expectedDeliveryAt,
                        @Reason AS reason,
                        N'Đã cập nhật lịch giao.' AS message
                    FROM dbo.DonHang d
                    WHERE d.MaDonHang = @OrderId
                    FOR JSON PATH, INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
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
                    'UPDATE_DELIVERY_SCHEDULE',
                    'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    @OldData,
                    @NewData
                );

                COMMIT;

                SELECT @NewData;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0
                    ROLLBACK;

                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        try
        {
            await connection.OpenAsync(cancellationToken);

            await using var command = new SqlCommand(sql, connection);

            command.Parameters.Add(
                "@OrderId", SqlDbType.BigInt).Value = id;

            command.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value = accountId;

            command.Parameters.Add(
                "@ExpectedVersion", SqlDbType.Binary, 8
            ).Value = expectedVersion;

            command.Parameters.Add(
                "@Reason", SqlDbType.NVarChar, 500
            ).Value = request.Reason.Trim();

            var requestedParameter = command.Parameters.Add(
                "@RequestedAt", SqlDbType.DateTime2);

            requestedParameter.Scale = 0;
            requestedParameter.Value =
                (object?)requestedUtc ?? DBNull.Value;

            var expectedParameter = command.Parameters.Add(
                "@ExpectedAt", SqlDbType.DateTime2);

            expectedParameter.Scale = 0;
            expectedParameter.Value = expectedUtc;

            var json = await command.ExecuteScalarAsync(
                cancellationToken) as string;

            if (string.IsNullOrWhiteSpace(json))
            {
                _logger.LogError(
                    "Không đọc được kết quả cập nhật lịch đơn {OrderId}.",
                    id);

                return StatusCode(500, new
                {
                    message = "Không đọc được kết quả xử lý. Hãy tải lại chi tiết để kiểm tra."
                });
            }

            return Content(json, "application/json");
        }
        catch (SqlException ex) when (ex.Number == 52501)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52502)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52503)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52504)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy tải lại và thử lại."
            });
        }
        catch (SqlException ex) when (ex.Number == 547)
        {
            _logger.LogWarning(
                ex,
                "Lịch giao đơn {OrderId} vi phạm ràng buộc dữ liệu.",
                id);

            return Conflict(new
            {
                message = "Lịch giao chưa đáp ứng ràng buộc dữ liệu. Hãy tải lại và kiểm tra các mốc thời gian."
            });
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Không cập nhật được lịch giao đơn {OrderId}.",
                id);

            return StatusCode(500, new
            {
                message = "Không cập nhật được lịch giao. Hãy kiểm tra log backend."
            });
        }
    }

    private static DateTime ToUtcSeconds(DateTimeOffset value)
    {
        var utc = value.UtcDateTime;

        return utc.AddTicks(
            -(utc.Ticks % TimeSpan.TicksPerSecond));
    }
}