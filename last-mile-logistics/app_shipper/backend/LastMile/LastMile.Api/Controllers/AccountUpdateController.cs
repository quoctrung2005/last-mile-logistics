using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class UpdateAccountRequest
{
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

    [Required]
    [StringLength(16)]
    public string ExpectedVersion { get; set; } = "";
}

[ApiController]
[Authorize]
[Route("api/v1/accounts")]
public class AccountUpdateController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public AccountUpdateController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPut("{id:long}")]
    public async Task<IActionResult> Update(
        long id,
        UpdateAccountRequest request,
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

        var fullName = request.FullName.Trim();

        if (string.IsNullOrWhiteSpace(fullName))
            return BadRequest(new { message = "Họ tên không được để trống." });

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
                message = "ExpectedVersion phải là chuỗi Base64 hợp lệ."
            });
        }

        if (expectedVersion.Length != 8)
        {
            return BadRequest(new
            {
                message = "ExpectedVersion phải giải mã thành đúng 8 byte."
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
                    @ActorBranch INT,
                    @OldRoleId INT,
                    @OldRole VARCHAR(50),
                    @OldBranch INT,
                    @CurrentVersion BINARY(8),
                    @NewRole VARCHAR(50),
                    @ShipperId BIGINT,
                    @OldJson NVARCHAR(MAX),
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
                    THROW 55601,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @ActorRoleId
                      AND q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                )
                    THROW 55602,
                        N'Bạn không có quyền cập nhật tài khoản.', 1;

                IF @ActorRole <> 'ADMIN' AND @ActorBranch IS NULL
                    THROW 55602,
                        N'Tài khoản chưa được gắn với bưu cục.', 1;

                SELECT
                    @OldRoleId = tk.MaVaiTro,
                    @OldRole = vt.KyHieuVaiTro,
                    @OldBranch = tk.MaBuuCuc,
                    @CurrentVersion = tk.PhienBan
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

                IF @OldRoleId IS NULL
                    THROW 55603,
                        N'Không tìm thấy tài khoản trong phạm vi quản lý.', 1;

                IF @CurrentVersion <> @ExpectedVersion
                    THROW 55604,
                        N'Tài khoản đã được cập nhật. Hãy tải lại và dùng version mới.', 1;

                SELECT @NewRole = KyHieuVaiTro
                FROM dbo.VaiTro WITH (HOLDLOCK)
                WHERE MaVaiTro = @RoleId
                  AND DangHoatDong = 1;

                IF @NewRole IS NULL
                    THROW 55605,
                        N'Vai trò không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF @NewRole <> 'ADMIN' AND @BranchId IS NULL
                    THROW 55605,
                        N'Tài khoản không phải admin phải thuộc một bưu cục.', 1;

                IF @BranchId IS NOT NULL
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.BuuCuc WITH (HOLDLOCK)
                       WHERE MaBuuCuc = @BranchId
                         AND DangHoatDong = 1
                   )
                    THROW 55605,
                        N'Bưu cục không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF @TargetId = @ActorId
                   AND (
                       @OldRoleId <> @RoleId
                       OR ISNULL(@OldBranch, -1)
                          <> ISNULL(@BranchId, -1)
                   )
                    THROW 55602,
                        N'Bạn không được tự đổi vai trò hoặc bưu cục của mình.', 1;

                IF @ActorRole <> 'ADMIN'
                BEGIN
                    IF @NewRole = 'ADMIN'
                        THROW 55602,
                            N'Bạn không được cấp vai trò admin.', 1;

                    IF @BranchId IS NULL OR @BranchId <> @ActorBranch
                        THROW 55602,
                            N'Bạn chỉ được quản lý tài khoản trong bưu cục của mình.', 1;

                    -- Không sửa tài khoản có quyền vượt quá
                    -- quyền của người thực hiện, hoặc cấp vai trò cao hơn.
                    IF EXISTS (
                        SELECT 1
                        FROM dbo.VaiTroQuyen targetPermission
                            WITH (HOLDLOCK)
                        WHERE targetPermission.MaVaiTro
                              IN (@OldRoleId, @RoleId)
                          AND NOT EXISTS (
                              SELECT 1
                              FROM dbo.VaiTroQuyen actorPermission
                                  WITH (HOLDLOCK)
                              WHERE actorPermission.MaVaiTro = @ActorRoleId
                                AND actorPermission.MaQuyen =
                                    targetPermission.MaQuyen
                          )
                    )
                        THROW 55602,
                            N'Vai trò hiện tại hoặc vai trò mới vượt quá quyền quản lý của bạn.', 1;
                END;

                IF @OldRole = 'ADMIN' AND @NewRole <> 'ADMIN'
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
                    THROW 55604,
                        N'Không được bỏ vai trò của admin hoạt động cuối cùng.', 1;

                SELECT @ShipperId = MaNhanVienGiaoHang
                FROM dbo.NhanVienGiaoHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaTaiKhoan = @TargetId;

                IF @ShipperId IS NOT NULL AND @NewRole <> 'SHIPPER'
                    THROW 55604,
                        N'Tài khoản đã có hồ sơ shipper, không thể chuyển sang vai trò khác bằng API này.', 1;

                IF @ShipperId IS NOT NULL
                   AND ISNULL(@OldBranch, -1)
                       <> ISNULL(@BranchId, -1)
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
                       OR EXISTS (
                           SELECT 1
                           FROM dbo.PhanCongPhuongTien
                               WITH (UPDLOCK, HOLDLOCK)
                           WHERE MaNhanVienGiaoHang = @ShipperId
                             AND ThoiGianKetThuc IS NULL
                       )
                        THROW 55604,
                            N'Hãy kết thúc nhiệm vụ, chuyến và phân công xe trước khi chuyển bưu cục.', 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                        JOIN dbo.TrangThaiDonHang tt
                            ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                        CROSS APPLY (
                            SELECT TOP (1)
                                pc.MaNhanVienGiaoHang
                            FROM dbo.PhanCongGiaoHang pc WITH (HOLDLOCK)
                            WHERE pc.MaDonHang = d.MaDonHang
                            ORDER BY
                                pc.ThoiGianPhanCong DESC,
                                pc.MaPhanCongGiaoHang DESC
                        ) latest
                        WHERE tt.KyHieuTrangThai = 'RETURNING'
                          AND latest.MaNhanVienGiaoHang = @ShipperId
                    )
                        THROW 55604,
                            N'Shipper còn nhiệm vụ hoàn hàng, chưa thể chuyển bưu cục.', 1;
                END;

                SELECT @OldJson = (
                    SELECT
                        MaTaiKhoan AS id,
                        HoTen AS fullName,
                        SoDienThoai AS phone,
                        Email AS email,
                        MaVaiTro AS roleId,
                        MaBuuCuc AS branchId,
                        CONVERT(VARBINARY(8), PhienBan) AS version
                    FROM dbo.TaiKhoan
                    WHERE MaTaiKhoan = @TargetId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                UPDATE dbo.TaiKhoan
                SET HoTen = @FullName,
                    SoDienThoai = @Phone,
                    Email = @Email,
                    MaVaiTro = @RoleId,
                    MaBuuCuc = @BranchId,
                    ThoiGianCapNhat = SYSUTCDATETIME()
                WHERE MaTaiKhoan = @TargetId
                  AND PhienBan = @ExpectedVersion;

                IF @@ROWCOUNT <> 1
                    THROW 55604,
                        N'Tài khoản đã thay đổi. Hãy tải lại.', 1;

                -- Thu hồi refresh token khi thay đổi quyền/phạm vi.
                IF @OldRoleId <> @RoleId
                   OR ISNULL(@OldBranch, -1) <> ISNULL(@BranchId, -1)
                BEGIN
                    UPDATE dbo.TokenLamMoi
                    SET ThuHoiLuc = SYSUTCDATETIME()
                    WHERE MaTaiKhoan = @TargetId
                      AND ThuHoiLuc IS NULL;
                END;

                SELECT @Result = (
                    SELECT
                        tk.MaTaiKhoan AS id,
                        tk.TenDangNhap AS username,
                        tk.HoTen AS fullName,
                        tk.SoDienThoai AS phone,
                        tk.Email AS email,
                        tk.MaVaiTro AS roleId,
                        vt.KyHieuVaiTro AS role,
                        tk.MaBuuCuc AS branchId,
                        tk.TrangThaiTaiKhoan AS status,
                        tk.ThoiGianCapNhat AS updatedAt,
                        CONVERT(VARBINARY(8), tk.PhienBan) AS version,
                        N'Cập nhật tài khoản thành công.' AS message
                    FROM dbo.TaiKhoan tk
                    JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @TargetId
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
                    'UPDATE_ACCOUNT',
                    'TaiKhoan',
                    CONVERT(VARCHAR(100), @TargetId),
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
            "@TargetId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@FullName", SqlDbType.NVarChar, 150).Value = fullName;

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

        command.Parameters.Add(
            "@ExpectedVersion", SqlDbType.Binary, 8).Value =
            expectedVersion;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 55601)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55602)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55603)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55604)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55605)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message = "Số điện thoại hoặc email đã được sử dụng."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy tải lại và thử lại."
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