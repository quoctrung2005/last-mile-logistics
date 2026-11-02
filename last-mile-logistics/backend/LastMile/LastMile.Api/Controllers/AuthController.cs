using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class LoginRequest
{
    [Required]
    [StringLength(100)]
    public string Username { get; set; } = "";

    [Required]
    [StringLength(72)]
    public string Password { get; set; } = "";
}

[ApiController]
[Route("api/v1/auth")]
public class AuthController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly LoginAttemptService _loginAttempts;

    public AuthController(IConfiguration configuration, LoginAttemptService loginAttempts)
    {
        _configuration = configuration;
        _loginAttempts = loginAttempts;
    }

    [AllowAnonymous]
    [EnableRateLimiting("login")]
    [HttpPost("login")]
    public async Task<IActionResult> Login(
        LoginRequest request,
        CancellationToken cancellationToken)
    {
        // BCrypt uses at most 72 UTF-8 bytes. Do not silently truncate longer
        // inputs or require the creation-time minimum for a legacy login.
        if (Encoding.UTF8.GetByteCount(request.Password) > 72)
            return Unauthorized(new { message = "Thông tin đăng nhập không hợp lệ." });

        long accountId;
        string passwordHash;
        string status;
        DateTime? lockedUntil;
        bool roleActive;

        try
        {
            // Đọc thông tin đăng nhập, đóng kết nối trước khi
            // service mở giao dịch cấp token.
            await using (var connection = new SqlConnection(
                _configuration.GetConnectionString("DefaultConnection")))
            {
                await connection.OpenAsync(cancellationToken);

                const string sql = """
                    SELECT
                        tk.MaTaiKhoan,
                        tk.MatKhauBam,
                        tk.TrangThaiTaiKhoan,
                        tk.KhoaDenLuc,
                        vt.DangHoatDong AS VaiTroHoatDong
                    FROM dbo.TaiKhoan tk
                    INNER JOIN dbo.VaiTro vt
                        ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.TenDangNhap = @Username;
                    """;

                await using var command = new SqlCommand(
                    sql, connection);

                command.Parameters.Add(
                    "@Username", SqlDbType.VarChar, 100
                ).Value = request.Username.Trim();

                await using var reader =
                    await command.ExecuteReaderAsync(
                        cancellationToken);

                if (!await reader.ReadAsync(cancellationToken))
                {
                    return Unauthorized(new
                    {
                        message = "Thông tin đăng nhập không hợp lệ."
                    });
                }

                accountId = Convert.ToInt64(
                    reader["MaTaiKhoan"]);

                passwordHash = reader["MatKhauBam"].ToString()!;
                status = reader["TrangThaiTaiKhoan"].ToString()!;

                roleActive = Convert.ToBoolean(
                    reader["VaiTroHoatDong"]);

                lockedUntil = reader["KhoaDenLuc"] == DBNull.Value
                    ? null
                    : Convert.ToDateTime(reader["KhoaDenLuc"]);
            }

            if (status != "ACTIVE"
                || !roleActive
                || lockedUntil > DateTime.UtcNow)
            {
                return Unauthorized(new
                {
                    message = "Thông tin đăng nhập không hợp lệ."
                });
            }

            bool passwordValid;

            try
            {
                passwordValid = BCrypt.Net.BCrypt.Verify(
                    request.Password,
                    passwordHash);
            }
            catch (Exception)
            {
                passwordValid = false;
            }

            if (!passwordValid)
            {
                await _loginAttempts.RecordFailureAsync(accountId, passwordHash, cancellationToken);
                return Unauthorized(new
                {
                    message = "Thông tin đăng nhập không hợp lệ."
                });
            }

            var tokenService = new AuthTokenService(_configuration);

            // Service kiểm tra lại hash trong giao dịch khóa tài khoản,
            // cập nhật thời gian đăng nhập và cấp token.
            var result = await tokenService.IssueAsync(
                accountId,
                passwordHash,
                cancellationToken);

            return Ok(result);
        }
        catch (UnauthorizedAccessException)
        {
            return Unauthorized(new
            {
                message = "Thông tin đăng nhập không hợp lệ."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Tài khoản đang được cập nhật đồng thời. "
                    + "Hãy thử đăng nhập lại."
            });
        }
    }

    [Authorize]
    [HttpGet("permissions")]
    public async Task<IActionResult> Permissions(CancellationToken cancellationToken)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId))
            return Unauthorized();

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
        await connection.OpenAsync(cancellationToken);

        // Only the authenticated account's live grants; no role-management access.
        const string sql = """
            SELECT q.KyHieuQuyen
            FROM dbo.TaiKhoan tk
            INNER JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            INNER JOIN dbo.VaiTroQuyen vq ON vq.MaVaiTro = vt.MaVaiTro
            INNER JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME())
            ORDER BY q.KyHieuQuyen;
            """;
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = accountId;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var permissions = new List<string>();
        while (await reader.ReadAsync(cancellationToken)) permissions.Add(reader.GetString(0));
        return Ok(new { accountId, permissions });
    }

    [Authorize]
    [HttpGet("me")]
    public IActionResult Me()
    {
        return Ok(new
        {
            accountId = User.FindFirstValue(
                ClaimTypes.NameIdentifier),

            username = User.Identity?.Name,
            fullName = User.FindFirstValue("fullName"),
            role = User.FindFirstValue(ClaimTypes.Role),
            branchId = User.FindFirstValue("branchId")
        });
    }
}
