using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class OrderRetryRequest
{
    [Required]
    public DateTimeOffset? RetryAt { get; set; }

    [Required]
    [StringLength(500)]
    public string Reason { get; set; } = "";
}

[ApiController]
[Authorize]
[Route("api/v1/orders")]
public class OrderRetryController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public OrderRetryController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{id:long}/retry")]
    public async Task<IActionResult> Retry(
        long id,
        [FromBody] OrderRetryRequest request)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã đơn hàng không hợp lệ."
            });
        }

        var reason = request.Reason.Trim();

        if (string.IsNullOrWhiteSpace(reason))
        {
            return BadRequest(new
            {
                message = "Phải nhập lý do giao lại."
            });
        }

        var utcRetryAt = request.RetryAt!.Value.UtcDateTime;

        // Database lưu DATETIME2(0): bỏ phần nhỏ hơn giây.
        utcRetryAt = new DateTime(
            utcRetryAt.Ticks
                - utcRetryAt.Ticks % TimeSpan.TicksPerSecond,
            DateTimeKind.Utc);

        if (utcRetryAt <= DateTime.UtcNow)
        {
            return BadRequest(new
            {
                message = "Thời gian giao lại phải nằm trong tương lai."
            });
        }

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Now DATETIME2(0) = SYSUTCDATETIME(),
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @AccountBranchId INT,
                    @OrderStatus VARCHAR(40),
                    @AssignmentId BIGINT,
                    @ShipperId BIGINT,
                    @AttemptId BIGINT,
                    @RequestId BIGINT,
                    @OldJson NVARCHAR(MAX),
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
                    THROW 52001,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DONHANG_CAPNHAT'
                )
                    THROW 52002,
                        N'Bạn không có quyền lên lịch giao lại.',
                        1;

                IF @Role <> 'ADMIN'
                   AND @AccountBranchId IS NULL
                    THROW 52002,
                        N'Tài khoản chưa được gán bưu cục.',
                        1;

                SELECT @OrderStatus = tt.KyHieuTrangThai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang =
                       d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (
                      @Role = 'ADMIN'
                      OR d.MaBuuCuc = @AccountBranchId
                  );

                IF @OrderStatus IS NULL
                    THROW 52003,
                        N'Không tìm thấy đơn hàng.',
                        1;

                IF @OrderStatus <> 'FAILED'
                    THROW 52004,
                        N'Chỉ đơn FAILED mới được lên lịch giao lại.',
                        1;

                -- Kiểm tra lại thời gian sau khi đã khóa đơn.
                SET @Now = SYSUTCDATETIME();

                IF @RetryAt <= @Now
                    THROW 52005,
                        N'Thời gian giao lại phải nằm trong tương lai.',
                        1;

                SELECT
                    @AssignmentId = MaPhanCongGiaoHang,
                    @ShipperId = MaNhanVienGiaoHang
                FROM dbo.PhanCongGiaoHang
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE MaDonHang = @OrderId
                  AND ThoiGianKetThuc IS NULL
                  AND TrangThaiPhanCong = 'IN_PROGRESS';

                IF @AssignmentId IS NULL
                    THROW 52004,
                        N'Đơn không có phân công IN_PROGRESS hiện hành để giao lại.',
                        1;

                SELECT TOP (1) @AttemptId = MaLanGiaoHang
                FROM dbo.LanGiaoHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaDonHang = @OrderId
                  AND MaPhanCongGiaoHang = @AssignmentId
                  AND KetQua = 'FAILED'
                ORDER BY SoLanThu DESC;

                IF @AttemptId IS NULL
                    THROW 52004,
                        N'Không tìm thấy lần giao thất bại của phân công hiện hành.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.YeuCauGiaoLaiHoacHoan
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND TrangThaiYeuCau IN (
                          'PENDING', 'APPROVED', 'IN_PROGRESS'
                      )
                )
                    THROW 52004,
                        N'Đơn đang có yêu cầu giao lại hoặc hoàn chưa kết thúc.',
                        1;

                SET @OldJson = (
                    SELECT
                        d.MaDonHang AS orderId,
                        @OrderStatus AS orderStatus,
                        d.ThoiGianYeuCauGiao AS requestedDeliveryAt,
                        lg.ThoiGianGiaoLaiDuKien AS retryAt
                    FROM dbo.DonHang d
                    INNER JOIN dbo.LanGiaoHang lg
                        ON lg.MaLanGiaoHang = @AttemptId
                    WHERE d.MaDonHang = @OrderId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                -- Người có quyền điều phối lập và duyệt lịch
                -- trong cùng một thao tác.
                INSERT INTO dbo.YeuCauGiaoLaiHoacHoan (
                    MaDonHang,
                    LoaiYeuCau,
                    TrangThaiYeuCau,
                    MaBuuCucHoan,
                    LyDo,
                    MaTaiKhoanYeuCau,
                    ThoiGianYeuCau
                )
                VALUES (
                    @OrderId,
                    'RETRY',
                    'APPROVED',
                    NULL,
                    @Reason,
                    @AccountId,
                    @Now
                );

                SET @RequestId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                UPDATE dbo.LanGiaoHang
                SET ThoiGianGiaoLaiDuKien = @RetryAt
                WHERE MaLanGiaoHang = @AttemptId;

                UPDATE dbo.DonHang
                SET ThoiGianYeuCauGiao = @RetryAt,
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = @Now
                WHERE MaDonHang = @OrderId;

                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'RETRY_WAITING',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = @Reason,
                    @NguonCapNhat = 'API';

                SET @Result = (
                    SELECT
                        @RequestId AS retryRequestId,
                        d.MaDonHang AS orderId,
                        d.KyHieuDonHang AS orderCode,
                        d.MaVanDon AS trackingNumber,
                        @AssignmentId AS assignmentId,
                        @ShipperId AS shipperId,
                        tt.KyHieuTrangThai AS orderStatus,
                        'APPROVED' AS requestStatus,
                        @RetryAt AS retryAt,
                        @Reason AS reason,
                        d.PhienBan AS version,
                        N'Đã lên lịch giao lại cho đơn hàng.'
                            AS message
                    FROM dbo.DonHang d
                    INNER JOIN dbo.TrangThaiDonHang tt
                        ON tt.MaTrangThaiDonHang =
                           d.MaTrangThaiHienTai
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
                    'SCHEDULE_RETRY',
                    'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
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

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt).Value = id;

        var retryParameter = command.Parameters.Add(
            "@RetryAt", SqlDbType.DateTime2);
        retryParameter.Scale = 0;
        retryParameter.Value = utcRetryAt;

        command.Parameters.Add(
            "@Reason", SqlDbType.NVarChar, 500).Value = reason;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return new ContentResult
            {
                StatusCode = StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = json
            };
        }
        catch (SqlException ex) when (
            ex.Number is >= 52001 and <= 52005)
        {
            var statusCode = ex.Number switch
            {
                52001 => StatusCodes.Status401Unauthorized,
                52002 => StatusCodes.Status403Forbidden,
                52003 => StatusCodes.Status404NotFound,
                52005 => StatusCodes.Status422UnprocessableEntity,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Có thao tác đồng thời. Hãy tải lại đơn và thử lại."
            });
        }
    }
}