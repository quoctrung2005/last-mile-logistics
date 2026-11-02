using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/roles")]
public class RolesController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public RolesController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> Get(
        [FromQuery] int? id = null,
        [FromQuery] string? keyword = null,
        [FromQuery] bool activeOnly = false,
        [FromQuery] bool lookupOnly = false,
        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        if (id.HasValue && id.Value <= 0)
            return BadRequest(new { message = "Mã vai trò không hợp lệ." });

        if (!id.HasValue && keyword?.Length > 100)
            return BadRequest(new { message = "Từ khóa tối đa 100 ký tự." });

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @ActorRole VARCHAR(50),
                @ActorRoleId INT,
                @AvailablePermissions NVARCHAR(MAX),
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
                THROW 55801,
                    N'Tài khoản không còn hợp lệ.', 1;

            -- Account screens need role labels/rules, not permission-management data.
            IF @LookupOnly = 1
            BEGIN
                IF @Id IS NOT NULL OR NOT EXISTS (
                    SELECT 1 FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @ActorRoleId AND q.KyHieuQuyen = 'TAIKHOAN_XEM'
                ) THROW 55802, N'Bạn không có quyền đọc danh mục vai trò tài khoản.', 1;

                SELECT (
                    SELECT JSON_QUERY(COALESCE((
                        SELECT vt.MaVaiTro AS id, vt.KyHieuVaiTro AS code,
                            vt.TenVaiTro AS name, vt.DangHoatDong AS isActive,
                            CONVERT(BIT, CASE WHEN vt.KyHieuVaiTro = 'ADMIN' THEN 0 ELSE 1 END) AS requiresBranch,
                            CONVERT(BIT, CASE WHEN vt.DangHoatDong = 1 AND EXISTS (
                                SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                                WHERE vq.MaVaiTro = @ActorRoleId AND q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                            ) AND (@ActorRole = 'ADMIN' OR (vt.KyHieuVaiTro <> 'ADMIN' AND NOT EXISTS (
                                SELECT 1 FROM dbo.VaiTroQuyen targetPermission
                                WHERE targetPermission.MaVaiTro = vt.MaVaiTro AND NOT EXISTS (
                                    SELECT 1 FROM dbo.VaiTroQuyen actorPermission
                                    WHERE actorPermission.MaVaiTro = @ActorRoleId
                                      AND actorPermission.MaQuyen = targetPermission.MaQuyen
                                )
                            ))) THEN 1 ELSE 0 END) AS canAssign
                        FROM dbo.VaiTro vt
                        WHERE (@ActiveOnly = 0 OR vt.DangHoatDong = 1)
                          AND (@Keyword IS NULL OR CHARINDEX(@Keyword, vt.KyHieuVaiTro) > 0 OR CHARINDEX(@Keyword, vt.TenVaiTro) > 0)
                        ORDER BY vt.MaVaiTro FOR JSON PATH
                    ), N'[]')) AS items FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );
                RETURN;
            END;

            IF @ActorRole <> 'ADMIN'
               OR NOT EXISTS (
                   SELECT 1
                   FROM dbo.VaiTroQuyen vq
                   JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                   WHERE vq.MaVaiTro = @ActorRoleId
                     AND q.KyHieuQuyen = 'PHANQUYEN_QUANLY'
               )
                THROW 55802,
                    N'API này dành cho admin quản lý phân quyền.', 1;

            SELECT @AvailablePermissions = (
                SELECT
                    q.MaQuyen AS id,
                    q.KyHieuQuyen AS code,
                    q.TenQuyen AS name,
                    q.MoTa AS description
                FROM dbo.Quyen q
                ORDER BY q.KyHieuQuyen
                FOR JSON PATH, INCLUDE_NULL_VALUES
            );

            IF @Id IS NOT NULL
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM dbo.VaiTro
                    WHERE MaVaiTro = @Id
                )
                    THROW 55803,
                        N'Không tìm thấy vai trò.', 1;

                SELECT @Result = (
                    SELECT
                        vt.MaVaiTro AS id,
                        vt.KyHieuVaiTro AS code,
                        vt.TenVaiTro AS name,
                        vt.MoTa AS description,
                        vt.DangHoatDong AS isActive,
                        vt.ThoiGianTao AS createdAt,

                        (
                            SELECT COUNT(*)
                            FROM dbo.TaiKhoan tk
                            WHERE tk.MaVaiTro = vt.MaVaiTro
                        ) AS accountCount,

                        JSON_QUERY(COALESCE((
                            SELECT
                                q.MaQuyen AS id,
                                q.KyHieuQuyen AS code,
                                q.TenQuyen AS name,
                                q.MoTa AS description,
                                vq.ThoiGianCapQuyen AS grantedAt
                            FROM dbo.VaiTroQuyen vq
                            JOIN dbo.Quyen q
                                ON q.MaQuyen = vq.MaQuyen
                            WHERE vq.MaVaiTro = vt.MaVaiTro
                            ORDER BY q.KyHieuQuyen
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        ), N'[]')) AS permissions,

                        JSON_QUERY(@AvailablePermissions)
                            AS availablePermissions

                    FROM dbo.VaiTro vt
                    WHERE vt.MaVaiTro = @Id
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );
            END
            ELSE
            BEGIN
                SELECT @Result = (
                    SELECT
                        JSON_QUERY(COALESCE((
                            SELECT
                                vt.MaVaiTro AS id,
                                vt.KyHieuVaiTro AS code,
                                vt.TenVaiTro AS name,
                                vt.MoTa AS description,
                                vt.DangHoatDong AS isActive,

                                (
                                    SELECT COUNT(*)
                                    FROM dbo.VaiTroQuyen vq
                                    WHERE vq.MaVaiTro = vt.MaVaiTro
                                ) AS permissionCount,

                                (
                                    SELECT COUNT(*)
                                    FROM dbo.TaiKhoan tk
                                    WHERE tk.MaVaiTro = vt.MaVaiTro
                                ) AS accountCount

                            FROM dbo.VaiTro vt
                            WHERE (
                                @ActiveOnly = 0
                                OR vt.DangHoatDong = 1
                            )
                              AND (
                                  @Keyword IS NULL
                                  OR CHARINDEX(
                                      @Keyword, vt.KyHieuVaiTro
                                  ) > 0
                                  OR CHARINDEX(
                                      @Keyword, vt.TenVaiTro
                                  ) > 0
                              )
                            ORDER BY vt.MaVaiTro
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        ), N'[]')) AS items,

                        JSON_QUERY(@AvailablePermissions)
                            AS availablePermissions

                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );
            END;

            SELECT @Result;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Id", SqlDbType.Int).Value =
            (object?)id ?? DBNull.Value;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
            id.HasValue || string.IsNullOrWhiteSpace(keyword)
                ? DBNull.Value
                : keyword.Trim();

        command.Parameters.Add(
            "@ActiveOnly", SqlDbType.Bit).Value = activeOnly;
        command.Parameters.Add("@LookupOnly", SqlDbType.Bit).Value = lookupOnly;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 55801)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55802)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55803)
        {
            return NotFound(new { message = ex.Message });
        }
    }
}
