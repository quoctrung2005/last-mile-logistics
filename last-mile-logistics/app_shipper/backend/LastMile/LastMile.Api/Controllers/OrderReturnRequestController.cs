using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CreateOrderReturnRequest
{
    [Required]
    [StringLength(500)]
    public string Reason { get; set; } = "";
}

[ApiController]
[Authorize]
[Route("api/v1/orders")]
public class OrderReturnRequestController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public OrderReturnRequestController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{id:long}/return-request")]
    public async Task<IActionResult> CreateReturnRequest(
        long id,
        [FromBody] CreateOrderReturnRequest request)
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
                message = "Phải nhập lý do hoàn hàng."
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
                    @OrderBranchId INT,
                    @OrderStatus VARCHAR(40),
                    @AssignmentId BIGINT,
                    @ShipperId BIGINT,
                    @OwnShipperId BIGINT,
                    @ReturnRequestId BIGINT,
                    @CancelledRetryCount INT,
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
                    THROW 52201,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND (
                          (@Role = 'SHIPPER'
                           AND q.KyHieuQuyen = 'NHIEMVU_CAPNHAT')
                          OR
                          (@Role <> 'SHIPPER'
                           AND q.KyHieuQuyen = 'DONHANG_CAPNHAT')
                      )
                )
                    THROW 52202,
                        N'Bạn không có quyền tạo yêu cầu hoàn hàng.',
                        1;

                IF @Role <> 'ADMIN'
                   AND @AccountBranchId IS NULL
                    THROW 52202,
                        N'Tài khoản chưa được gán bưu cục.',
                        1;

                IF @Role = 'SHIPPER'
                BEGIN
                    SELECT @OwnShipperId = MaNhanVienGiaoHang
                    FROM dbo.NhanVienGiaoHang
                    WHERE MaTaiKhoan = @AccountId
                      AND DangHoatDong = 1;

                    IF @OwnShipperId IS NULL
                        THROW 52202,
                            N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                            1;
                END;

                SELECT
                    @OrderBranchId = d.MaBuuCuc,
                    @OrderStatus = tt.KyHieuTrangThai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang =
                       d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (
                      @Role = 'ADMIN'
                      OR d.MaBuuCuc = @AccountBranchId
                  );

                IF @OrderBranchId IS NULL
                    THROW 52203,
                        N'Không tìm thấy đơn hàng.',
                        1;

                IF @OrderStatus NOT IN ('FAILED', 'RETRY_WAITING')
                    THROW 52204,
                        N'Chỉ đơn FAILED hoặc RETRY_WAITING mới được yêu cầu hoàn theo API này.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.BuuCuc
                    WHERE MaBuuCuc = @OrderBranchId
                      AND DangHoatDong = 1
                )
                    THROW 52204,
                        N'Bưu cục nhận hoàn đã ngừng hoạt động.',
                        1;

                SELECT
                    @AssignmentId = MaPhanCongGiaoHang,
                    @ShipperId = MaNhanVienGiaoHang
                FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaDonHang = @OrderId
                  AND ThoiGianKetThuc IS NULL
                  AND TrangThaiPhanCong = 'IN_PROGRESS'
                  AND (
                      @Role <> 'SHIPPER'
                      OR MaNhanVienGiaoHang = @OwnShipperId
                  );

                IF @AssignmentId IS NULL
                    THROW 52204,
                        N'Không có phân công IN_PROGRESS hiện hành để shipper thực hiện hoàn hàng.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.YeuCauGiaoLaiHoacHoan
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND LoaiYeuCau IN ('RETURN', 'RECALL')
                      AND TrangThaiYeuCau IN (
                          'PENDING', 'APPROVED', 'IN_PROGRESS'
                      )
                )
                    THROW 52204,
                        N'Đơn đã có yêu cầu hoàn hoặc thu hồi chưa kết thúc.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.YeuCauGiaoLaiHoacHoan
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND LoaiYeuCau = 'RETRY'
                      AND TrangThaiYeuCau = 'IN_PROGRESS'
                )
                    THROW 52204,
                        N'Lần giao lại chưa được kết thúc. Hãy ghi nhận kết quả trước khi yêu cầu hoàn.',
                        1;

                SET @OldJson = (
                    SELECT
                        @OrderId AS orderId,
                        @OrderStatus AS orderStatus,
                        JSON_QUERY((
                            SELECT
                                MaYeuCauGiaoLaiHoacHoan AS requestId,
                                TrangThaiYeuCau AS requestStatus
                            FROM dbo.YeuCauGiaoLaiHoacHoan
                            WHERE MaDonHang = @OrderId
                              AND LoaiYeuCau = 'RETRY'
                              AND TrangThaiYeuCau IN (
                                  'PENDING', 'APPROVED'
                              )
                            FOR JSON PATH
                        )) AS waitingRetryRequests
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                SET @Now = SYSUTCDATETIME();

                -- Đã chọn hoàn thì không giữ lịch giao lại đang chờ.
                UPDATE dbo.YeuCauGiaoLaiHoacHoan
                SET TrangThaiYeuCau = 'CANCELLED',
                    ThoiGianHoanTat = @Now
                WHERE MaDonHang = @OrderId
                  AND LoaiYeuCau = 'RETRY'
                  AND TrangThaiYeuCau IN ('PENDING', 'APPROVED');

                SET @CancelledRetryCount = @@ROWCOUNT;

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
                    'RETURN',
                    'APPROVED',
                    @OrderBranchId,
                    @Reason,
                    @AccountId,
                    @Now
                );

                SET @ReturnRequestId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                UPDATE dbo.DonHang
                SET MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = @Now
                WHERE MaDonHang = @OrderId;

                SET @Result = (
                    SELECT
                        @ReturnRequestId AS returnRequestId,
                        d.MaDonHang AS orderId,
                        d.KyHieuDonHang AS orderCode,
                        d.MaVanDon AS trackingNumber,
                        @OrderStatus AS orderStatus,
                        'APPROVED' AS requestStatus,
                        @OrderBranchId AS returnBranchId,
                        b.TenBuuCuc AS returnBranchName,
                        @AssignmentId AS assignmentId,
                        @ShipperId AS shipperId,
                        @CancelledRetryCount AS cancelledRetryCount,
                        @Reason AS reason,
                        @Now AS requestedAt,
                        d.PhienBan AS version,
                        N'Đã duyệt yêu cầu hoàn. Chờ shipper bắt đầu hoàn hàng.'
                            AS message
                    FROM dbo.DonHang d
                    INNER JOIN dbo.BuuCuc b
                        ON b.MaBuuCuc = @OrderBranchId
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
                    'REQUEST_RETURN',
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
            ex.Number is >= 52201 and <= 52204)
        {
            var statusCode = ex.Number switch
            {
                52201 => StatusCodes.Status401Unauthorized,
                52202 => StatusCodes.Status403Forbidden,
                52203 => StatusCodes.Status404NotFound,
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
