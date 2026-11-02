using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class UpdateCustomerAddressRequest
{
    [StringLength(100)]
    public string? Label { get; set; }

    [StringLength(150)]
    public string? ContactName { get; set; }

    [RegularExpression(
        @"^\+?[0-9]{9,15}$",
        ErrorMessage = "Số điện thoại phải có từ 9 đến 15 chữ số.")]
    public string? Phone { get; set; }

    [Required]
    [StringLength(300)]
    public string Address { get; set; } = "";

    [Range(1, int.MaxValue)]
    public int? AreaId { get; set; }

    [Range(
        typeof(decimal), "-90", "90",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? Latitude { get; set; }

    [Range(
        typeof(decimal), "-180", "180",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? Longitude { get; set; }

    [Required]
    public bool? IsDefault { get; set; }

    [Required]
    public bool? IsActive { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/customers")]
public class CustomerAddressUpdateController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CustomerAddressUpdateController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPut("{customerId:long}/addresses/{addressId:long}")]
    public async Task<IActionResult> Update(
        long customerId,
        long addressId,
        UpdateCustomerAddressRequest request,
        CancellationToken cancellationToken)
    {
        if (customerId <= 0 || addressId <= 0)
        {
            return BadRequest(new
            {
                message = "Mã khách hàng hoặc mã địa chỉ không hợp lệ."
            });
        }

        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        if (string.IsNullOrWhiteSpace(request.Address))
        {
            return BadRequest(new
            {
                message = "Địa chỉ không được để trống."
            });
        }

        if (request.IsDefault == true && request.IsActive == false)
        {
            return BadRequest(new
            {
                message = "Địa chỉ ngừng hoạt động không thể là địa chỉ mặc định."
            });
        }

        if (request.Latitude.HasValue != request.Longitude.HasValue)
        {
            return BadRequest(new
            {
                message = "Phải nhập cả latitude và longitude hoặc bỏ trống cả hai."
            });
        }

        if ((request.Latitude.HasValue
             && decimal.Round(request.Latitude.Value, 6)
                != request.Latitude.Value)
            || (request.Longitude.HasValue
                && decimal.Round(request.Longitude.Value, 6)
                   != request.Longitude.Value))
        {
            return BadRequest(new
            {
                message = "Tọa độ chỉ được có tối đa 6 chữ số thập phân."
            });
        }

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @RoleId INT,
                    @CustomerName NVARCHAR(150),
                    @CustomerPhone VARCHAR(20),
                    @CustomerActive BIT,
                    @PreviousDefaultId BIGINT,
                    @DefaultAddressId BIGINT,
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
                    THROW 54501,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1 FROM dbo.TaiKhoan tk
                    JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @AccountId
                      AND (vt.KyHieuVaiTro = 'ADMIN' OR tk.MaBuuCuc IS NOT NULL)
                )
                    THROW 54502, N'Tài khoản chưa được gắn với bưu cục.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DONHANG_CAPNHAT'
                )
                    THROW 54502,
                        N'Bạn không có quyền sửa địa chỉ khách hàng.', 1;

                SELECT
                    @CustomerName = kh.HoTen,
                    @CustomerPhone = kh.SoDienThoai,
                    @CustomerActive = kh.DangHoatDong
                FROM dbo.KhachHang kh WITH (UPDLOCK, HOLDLOCK)
                WHERE kh.MaKhachHang = @CustomerId;

                IF @CustomerName IS NULL
                    THROW 54503,
                        N'Không tìm thấy khách hàng.', 1;

                IF @CustomerActive = 0
                    THROW 54504,
                        N'Khách hàng đã ngừng hoạt động. Hãy kích hoạt lại trước.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.DiaChiKhachHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDiaChiKhachHang = @AddressId
                      AND MaKhachHang = @CustomerId
                )
                    THROW 54503,
                        N'Không tìm thấy địa chỉ của khách hàng này.', 1;

                IF @AreaId IS NOT NULL
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.KhuVuc WITH (HOLDLOCK)
                       WHERE MaKhuVuc = @AreaId
                         AND DangHoatDong = 1
                   )
                    THROW 54505,
                        N'Khu vực không tồn tại hoặc đã ngừng hoạt động.', 1;

                SELECT @PreviousDefaultId = MaDiaChiKhachHang
                FROM dbo.DiaChiKhachHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaKhachHang = @CustomerId
                  AND DangHoatDong = 1
                  AND LaMacDinh = 1;

                SELECT @OldJson = (
                    SELECT
                        dc.MaDiaChiKhachHang AS id,
                        dc.MaKhachHang AS customerId,
                        dc.NhanDiaChi AS label,
                        dc.TenNguoiLienHe AS contactName,
                        dc.SoDienThoaiLienHe AS phone,
                        dc.DiaChi AS address,
                        dc.MaKhuVuc AS areaId,
                        dc.ViDo AS latitude,
                        dc.KinhDo AS longitude,
                        dc.LaMacDinh AS isDefault,
                        dc.DangHoatDong AS isActive,
                        @PreviousDefaultId AS defaultAddressId
                    FROM dbo.DiaChiKhachHang dc
                    WHERE dc.MaDiaChiKhachHang = @AddressId
                      AND dc.MaKhachHang = @CustomerId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                IF @IsDefault = 1
                BEGIN
                    UPDATE dbo.DiaChiKhachHang
                    SET LaMacDinh = 0
                    WHERE MaKhachHang = @CustomerId
                      AND LaMacDinh = 1;
                END;

                UPDATE dbo.DiaChiKhachHang
                SET NhanDiaChi = @Label,
                    TenNguoiLienHe =
                        COALESCE(@ContactName, @CustomerName),
                    SoDienThoaiLienHe =
                        COALESCE(@ContactPhone, @CustomerPhone),
                    DiaChi = @Address,
                    MaKhuVuc = @AreaId,
                    ViDo = @Latitude,
                    KinhDo = @Longitude,
                    LaMacDinh = @IsDefault,
                    DangHoatDong = @IsActive
                WHERE MaDiaChiKhachHang = @AddressId
                  AND MaKhachHang = @CustomerId;

                -- Nếu còn địa chỉ hoạt động thì bảo đảm có
                -- một địa chỉ mặc định.
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.DiaChiKhachHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaKhachHang = @CustomerId
                      AND DangHoatDong = 1
                      AND LaMacDinh = 1
                )
                BEGIN
                    DECLARE @ReplacementId BIGINT;

                    SELECT TOP (1)
                        @ReplacementId = MaDiaChiKhachHang
                    FROM dbo.DiaChiKhachHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaKhachHang = @CustomerId
                      AND DangHoatDong = 1
                    ORDER BY
                        CASE
                            WHEN MaDiaChiKhachHang = @AddressId
                                THEN 1
                            ELSE 0
                        END,
                        MaDiaChiKhachHang;

                    IF @ReplacementId IS NOT NULL
                    BEGIN
                        UPDATE dbo.DiaChiKhachHang
                        SET LaMacDinh = 1
                        WHERE MaDiaChiKhachHang = @ReplacementId;
                    END;
                END;

                SELECT @DefaultAddressId = MaDiaChiKhachHang
                FROM dbo.DiaChiKhachHang
                WHERE MaKhachHang = @CustomerId
                  AND DangHoatDong = 1
                  AND LaMacDinh = 1;

                SELECT @Result = (
                    SELECT
                        dc.MaDiaChiKhachHang AS id,
                        dc.MaKhachHang AS customerId,
                        dc.NhanDiaChi AS label,
                        dc.TenNguoiLienHe AS contactName,
                        dc.SoDienThoaiLienHe AS phone,
                        dc.DiaChi AS address,
                        dc.MaKhuVuc AS areaId,
                        dc.ViDo AS latitude,
                        dc.KinhDo AS longitude,
                        dc.LaMacDinh AS isDefault,
                        dc.DangHoatDong AS isActive,
                        @DefaultAddressId AS defaultAddressId,
                        N'Cập nhật địa chỉ thành công.' AS message
                    FROM dbo.DiaChiKhachHang dc
                    WHERE dc.MaDiaChiKhachHang = @AddressId
                      AND dc.MaKhachHang = @CustomerId
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
                    'UPDATE_CUSTOMER_ADDRESS',
                    'DiaChiKhachHang',
                    CONVERT(VARCHAR(100), @AddressId),
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
            "@CustomerId", SqlDbType.BigInt).Value = customerId;

        command.Parameters.Add(
            "@AddressId", SqlDbType.BigInt).Value = addressId;

        command.Parameters.Add(
            "@Label", SqlDbType.NVarChar, 100).Value =
            OptionalText(request.Label);

        command.Parameters.Add(
            "@ContactName", SqlDbType.NVarChar, 150).Value =
            OptionalText(request.ContactName);

        command.Parameters.Add(
            "@ContactPhone", SqlDbType.VarChar, 20).Value =
            OptionalText(request.Phone);

        command.Parameters.Add(
            "@Address", SqlDbType.NVarChar, 300).Value =
            request.Address.Trim();

        command.Parameters.Add(
            "@AreaId", SqlDbType.Int).Value =
            (object?)request.AreaId ?? DBNull.Value;

        command.Parameters.Add(
            "@IsDefault", SqlDbType.Bit).Value =
            request.IsDefault!.Value;

        command.Parameters.Add(
            "@IsActive", SqlDbType.Bit).Value =
            request.IsActive!.Value;

        var latitudeParameter = command.Parameters.Add(
            "@Latitude", SqlDbType.Decimal);

        latitudeParameter.Precision = 9;
        latitudeParameter.Scale = 6;
        latitudeParameter.Value =
            (object?)request.Latitude ?? DBNull.Value;

        var longitudeParameter = command.Parameters.Add(
            "@Longitude", SqlDbType.Decimal);

        longitudeParameter.Precision = 10;
        longitudeParameter.Scale = 6;
        longitudeParameter.Value =
            (object?)request.Longitude ?? DBNull.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 54501)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54502)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54503)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54504)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54505)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627 or 1205)
        {
            return Conflict(new
            {
                message = "Địa chỉ đang được cập nhật đồng thời. Hãy tải lại và thử lại."
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
