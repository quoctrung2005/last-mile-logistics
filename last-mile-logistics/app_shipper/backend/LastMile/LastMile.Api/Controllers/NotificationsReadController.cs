using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/notifications")]
public class NotificationsReadController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public NotificationsReadController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> Get(
        [FromQuery]
        [Range(typeof(long), "1", "9223372036854775807")]
        long? id = null,

        [FromQuery]
        bool unreadOnly = false,

        [FromQuery]
        [Range(1, int.MaxValue)]
        int page = 1,

        [FromQuery]
        [Range(1, 100)]
        int pageSize = 10,

        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @Result NVARCHAR(MAX),
                @TotalItems BIGINT,
                @UnreadCount BIGINT;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.TaiKhoan tk
                JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  )
            )
                THROW 57101,
                    N'Tài khoản không còn hợp lệ.', 1;

            -- Chỉ lấy thông báo của tài khoản đang đăng nhập.
            SELECT
                MaThongBao AS id,
                LoaiThongBao AS type,
                TieuDe AS title,
                NoiDung AS content,
                LoaiDoiTuongThamChieu AS referenceType,
                MaDoiTuongThamChieu AS referenceId,
                DaDoc AS isRead,
                ThoiGianTao AS createdAt,
                ThoiGianDoc AS readAt

            INTO #Notifications

            FROM dbo.ThongBao
            WHERE MaTaiKhoan = @ActorId;

            IF @Id IS NOT NULL
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM #Notifications
                    WHERE id = @Id
                )
                    THROW 57103,
                        N'Không tìm thấy thông báo của bạn.', 1;

                SELECT @Result = (
                    SELECT *
                    FROM #Notifications
                    WHERE id = @Id
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );
            END
            ELSE
            BEGIN
                SELECT @UnreadCount = COUNT_BIG(*)
                FROM #Notifications
                WHERE isRead = 0;

                SELECT @TotalItems = COUNT_BIG(*)
                FROM #Notifications
                WHERE @UnreadOnly = 0 OR isRead = 0;

                SELECT @Result = (
                    SELECT
                        @Page AS page,
                        @PageSize AS pageSize,
                        @TotalItems AS totalItems,
                        @UnreadCount AS unreadCount,

                        JSON_QUERY((
                            SELECT *
                            FROM #Notifications
                            WHERE @UnreadOnly = 0 OR isRead = 0
                            ORDER BY createdAt DESC, id DESC
                            OFFSET @Offset ROWS
                            FETCH NEXT @PageSize ROWS ONLY
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        )) AS items

                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );
            END;

            SELECT @Result;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = actorId;

        command.Parameters.Add(
            "@Id", SqlDbType.BigInt).Value =
            (object?)id ?? DBNull.Value;

        command.Parameters.Add(
            "@UnreadOnly", SqlDbType.Bit).Value = unreadOnly;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value = pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.BigInt).Value =
            ((long)page - 1) * pageSize;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 57101)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57103)
        {
            return NotFound(new { message = ex.Message });
        }
    }
}