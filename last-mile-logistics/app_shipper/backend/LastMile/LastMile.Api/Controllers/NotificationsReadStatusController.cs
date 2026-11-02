using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class MarkNotificationsReadRequest : IValidatableObject
{
    public List<long>? Ids { get; set; }

    public bool All { get; set; }

    public IEnumerable<ValidationResult> Validate(
        ValidationContext validationContext)
    {
        if (All)
        {
            if (Ids is { Count: > 0 })
            {
                yield return new ValidationResult(
                    "Khi all = true, không gửi ids.",
                    new[] { nameof(Ids) });
            }

            yield break;
        }

        if (Ids is null || Ids.Count == 0)
        {
            yield return new ValidationResult(
                "Phải gửi ids hoặc đặt all = true.",
                new[] { nameof(Ids) });

            yield break;
        }

        if (Ids.Count > 100)
        {
            yield return new ValidationResult(
                "Mỗi lần tối đa 100 thông báo.",
                new[] { nameof(Ids) });
        }

        if (Ids.Any(id => id <= 0))
        {
            yield return new ValidationResult(
                "Các id phải lớn hơn 0.",
                new[] { nameof(Ids) });
        }

        if (Ids.Distinct().Count() != Ids.Count)
        {
            yield return new ValidationResult(
                "Danh sách ids không được trùng.",
                new[] { nameof(Ids) });
        }
    }
}

[ApiController]
[Authorize]
[Route("api/v1/notifications")]
public class NotificationsReadStatusController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public NotificationsReadStatusController(
        IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPatch("read")]
    public async Task<IActionResult> MarkRead(
        MarkNotificationsReadRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                    JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                        ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @ActorId
                      AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                      AND vt.DangHoatDong = 1
                      AND (
                          tk.KhoaDenLuc IS NULL
                          OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                      )
                )
                    THROW 57201,
                        N'Tài khoản không còn hợp lệ.', 1;

                DECLARE @Requested TABLE (
                    Id BIGINT NOT NULL PRIMARY KEY
                );

                INSERT INTO @Requested (Id)
                SELECT CONVERT(BIGINT, [value])
                FROM OPENJSON(@IdsJson);

                -- Nếu chọn từng thông báo, tất cả phải thuộc
                -- tài khoản đang đăng nhập.
                IF @All = 0
                   AND EXISTS (
                       SELECT 1
                       FROM @Requested r
                       WHERE NOT EXISTS (
                           SELECT 1
                           FROM dbo.ThongBao tb WITH (UPDLOCK, HOLDLOCK)
                           WHERE tb.MaThongBao = r.Id
                             AND tb.MaTaiKhoan = @ActorId
                       )
                   )
                    THROW 57203,
                        N'Có thông báo không tồn tại hoặc không thuộc tài khoản của bạn.', 1;

                DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

                UPDATE tb WITH (UPDLOCK, HOLDLOCK)
                SET DaDoc = 1,
                    ThoiGianDoc = @Now
                FROM dbo.ThongBao tb
                WHERE tb.MaTaiKhoan = @ActorId
                  AND tb.DaDoc = 0
                  AND tb.ThoiGianTao <= @Now
                  AND (
                      @All = 1
                      OR EXISTS (
                          SELECT 1
                          FROM @Requested r
                          WHERE r.Id = tb.MaThongBao
                      )
                  );

                DECLARE
                    @UpdatedCount INT = @@ROWCOUNT,
                    @UnreadCount BIGINT,
                    @Result NVARCHAR(MAX);

                SELECT @UnreadCount = COUNT_BIG(*)
                FROM dbo.ThongBao
                WHERE MaTaiKhoan = @ActorId
                  AND DaDoc = 0;

                SELECT @Result = (
                    SELECT
                        @UpdatedCount AS updatedCount,
                        @UnreadCount AS unreadCount,
                        N'Đã đánh dấu thông báo đã đọc.' AS message
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                COMMIT;
                SELECT @Result;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK;
                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = actorId;

        command.Parameters.Add(
            "@All", SqlDbType.Bit).Value = request.All;

        command.Parameters.Add(
            "@IdsJson", SqlDbType.NVarChar, -1).Value =
            JsonSerializer.Serialize(
                request.Ids ?? new List<long>());

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 57201)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57203)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Thông báo đang được cập nhật đồng thời. Hãy thử lại."
            });
        }
    }
}