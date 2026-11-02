using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CreateAccountRequest
{
    [Required]
    [StringLength(100, MinimumLength = 3)]
    [RegularExpression(
        @"^[A-Za-z0-9][A-Za-z0-9._-]*$",
        ErrorMessage = "Username chỉ gồm chữ Latin, số, dấu chấm, gạch dưới hoặc gạch ngang.")]
    public string Username { get; set; } = "";

    [Required]
    [StringLength(72, MinimumLength = 8)]
    public string Password { get; set; } = "";

    [Required]
    [StringLength(150)]
    public string FullName { get; set; } = "";

    [RegularExpression(
        @"^\+?[0-9]{9,15}$",
        ErrorMessage = "Số điện thoại phải có từ 9 đến 15 chữ số.")]
    public string? Phone { get; set; }

    [EmailAddress]
    [StringLength(150)]
    public string? Email { get; set; }

    [Range(1, int.MaxValue)]
    public int RoleId { get; set; }

    [Range(1, int.MaxValue)]
    public int? BranchId { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/accounts")]
public class AccountCreateController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public AccountCreateController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost]
    public async Task<IActionResult> Create(
        CreateAccountRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        var fullName = request.FullName.Trim();

        if (string.IsNullOrWhiteSpace(fullName))
        {
            return BadRequest(new
            {
                message = "Họ tên không được để trống."
            });
        }

        if (string.IsNullOrWhiteSpace(request.Password))
        {
            return BadRequest(new
            {
                message = "Mật khẩu không được chỉ chứa khoảng trắng."
            });
        }

        if (Encoding.UTF8.GetByteCount(request.Password) > 72)
        {
            return BadRequest(new
            {
                message = "Mật khẩu không được vượt quá 72 byte UTF-8."
            });
        }

        var username = request.Username.ToLowerInvariant();

        var accountCode = "TK-" + Guid.NewGuid()
            .ToString("N")[..27]
            .ToUpperInvariant();

        var passwordHash = BCrypt.Net.BCrypt.HashPassword(
            request.Password,
            workFactor: 12);

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @ActorRole VARCHAR(50),
                    @ActorRoleId INT,
                    @ActorBranch INT,
                    @TargetRole VARCHAR(50),
                    @Result NVARCHAR(MAX);

                SELECT
                    @ActorRole = vt.KyHieuVaiTro,
                    @ActorRoleId = tk.MaVaiTro,
                    @ActorBranch = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
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
                    THROW 55501,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @ActorRoleId
                      AND q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                )
                    THROW 55502,
                        N'Bạn không có quyền tạo tài khoản.', 1;

                SELECT @TargetRole = KyHieuVaiTro
                FROM dbo.VaiTro WITH (HOLDLOCK)
                WHERE MaVaiTro = @RoleId
                  AND DangHoatDong = 1;

                IF @TargetRole IS NULL
                    THROW 55504,
                        N'Vai trò không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF @TargetRole <> 'ADMIN' AND @BranchId IS NULL
                    THROW 55504,
                        N'Tài khoản không phải admin phải được gắn với bưu cục.', 1;

                IF @BranchId IS NOT NULL
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.BuuCuc WITH (HOLDLOCK)
                       WHERE MaBuuCuc = @BranchId
                         AND DangHoatDong = 1
                   )
                    THROW 55504,
                        N'Bưu cục không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF @ActorRole <> 'ADMIN'
                BEGIN
                    IF @TargetRole = 'ADMIN'
                        THROW 55502,
                            N'Bạn không được tạo tài khoản admin.', 1;

                    IF @ActorBranch IS NULL
                       OR @BranchId IS NULL
                       OR @BranchId <> @ActorBranch
                        THROW 55502,
                            N'Bạn chỉ được tạo tài khoản trong bưu cục của mình.', 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.VaiTroQuyen targetPermission
                            WITH (HOLDLOCK)
                        WHERE targetPermission.MaVaiTro = @RoleId
                          AND NOT EXISTS (
                              SELECT 1
                              FROM dbo.VaiTroQuyen actorPermission
                                  WITH (HOLDLOCK)
                              WHERE actorPermission.MaVaiTro = @ActorRoleId
                                AND actorPermission.MaQuyen =
                                    targetPermission.MaQuyen
                          )
                    )
                        THROW 55502,
                            N'Bạn không được cấp vai trò có quyền vượt quá quyền của mình.', 1;
                END;

                INSERT INTO dbo.TaiKhoan (
                    KyHieuTaiKhoan,
                    TenDangNhap,
                    MatKhauBam,
                    HoTen,
                    SoDienThoai,
                    Email,
                    MaVaiTro,
                    MaBuuCuc,
                    TrangThaiTaiKhoan
                )
                VALUES (
                    @AccountCode,
                    @Username,
                    @PasswordHash,
                    @FullName,
                    @Phone,
                    @Email,
                    @RoleId,
                    @BranchId,
                    'ACTIVE'
                );

                DECLARE @NewAccountId BIGINT =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                SELECT @Result = (
                    SELECT
                        tk.MaTaiKhoan AS id,
                        tk.KyHieuTaiKhoan AS accountCode,
                        tk.TenDangNhap AS username,
                        tk.HoTen AS fullName,
                        tk.SoDienThoai AS phone,
                        tk.Email AS email,
                        tk.MaVaiTro AS roleId,
                        vt.KyHieuVaiTro AS role,
                        tk.MaBuuCuc AS branchId,
                        tk.TrangThaiTaiKhoan AS status,
                        tk.ThoiGianTao AS createdAt,
                        CONVERT(VARBINARY(8), tk.PhienBan) AS version,
                        N'Tạo tài khoản thành công.' AS message
                    FROM dbo.TaiKhoan tk
                    JOIN dbo.VaiTro vt
                        ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @NewAccountId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                -- Không lưu mật khẩu hoặc hash vào nhật ký.
                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan,
                    LoaiThaoTac,
                    TenDoiTuong,
                    MaDoiTuong,
                    DuLieuMoiJson
                )
                VALUES (
                    @ActorId,
                    'CREATE_ACCOUNT',
                    'TaiKhoan',
                    CONVERT(VARCHAR(100), @NewAccountId),
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
            "@AccountCode", SqlDbType.VarChar, 30).Value =
            accountCode;

        command.Parameters.Add(
            "@Username", SqlDbType.VarChar, 100).Value =
            username;

        command.Parameters.Add(
            "@PasswordHash", SqlDbType.VarChar, 255).Value =
            passwordHash;

        command.Parameters.Add(
            "@FullName", SqlDbType.NVarChar, 150).Value =
            fullName;

        command.Parameters.Add(
            "@Phone", SqlDbType.VarChar, 20).Value =
            OptionalText(request.Phone);

        command.Parameters.Add(
            "@Email", SqlDbType.VarChar, 150).Value =
            OptionalText(request.Email);

        command.Parameters.Add(
            "@RoleId", SqlDbType.Int).Value = request.RoleId;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
            (object?)request.BranchId ?? DBNull.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return new ContentResult
            {
                StatusCode = StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = result?.ToString() ?? "{}"
            };
        }
        catch (SqlException ex) when (ex.Number == 55501)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55502)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55504)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message = "Tên đăng nhập, số điện thoại, email hoặc mã tài khoản đã tồn tại."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy thử lại."
            });
        }
    }

    private static object OptionalText(string? value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? DBNull.Value
            : value.Trim();
    }
}