using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class AddCustomerAddressRequest
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

    public bool IsDefault { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/customers")]
public class CustomerAddressCreateController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CustomerAddressCreateController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{customerId:long}/addresses")]
    public async Task<IActionResult> Create(
        long customerId,
        AddCustomerAddressRequest request,
        CancellationToken cancellationToken)
    {
        if (customerId <= 0)
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

        if (string.IsNullOrWhiteSpace(request.Address))
        {
            return BadRequest(new
            {
                message = "Địa chỉ không được để trống."
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
                    @MakeDefault BIT = @IsDefault,
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
                    THROW 54401,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1 FROM dbo.TaiKhoan tk
                    JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @AccountId
                      AND (vt.KyHieuVaiTro = 'ADMIN' OR tk.MaBuuCuc IS NOT NULL)
                )
                    THROW 54402, N'Tài khoản chưa được gắn với bưu cục.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DONHANG_CAPNHAT'
                )
                    THROW 54402,
                        N'Bạn không có quyền thêm địa chỉ khách hàng.', 1;

                -- Khóa khách hàng để các thao tác thêm địa chỉ
                -- của cùng khách hàng không chạy chồng nhau.
                SELECT
                    @CustomerName = kh.HoTen,
                    @CustomerPhone = kh.SoDienThoai,
                    @CustomerActive = kh.DangHoatDong
                FROM dbo.KhachHang kh WITH (UPDLOCK, HOLDLOCK)
                WHERE kh.MaKhachHang = @CustomerId;

                IF @CustomerName IS NULL
                    THROW 54403,
                        N'Không tìm thấy khách hàng.', 1;

                IF @CustomerActive = 0
                    THROW 54404,
                        N'Khách hàng đã ngừng hoạt động. Hãy kích hoạt lại trước.', 1;

                IF @AreaId IS NOT NULL
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.KhuVuc WITH (HOLDLOCK)
                       WHERE MaKhuVuc = @AreaId
                         AND DangHoatDong = 1
                   )
                    THROW 54405,
                        N'Khu vực không tồn tại hoặc đã ngừng hoạt động.', 1;

                -- Nếu chưa có địa chỉ mặc định đang hoạt động,
                -- địa chỉ mới tự động trở thành mặc định.
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.DiaChiKhachHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaKhachHang = @CustomerId
                      AND DangHoatDong = 1
                      AND LaMacDinh = 1
                )
                    SET @MakeDefault = 1;

                DECLARE @PreviousDefaultId BIGINT;

                SELECT @PreviousDefaultId = MaDiaChiKhachHang
                FROM dbo.DiaChiKhachHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaKhachHang = @CustomerId
                  AND DangHoatDong = 1
                  AND LaMacDinh = 1;

                IF @MakeDefault = 1
                BEGIN
                    UPDATE dbo.DiaChiKhachHang
                    SET LaMacDinh = 0
                    WHERE MaKhachHang = @CustomerId
                      AND LaMacDinh = 1;
                END;

                INSERT INTO dbo.DiaChiKhachHang (
                    MaKhachHang,
                    NhanDiaChi,
                    TenNguoiLienHe,
                    SoDienThoaiLienHe,
                    DiaChi,
                    MaKhuVuc,
                    ViDo,
                    KinhDo,
                    LaMacDinh,
                    DangHoatDong
                )
                VALUES (
                    @CustomerId,
                    @Label,
                    COALESCE(@ContactName, @CustomerName),
                    COALESCE(@ContactPhone, @CustomerPhone),
                    @Address,
                    @AreaId,
                    @Latitude,
                    @Longitude,
                    @MakeDefault,
                    1
                );

                DECLARE @AddressId BIGINT =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

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
                        N'Thêm địa chỉ thành công.' AS message
                    FROM dbo.DiaChiKhachHang dc
                    WHERE dc.MaDiaChiKhachHang = @AddressId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                DECLARE @OldJson NVARCHAR(MAX);

                SELECT @OldJson = (
                    SELECT
                        @CustomerId AS customerId,
                        @PreviousDefaultId AS previousDefaultAddressId
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
                    'CREATE_CUSTOMER_ADDRESS',
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
            "@IsDefault", SqlDbType.Bit).Value = request.IsDefault;

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

            return new ContentResult
            {
                StatusCode = StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = result?.ToString() ?? "{}"
            };
        }
        catch (SqlException ex) when (ex.Number == 54401)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54402)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54403)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54404)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54405)
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
