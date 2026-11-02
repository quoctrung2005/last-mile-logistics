using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;

namespace LastMile.Api.Services;

public sealed class LoginAttemptService(IConfiguration configuration, IOptions<LoginSecurityOptions> options)
{
    public async Task RecordFailureAsync(long accountId, string verifiedHash, CancellationToken cancellationToken)
    {
        await using var connection = new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand("""
            SET NOCOUNT ON;
            SET XACT_ABORT ON;
            BEGIN TRY
                BEGIN TRAN;
                DECLARE @Hash VARCHAR(255), @Count INT, @LockedUntil DATETIME2(0), @Now DATETIME2(0);
                -- Same first lock as token issuance, logout and password changes.
                SELECT @Hash = tk.MatKhauBam, @Count = tk.SoLanDangNhapSai, @LockedUntil = tk.KhoaDenLuc
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK) ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @Id AND tk.TrangThaiTaiKhoan = 'ACTIVE' AND vt.DangHoatDong = 1;
                SET @Now = SYSUTCDATETIME();

                -- BCrypt ran outside SQL. Ignore its stale result after a reset,
                -- admin lock/deactivation, or another attempt locking the account.
                IF @Hash COLLATE Latin1_General_100_BIN2 = @VerifiedHash COLLATE Latin1_General_100_BIN2
                   AND (@LockedUntil IS NULL OR @LockedUntil <= @Now)
                BEGIN
                    -- An expired temporary lock begins a fresh round. Clamp the
                    -- counter at the threshold, including concurrent submissions.
                    SET @Count = CASE WHEN @LockedUntil IS NOT NULL THEN 1
                                      WHEN @Count >= @MaxFailures THEN @MaxFailures
                                      ELSE @Count + 1 END;
                    UPDATE dbo.TaiKhoan
                    SET SoLanDangNhapSai = @Count,
                        KhoaDenLuc = CASE WHEN @Count >= @MaxFailures THEN DATEADD(MINUTE, @LockMinutes, @Now) ELSE NULL END
                    WHERE MaTaiKhoan = @Id;
                END;
                COMMIT;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK;
                THROW;
            END CATCH;
            """, connection);
        command.Parameters.Add("@Id", SqlDbType.BigInt).Value = accountId;
        command.Parameters.Add("@VerifiedHash", SqlDbType.VarChar, 255).Value = verifiedHash;
        command.Parameters.Add("@MaxFailures", SqlDbType.Int).Value = options.Value.MaxFailedAttempts;
        command.Parameters.Add("@LockMinutes", SqlDbType.Int).Value = options.Value.LockoutMinutes;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
