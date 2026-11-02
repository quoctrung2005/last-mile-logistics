using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/shippers")]
public class ShippersController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public ShippersController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> Get(
        [FromQuery] long? id = null,
        [FromQuery] string? keyword = null,
        [FromQuery] int? branchId = null,
        [FromQuery] string? availability = null,
        [FromQuery] bool activeOnly = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] bool? isActive = null,
        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        if (id.HasValue && id.Value <= 0)
            return BadRequest(new { message = "Mã shipper không hợp lệ." });

        if (!id.HasValue)
        {
            if (page < 1 || pageSize < 1 || pageSize > 100)
            {
                return BadRequest(new
                {
                    message = "Page phải từ 1; pageSize từ 1 đến 100."
                });
            }

            if (branchId.HasValue && branchId.Value <= 0)
                return BadRequest(new { message = "Mã bưu cục không hợp lệ." });

            if (keyword?.Length > 150)
                return BadRequest(new { message = "Từ khóa tối đa 150 ký tự." });

            availability = string.IsNullOrWhiteSpace(availability)
                ? null
                : availability.Trim().ToUpperInvariant();

            if (availability is not null
                && availability is not (
                    "AVAILABLE" or "DELIVERING" or "BREAK" or "OFFLINE"))
            {
                return BadRequest(new
                {
                    message = "Availability phải là AVAILABLE, DELIVERING, BREAK hoặc OFFLINE."
                });
            }
        }

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @Role VARCHAR(50),
                @RoleId INT,
                @AccountBranch INT,
                @Result NVARCHAR(MAX);

            SELECT
                @Role = vt.KyHieuVaiTro,
                @RoleId = tk.MaVaiTro,
                @AccountBranch = tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
              );

            IF @Role IS NULL
                THROW 54701,
                    N'Tài khoản không còn hợp lệ.', 1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vq
                JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen = 'TAIKHOAN_XEM'
            )
                THROW 54702,
                    N'Bạn không có quyền xem hồ sơ shipper.', 1;

            IF @Role <> 'ADMIN' AND @AccountBranch IS NULL
                THROW 54702,
                    N'Tài khoản chưa được gắn với bưu cục.', 1;

            IF @Id IS NULL
               AND @Role <> 'ADMIN'
               AND @BranchId IS NOT NULL
               AND @BranchId <> @AccountBranch
                THROW 54702,
                    N'Bạn chỉ được xem shipper thuộc bưu cục của mình.', 1;

            SELECT
                nv.MaNhanVienGiaoHang AS Id,
                nv.MaNhanVien AS EmployeeCode,
                nv.MaTaiKhoan AS AccountId,
                tk.TenDangNhap AS Username,
                tk.HoTen AS FullName,
                tk.SoDienThoai AS Phone,
                tk.Email AS Email,
                tk.MaBuuCuc AS BranchId,
                bc.TenBuuCuc AS BranchName,
                tk.TrangThaiTaiKhoan AS AccountStatus,
                vt.KyHieuVaiTro AS AccountRole,
                nv.TrangThaiSanSang AS Availability,
                nv.DangHoatDong AS IsActive,
                nv.CCCD AS IdentityNumber,
                nv.SoBangLai AS LicenseNumber,
                nv.NgayHetHanBangLai AS LicenseExpiresAt,
                nv.ViDoHienTai AS Latitude,
                nv.KinhDoHienTai AS Longitude,
                nv.ThoiGianCapNhatViTri AS LocationUpdatedAt,
                (
                    SELECT pcp.MaPhanCongPhuongTien AS assignmentId,
                        pt.MaPhuongTien AS id, pt.KyHieuPhuongTien AS code,
                        pt.BienSo AS licensePlate, pt.LoaiXe AS vehicleType,
                        pt.KhoiLuongDenKg AS maxWeightKg, pt.TheTichToiDaM3 AS maxVolumeM3,
                        pt.TrangThaiPhuongTien AS status, pt.DangHoatDong AS isActive,
                        pcp.ThoiGianPhanCong AS assignedAt
                    FROM dbo.PhanCongPhuongTien pcp
                    JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = pcp.MaPhuongTien
                    WHERE pcp.MaNhanVienGiaoHang = nv.MaNhanVienGiaoHang AND pcp.ThoiGianKetThuc IS NULL
                    FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
                ) AS CurrentVehicleJson,
                (
                    SELECT COUNT(*)
                    FROM dbo.PhanCongGiaoHang pc
                    WHERE pc.MaNhanVienGiaoHang = nv.MaNhanVienGiaoHang
                      AND pc.ThoiGianKetThuc IS NULL
                      AND pc.TrangThaiPhanCong IN (
                          'PENDING', 'ACCEPTED', 'IN_PROGRESS'
                      )
                ) AS ActiveAssignmentCount
            INTO #Shippers
            FROM dbo.NhanVienGiaoHang nv
            JOIN dbo.TaiKhoan tk
                ON tk.MaTaiKhoan = nv.MaTaiKhoan
            JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            LEFT JOIN dbo.BuuCuc bc
                ON bc.MaBuuCuc = tk.MaBuuCuc
            WHERE (
                @Role = 'ADMIN'
                OR tk.MaBuuCuc = @AccountBranch
            )
              AND (@Id IS NULL OR nv.MaNhanVienGiaoHang = @Id)
              AND (
                  @Id IS NOT NULL
                  OR (
                      (@BranchId IS NULL OR tk.MaBuuCuc = @BranchId)
                      AND (@IsActive IS NULL OR nv.DangHoatDong = @IsActive)
                      AND (
                          @Availability IS NULL
                          OR nv.TrangThaiSanSang = @Availability
                      )
                      AND (
                          @ActiveOnly = 0
                          OR (
                              nv.DangHoatDong = 1
                              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                              AND vt.KyHieuVaiTro = 'SHIPPER'
                              AND vt.DangHoatDong = 1
                              AND (
                                  tk.KhoaDenLuc IS NULL
                                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                              )
                          )
                      )
                      AND (
                          @Keyword IS NULL
                          OR CHARINDEX(@Keyword, nv.MaNhanVien) > 0
                          OR CHARINDEX(@Keyword, tk.HoTen) > 0
                          OR CHARINDEX(@Keyword, tk.TenDangNhap) > 0
                          OR CHARINDEX(@Keyword, tk.SoDienThoai) > 0
                      )
                  )
              );

            IF @Id IS NOT NULL
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM #Shippers)
                    THROW 54703,
                        N'Không tìm thấy shipper.', 1;

                SELECT @Result = (
                    SELECT
                        s.Id AS id,
                        s.EmployeeCode AS employeeCode,
                        s.AccountId AS accountId,
                        s.Username AS username,
                        s.FullName AS fullName,
                        s.Phone AS phone,
                        s.Email AS email,
                        s.BranchId AS branchId,
                        s.BranchName AS branchName,
                        s.AccountStatus AS accountStatus,
                        s.AccountRole AS accountRole,
                        s.Availability AS availability,
                        s.IsActive AS isActive,
                        s.IdentityNumber AS identityNumber,
                        s.LicenseNumber AS licenseNumber,
                        s.LicenseExpiresAt AS licenseExpiresAt,
                        s.Latitude AS latitude,
                        s.Longitude AS longitude,
                        s.LocationUpdatedAt AS locationUpdatedAt,
                        s.ActiveAssignmentCount AS activeAssignmentCount,

                        JSON_QUERY(COALESCE((
                            SELECT
                                kv.MaKhuVuc AS id,
                                kv.KyHieuKhuVuc AS code,
                                kv.TenKhuVuc AS name,
                                p.LaChinh AS isPrimary,
                                kv.DangHoatDong AS isActive
                            FROM dbo.KhuVucNhanVienGiaoHang p
                            JOIN dbo.KhuVuc kv
                                ON kv.MaKhuVuc = p.MaKhuVuc
                            WHERE p.MaNhanVienGiaoHang = s.Id
                            ORDER BY p.LaChinh DESC, kv.MaKhuVuc
                            FOR JSON PATH
                        ), N'[]')) AS areas,

                        JSON_QUERY(s.CurrentVehicleJson) AS currentVehicle
                    FROM #Shippers s
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
                        (SELECT COUNT(*) FROM #Shippers) AS totalItems,
                        JSON_QUERY(COALESCE((
                            SELECT
                                s.Id AS id,
                                s.EmployeeCode AS employeeCode,
                                s.AccountId AS accountId,
                                s.Username AS username,
                                s.FullName AS fullName,
                                s.Phone AS phone,
                                s.BranchId AS branchId,
                                s.BranchName AS branchName,
                                s.AccountStatus AS accountStatus,
                                s.Availability AS availability,
                                s.IsActive AS isActive,
                                JSON_QUERY(s.CurrentVehicleJson) AS currentVehicle,
                                s.ActiveAssignmentCount
                                    AS activeAssignmentCount
                            FROM #Shippers s
                            ORDER BY s.FullName, s.Id
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
            "@AccountId", SqlDbType.BigInt).Value = accountId;

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
            "@Availability", SqlDbType.VarChar, 20).Value =
            id.HasValue ? DBNull.Value : (object?)availability ?? DBNull.Value;

        command.Parameters.Add(
            "@ActiveOnly", SqlDbType.Bit).Value = activeOnly;
        command.Parameters.Add("@IsActive", SqlDbType.Bit).Value = (object?)isActive ?? DBNull.Value;

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
        catch (SqlException ex) when (ex.Number == 54701)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54702)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54703)
        {
            return NotFound(new { message = ex.Message });
        }
    }
}
