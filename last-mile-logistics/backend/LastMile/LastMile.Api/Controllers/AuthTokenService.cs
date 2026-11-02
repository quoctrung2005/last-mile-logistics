using System.Data;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;
using Microsoft.IdentityModel.Tokens;

namespace LastMile.Api.Services;

public class AuthTokenService
{
    private readonly IConfiguration _configuration;

    public AuthTokenService(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public Task<object> IssueAsync(
        long accountId,
        string verifiedPasswordHash,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(verifiedPasswordHash))
            throw new UnauthorizedAccessException();

        return CreateSessionAsync(
            accountId,
            null,
            verifiedPasswordHash,
            cancellationToken);
    }

    public Task<object> RefreshAsync(
        string refreshToken,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(refreshToken))
            throw new UnauthorizedAccessException();

        return CreateSessionAsync(
            null,
            refreshToken,
            null,
            cancellationToken);
    }

    private async Task<object> CreateSessionAsync(
        long? accountId,
        string? refreshToken,
        string? verifiedPasswordHash,
        CancellationToken cancellationToken)
    {
        var jwtKey = _configuration["Jwt:Key"]
            ?? throw new InvalidOperationException(
                "Chưa cấu hình Jwt:Key.");

        var issuer = _configuration["Jwt:Issuer"]
            ?? throw new InvalidOperationException(
                "Chưa cấu hình Jwt:Issuer.");

        var audience = _configuration["Jwt:Audience"]
            ?? throw new InvalidOperationException(
                "Chưa cấu hình Jwt:Audience.");

        var accessMinutes = _configuration.GetValue<int?>(
            "Jwt:ExpireMinutes") ?? 60;

        var refreshDays = _configuration.GetValue<int?>(
            "Jwt:RefreshExpireDays") ?? 7;

        if (accessMinutes is < 1 or > 1440)
        {
            throw new InvalidOperationException(
                "Jwt:ExpireMinutes phải từ 1 đến 1440.");
        }

        if (refreshDays is < 1 or > 90)
        {
            throw new InvalidOperationException(
                "Jwt:RefreshExpireDays phải từ 1 đến 90.");
        }

        var oldHash = refreshToken is null
            ? null
            : HashRefreshToken(refreshToken);

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync(cancellationToken);

        await using var transaction =
            (SqlTransaction)await connection.BeginTransactionAsync(
                cancellationToken);

        var sessionId = Guid.NewGuid();
        // Lookup only: read-committed locks end at this statement. All mutations
        // then lock account -> session -> refresh token, including logout/reset.
        if (oldHash is not null)
        {
            await using var lookup = new SqlCommand("""
                SELECT MaTaiKhoan, MaPhien
                FROM dbo.TokenLamMoi
                WHERE GiaTriBamToken = @Hash;
                """, connection, transaction);

            lookup.Parameters.Add(
                "@Hash", SqlDbType.VarChar, 255).Value = oldHash;

            // Dispose before any subsequent command uses this connection;
            // refresh must also work with MultipleActiveResultSets disabled.
            await using (var lookupReader = await lookup.ExecuteReaderAsync(cancellationToken))
            {
                if (!await lookupReader.ReadAsync(cancellationToken)
                    || lookupReader["MaPhien"] == DBNull.Value)
                    throw new UnauthorizedAccessException();
                accountId = Convert.ToInt64(lookupReader["MaTaiKhoan"]);
                sessionId = (Guid)lookupReader["MaPhien"];
            }
        }

        if (!accountId.HasValue || accountId.Value <= 0)
            throw new UnauthorizedAccessException();

        string username;
        string fullName;
        string role;
        int? branchId;

        // Khóa tài khoản đến khi giao dịch cấp token hoàn tất.
        await using (var accountCommand = new SqlCommand("""
            SELECT
                tk.TenDangNhap,
                tk.HoTen,
                tk.MaBuuCuc,
                tk.MatKhauBam,
                vt.KyHieuVaiTro
            FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @Id
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
              );
            """, connection, transaction))
        {
            accountCommand.Parameters.Add(
                "@Id", SqlDbType.BigInt).Value = accountId.Value;

            await using var reader =
                await accountCommand.ExecuteReaderAsync(
                    cancellationToken);

            if (!await reader.ReadAsync(cancellationToken))
                throw new UnauthorizedAccessException();

            // Login: hash hiện tại phải khớp hash mà
            // AuthController đã xác minh bằng BCrypt.
            if (refreshToken is null)
            {
                var currentPasswordHash =
                    reader["MatKhauBam"].ToString();

                if (!string.Equals(
                        currentPasswordHash,
                        verifiedPasswordHash,
                        StringComparison.Ordinal))
                {
                    throw new UnauthorizedAccessException();
                }
            }

            username = reader["TenDangNhap"].ToString()!;
            fullName = reader["HoTen"].ToString()!;
            role = reader["KyHieuVaiTro"].ToString()!;

            branchId = reader["MaBuuCuc"] == DBNull.Value
                ? null
                : Convert.ToInt32(reader["MaBuuCuc"]);
        }

        long? oldTokenId = null;

        if (oldHash is not null)
        {
            await using (var sessionCommand = new SqlCommand("""
                SELECT COUNT(*) FROM dbo.PhienDangNhap WITH (UPDLOCK, HOLDLOCK)
                WHERE MaPhien = @SessionId AND MaTaiKhoan = @AccountId
                  AND ThuHoiLuc IS NULL AND HetHanLuc > SYSUTCDATETIME();
                """, connection, transaction))
            {
                sessionCommand.Parameters.Add("@SessionId", SqlDbType.UniqueIdentifier).Value = sessionId;
                sessionCommand.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = accountId.Value;
                if (Convert.ToInt32(await sessionCommand.ExecuteScalarAsync(cancellationToken)) != 1)
                    throw new UnauthorizedAccessException();
            }
            await using var tokenCommand = new SqlCommand("""
                SELECT
                    MaTokenLamMoi,
                    HetHanLuc,
                    ThuHoiLuc
                FROM dbo.TokenLamMoi WITH (UPDLOCK, HOLDLOCK)
                WHERE GiaTriBamToken = @Hash
                  AND MaPhien = @SessionId
                  AND MaTaiKhoan = @AccountId;
                """, connection, transaction);

            tokenCommand.Parameters.Add(
                "@Hash", SqlDbType.VarChar, 255).Value = oldHash;
            tokenCommand.Parameters.Add("@SessionId", SqlDbType.UniqueIdentifier).Value = sessionId;

            tokenCommand.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value =
                accountId.Value;

            await using var reader =
                await tokenCommand.ExecuteReaderAsync(
                    cancellationToken);

            if (!await reader.ReadAsync(cancellationToken))
                throw new UnauthorizedAccessException();

            if (reader["ThuHoiLuc"] != DBNull.Value
                || Convert.ToDateTime(reader["HetHanLuc"])
                    <= DateTime.UtcNow)
            {
                throw new UnauthorizedAccessException();
            }

            oldTokenId = Convert.ToInt64(
                reader["MaTokenLamMoi"]);
        }

        // Đồng bộ độ chính xác với DATETIME2(0).
        var now = DateTime.UtcNow;

        now = new DateTime(
            now.Ticks - now.Ticks % TimeSpan.TicksPerSecond,
            DateTimeKind.Utc);

        var expiresAt = now.AddMinutes(accessMinutes);
        var refreshExpiresAt = now.AddDays(refreshDays);

        // Rotation extends the same session; revoking a rotated refresh token
        // never revokes the session or its previously issued access tokens.
        await using (var sessionCommand = new SqlCommand(refreshToken is null ? """
            INSERT dbo.PhienDangNhap(MaPhien, MaTaiKhoan, ThoiGianTao, HetHanLuc)
            VALUES(@SessionId, @AccountId, @Now, @ExpiresAt);
            """ : """
            UPDATE dbo.PhienDangNhap SET HetHanLuc = @ExpiresAt
            WHERE MaPhien = @SessionId AND MaTaiKhoan = @AccountId AND ThuHoiLuc IS NULL;
            """, connection, transaction))
        {
            sessionCommand.Parameters.Add("@SessionId", SqlDbType.UniqueIdentifier).Value = sessionId;
            sessionCommand.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = accountId.Value;
            sessionCommand.Parameters.Add("@Now", SqlDbType.DateTime2).Value = now;
            sessionCommand.Parameters.Add("@ExpiresAt", SqlDbType.DateTime2).Value = refreshExpiresAt;
            if (await sessionCommand.ExecuteNonQueryAsync(cancellationToken) != 1)
                throw new UnauthorizedAccessException();
        }

        // Chỉ cập nhật thời gian đăng nhập khi login,
        // trong cùng giao dịch cấp token.
        if (refreshToken is null)
        {
            await using var updateLoginCommand = new SqlCommand("""
                UPDATE dbo.TaiKhoan
                SET DangNhapCuoiLuc = @Now,
                    SoLanDangNhapSai = 0,
                    KhoaDenLuc = NULL
                WHERE MaTaiKhoan = @Id;
                """, connection, transaction);

            updateLoginCommand.Parameters.Add(
                "@Id", SqlDbType.BigInt).Value = accountId.Value;

            var loginTimeParameter =
                updateLoginCommand.Parameters.Add(
                    "@Now", SqlDbType.DateTime2);

            loginTimeParameter.Scale = 0;
            loginTimeParameter.Value = now;

            await updateLoginCommand.ExecuteNonQueryAsync(
                cancellationToken);
        }

        var newRefreshToken = Base64UrlEncoder.Encode(
            RandomNumberGenerator.GetBytes(32));

        var newRefreshHash = HashRefreshToken(newRefreshToken);

        var claims = new List<Claim>
        {
            new(
                ClaimTypes.NameIdentifier,
                accountId.Value.ToString()),

            new(ClaimTypes.Name, username),
            new(ClaimTypes.Role, role),
            new("sid", sessionId.ToString("N")),
            new("fullName", fullName),

            new(
                JwtRegisteredClaimNames.Jti,
                Guid.NewGuid().ToString("N"))
        };

        if (branchId.HasValue)
        {
            claims.Add(new Claim(
                "branchId",
                branchId.Value.ToString()));
        }

        var jwt = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            notBefore: now,
            expires: expiresAt,
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(
                    Encoding.UTF8.GetBytes(jwtKey)),
                SecurityAlgorithms.HmacSha256));

        var accessToken =
            new JwtSecurityTokenHandler().WriteToken(jwt);

        // Refresh token được xoay vòng:
        // thu hồi token cũ và tạo token mới trong cùng giao dịch.
        if (oldTokenId.HasValue)
        {
            await using var revokeCommand = new SqlCommand("""
                UPDATE dbo.TokenLamMoi
                SET ThuHoiLuc = @Now,
                    TokenThayTheBam = @NewHash
                WHERE MaTokenLamMoi = @Id
                  AND ThuHoiLuc IS NULL;
                """, connection, transaction);

            var revokedAtParameter =
                revokeCommand.Parameters.Add(
                    "@Now", SqlDbType.DateTime2);

            revokedAtParameter.Scale = 0;
            revokedAtParameter.Value = now;

            revokeCommand.Parameters.Add(
                "@NewHash", SqlDbType.VarChar, 255).Value =
                newRefreshHash;

            revokeCommand.Parameters.Add(
                "@Id", SqlDbType.BigInt).Value = oldTokenId.Value;

            var affectedRows =
                await revokeCommand.ExecuteNonQueryAsync(
                    cancellationToken);

            if (affectedRows != 1)
                throw new UnauthorizedAccessException();
        }

        await using (var insertCommand = new SqlCommand("""
            INSERT INTO dbo.TokenLamMoi (
                MaTaiKhoan,
                MaPhien,
                GiaTriBamToken,
                HetHanLuc,
                ThoiGianTao
            )
            VALUES (
                @AccountId,
                @SessionId,
                @Hash,
                @ExpiresAt,
                @Now
            );
            """, connection, transaction))
        {
            insertCommand.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value =
                accountId.Value;
            insertCommand.Parameters.Add("@SessionId", SqlDbType.UniqueIdentifier).Value = sessionId;

            insertCommand.Parameters.Add(
                "@Hash", SqlDbType.VarChar, 255).Value =
                newRefreshHash;

            var refreshExpiryParameter =
                insertCommand.Parameters.Add(
                    "@ExpiresAt", SqlDbType.DateTime2);

            refreshExpiryParameter.Scale = 0;
            refreshExpiryParameter.Value = refreshExpiresAt;

            var createdAtParameter =
                insertCommand.Parameters.Add(
                    "@Now", SqlDbType.DateTime2);

            createdAtParameter.Scale = 0;
            createdAtParameter.Value = now;

            await insertCommand.ExecuteNonQueryAsync(
                cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);

        return new
        {
            accessToken,
            refreshToken = newRefreshToken,
            tokenType = "Bearer",
            expiresAt,
            refreshExpiresAt,

            user = new
            {
                accountId = accountId.Value,
                username,
                fullName,
                role,
                branchId
            }
        };
    }

    private static string HashRefreshToken(string token)
    {
        return Convert.ToHexString(
            SHA256.HashData(
                Encoding.UTF8.GetBytes(token)));
    }
}
