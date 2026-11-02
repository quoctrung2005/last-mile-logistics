using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class LogoutRequest
{
    [Required]
    [StringLength(43, MinimumLength = 43)]
    [RegularExpression(@"^[A-Za-z0-9_-]{43}$")]
    public string RefreshToken { get; set; } = "";

    public bool AllSessions { get; set; }
}

[ApiController]
[Route("api/v1/auth")]
public class AuthLogoutController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public AuthLogoutController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [AllowAnonymous]
    [HttpPost("logout")]
    public async Task<IActionResult> Logout(
        LogoutRequest request,
        CancellationToken cancellationToken)
    {
        var tokenHash = Convert.ToHexString(
            SHA256.HashData(
                Encoding.UTF8.GetBytes(request.RefreshToken)));

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @AccountId BIGINT,
                    @SessionId UNIQUEIDENTIFIER,
                    @LockedAccountId BIGINT,
                    @RevokedCount INT = 0,
                    @Now DATETIME2(0),
                    @AuditJson NVARCHAR(MAX);

                SELECT @AccountId = MaTaiKhoan, @SessionId = MaPhien
                FROM dbo.TokenLamMoi
                WHERE GiaTriBamToken = @Hash;

                IF @AccountId IS NOT NULL
                BEGIN
                    -- Cùng thứ tự khóa với service refresh:
                    -- tài khoản -> phiên -> token.
                    SELECT @LockedAccountId = MaTaiKhoan
                    FROM dbo.TaiKhoan WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaTaiKhoan = @AccountId;

                    SET @Now = SYSUTCDATETIME();

                    -- A rotated predecessor still identifies this session. This
                    -- makes logout safe when refresh won the account lock first.
                    -- Revocation of that predecessor alone is NOT session state.
                    IF EXISTS (
                        SELECT 1 FROM dbo.PhienDangNhap WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaTaiKhoan = @AccountId AND MaPhien = @SessionId
                          AND ThuHoiLuc IS NULL AND HetHanLuc > @Now
                    ) AND EXISTS (
                        SELECT 1 FROM dbo.TokenLamMoi WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaTaiKhoan = @AccountId AND MaPhien = @SessionId
                          AND GiaTriBamToken = @Hash AND HetHanLuc > @Now
                          AND (ThuHoiLuc IS NULL OR TokenThayTheBam IS NOT NULL)
                    )
                    BEGIN
                        UPDATE dbo.PhienDangNhap
                        SET ThuHoiLuc = @Now
                        WHERE MaTaiKhoan = @AccountId AND ThuHoiLuc IS NULL
                          AND (@AllSessions = 1 OR MaPhien = @SessionId);

                        UPDATE dbo.TokenLamMoi
                        SET ThuHoiLuc = @Now
                        WHERE MaTaiKhoan = @AccountId AND ThuHoiLuc IS NULL
                          AND (@AllSessions = 1 OR MaPhien = @SessionId);
                        SET @RevokedCount = @@ROWCOUNT;
                    END;

                    IF @RevokedCount > 0
                    BEGIN
                        SELECT @AuditJson = (
                            SELECT
                                @AllSessions AS allSessions,
                                @RevokedCount AS revokedRefreshTokenCount
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        );

                        INSERT INTO dbo.NhatKyHoatDong (
                            MaTaiKhoan,
                            LoaiThaoTac,
                            TenDoiTuong,
                            MaDoiTuong,
                            DuLieuMoiJson
                        )
                        VALUES (
                            @AccountId,
                            'LOGOUT',
                            'TaiKhoan',
                            CONVERT(VARCHAR(100), @AccountId),
                            @AuditJson
                        );
                    END;
                END;

                COMMIT;
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
            "@Hash", SqlDbType.VarChar, 255).Value = tokenHash;

        command.Parameters.Add(
            "@AllSessions", SqlDbType.Bit).Value =
            request.AllSessions;

        try
        {
            await connection.OpenAsync(cancellationToken);

            await command.ExecuteNonQueryAsync(cancellationToken);

            return Ok(new
            {
                message = "Đã xử lý yêu cầu đăng xuất. Hãy xóa token đã lưu trên thiết bị."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Phiên đăng nhập đang được cập nhật đồng thời. Hãy thử lại."
            });
        }
    }
}
