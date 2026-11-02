using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CancelOrderRequest
{
    [Required, StringLength(500)]
    public string Reason { get; set; } = "";
}

[Authorize]
[ApiController]
[Route("api/v1/orders")]
public class OrderCancelController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<OrderCancelController> _logger;

    public OrderCancelController(
        IConfiguration configuration,
        ILogger<OrderCancelController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPost("{id:long}/cancel")]
    public async Task<IActionResult> Cancel(
        long id,
        CancelOrderRequest request)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã đơn phải lớn hơn 0." });

        if (string.IsNullOrWhiteSpace(request.Reason))
            return BadRequest(new { message = "Phải nhập lý do hủy." });

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        var reason = request.Reason.Trim();

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Allowed BIT = 0,
                    @IsAdmin BIT = 0,
                    @BranchId INT;

                SELECT
                    @Allowed = 1,
                    @IsAdmin = CASE
                        WHEN vt.KyHieuVaiTro = 'ADMIN' THEN 1 ELSE 0 END,
                    @BranchId = tk.MaBuuCuc
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
                      JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                      WHERE vq.MaVaiTro = tk.MaVaiTro
                        AND q.KyHieuQuyen = 'DONHANG_HUY'
                  );

                IF @Allowed = 0
                   OR (@IsAdmin = 0 AND @BranchId IS NULL)
                    THROW 52301, N'Không có quyền hủy đơn.', 1;

                DECLARE
                    @OldStatusId SMALLINT,
                    @OldStatus VARCHAR(40),
                    @CancelledStatusId SMALLINT;

                SELECT
                    @OldStatusId = d.MaTrangThaiHienTai,
                    @OldStatus = tt.KyHieuTrangThai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (@IsAdmin = 1 OR d.MaBuuCuc = @BranchId);

                IF @OldStatus IS NULL
                    THROW 52302, N'Không tìm thấy đơn trong phạm vi được xem.', 1;

                SELECT @CancelledStatusId = MaTrangThaiDonHang
                FROM dbo.TrangThaiDonHang
                WHERE KyHieuTrangThai = 'CANCELLED';

                IF @CancelledStatusId IS NULL
                    THROW 52304, N'Chưa có danh mục trạng thái CANCELLED.', 1;

                IF @OldStatus = 'CANCELLED'
                    THROW 52303, N'Đơn đã được hủy trước đó.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.ChuyenTrangThaiDonHang WITH (HOLDLOCK)
                    WHERE MaTrangThaiCu = @OldStatusId
                      AND MaTrangThaiMoi = @CancelledStatusId
                )
                    THROW 52303, N'Trạng thái hiện tại không cho phép hủy đơn.', 1;

                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'CANCELLED',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = @Reason,
                    @NguonCapNhat = 'API';

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan, LoaiThaoTac, TenDoiTuong,
                    MaDoiTuong, DuLieuCuJson, DuLieuMoiJson
                )
                VALUES (
                    @AccountId,
                    'CANCEL_ORDER',
                    'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    (
                        SELECT @OldStatus AS status
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    ),
                    (
                        SELECT 'CANCELLED' AS status, @Reason AS reason
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )
                );

                COMMIT;

                SELECT @OldStatus AS PreviousStatus;
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
            await connection.OpenAsync();

            await using var command = new SqlCommand(sql, connection);

            command.Parameters.Add(
                "@OrderId", SqlDbType.BigInt).Value = id;

            command.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value = accountId;

            command.Parameters.Add(
                "@Reason", SqlDbType.NVarChar, 500).Value = reason;

            var previousStatus =
                (string)(await command.ExecuteScalarAsync())!;

            return Ok(new
            {
                id,
                previousStatus,
                status = "CANCELLED",
                reason,
                message = "Hủy đơn thành công."
            });
        }
        catch (SqlException ex) when (ex.Number == 52301)
        {
            return Forbid();
        }
        catch (SqlException ex) when (ex.Number == 52302)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex)
            when (ex.Number == 52303 || ex.Number == 51001)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex)
        {
            _logger.LogError(ex, "Không hủy được đơn {OrderId}.", id);

            return StatusCode(500, new
            {
                message = "Không hủy được đơn. Xem log Visual Studio."
            });
        }
    }
}