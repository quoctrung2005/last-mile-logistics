using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class UpdateCustomerRequest
{
    [Required]
    [StringLength(150)]
    public string FullName { get; set; } = "";

    [Required]
    [RegularExpression(
        @"^\+?[0-9]{9,15}$",
        ErrorMessage = "Số điện thoại phải có từ 9 đến 15 chữ số.")]
    public string Phone { get; set; } = "";

    [EmailAddress]
    [StringLength(150)]
    public string? Email { get; set; }

    [Required]
    [RegularExpression(
        "^(INDIVIDUAL|BUSINESS)$",
        ErrorMessage = "Type phải là INDIVIDUAL hoặc BUSINESS.")]
    public string Type { get; set; } = "";

    [Required]
    public bool? IsActive { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/customers")]
public class CustomerUpdateController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CustomerUpdateController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPut("{id:long}")]
    public async Task<IActionResult> Update(
        long id,
        UpdateCustomerRequest request,
        CancellationToken cancellationToken)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã khách hàng không hợp lệ."
            });
        }

        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        var fullName = request.FullName.Trim();

        if (string.IsNullOrWhiteSpace(fullName))
        {
            return BadRequest(new
            {
                message = "Tên khách hàng không được để trống."
            });
        }

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @RoleId INT,
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT @RoleId = tk.MaVaiTro
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @AccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @RoleId IS NULL
                    THROW 54301,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1 FROM dbo.TaiKhoan tk
                    JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @AccountId
                      AND (vt.KyHieuVaiTro = 'ADMIN' OR tk.MaBuuCuc IS NOT NULL)
                )
                    THROW 54302, N'Tài khoản chưa được gắn với bưu cục.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q
                        ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DONHANG_CAPNHAT'
                )
                    THROW 54302,
                        N'Bạn không có quyền cập nhật khách hàng.', 1;

                SELECT @OldJson = (
                    SELECT
                        kh.MaKhachHang AS id,
                        kh.KyHieuKhachHang AS customerCode,
                        kh.HoTen AS fullName,
                        kh.SoDienThoai AS phone,
                        kh.Email AS email,
                        kh.LoaiKhachHang AS type,
                        kh.DangHoatDong AS isActive
                    FROM dbo.KhachHang kh WITH (UPDLOCK, HOLDLOCK)
                    WHERE kh.MaKhachHang = @CustomerId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                IF NULLIF(@OldJson, N'') IS NULL
                    THROW 54303,
                        N'Không tìm thấy khách hàng.', 1;

                UPDATE dbo.KhachHang
                SET HoTen = @FullName,
                    SoDienThoai = @Phone,
                    Email = @Email,
                    LoaiKhachHang = @Type,
                    DangHoatDong = @IsActive
                WHERE MaKhachHang = @CustomerId;

                SELECT @Result = (
                    SELECT
                        kh.MaKhachHang AS id,
                        kh.KyHieuKhachHang AS customerCode,
                        kh.HoTen AS fullName,
                        kh.SoDienThoai AS phone,
                        kh.Email AS email,
                        kh.LoaiKhachHang AS type,
                        kh.DangHoatDong AS isActive,
                        kh.ThoiGianTao AS createdAt,
                        N'Cập nhật khách hàng thành công.' AS message
                    FROM dbo.KhachHang kh
                    WHERE kh.MaKhachHang = @CustomerId
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
                    @AccountId,
                    'UPDATE_CUSTOMER',
                    'KhachHang',
                    CONVERT(VARCHAR(100), @CustomerId),
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
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@CustomerId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@FullName", SqlDbType.NVarChar, 150).Value = fullName;

        command.Parameters.Add(
            "@Phone", SqlDbType.VarChar, 20).Value = request.Phone;

        command.Parameters.Add(
            "@Email", SqlDbType.VarChar, 150).Value =
            string.IsNullOrWhiteSpace(request.Email)
                ? DBNull.Value
                : request.Email.Trim();

        command.Parameters.Add(
            "@Type", SqlDbType.VarChar, 20).Value = request.Type;

        command.Parameters.Add(
            "@IsActive", SqlDbType.Bit).Value =
            request.IsActive!.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 54301)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54302)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54303)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy tải lại và thử lại."
            });
        }
    }
}
