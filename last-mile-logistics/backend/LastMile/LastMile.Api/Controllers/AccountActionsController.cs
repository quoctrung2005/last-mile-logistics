using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class AccountActionRequest
{
    [Required]
    [RegularExpression("^(LOCK|UNLOCK|DEACTIVATE|ACTIVATE)$")]
    public string Action { get; set; } = "";

    [Required]
    [StringLength(500)]
    public string Reason { get; set; } = "";

    [Required]
    [StringLength(16)]
    public string ExpectedVersion { get; set; } = "";
}

public class AdminResetPasswordRequest
{
    [Required, StringLength(72, MinimumLength = 8)]
    public string NewPassword { get; set; } = "";

    [Required, StringLength(500)]
    public string Reason { get; set; } = "";

    [Required, StringLength(16)]
    public string ExpectedVersion { get; set; } = "";
}

[ApiController]
[Authorize]
[Route("api/v1/accounts")]
public class AccountActionsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public AccountActionsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    // Administrative reset: account-management permission AND live ADMIN role.
    // Self-service password changes remain in AuthChangePasswordController.
    [HttpPost("{id:long}/reset-password")]
    public async Task<IActionResult> ResetPassword(long id, AdminResetPasswordRequest request, CancellationToken cancellationToken)
    {
        if (id <= 0) return BadRequest(new { message = "Mã tài khoản không hợp lệ." });
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var actorId)) return Unauthorized();
        if (string.IsNullOrWhiteSpace(request.Reason)) return BadRequest(new { message = "Phải nhập lý do." });
        if (string.IsNullOrWhiteSpace(request.NewPassword) || Encoding.UTF8.GetByteCount(request.NewPassword) > 72)
            return BadRequest(new { message = "Mật khẩu không được chỉ chứa khoảng trắng hoặc vượt quá 72 byte UTF-8." });
        if (request.Reason.Contains(request.NewPassword, StringComparison.Ordinal))
            return BadRequest(new { message = "Không ghi mật khẩu vào lý do." });
        byte[] version;
        try { version = Convert.FromBase64String(request.ExpectedVersion); }
        catch (FormatException) { return BadRequest(new { message = "ExpectedVersion phải là Base64 hợp lệ." }); }
        if (version.Length != 8) return BadRequest(new { message = "ExpectedVersion phải có 8 byte." });

        await using var connection = new SqlConnection(_configuration.GetConnectionString("DefaultConnection"));
        await using var command = new SqlCommand("""
            SET NOCOUNT ON;
            SET XACT_ABORT ON;
            BEGIN TRY
                BEGIN TRAN;
                DECLARE @RoleId INT, @Role VARCHAR(50), @Version BINARY(8), @Result NVARCHAR(MAX);
                -- Lock both accounts in ID order, including concurrent admin
                -- resets of each other. Then lock sessions before refresh tokens.
                DECLARE @FirstId BIGINT = CASE WHEN @ActorId < @TargetId THEN @ActorId ELSE @TargetId END,
                        @SecondId BIGINT = CASE WHEN @ActorId < @TargetId THEN @TargetId ELSE @ActorId END,
                        @LockedId BIGINT;
                SELECT @LockedId = MaTaiKhoan FROM dbo.TaiKhoan WITH (UPDLOCK, HOLDLOCK) WHERE MaTaiKhoan = @FirstId;
                SELECT @LockedId = MaTaiKhoan FROM dbo.TaiKhoan WITH (UPDLOCK, HOLDLOCK) WHERE MaTaiKhoan = @SecondId;
                SELECT @RoleId = tk.MaVaiTro, @Role = vt.KyHieuVaiTro
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK) ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1 AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());
                IF @Role IS NULL THROW 55701, N'Tài khoản không còn hợp lệ.', 1;
                IF @Role <> 'ADMIN' OR NOT EXISTS (
                    SELECT 1 FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK) JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @RoleId AND q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                ) THROW 55702, N'Chỉ admin có quyền quản lý tài khoản được đặt lại mật khẩu.', 1;
                IF @ActorId = @TargetId THROW 55702, N'Hãy dùng chức năng đổi mật khẩu của tôi cho chính tài khoản đang đăng nhập.', 1;
                SELECT @Version = PhienBan FROM dbo.TaiKhoan WITH (UPDLOCK, HOLDLOCK) WHERE MaTaiKhoan = @TargetId;
                IF @Version IS NULL THROW 55703, N'Không tìm thấy tài khoản.', 1;
                IF @Version <> @ExpectedVersion THROW 55704, N'Tài khoản đã thay đổi. Hãy tải lại version mới.', 1;
                DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
                UPDATE dbo.TaiKhoan SET MatKhauBam = @Hash, ThoiGianCapNhat = @Now
                WHERE MaTaiKhoan = @TargetId AND PhienBan = @ExpectedVersion;
                IF @@ROWCOUNT <> 1 THROW 55704, N'Tài khoản đã thay đổi. Hãy tải lại.', 1;
                -- Reset does not activate/unlock accounts or clear failed-login counters.
                UPDATE dbo.PhienDangNhap SET ThuHoiLuc = @Now WHERE MaTaiKhoan = @TargetId AND ThuHoiLuc IS NULL;
                UPDATE dbo.TokenLamMoi SET ThuHoiLuc = @Now WHERE MaTaiKhoan = @TargetId AND ThuHoiLuc IS NULL;
                IF OBJECT_ID(N'dbo.TokenKhoiPhucMatKhau', N'U') IS NOT NULL
                    UPDATE dbo.TokenKhoiPhucMatKhau SET DaDungLuc = @Now WHERE MaTaiKhoan = @TargetId AND DaDungLuc IS NULL;
                -- Audit metadata only: no password, hash or token in either JSON column.
                INSERT dbo.NhatKyHoatDong (MaTaiKhoan, LoaiThaoTac, TenDoiTuong, MaDoiTuong, DuLieuMoiJson)
                VALUES (@ActorId, 'ADMIN_RESET_PASSWORD', 'TaiKhoan', CONVERT(VARCHAR(100), @TargetId),
                    (SELECT 'ADMIN_RESET' AS method, @Reason AS reason FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
                SELECT @Result = (SELECT MaTaiKhoan AS id, CONVERT(VARBINARY(8), PhienBan) AS version,
                    CAST(1 AS BIT) AS refreshTokensRevoked, CAST(1 AS BIT) AS accessTokensRevoked,
                    N'Đã đặt lại mật khẩu và thu hồi toàn bộ phiên đăng nhập, gồm access token và refresh token.' AS message
                    FROM dbo.TaiKhoan WHERE MaTaiKhoan = @TargetId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
                COMMIT;
                SELECT @Result;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK;
                THROW;
            END CATCH;
            """, connection);
        command.Parameters.Add("@ActorId", SqlDbType.BigInt).Value = actorId;
        command.Parameters.Add("@TargetId", SqlDbType.BigInt).Value = id;
        command.Parameters.Add("@ExpectedVersion", SqlDbType.Binary, 8).Value = version;
        command.Parameters.Add("@Reason", SqlDbType.NVarChar, 500).Value = request.Reason.Trim();
        command.Parameters.Add("@Hash", SqlDbType.VarChar, 255).Value = BCrypt.Net.BCrypt.HashPassword(request.NewPassword, workFactor: 12);
        try
        {
            await connection.OpenAsync(cancellationToken);
            var result = await command.ExecuteScalarAsync(cancellationToken);
            return Content(result?.ToString() ?? "{}", "application/json");
        }
        catch (SqlException ex) when (ex.Number == 55701) { return Unauthorized(new { message = ex.Message }); }
        catch (SqlException ex) when (ex.Number == 55702) { return StatusCode(403, new { message = ex.Message }); }
        catch (SqlException ex) when (ex.Number == 55703) { return NotFound(new { message = ex.Message }); }
        catch (SqlException ex) when (ex.Number is 55704 or 1205) { return Conflict(new { message = "Tài khoản đã thay đổi hoặc đang được xử lý đồng thời. Hãy tải lại và thử lại." }); }
    }

    [HttpPost("{id:long}/actions")]
    public async Task<IActionResult> Execute(
        long id,
        AccountActionRequest request,
        CancellationToken cancellationToken)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã tài khoản không hợp lệ." });

        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        if (string.IsNullOrWhiteSpace(request.Reason))
            return BadRequest(new { message = "Phải nhập lý do." });

        byte[] expectedVersion;

        try
        {
            expectedVersion = Convert.FromBase64String(
                request.ExpectedVersion);
        }
        catch (FormatException)
        {
            return BadRequest(new
            {
                message = "ExpectedVersion phải là Base64 hợp lệ."
            });
        }

        if (expectedVersion.Length != 8)
            return BadRequest(new { message = "ExpectedVersion phải có 8 byte." });

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
                    @TargetRoleId INT,
                    @OldStatus VARCHAR(20),
                    @NewStatus VARCHAR(20),
                    @CurrentVersion BINARY(8),
                    @LockedUntil DATETIME2(0),
                    @ShipperId BIGINT,
                    @HasWork BIT = 0,
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT
                    @ActorRole = vt.KyHieuVaiTro,
                    @ActorRoleId = tk.MaVaiTro,
                    @ActorBranch = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @ActorRole IS NULL
                    THROW 55701, N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @ActorRoleId
                      AND q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                )
                    THROW 55702, N'Bạn không có quyền quản lý tài khoản.', 1;

                IF @ActorRole <> 'ADMIN' AND @ActorBranch IS NULL
                    THROW 55702, N'Tài khoản chưa thuộc bưu cục.', 1;

                IF @TargetId = @ActorId
                    THROW 55702,
                        N'Không được thực hiện thao tác này trên chính tài khoản đang đăng nhập.', 1;

                SELECT
                    @TargetRole = vt.KyHieuVaiTro,
                    @TargetRoleId = tk.MaVaiTro,
                    @OldStatus = tk.TrangThaiTaiKhoan,
                    @CurrentVersion = tk.PhienBan,
                    @LockedUntil = tk.KhoaDenLuc
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @TargetId
                  AND (
                      @ActorRole = 'ADMIN'
                      OR (
                          tk.MaBuuCuc = @ActorBranch
                          AND vt.KyHieuVaiTro <> 'ADMIN'
                      )
                  );

                IF @OldStatus IS NULL
                    THROW 55703, N'Không tìm thấy tài khoản.', 1;

                IF @CurrentVersion <> @ExpectedVersion
                    THROW 55704,
                        N'Tài khoản đã thay đổi. Hãy tải lại version mới.', 1;

                IF @ActorRole <> 'ADMIN'
                   AND EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen targetPermission WITH (HOLDLOCK)
                       WHERE targetPermission.MaVaiTro = @TargetRoleId
                         AND NOT EXISTS (
                             SELECT 1
                             FROM dbo.VaiTroQuyen actorPermission WITH (HOLDLOCK)
                             WHERE actorPermission.MaVaiTro = @ActorRoleId
                               AND actorPermission.MaQuyen =
                                   targetPermission.MaQuyen
                         )
                   )
                    THROW 55702,
                        N'Tài khoản này vượt quá quyền quản lý của bạn.', 1;

                IF @Action = 'LOCK'
                BEGIN
                    IF @OldStatus <> 'ACTIVE'
                        THROW 55704,
                            N'Chỉ tài khoản ACTIVE mới được khóa.', 1;
                    SET @NewStatus = 'LOCKED';
                END
                ELSE IF @Action = 'UNLOCK'
                BEGIN
                    IF @OldStatus <> 'LOCKED'
                       AND NOT (
                           @OldStatus = 'ACTIVE'
                           AND @LockedUntil > SYSUTCDATETIME()
                       )
                        THROW 55704,
                            N'Tài khoản hiện không bị khóa.', 1;
                    SET @NewStatus = 'ACTIVE';
                END
                ELSE IF @Action = 'DEACTIVATE'
                BEGIN
                    IF @OldStatus = 'INACTIVE'
                        THROW 55704,
                            N'Tài khoản đã ngừng hoạt động.', 1;
                    SET @NewStatus = 'INACTIVE';
                END
                ELSE
                BEGIN
                    IF @OldStatus <> 'INACTIVE'
                        THROW 55704,
                            N'Chỉ tài khoản INACTIVE mới cần kích hoạt lại.', 1;
                    SET @NewStatus = 'ACTIVE';
                END;

                IF @NewStatus = 'ACTIVE'
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.TaiKhoan tk
                       JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                           ON vt.MaVaiTro = tk.MaVaiTro
                       LEFT JOIN dbo.BuuCuc bc WITH (HOLDLOCK)
                           ON bc.MaBuuCuc = tk.MaBuuCuc
                       WHERE tk.MaTaiKhoan = @TargetId
                         AND vt.DangHoatDong = 1
                         AND (
                             vt.KyHieuVaiTro = 'ADMIN'
                             OR bc.DangHoatDong = 1
                         )
                   )
                    THROW 55705,
                        N'Vai trò hoặc bưu cục không còn hoạt động.', 1;

                IF @TargetRole = 'ADMIN'
                   AND @NewStatus <> 'ACTIVE'
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                       JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                           ON vt.MaVaiTro = tk.MaVaiTro
                       WHERE tk.MaTaiKhoan <> @TargetId
                         AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                         AND vt.KyHieuVaiTro = 'ADMIN'
                         AND vt.DangHoatDong = 1
                         AND (
                             tk.KhoaDenLuc IS NULL
                             OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                         )
                   )
                    THROW 55704,
                        N'Không được khóa hoặc ngừng hoạt động admin hoạt động cuối cùng.', 1;

                SELECT @ShipperId = MaNhanVienGiaoHang
                FROM dbo.NhanVienGiaoHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaTaiKhoan = @TargetId;

                IF @ShipperId IS NOT NULL
                BEGIN
                    IF EXISTS (
                        SELECT 1
                        FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaNhanVienGiaoHang = @ShipperId
                          AND ThoiGianKetThuc IS NULL
                    )
                       OR EXISTS (
                           SELECT 1
                           FROM dbo.ChuyenGiaoHang WITH (UPDLOCK, HOLDLOCK)
                           WHERE MaNhanVienGiaoHang = @ShipperId
                             AND TrangThaiChuyen IN (
                                 'PLANNED', 'ASSIGNED',
                                 'ACCEPTED', 'IN_PROGRESS'
                             )
                       )
                        SET @HasWork = 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                        JOIN dbo.TrangThaiDonHang tt
                            ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                        CROSS APPLY (
                            SELECT TOP (1) pc.MaNhanVienGiaoHang
                            FROM dbo.PhanCongGiaoHang pc WITH (HOLDLOCK)
                            WHERE pc.MaDonHang = d.MaDonHang
                            ORDER BY
                                pc.ThoiGianPhanCong DESC,
                                pc.MaPhanCongGiaoHang DESC
                        ) latest
                        WHERE tt.KyHieuTrangThai = 'RETURNING'
                          AND latest.MaNhanVienGiaoHang = @ShipperId
                    )
                        SET @HasWork = 1;

                    IF @Action = 'DEACTIVATE'
                       AND @HasWork = 1
                        THROW 55704,
                            N'Hãy xử lý hết nhiệm vụ, chuyến và hoàn hàng trước khi ngừng hoạt động.', 1;

                    IF @Action = 'DEACTIVATE'
                       AND EXISTS (
                           SELECT 1
                           FROM dbo.PhanCongPhuongTien WITH (UPDLOCK, HOLDLOCK)
                           WHERE MaNhanVienGiaoHang = @ShipperId
                             AND ThoiGianKetThuc IS NULL
                       )
                        THROW 55704,
                            N'Hãy kết thúc phân công xe trước khi ngừng hoạt động.', 1;
                END;

                SELECT @OldJson = (
                    SELECT
                        MaTaiKhoan AS id,
                        TrangThaiTaiKhoan AS status,
                        KhoaDenLuc AS lockedUntil,
                        SoLanDangNhapSai AS failedLoginCount
                    FROM dbo.TaiKhoan
                    WHERE MaTaiKhoan = @TargetId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                UPDATE dbo.TaiKhoan
                SET TrangThaiTaiKhoan = @NewStatus,
                    KhoaDenLuc = NULL,
                    SoLanDangNhapSai = CASE
                        WHEN @NewStatus = 'ACTIVE' THEN 0
                        ELSE SoLanDangNhapSai
                    END,
                    ThoiGianCapNhat = SYSUTCDATETIME()
                WHERE MaTaiKhoan = @TargetId
                  AND PhienBan = @ExpectedVersion;

                IF @@ROWCOUNT <> 1
                    THROW 55704,
                        N'Tài khoản đã thay đổi. Hãy tải lại.', 1;

                IF @NewStatus <> 'ACTIVE'
                BEGIN
                    UPDATE dbo.PhienDangNhap
                    SET ThuHoiLuc = SYSUTCDATETIME()
                    WHERE MaTaiKhoan = @TargetId AND ThuHoiLuc IS NULL;

                    UPDATE dbo.TokenLamMoi
                    SET ThuHoiLuc = SYSUTCDATETIME()
                    WHERE MaTaiKhoan = @TargetId
                      AND ThuHoiLuc IS NULL;
                END;

                SELECT @Result = (
                    SELECT
                        tk.MaTaiKhoan AS id,
                        tk.TenDangNhap AS username,
                        @Action AS action,
                        tk.TrangThaiTaiKhoan AS status,
                        @Reason AS reason,
                        CONVERT(BIT, CASE
                            WHEN @Action = 'LOCK' AND @HasWork = 1
                                THEN 1
                            ELSE 0
                        END) AS needsOperationalReview,
                        CONVERT(VARBINARY(8), tk.PhienBan) AS version,
                        N'Cập nhật trạng thái tài khoản thành công.' AS message
                    FROM dbo.TaiKhoan tk
                    WHERE tk.MaTaiKhoan = @TargetId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan, LoaiThaoTac, TenDoiTuong,
                    MaDoiTuong, DuLieuCuJson, DuLieuMoiJson
                )
                VALUES (
                    @ActorId,
                    CONCAT('ACCOUNT_', @Action),
                    'TaiKhoan',
                    CONVERT(VARCHAR(100), @TargetId),
                    @OldJson,
                    @Result
                );

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
            "@TargetId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@Action", SqlDbType.VarChar, 20).Value = request.Action;

        command.Parameters.Add(
            "@Reason", SqlDbType.NVarChar, 500).Value =
            request.Reason.Trim();

        command.Parameters.Add(
            "@ExpectedVersion", SqlDbType.Binary, 8).Value =
            expectedVersion;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(cancellationToken);

            return Content(result?.ToString() ?? "{}", "application/json");
        }
        catch (SqlException ex) when (ex.Number == 55701)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55702)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55703)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55704)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55705)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy thử lại."
            });
        }
    }
}
