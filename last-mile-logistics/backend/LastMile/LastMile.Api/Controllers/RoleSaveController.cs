using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class SaveRoleRequest
{
    [Range(1, int.MaxValue)]
    public int? Id { get; set; }

    [Required]
    [StringLength(50)]
    [RegularExpression(
        @"^[A-Z][A-Z0-9_]*$",
        ErrorMessage = "Code phải bắt đầu bằng chữ in hoa, chỉ gồm chữ in hoa, số và dấu gạch dưới.")]
    public string Code { get; set; } = "";

    [Required]
    [StringLength(100)]
    public string Name { get; set; } = "";

    [StringLength(500)]
    public string? Description { get; set; }

    [Required]
    public bool? IsActive { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/roles")]
public class RoleSaveController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public RoleSaveController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost]
    public async Task<IActionResult> Save(
        SaveRoleRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        var name = request.Name.Trim();

        if (string.IsNullOrWhiteSpace(name))
        {
            return BadRequest(new
            {
                message = "Tên vai trò không được để trống."
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
                    @RoleId INT = @Id,
                    @OldCode VARCHAR(50),
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
                    THROW 55901,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF @ActorRole <> 'ADMIN'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                       JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                       WHERE vq.MaVaiTro = @ActorRoleId
                         AND q.KyHieuQuyen = 'PHANQUYEN_QUANLY'
                   )
                    THROW 55902,
                        N'API này dành cho admin quản lý vai trò.', 1;

                IF @RoleId IS NOT NULL
                BEGIN
                    SELECT @OldCode = KyHieuVaiTro
                    FROM dbo.VaiTro WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaVaiTro = @RoleId;

                    IF @OldCode IS NULL
                        THROW 55903,
                            N'Không tìm thấy vai trò.', 1;

                    IF @OldCode COLLATE Latin1_General_100_BIN2
                       <> @Code COLLATE Latin1_General_100_BIN2
                        THROW 55904,
                            N'Không được thay đổi mã vai trò đã tạo.', 1;

                    IF @OldCode = 'ADMIN' AND @IsActive = 0
                        THROW 55904,
                            N'Không được ngừng hoạt động vai trò ADMIN.', 1;

                    IF @IsActive = 0
                       AND EXISTS (
                           SELECT 1
                           FROM dbo.TaiKhoan WITH (UPDLOCK, HOLDLOCK)
                           WHERE MaVaiTro = @RoleId
                             AND TrangThaiTaiKhoan IN ('ACTIVE', 'LOCKED')
                       )
                        THROW 55904,
                            N'Vai trò còn tài khoản ACTIVE hoặc LOCKED. Hãy chuyển vai trò hoặc ngừng hoạt động các tài khoản trước.', 1;

                    SELECT @OldJson = (
                        SELECT
                            MaVaiTro AS id,
                            KyHieuVaiTro AS code,
                            TenVaiTro AS name,
                            MoTa AS description,
                            DangHoatDong AS isActive
                        FROM dbo.VaiTro
                        WHERE MaVaiTro = @RoleId
                        FOR JSON PATH,
                            INCLUDE_NULL_VALUES,
                            WITHOUT_ARRAY_WRAPPER
                    );

                    UPDATE dbo.VaiTro
                    SET TenVaiTro = @Name,
                        MoTa = @Description,
                        DangHoatDong = @IsActive
                    WHERE MaVaiTro = @RoleId;
                END
                ELSE
                BEGIN
                    INSERT INTO dbo.VaiTro (
                        KyHieuVaiTro,
                        TenVaiTro,
                        MoTa,
                        DangHoatDong
                    )
                    VALUES (
                        @Code,
                        @Name,
                        @Description,
                        @IsActive
                    );

                    SET @RoleId =
                        CONVERT(INT, SCOPE_IDENTITY());
                END;

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
                            FROM dbo.VaiTroQuyen vq
                            WHERE vq.MaVaiTro = vt.MaVaiTro
                        ) AS permissionCount,
                        CASE
                            WHEN @Id IS NULL
                                THEN N'Tạo vai trò thành công.'
                            ELSE N'Cập nhật vai trò thành công.'
                        END AS message
                    FROM dbo.VaiTro vt
                    WHERE vt.MaVaiTro = @RoleId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
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
                    @ActorId,
                    CASE
                        WHEN @Id IS NULL THEN 'CREATE_ROLE'
                        ELSE 'UPDATE_ROLE'
                    END,
                    'VaiTro',
                    CONVERT(VARCHAR(100), @RoleId),
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

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = actorId;

        command.Parameters.Add(
            "@Id", SqlDbType.Int).Value =
            (object?)request.Id ?? DBNull.Value;

        command.Parameters.Add(
            "@Code", SqlDbType.VarChar, 50).Value = request.Code;

        command.Parameters.Add(
            "@Name", SqlDbType.NVarChar, 100).Value = name;

        command.Parameters.Add(
            "@Description", SqlDbType.NVarChar, 500).Value =
            string.IsNullOrWhiteSpace(request.Description)
                ? DBNull.Value
                : request.Description.Trim();

        command.Parameters.Add(
            "@IsActive", SqlDbType.Bit).Value =
            request.IsActive!.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return new ContentResult
            {
                StatusCode = request.Id.HasValue
                    ? StatusCodes.Status200OK
                    : StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = result?.ToString() ?? "{}"
            };
        }
        catch (SqlException ex) when (ex.Number == 55901)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55902)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55903)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55904)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message = "Mã hoặc tên vai trò đã tồn tại."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được cập nhật đồng thời. Hãy thử lại."
            });
        }
    }
}