using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/accounts")]
public class AccountsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public AccountsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> Get(
        [FromQuery] long? id = null,
        [FromQuery] string? keyword = null,
        [FromQuery] int? branchId = null,
        [FromQuery] int? roleId = null,
        [FromQuery] string? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] bool eligibleForShipper = false,
        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        if (id.HasValue && id.Value <= 0)
            return BadRequest(new { message = "Mã tài khoản không hợp lệ." });

        if (!id.HasValue)
        {
            if (page < 1 || pageSize < 1 || pageSize > 100)
            {
                return BadRequest(new
                {
                    message = "Page phải từ 1; pageSize từ 1 đến 100."
                });
            }

            if ((branchId.HasValue && branchId.Value <= 0)
                || (roleId.HasValue && roleId.Value <= 0))
            {
                return BadRequest(new
                {
                    message = "Mã bưu cục và mã vai trò phải lớn hơn 0."
                });
            }

            if (keyword?.Length > 150)
                return BadRequest(new { message = "Từ khóa tối đa 150 ký tự." });

            status = string.IsNullOrWhiteSpace(status)
                ? null
                : status.Trim().ToUpperInvariant();

            if (status is not null
                && status is not ("ACTIVE" or "LOCKED" or "INACTIVE"))
            {
                return BadRequest(new
                {
                    message = "Status phải là ACTIVE, LOCKED hoặc INACTIVE."
                });
            }
        }

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @ActorRole VARCHAR(50),
                @ActorRoleId INT,
                @ActorBranch INT,
                @Result NVARCHAR(MAX);

            SELECT
                @ActorRole = vt.KyHieuVaiTro,
                @ActorRoleId = tk.MaVaiTro,
                @ActorBranch = tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
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
                THROW 55401,
                    N'Tài khoản không còn hợp lệ.', 1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vq
                JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @ActorRoleId
                  AND q.KyHieuQuyen = 'TAIKHOAN_XEM'
            )
                THROW 55402,
                    N'Bạn không có quyền xem tài khoản.', 1;

            IF @ActorRole <> 'ADMIN' AND @ActorBranch IS NULL
                THROW 55402,
                    N'Tài khoản chưa được gắn với bưu cục.', 1;

            IF @Id IS NULL
               AND @ActorRole <> 'ADMIN'
               AND @BranchId IS NOT NULL
               AND @BranchId <> @ActorBranch
                THROW 55402,
                    N'Bạn chỉ được xem tài khoản thuộc bưu cục của mình.', 1;

            SELECT
                tk.MaTaiKhoan AS Id,
                tk.KyHieuTaiKhoan AS AccountCode,
                tk.TenDangNhap AS Username,
                tk.HoTen AS FullName,
                tk.SoDienThoai AS Phone,
                tk.Email AS Email,
                tk.MaVaiTro AS RoleId,
                vt.KyHieuVaiTro AS RoleCode,
                vt.TenVaiTro AS RoleName,
                vt.DangHoatDong AS RoleActive,
                tk.MaBuuCuc AS BranchId,
                bc.TenBuuCuc AS BranchName,
                tk.TrangThaiTaiKhoan AS Status,
                tk.SoLanDangNhapSai AS FailedLoginCount,
                tk.KhoaDenLuc AS LockedUntil,
                tk.DangNhapCuoiLuc AS LastLoginAt,
                tk.ThoiGianTao AS CreatedAt,
                tk.ThoiGianCapNhat AS UpdatedAt,
                CONVERT(VARBINARY(8), tk.PhienBan) AS Version,
                CONVERT(BIT, CASE
                    WHEN tk.TrangThaiTaiKhoan = 'LOCKED'
                         OR tk.KhoaDenLuc > SYSUTCDATETIME()
                        THEN 1
                    ELSE 0
                END) AS IsLocked
            INTO #Accounts
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            LEFT JOIN dbo.BuuCuc bc
                ON bc.MaBuuCuc = tk.MaBuuCuc
            WHERE (
                @ActorRole = 'ADMIN'
                OR (
                    tk.MaBuuCuc = @ActorBranch
                    AND vt.KyHieuVaiTro <> 'ADMIN'
                )
            )
              AND (@Id IS NULL OR tk.MaTaiKhoan = @Id)
              AND (@EligibleForShipper = 0 OR (
                  vt.KyHieuVaiTro = 'SHIPPER' AND vt.DangHoatDong = 1
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME())
                  AND bc.DangHoatDong = 1
                  AND NOT EXISTS (SELECT 1 FROM dbo.NhanVienGiaoHang nv WHERE nv.MaTaiKhoan = tk.MaTaiKhoan)
              ))
              AND (
                  @Id IS NOT NULL
                  OR (
                      (@BranchId IS NULL OR tk.MaBuuCuc = @BranchId)
                      AND (@RoleId IS NULL OR tk.MaVaiTro = @RoleId)
                      AND (
                          @Status IS NULL
                          OR tk.TrangThaiTaiKhoan = @Status
                      )
                      AND (
                          @Keyword IS NULL
                          OR CHARINDEX(@Keyword, tk.TenDangNhap) > 0
                          OR CHARINDEX(@Keyword, tk.HoTen) > 0
                          OR CHARINDEX(@Keyword, tk.SoDienThoai) > 0
                          OR CHARINDEX(@Keyword, tk.Email) > 0
                          OR CHARINDEX(@Keyword, tk.KyHieuTaiKhoan) > 0
                      )
                  )
              );

            IF @Id IS NOT NULL
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM #Accounts)
                    THROW 55403,
                        N'Không tìm thấy tài khoản.', 1;

                SELECT @Result = (
                    SELECT
                        Id AS id,
                        AccountCode AS accountCode,
                        Username AS username,
                        FullName AS fullName,
                        Phone AS phone,
                        Email AS email,
                        RoleId AS roleId,
                        RoleCode AS role,
                        RoleName AS roleName,
                        RoleActive AS roleActive,
                        BranchId AS branchId,
                        BranchName AS branchName,
                        Status AS status,
                        IsLocked AS isLocked,
                        FailedLoginCount AS failedLoginCount,
                        LockedUntil AS lockedUntil,
                        LastLoginAt AS lastLoginAt,
                        CreatedAt AS createdAt,
                        UpdatedAt AS updatedAt,
                        (SELECT nv.MaNhanVienGiaoHang FROM dbo.NhanVienGiaoHang nv WHERE nv.MaTaiKhoan = #Accounts.Id) AS linkedShipperId,
                        Version AS version
                    FROM #Accounts
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );
            END
            ELSE
            BEGIN
                SELECT @Result = (
                    SELECT
                        @Page AS page,
                        @PageSize AS pageSize,
                        (SELECT COUNT(*) FROM #Accounts) AS totalItems,
                        JSON_QUERY(COALESCE((
                            SELECT
                                Id AS id,
                                AccountCode AS accountCode,
                                Username AS username,
                                FullName AS fullName,
                                Phone AS phone,
                                Email AS email,
                                RoleId AS roleId,
                                RoleCode AS role,
                                RoleName AS roleName,
                                BranchId AS branchId,
                                BranchName AS branchName,
                                Status AS status,
                                IsLocked AS isLocked,
                                LockedUntil AS lockedUntil,
                                LastLoginAt AS lastLoginAt,
                                Version AS version
                            FROM #Accounts
                            ORDER BY FullName, Id
                            OFFSET @Offset ROWS
                            FETCH NEXT @PageSize ROWS ONLY
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        ), N'[]')) AS items
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );
            END;

            SELECT @Result;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = accountId;
        command.Parameters.Add("@EligibleForShipper", SqlDbType.Bit).Value = eligibleForShipper;

        command.Parameters.Add(
            "@Id", SqlDbType.BigInt).Value =
            (object?)id ?? DBNull.Value;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 150).Value =
            id.HasValue || string.IsNullOrWhiteSpace(keyword)
                ? DBNull.Value
                : keyword.Trim();

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
            id.HasValue ? DBNull.Value : (object?)branchId ?? DBNull.Value;

        command.Parameters.Add(
            "@RoleId", SqlDbType.Int).Value =
            id.HasValue ? DBNull.Value : (object?)roleId ?? DBNull.Value;

        command.Parameters.Add(
            "@Status", SqlDbType.VarChar, 20).Value =
            id.HasValue ? DBNull.Value : (object?)status ?? DBNull.Value;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = id.HasValue ? 1 : page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value =
            id.HasValue ? 10 : pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.BigInt).Value =
            id.HasValue ? 0L : ((long)page - 1) * pageSize;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 55401)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55402)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55403)
        {
            return NotFound(new { message = ex.Message });
        }
    }
}
