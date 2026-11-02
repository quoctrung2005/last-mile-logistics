using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class UpdateRolePermissionsRequest
{
    [Required]
    [MaxLength(500)]
    public List<int> PermissionIds { get; set; } = null!;

    [Required]
    [MaxLength(500)]
    public List<int> ExpectedPermissionIds { get; set; } = null!;

    [Required]
    [StringLength(500)]
    public string Reason { get; set; } = "";
}

[ApiController]
[Authorize]
[Route("api/v1/roles")]
public class RolePermissionsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public RolePermissionsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPut("{id:int}/permissions")]
    public async Task<IActionResult> Update(
        int id,
        UpdateRolePermissionsRequest request,
        CancellationToken cancellationToken)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã vai trò không hợp lệ." });

        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        if (string.IsNullOrWhiteSpace(request.Reason))
            return BadRequest(new { message = "Phải nhập lý do cập nhật quyền." });

        if (request.PermissionIds.Any(x => x <= 0)
            || request.ExpectedPermissionIds.Any(x => x <= 0))
        {
            return BadRequest(new
            {
                message = "Mã quyền phải lớn hơn 0."
            });
        }

        if (request.PermissionIds.Distinct().Count()
                != request.PermissionIds.Count
            || request.ExpectedPermissionIds.Distinct().Count()
                != request.ExpectedPermissionIds.Count)
        {
            return BadRequest(new
            {
                message = "Danh sách quyền không được chứa mã trùng."
            });
        }

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @ActorRole VARCHAR(50),
                    @ActorRoleId INT,
                    @TargetRole VARCHAR(50),
                    @Changed BIT = 0,
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT
                    @ActorRole = vt.KyHieuVaiTro,
                    @ActorRoleId = tk.MaVaiTro
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @ActorRole IS NULL
                    THROW 56001,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF @ActorRole <> 'ADMIN'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                       JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                       WHERE vq.MaVaiTro = @ActorRoleId
                         AND q.KyHieuQuyen = 'PHANQUYEN_QUANLY'
                   )
                    THROW 56002,
                        N'API này dành cho admin quản lý phân quyền.', 1;

                SELECT @TargetRole = KyHieuVaiTro
                FROM dbo.VaiTro WITH (UPDLOCK, HOLDLOCK)
                WHERE MaVaiTro = @RoleId;

                IF @TargetRole IS NULL
                    THROW 56003,
                        N'Không tìm thấy vai trò.', 1;

                CREATE TABLE #Requested (
                    PermissionId INT NOT NULL PRIMARY KEY
                );

                CREATE TABLE #Expected (
                    PermissionId INT NOT NULL PRIMARY KEY
                );

                CREATE TABLE #Current (
                    PermissionId INT NOT NULL PRIMARY KEY
                );

                INSERT INTO #Requested (PermissionId)
                SELECT CONVERT(INT, [value])
                FROM OPENJSON(@PermissionIdsJson);

                INSERT INTO #Expected (PermissionId)
                SELECT CONVERT(INT, [value])
                FROM OPENJSON(@ExpectedPermissionIdsJson);

                INSERT INTO #Current (PermissionId)
                SELECT MaQuyen
                FROM dbo.VaiTroQuyen WITH (UPDLOCK, HOLDLOCK)
                WHERE MaVaiTro = @RoleId;

                -- So sánh theo tập hợp, không phụ thuộc thứ tự ID.
                IF EXISTS (
                    SELECT PermissionId FROM #Current
                    EXCEPT
                    SELECT PermissionId FROM #Expected
                )
                   OR EXISTS (
                       SELECT PermissionId FROM #Expected
                       EXCEPT
                       SELECT PermissionId FROM #Current
                   )
                    THROW 56004,
                        N'Quyền của vai trò đã thay đổi. Hãy tải lại trước khi cập nhật.', 1;

                IF EXISTS (
                    SELECT 1
                    FROM #Requested r
                    LEFT JOIN dbo.Quyen q WITH (HOLDLOCK)
                        ON q.MaQuyen = r.PermissionId
                    WHERE q.MaQuyen IS NULL
                )
                    THROW 56005,
                        N'Danh sách chứa quyền không tồn tại.', 1;

                -- Bảo vệ khả năng quản trị hệ thống.
                IF @TargetRole = 'ADMIN'
                   AND (
                       NOT EXISTS (
                           SELECT 1
                           FROM #Requested r
                           JOIN dbo.Quyen q ON q.MaQuyen = r.PermissionId
                           WHERE q.KyHieuQuyen = 'PHANQUYEN_QUANLY'
                       )
                       OR NOT EXISTS (
                           SELECT 1
                           FROM #Requested r
                           JOIN dbo.Quyen q ON q.MaQuyen = r.PermissionId
                           WHERE q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                       )
                       OR NOT EXISTS (
                           SELECT 1
                           FROM #Requested r
                           JOIN dbo.Quyen q ON q.MaQuyen = r.PermissionId
                           WHERE q.KyHieuQuyen = 'TAIKHOAN_XEM'
                       )
                   )
                    THROW 56004,
                        N'Vai trò ADMIN phải giữ quyền quản lý phân quyền, quản lý và xem tài khoản.', 1;

                IF EXISTS (
                    SELECT PermissionId FROM #Requested
                    EXCEPT
                    SELECT PermissionId FROM #Current
                )
                   OR EXISTS (
                       SELECT PermissionId FROM #Current
                       EXCEPT
                       SELECT PermissionId FROM #Requested
                   )
                    SET @Changed = 1;

                SELECT @OldJson = (
                    SELECT
                        @RoleId AS roleId,
                        JSON_QUERY(COALESCE((
                            SELECT
                                c.PermissionId AS id,
                                q.KyHieuQuyen AS code
                            FROM #Current c
                            JOIN dbo.Quyen q ON q.MaQuyen = c.PermissionId
                            ORDER BY c.PermissionId
                            FOR JSON PATH
                        ), N'[]')) AS permissions
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                DELETE vq
                FROM dbo.VaiTroQuyen vq
                WHERE vq.MaVaiTro = @RoleId
                  AND NOT EXISTS (
                      SELECT 1
                      FROM #Requested r
                      WHERE r.PermissionId = vq.MaQuyen
                  );

                INSERT INTO dbo.VaiTroQuyen (
                    MaVaiTro,
                    MaQuyen
                )
                SELECT @RoleId, r.PermissionId
                FROM #Requested r
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    WHERE vq.MaVaiTro = @RoleId
                      AND vq.MaQuyen = r.PermissionId
                );

                IF @Changed = 1
                BEGIN
                    UPDATE token
                    SET ThuHoiLuc = SYSUTCDATETIME()
                    FROM dbo.TokenLamMoi token
                    JOIN dbo.TaiKhoan tk
                        ON tk.MaTaiKhoan = token.MaTaiKhoan
                    WHERE tk.MaVaiTro = @RoleId
                      AND token.ThuHoiLuc IS NULL;
                END;

                SELECT @Result = (
                    SELECT
                        vt.MaVaiTro AS id,
                        vt.KyHieuVaiTro AS code,
                        vt.TenVaiTro AS name,
                        @Changed AS changed,
                        @Reason AS reason,
                        (
                            SELECT COUNT(*)
                            FROM dbo.VaiTroQuyen vq
                            WHERE vq.MaVaiTro = @RoleId
                        ) AS permissionCount,
                        JSON_QUERY(COALESCE((
                            SELECT
                                q.MaQuyen AS id,
                                q.KyHieuQuyen AS code,
                                q.TenQuyen AS name,
                                vq.ThoiGianCapQuyen AS grantedAt
                            FROM dbo.VaiTroQuyen vq
                            JOIN dbo.Quyen q
                                ON q.MaQuyen = vq.MaQuyen
                            WHERE vq.MaVaiTro = @RoleId
                            ORDER BY q.KyHieuQuyen
                            FOR JSON PATH
                        ), N'[]')) AS permissions,
                        N'Cập nhật quyền thành công.' AS message
                    FROM dbo.VaiTro vt
                    WHERE vt.MaVaiTro = @RoleId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                IF @Changed = 1
                BEGIN
                    INSERT INTO dbo.NhatKyHoatDong (
                        MaTaiKhoan,
                        LoaiThaoTac,
                        TenDoiTuong,
                        MaDoiTuong,
                        DuLieuCuJson,
                        DuLieuMoiJson
                    )
                    VALUES (
                        @ActorId,
                        'UPDATE_ROLE_PERMISSIONS',
                        'VaiTro',
                        CONVERT(VARCHAR(100), @RoleId),
                        @OldJson,
                        @Result
                    );
                END;

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
            "@RoleId", SqlDbType.Int).Value = id;

        command.Parameters.Add(
            "@PermissionIdsJson", SqlDbType.NVarChar, -1).Value =
            JsonSerializer.Serialize(request.PermissionIds);

        command.Parameters.Add(
            "@ExpectedPermissionIdsJson", SqlDbType.NVarChar, -1).Value =
            JsonSerializer.Serialize(request.ExpectedPermissionIds);

        command.Parameters.Add(
            "@Reason", SqlDbType.NVarChar, 500).Value =
            LastMile.Api.Services.AuditDataSanitizer.Text(request.Reason.Trim());

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 56001)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56002)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56003)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56004)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56005)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627 or 1205)
        {
            return Conflict(new
            {
                message = "Phân quyền đang được cập nhật đồng thời. Hãy tải lại và thử lại."
            });
        }
    }
}
