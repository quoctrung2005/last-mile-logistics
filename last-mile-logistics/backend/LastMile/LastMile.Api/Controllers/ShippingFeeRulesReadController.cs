using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/shipping-fees/rules")]
public class ShippingFeeRulesReadController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public ShippingFeeRulesReadController(
        IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> Get(
        [FromQuery]
        [Range(typeof(long), "1", "9223372036854775807")]
        long? id = null,

        [FromQuery]
        [Range(1, int.MaxValue)]
        int? serviceId = null,

        [FromQuery]
        [Range(1, int.MaxValue)]
        int? areaId = null,

        [FromQuery]
        bool activeOnly = false,

        [FromQuery] bool? isActive = null,
        [FromQuery] bool? globalOnly = null,

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
                @ActorRole VARCHAR(50),
                @ActorRoleId INT,
                @Result NVARCHAR(MAX),
                @Now DATETIME2(0) = SYSUTCDATETIME();

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
                  OR tk.KhoaDenLuc <= @Now
              );

            IF @ActorRole IS NULL
                THROW 56701,
                    N'Tài khoản không còn hợp lệ.', 1;

            IF @ActorRole <> 'ADMIN'
               OR NOT EXISTS (
                   SELECT 1
                   FROM dbo.VaiTroQuyen vq
                   JOIN dbo.Quyen q
                       ON q.MaQuyen = vq.MaQuyen
                   WHERE vq.MaVaiTro = @ActorRoleId
                     AND q.KyHieuQuyen = 'BANGGIA_QUANLY'
               )
                THROW 56702,
                    N'Bạn không có quyền xem cấu hình tính phí.', 1;

            SELECT
                qt.MaQuyTacTinhPhi AS id,
                qt.MaLoaiDichVu AS serviceId,
                dv.KyHieuDichVu AS serviceCode,
                dv.TenDichVu AS serviceName,
                dv.DangHoatDong AS serviceIsActive,

                qt.MaKhuVuc AS areaId,
                kv.KyHieuKhuVuc AS areaCode,
                kv.TenKhuVuc AS areaName,
                kv.DangHoatDong AS areaIsActive,

                qt.KhoangCachTuKm AS distanceFromKm,
                qt.KhoangCachDenKm AS distanceToKm,
                qt.KhoiLuongTuKg AS weightFromKg,
                qt.KhoiLuongDenKg AS weightToKg,

                qt.PhiCoBan AS baseFee,
                qt.PhiMoiKm AS feePerKm,
                qt.PhiMoiKg AS feePerKg,
                CONVERT(VARCHAR(40), qt.PhiCoBan) AS baseFeeExact,
                CONVERT(VARCHAR(40), qt.PhiMoiKm) AS feePerKmExact,
                CONVERT(VARCHAR(40), qt.PhiMoiKg) AS feePerKgExact,

                qt.HieuLucTu AS effectiveFrom,
                qt.HieuLucDen AS effectiveTo,
                qt.DangHoatDong AS isActive,

                CONVERT(BIT, CASE
                    WHEN qt.DangHoatDong = 1
                     AND dv.DangHoatDong = 1
                     AND (
                         qt.MaKhuVuc IS NULL
                         OR kv.DangHoatDong = 1
                     )
                     AND qt.HieuLucTu <= @Now
                     AND (
                         qt.HieuLucDen IS NULL
                         OR @Now < qt.HieuLucDen
                     )
                    THEN 1
                    ELSE 0
                END) AS isEffectiveNow

            INTO #Rules

            FROM dbo.QuyTacTinhPhi qt
            JOIN dbo.LoaiDichVu dv
                ON dv.MaLoaiDichVu = qt.MaLoaiDichVu
            LEFT JOIN dbo.KhuVuc kv
                ON kv.MaKhuVuc = qt.MaKhuVuc

            WHERE (
                @Id IS NOT NULL
                AND qt.MaQuyTacTinhPhi = @Id
            )
            OR (
                @Id IS NULL
                AND (
                    @ServiceId IS NULL
                    OR qt.MaLoaiDichVu = @ServiceId
                )
                AND (
                    @AreaId IS NULL
                    OR qt.MaKhuVuc = @AreaId
                )
                AND (
                    @ActiveOnly = 0
                    OR qt.DangHoatDong = 1
                )
                AND (@IsActive IS NULL OR qt.DangHoatDong = @IsActive)
                AND (@GlobalOnly IS NULL OR (@GlobalOnly = 1 AND qt.MaKhuVuc IS NULL) OR (@GlobalOnly = 0 AND qt.MaKhuVuc IS NOT NULL))
            );

            IF @Id IS NOT NULL
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM #Rules)
                    THROW 56703,
                        N'Không tìm thấy quy tắc tính phí.', 1;

                SELECT @Result = (
                    SELECT *
                    FROM #Rules
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );
            END
            ELSE
            BEGIN
                DECLARE @TotalItems BIGINT;

                SELECT @TotalItems = COUNT_BIG(*)
                FROM #Rules;

                SELECT @Result = (
                    SELECT
                        @Page AS page,
                        @PageSize AS pageSize,
                        @TotalItems AS totalItems,

                        JSON_QUERY(COALESCE((
                            SELECT *
                            FROM #Rules
                            ORDER BY id DESC
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
            "@ServiceId", SqlDbType.Int).Value =
            (object?)serviceId ?? DBNull.Value;

        command.Parameters.Add(
            "@AreaId", SqlDbType.Int).Value =
            (object?)areaId ?? DBNull.Value;

        command.Parameters.Add(
            "@ActiveOnly", SqlDbType.Bit).Value = activeOnly;
        command.Parameters.Add("@IsActive", SqlDbType.Bit).Value = (object?)isActive ?? DBNull.Value;
        command.Parameters.Add("@GlobalOnly", SqlDbType.Bit).Value = (object?)globalOnly ?? DBNull.Value;

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
        catch (SqlException ex) when (ex.Number == 56701)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56702)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56703)
        {
            return NotFound(new { message = ex.Message });
        }
    }
}
