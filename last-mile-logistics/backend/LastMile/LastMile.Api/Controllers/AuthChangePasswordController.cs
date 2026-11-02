using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class ChangePasswordRequest
{
    [Required]
    [StringLength(72)]
    public string CurrentPassword { get; set; } = "";

    [Required]
    [StringLength(72, MinimumLength = 8)]
    public string NewPassword { get; set; } = "";

    [Required]
    [Compare(
        nameof(NewPassword),
        ErrorMessage = "Xác nhận mật khẩu không khớp.")]
    public string ConfirmPassword { get; set; } = "";
}

[ApiController]
[Authorize]
[Route("api/v1/auth")]
public class AuthChangePasswordController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public AuthChangePasswordController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword(
        ChangePasswordRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        if (string.IsNullOrWhiteSpace(request.NewPassword))
        {
            return BadRequest(new
            {
                message = "Mật khẩu mới không được chỉ chứa khoảng trắng."
            });
        }

        if (Encoding.UTF8.GetByteCount(request.CurrentPassword) > 72
            || Encoding.UTF8.GetByteCount(request.NewPassword) > 72)
        {
            return BadRequest(new
            {
                message = "Mật khẩu không được vượt quá 72 byte UTF-8."
            });
        }

        if (request.CurrentPassword == request.NewPassword)
        {
            return BadRequest(new
            {
                message = "Mật khẩu mới phải khác mật khẩu hiện tại."
            });
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync(cancellationToken);

        string oldPasswordHash;

        await using (var readCommand = new SqlCommand("""
            SELECT tk.MatKhauBam
            FROM dbo.TaiKhoan tk
            INNER JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
              );
            """, connection))
        {
            readCommand.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value = accountId;

            var value = await readCommand.ExecuteScalarAsync(
                cancellationToken);

            if (value is null || value == DBNull.Value)
                return Unauthorized();

            oldPasswordHash = value.ToString()!;
        }

        bool passwordValid;

        try
        {
            passwordValid = BCrypt.Net.BCrypt.Verify(
                request.CurrentPassword,
                oldPasswordHash);
        }
        catch (Exception)
        {
            passwordValid = false;
        }

        if (!passwordValid)
        {
            return BadRequest(new
            {
                message = "Mật khẩu hiện tại không đúng."
            });
        }

        var newPasswordHash = BCrypt.Net.BCrypt.HashPassword(
            request.NewPassword,
            workFactor: 12);

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @CurrentHash VARCHAR(255),
                    @Result NVARCHAR(MAX);

                -- Kiểm tra lại trạng thái và hash sau khi
                -- xác minh mật khẩu ở phía C#.
                SELECT @CurrentHash = tk.MatKhauBam
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @AccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @CurrentHash IS NULL
                    THROW 56101,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF @CurrentHash COLLATE Latin1_General_100_BIN2
                   <> @OldHash COLLATE Latin1_General_100_BIN2
                    THROW 56104,
                        N'Mật khẩu đã thay đổi trong lúc xử lý. Hãy đăng nhập lại.', 1;

                UPDATE dbo.TaiKhoan
                SET MatKhauBam = @NewHash,
                    SoLanDangNhapSai = 0,
                    ThoiGianCapNhat = SYSUTCDATETIME()
                WHERE MaTaiKhoan = @AccountId;

                UPDATE dbo.PhienDangNhap
                SET ThuHoiLuc = SYSUTCDATETIME()
                WHERE MaTaiKhoan = @AccountId AND ThuHoiLuc IS NULL;

                UPDATE dbo.TokenLamMoi
                SET ThuHoiLuc = SYSUTCDATETIME()
                WHERE MaTaiKhoan = @AccountId
                  AND ThuHoiLuc IS NULL;

                SELECT @Result = (
                    SELECT
                        tk.MaTaiKhoan AS accountId,
                        tk.ThoiGianCapNhat AS changedAt,
                        N'Đổi mật khẩu thành công. Hãy đăng nhập lại.'
                            AS message
                    FROM dbo.TaiKhoan tk
                    WHERE tk.MaTaiKhoan = @AccountId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
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
                    @AccountId,
                    'CHANGE_PASSWORD',
                    'TaiKhoan',
                    CONVERT(VARCHAR(100), @AccountId),
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
            "@OldHash", SqlDbType.VarChar, 255).Value =
            oldPasswordHash;

        command.Parameters.Add(
            "@NewHash", SqlDbType.VarChar, 255).Value =
            newPasswordHash;

        try
        {
            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 56101)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56104)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Tài khoản đang được cập nhật đồng thời. Hãy thử lại."
            });
        }
    }
}
