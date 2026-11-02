using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public sealed class UpdateMyProfileRequest
{
    [Required, StringLength(150, MinimumLength = 2)]
    public string FullName { get; set; } = "";

    [RegularExpression(@"^\+?[0-9]{9,15}$", ErrorMessage = "Số điện thoại phải từ 9 đến 15 chữ số.")]
    public string? Phone { get; set; }

    [EmailAddress, StringLength(150)]
    public string? Email { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/my/profile")]
public class MyShipperProfileController(IConfiguration configuration) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken cancellationToken)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId))
            return Unauthorized();

        // Identity comes only from the authenticated session, never query IDs.
        var sql = $$"""
            SET NOCOUNT ON;
            DECLARE @Role VARCHAR(50), @RoleId INT, @BranchId INT,
                    @ShipperId BIGINT, @Today DATE = {{VietnamDate.SqlDate("SYSUTCDATETIME()")}};
            SELECT @Role = vt.KyHieuVaiTro, @RoleId = tk.MaVaiTro, @BranchId = tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());

            IF @Role IS NULL
                THROW 55001, N'Tài khoản không còn hoạt động hoặc đang bị khóa.', 1;
            IF @Role <> 'SHIPPER' OR NOT EXISTS (
                SELECT 1 FROM dbo.VaiTroQuyen vq
                JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @RoleId AND q.KyHieuQuyen = 'NHIEMVU_XEM'
            )
                THROW 55002, N'Tài khoản không có quyền xem hồ sơ tài xế.', 1;
            IF NOT EXISTS (SELECT 1 FROM dbo.BuuCuc WHERE MaBuuCuc = @BranchId AND DangHoatDong = 1)
                THROW 55002, N'Bưu cục của tài xế không còn hoạt động.', 1;
            SELECT @ShipperId = MaNhanVienGiaoHang
            FROM dbo.NhanVienGiaoHang WHERE MaTaiKhoan = @AccountId AND DangHoatDong = 1;
            IF @ShipperId IS NULL
                THROW 55002, N'Tài khoản chưa có hồ sơ tài xế đang hoạt động.', 1;

            SELECT nv.MaNhanVienGiaoHang AS shipperId, nv.MaTaiKhoan AS accountId,
                   nv.MaNhanVien AS employeeCode, tk.TenDangNhap AS username,
                   tk.HoTen AS fullName, tk.SoDienThoai AS phone, tk.Email AS email,
                   nv.TrangThaiSanSang AS availability, nv.CCCD AS identityNumber,
                   nv.SoBangLai AS licenseNumber, nv.NgayHetHanBangLai AS licenseExpiresAt,
                   @Today AS serverDate,
                   CASE WHEN nv.NgayHetHanBangLai IS NULL THEN 'NOT_PROVIDED'
                        WHEN nv.NgayHetHanBangLai < @Today THEN 'EXPIRED'
                        WHEN DATEDIFF(DAY, @Today, nv.NgayHetHanBangLai) <= 30 THEN 'EXPIRING'
                        ELSE 'VALID' END AS licenseStatus,
                   DATEDIFF(DAY, @Today, nv.NgayHetHanBangLai) AS licenseDaysRemaining,
                   JSON_QUERY((
                       SELECT bc.MaBuuCuc AS id, bc.KyHieuBuuCuc AS code,
                              bc.TenBuuCuc AS name, bc.DiaChi AS address,
                              bc.SoDienThoai AS phone, bc.Email AS email
                       FROM dbo.BuuCuc bc WHERE bc.MaBuuCuc = @BranchId
                       FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
                   )) AS branch,
                   JSON_QUERY((
                       SELECT p.MaPhanCongPhuongTien AS assignmentId, pt.MaPhuongTien AS id,
                              pt.KyHieuPhuongTien AS code, pt.BienSo AS licensePlate,
                              pt.LoaiXe AS vehicleType, pt.KhoiLuongDenKg AS maxWeightKg,
                              pt.TheTichToiDaM3 AS maxVolumeM3, pt.TrangThaiPhuongTien AS status,
                              pt.DangHoatDong AS isActive, p.ThoiGianPhanCong AS assignedAt
                       FROM dbo.PhanCongPhuongTien p
                       JOIN dbo.PhuongTien pt ON pt.MaPhuongTien = p.MaPhuongTien
                       WHERE p.MaNhanVienGiaoHang = @ShipperId AND p.ThoiGianKetThuc IS NULL
                       FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
                   )) AS currentVehicle,
                   JSON_QUERY(COALESCE((
                       SELECT kv.MaKhuVuc AS id, kv.KyHieuKhuVuc AS code, kv.TenKhuVuc AS name,
                              p.LaChinh AS isPrimary, kv.DangHoatDong AS isActive
                       FROM dbo.KhuVucNhanVienGiaoHang p
                       JOIN dbo.KhuVuc kv ON kv.MaKhuVuc = p.MaKhuVuc
                       WHERE p.MaNhanVienGiaoHang = @ShipperId
                       ORDER BY p.LaChinh DESC, kv.MaKhuVuc FOR JSON PATH
                   ), N'[]')) AS areas
            FROM dbo.NhanVienGiaoHang nv JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan = nv.MaTaiKhoan
            WHERE nv.MaNhanVienGiaoHang = @ShipperId AND nv.DangHoatDong = 1
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
            FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER;
            """;
        await using var connection = new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = accountId;
        try
        {
            await connection.OpenAsync(cancellationToken);
            var result = (string?)await command.ExecuteScalarAsync(cancellationToken);
            if (string.IsNullOrWhiteSpace(result))
                return StatusCode(403, new { message = "Hồ sơ tài xế không còn hoạt động." });
            return Content(result, "application/json");
        }
        catch (SqlException ex) when (ex.Number is 55001 or 55002)
        {
            return StatusCode(ex.Number == 55001 ? 401 : 403, new { message = ex.Message });
        }
    }

    [HttpPatch]
    public async Task<IActionResult> Update([FromBody] UpdateMyProfileRequest request, CancellationToken cancellationToken)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId))
            return Unauthorized();

        var fullName = request.FullName?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(fullName))
            return BadRequest(new { message = "Họ tên không được để trống." });

        var phone = string.IsNullOrWhiteSpace(request.Phone) ? null : request.Phone.Trim();
        var email = string.IsNullOrWhiteSpace(request.Email) ? null : request.Email.Trim();

        const string sql = """
            SET NOCOUNT ON;
            DECLARE @Role VARCHAR(50), @ShipperId BIGINT;

            SELECT @Role = vt.KyHieuVaiTro
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());

            IF @Role IS NULL
                THROW 55001, N'Tài khoản không còn hoạt động hoặc đang bị khóa.', 1;

            IF @Role <> 'SHIPPER'
                THROW 55002, N'Chỉ tài xế mới được cập nhật hồ sơ qua chức năng này.', 1;

            SELECT @ShipperId = MaNhanVienGiaoHang
            FROM dbo.NhanVienGiaoHang
            WHERE MaTaiKhoan = @AccountId AND DangHoatDong = 1;

            IF @ShipperId IS NULL
                THROW 55002, N'Tài khoản chưa có hồ sơ tài xế đang hoạt động.', 1;

            UPDATE dbo.TaiKhoan
            SET HoTen = @FullName,
                SoDienThoai = @Phone,
                Email = @Email,
                ThoiGianCapNhat = SYSUTCDATETIME()
            WHERE MaTaiKhoan = @AccountId;

            SELECT 1;
            """;

        await using var connection = new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = accountId;
        command.Parameters.Add("@FullName", SqlDbType.NVarChar, 150).Value = fullName;
        command.Parameters.Add("@Phone", SqlDbType.VarChar, 20).Value = (object?)phone ?? DBNull.Value;
        command.Parameters.Add("@Email", SqlDbType.VarChar, 150).Value = (object?)email ?? DBNull.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);
            await command.ExecuteNonQueryAsync(cancellationToken);
            return Ok(new { message = "Cập nhật hồ sơ thành công." });
        }
        catch (SqlException ex) when (ex.Number is 55001 or 55002)
        {
            return StatusCode(ex.Number == 55001 ? 401 : 403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number is 2601 or 2627)
        {
            return Conflict(new { message = "Số điện thoại hoặc email đã được sử dụng bởi tài khoản khác." });
        }
    }
}
