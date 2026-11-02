using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Net;
using System.Net.Mail;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Data.SqlClient;
using Microsoft.IdentityModel.Tokens;

namespace LastMile.Api.Controllers;

public class PasswordRecoveryRequest
{
    [Required]
    [RegularExpression("^(REQUEST|RESET)$")]
    public string Action { get; set; } = "";

    [EmailAddress]
    [StringLength(150)]
    public string? Email { get; set; }

    [StringLength(43, MinimumLength = 43)]
    [RegularExpression(@"^[A-Za-z0-9_-]{43}$")]
    public string? RecoveryToken { get; set; }

    [StringLength(72, MinimumLength = 8)]
    public string? NewPassword { get; set; }

    [Compare(
        nameof(NewPassword),
        ErrorMessage = "Xác nhận mật khẩu không khớp.")]
    public string? ConfirmPassword { get; set; }
}

[ApiController]
[AllowAnonymous]
[EnableRateLimiting("password-recovery")]
[Route("api/v1/auth")]
public class AuthPasswordRecoveryController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<AuthPasswordRecoveryController> _logger;

    public AuthPasswordRecoveryController(
        IConfiguration configuration,
        ILogger<AuthPasswordRecoveryController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPost("password-recovery")]
    public async Task<IActionResult> Execute(
        PasswordRecoveryRequest request,
        CancellationToken cancellationToken)
    {
        if (request.Action == "REQUEST")
        {
            if (string.IsNullOrWhiteSpace(request.Email))
                return BadRequest(new { message = "Phải nhập email." });

            return await RequestRecovery(
                request.Email.Trim(),
                cancellationToken);
        }

        if (string.IsNullOrWhiteSpace(request.RecoveryToken))
        {
            return BadRequest(new
            {
                message = "Phải nhập mã khôi phục."
            });
        }

        if (string.IsNullOrWhiteSpace(request.NewPassword)
            || string.IsNullOrWhiteSpace(request.ConfirmPassword))
        {
            return BadRequest(new
            {
                message = "Phải nhập mật khẩu mới và xác nhận mật khẩu."
            });
        }

        if (Encoding.UTF8.GetByteCount(request.NewPassword) > 72)
        {
            return BadRequest(new
            {
                message = "Mật khẩu không được vượt quá 72 byte UTF-8."
            });
        }

        return await ResetPassword(
            request.RecoveryToken,
            request.NewPassword,
            cancellationToken);
    }

    private async Task<IActionResult> RequestRecovery(
        string email,
        CancellationToken cancellationToken)
    {
        var host = _configuration["Email:Host"];
        var from = _configuration["Email:From"];
        var username = _configuration["Email:Username"];
        var password = _configuration["Email:Password"];

        var port = _configuration.GetValue<int?>("Email:Port") ?? 587;

        if (string.IsNullOrWhiteSpace(host)
            || string.IsNullOrWhiteSpace(username)
            || string.IsNullOrWhiteSpace(password)
            || port is < 1 or > 65535
            || !MailAddress.TryCreate(from, out var fromAddress))
        {
            return StatusCode(503, new
            {
                message = "Chưa cấu hình dịch vụ gửi email khôi phục."
            });
        }

        var recoveryToken = Base64UrlEncoder.Encode(
            RandomNumberGenerator.GetBytes(32));

        var tokenHash = HashToken(recoveryToken);

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync(cancellationToken);

        await using var command = new SqlCommand("""
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @AccountId BIGINT,
                    @Recipient VARCHAR(150),
                    @Created BIT = 0,
                    @Now DATETIME2(0);

                SELECT
                    @AccountId = tk.MaTaiKhoan,
                    @Recipient = tk.Email
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.Email = @Email
                  AND tk.TrangThaiTaiKhoan IN ('ACTIVE', 'LOCKED')
                  AND vt.DangHoatDong = 1;

                SET @Now = SYSUTCDATETIME();

                -- Tối đa một mã mới mỗi phút cho một tài khoản.
                -- Yêu cầu mới không vô hiệu hóa mã cũ.
                IF @AccountId IS NOT NULL
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.TokenKhoiPhucMatKhau
                           WITH (UPDLOCK, HOLDLOCK)
                       WHERE MaTaiKhoan = @AccountId
                         AND ThoiGianTao > DATEADD(MINUTE, -1, @Now)
                   )
                BEGIN
                    INSERT INTO dbo.TokenKhoiPhucMatKhau (
                        MaTaiKhoan,
                        GiaTriBamToken,
                        ThoiGianTao,
                        HetHanLuc
                    )
                    VALUES (
                        @AccountId,
                        @Hash,
                        @Now,
                        DATEADD(MINUTE, 15, @Now)
                    );

                    SET @Created = 1;
                END;

                COMMIT;

                SELECT CASE
                    WHEN @Created = 1 THEN @Recipient
                    ELSE NULL
                END;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK;
                THROW;
            END CATCH;
            """, connection);

        command.Parameters.Add(
            "@Email", SqlDbType.VarChar, 150).Value = email;

        command.Parameters.Add(
            "@Hash", SqlDbType.VarChar, 64).Value = tokenHash;

        var recipientValue = await command.ExecuteScalarAsync(
            cancellationToken);

        if (recipientValue is not null && recipientValue != DBNull.Value)
        {
            try
            {
                using var message = new MailMessage
                {
                    From = fromAddress,
                    Subject = "Khôi phục mật khẩu Last-mile Logistics",
                    Body = $"""
                        Bạn vừa yêu cầu khôi phục mật khẩu.

                        Mã khôi phục:
                        {recoveryToken}

                        Mã có hiệu lực trong 15 phút và chỉ sử dụng một lần.

                        Nếu bạn không yêu cầu, hãy bỏ qua email này.
                        """,
                    IsBodyHtml = false
                };

                message.To.Add(recipientValue.ToString()!);

                using var smtp = new SmtpClient(host, port)
                {
                    EnableSsl = _configuration.GetValue<bool?>(
                        "Email:EnableSsl") ?? true,
                    UseDefaultCredentials = false,
                    Credentials = new NetworkCredential(username, password)
                };

                await smtp.SendMailAsync(message);
            }
            catch (SmtpException ex)
            {
                // Không ghi mã khôi phục vào log.
                _logger.LogError(ex, "Không thể gửi email khôi phục mật khẩu.");
            }
        }

        // Cùng thông báo cho email tồn tại, không tồn tại
        // hoặc yêu cầu vừa được gửi gần đây.
        return Ok(new
        {
            message = "Nếu email thuộc tài khoản hợp lệ, mã khôi phục sẽ được gửi đến email đó. Nếu chưa nhận được, hãy chờ ít nhất một phút trước khi thử lại."
        });
    }

    private async Task<IActionResult> ResetPassword(
        string recoveryToken,
        string newPassword,
        CancellationToken cancellationToken)
    {
        var tokenHash = HashToken(recoveryToken);

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync(cancellationToken);

        long accountId;

        await using (var lookup = new SqlCommand("""
            SELECT MaTaiKhoan
            FROM dbo.TokenKhoiPhucMatKhau
            WHERE GiaTriBamToken = @Hash
              AND DaDungLuc IS NULL
              AND HetHanLuc > SYSUTCDATETIME();
            """, connection))
        {
            lookup.Parameters.Add(
                "@Hash", SqlDbType.VarChar, 64).Value = tokenHash;

            var value = await lookup.ExecuteScalarAsync(cancellationToken);

            if (value is null || value == DBNull.Value)
                return InvalidRecoveryToken();

            accountId = Convert.ToInt64(value);
        }

        var passwordHash = BCrypt.Net.BCrypt.HashPassword(
            newPassword,
            workFactor: 12);

        await using var command = new SqlCommand("""
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                    JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                        ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @AccountId
                      AND tk.TrangThaiTaiKhoan IN ('ACTIVE', 'LOCKED')
                      AND vt.DangHoatDong = 1
                )
                    THROW 56201,
                        N'Mã khôi phục không hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.TokenKhoiPhucMatKhau WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaTaiKhoan = @AccountId
                      AND GiaTriBamToken = @Hash
                      AND DaDungLuc IS NULL
                      AND HetHanLuc > SYSUTCDATETIME()
                )
                    THROW 56201,
                        N'Mã khôi phục không hợp lệ.', 1;

                DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

                UPDATE dbo.TaiKhoan
                SET MatKhauBam = @PasswordHash,
                    SoLanDangNhapSai = 0,
                    ThoiGianCapNhat = @Now
                WHERE MaTaiKhoan = @AccountId;

                -- Đổi mật khẩu không tự mở khóa tài khoản.
                UPDATE dbo.TokenKhoiPhucMatKhau
                SET DaDungLuc = @Now
                WHERE MaTaiKhoan = @AccountId
                  AND DaDungLuc IS NULL;

                UPDATE dbo.PhienDangNhap
                SET ThuHoiLuc = @Now
                WHERE MaTaiKhoan = @AccountId AND ThuHoiLuc IS NULL;

                UPDATE dbo.TokenLamMoi
                SET ThuHoiLuc = @Now
                WHERE MaTaiKhoan = @AccountId
                  AND ThuHoiLuc IS NULL;

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan,
                    LoaiThaoTac,
                    TenDoiTuong,
                    MaDoiTuong,
                    DuLieuMoiJson
                )
                VALUES (
                    @AccountId,
                    'RESET_PASSWORD',
                    'TaiKhoan',
                    CONVERT(VARCHAR(100), @AccountId),
                    N'{"method":"EMAIL_RECOVERY"}'
                );

                COMMIT;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK;
                THROW;
            END CATCH;
            """, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Hash", SqlDbType.VarChar, 64).Value = tokenHash;

        command.Parameters.Add(
            "@PasswordHash", SqlDbType.VarChar, 255).Value = passwordHash;

        try
        {
            await command.ExecuteNonQueryAsync(cancellationToken);

            return Ok(new
            {
                message = "Đặt lại mật khẩu thành công. Hãy đăng nhập bằng mật khẩu mới."
            });
        }
        catch (SqlException ex) when (ex.Number == 56201)
        {
            return InvalidRecoveryToken();
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Yêu cầu đang được xử lý đồng thời. Hãy thử lại."
            });
        }
    }

    private IActionResult InvalidRecoveryToken()
    {
        return Unauthorized(new
        {
            message = "Mã khôi phục không hợp lệ, đã hết hạn hoặc đã được sử dụng."
        });
    }

    private static string HashToken(string token)
    {
        return Convert.ToHexString(
            SHA256.HashData(Encoding.UTF8.GetBytes(token)));
    }
}
