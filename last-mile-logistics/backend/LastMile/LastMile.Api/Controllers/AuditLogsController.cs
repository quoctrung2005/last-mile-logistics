using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using LastMile.Api.Services;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/audit-logs")]
public class AuditLogsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public AuditLogsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> Get(
        [FromQuery]
        [Range(typeof(long), "1", "9223372036854775807")]
        long? id = null,

        [FromQuery]
        [Range(typeof(long), "1", "9223372036854775807")]
        long? accountId = null,

        [FromQuery]
        [StringLength(50)]
        string? action = null,

        [FromQuery]
        [StringLength(100)]
        string? objectType = null,

        [FromQuery]
        [StringLength(100)]
        string? objectId = null,

        [FromQuery, StringLength(100)] string? keyword = null,

        [FromQuery] DateOnly? from = null,
        [FromQuery] DateOnly? to = null,

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

        var vietnamOffset = TimeSpan.FromHours(7);

        var today = DateOnly.FromDateTime(
            DateTimeOffset.UtcNow.ToOffset(vietnamOffset).DateTime);

        var toDate = to ?? today;

        var minimumDate = new DateOnly(1900, 1, 1);
        var maximumDate = new DateOnly(9999, 12, 30);

        if (toDate < minimumDate || toDate > maximumDate)
        {
            return BadRequest(new
            {
                message = "Ngày to phải từ 1900-01-01 đến 9999-12-30."
            });
        }

        var defaultFrom = toDate.AddDays(-29);

        if (defaultFrom < minimumDate)
            defaultFrom = minimumDate;

        var fromDate = from ?? defaultFrom;

        if (fromDate < minimumDate || fromDate > toDate)
        {
            return BadRequest(new
            {
                message =
                    "Ngày from phải từ 1900-01-01 "
                    + "và không được sau ngày to."
            });
        }

        if (toDate.DayNumber - fromDate.DayNumber > 365)
        {
            return BadRequest(new
            {
                message = "Mỗi lần tra cứu tối đa 366 ngày."
            });
        }

        var fromUtc = new DateTimeOffset(
            fromDate.ToDateTime(TimeOnly.MinValue),
            vietnamOffset).UtcDateTime;

        var toUtcExclusive = new DateTimeOffset(
            toDate.AddDays(1).ToDateTime(TimeOnly.MinValue),
            vietnamOffset).UtcDateTime;

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @ActorRole VARCHAR(50),
                @ActorRoleId INT,
                @Result NVARCHAR(MAX);

            SELECT
                @ActorRole = vt.KyHieuVaiTro,
                @ActorRoleId = tk.MaVaiTro
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
                THROW 57501,
                    N'Tài khoản không còn hợp lệ.', 1;

            IF @ActorRole <> 'ADMIN'
               OR NOT EXISTS (
                   SELECT 1
                   FROM dbo.VaiTroQuyen vq
                   JOIN dbo.Quyen q
                       ON q.MaQuyen = vq.MaQuyen
                   WHERE vq.MaVaiTro = @ActorRoleId
                     AND q.KyHieuQuyen = 'NHATKY_XEM'
               )
                THROW 57502,
                    N'Bạn không có quyền xem nhật ký hệ thống.', 1;

            IF @Id IS NOT NULL
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.NhatKyHoatDong
                    WHERE MaNhatKy = @Id
                )
                    THROW 57503,
                        N'Không tìm thấy nhật ký.', 1;

                SELECT @Result = (
                    SELECT
                        nk.MaNhatKy AS id,
                        nk.MaTaiKhoan AS accountId,
                        tk.TenDangNhap AS username,
                        tk.HoTen AS fullName,
                        nk.LoaiThaoTac AS action,
                        nk.TenDoiTuong AS objectType,
                        nk.MaDoiTuong AS objectId,

                        JSON_QUERY(CASE WHEN ISJSON(nk.DuLieuCuJson) = 1 THEN nk.DuLieuCuJson ELSE N'null' END) AS oldData,
                        JSON_QUERY(CASE WHEN ISJSON(nk.DuLieuMoiJson) = 1 THEN nk.DuLieuMoiJson ELSE N'null' END) AS newData,
                        CONVERT(BIT, CASE WHEN nk.DuLieuCuJson IS NOT NULL AND ISJSON(nk.DuLieuCuJson) <> 1 THEN 1 ELSE 0 END) AS oldDataInvalid,
                        CONVERT(BIT, CASE WHEN nk.DuLieuMoiJson IS NOT NULL AND ISJSON(nk.DuLieuMoiJson) <> 1 THEN 1 ELSE 0 END) AS newDataInvalid,

                        nk.DiaChiIP AS ipAddress,
                        nk.ThongTinThietBi AS deviceInfo,
                        nk.ThoiGianTao AS createdAtUtc

                    FROM dbo.NhatKyHoatDong nk
                    LEFT JOIN dbo.TaiKhoan tk
                        ON tk.MaTaiKhoan = nk.MaTaiKhoan
                    WHERE nk.MaNhatKy = @Id

                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );
            END
            ELSE
            BEGIN
                SELECT
                    nk.MaNhatKy AS id,
                    nk.MaTaiKhoan AS accountId,
                    tk.TenDangNhap AS username,
                    tk.HoTen AS fullName,
                    nk.LoaiThaoTac AS action,
                    nk.TenDoiTuong AS objectType,
                    nk.MaDoiTuong AS objectId,
                    nk.ThoiGianTao AS createdAtUtc

                INTO #Logs

                FROM dbo.NhatKyHoatDong nk
                LEFT JOIN dbo.TaiKhoan tk
                    ON tk.MaTaiKhoan = nk.MaTaiKhoan

                WHERE nk.ThoiGianTao >= @FromUtc
                  AND nk.ThoiGianTao < @ToUtcExclusive
                  AND (
                      @AccountId IS NULL
                      OR nk.MaTaiKhoan = @AccountId
                  )
                  AND (
                      @Action IS NULL
                      OR nk.LoaiThaoTac = @Action
                  )
                  AND (
                      @ObjectType IS NULL
                      OR nk.TenDoiTuong = @ObjectType
                  )
                  AND (
                      @ObjectId IS NULL
                      OR nk.MaDoiTuong = @ObjectId
                  )
                  AND (@Keyword IS NULL OR CHARINDEX(@Keyword, nk.LoaiThaoTac) > 0
                    OR CHARINDEX(@Keyword, nk.TenDoiTuong) > 0 OR CHARINDEX(@Keyword, nk.MaDoiTuong) > 0
                    OR CHARINDEX(@Keyword, tk.TenDangNhap) > 0 OR CHARINDEX(@Keyword, tk.HoTen) > 0);

                DECLARE @TotalItems BIGINT;

                SELECT @TotalItems = COUNT_BIG(*)
                FROM #Logs;

                SELECT @Result = (
                    SELECT
                        @FromDate AS [from],
                        @ToDate AS [to],
                        'Asia/Ho_Chi_Minh' AS timeZone,
                        @Page AS page,
                        @PageSize AS pageSize,
                        @TotalItems AS totalItems,

                        JSON_QUERY(COALESCE((
                            SELECT *
                            FROM #Logs
                            ORDER BY createdAtUtc DESC, id DESC
                            OFFSET @Offset ROWS
                            FETCH NEXT @PageSize ROWS ONLY
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        ), N'[]')) AS items

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
            "@AccountId", SqlDbType.BigInt).Value =
            (object?)accountId ?? DBNull.Value;

        AddText(
            command, "@Action",
            SqlDbType.VarChar, 50, action);

        AddText(
            command, "@ObjectType",
            SqlDbType.VarChar, 100, objectType);

        AddText(
            command, "@ObjectId",
            SqlDbType.VarChar, 100, objectId);
        AddText(command, "@Keyword", SqlDbType.NVarChar, 100, keyword);

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
                AuditDataSanitizer.Json(result?.ToString() ?? "{}"),
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 57501)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57502)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57503)
        {
            return NotFound(new { message = ex.Message });
        }
    }

    private static void AddText(
        SqlCommand command,
        string name,
        SqlDbType type,
        int size,
        string? value)
    {
        command.Parameters.Add(name, type, size).Value =
            string.IsNullOrWhiteSpace(value)
                ? DBNull.Value
                : value.Trim();
    }
}
