using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CreateCustomerRequest
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
    public string Type { get; set; } = "INDIVIDUAL";

    public CreateCustomerInitialAddressRequest? Address { get; set; }
}

public class CreateCustomerInitialAddressRequest
{
    [StringLength(100)]
    public string? Label { get; set; }

    [StringLength(150)]
    public string? ContactName { get; set; }

    [RegularExpression(@"^\+?[0-9]{9,15}$")]
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
}

[ApiController]
[Authorize]
[Route("api/v1/customers")]
public class CustomerCreateController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CustomerCreateController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost]
    public async Task<IActionResult> Create(
        CreateCustomerRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        var fullName = request.FullName.Trim();
        var address = request.Address;

        if (string.IsNullOrWhiteSpace(fullName))
        {
            return BadRequest(new
            {
                message = "Tên khách hàng không được để trống."
            });
        }

        if (address is not null)
        {
            if (string.IsNullOrWhiteSpace(address.Address))
            {
                return BadRequest(new
                {
                    message = "Địa chỉ không được để trống."
                });
            }

            if (address.Latitude.HasValue
                != address.Longitude.HasValue)
            {
                return BadRequest(new
                {
                    message = "Phải nhập cả latitude và longitude hoặc bỏ trống cả hai."
                });
            }

            if ((address.Latitude.HasValue
                 && decimal.Round(address.Latitude.Value, 6)
                    != address.Latitude.Value)
                || (address.Longitude.HasValue
                    && decimal.Round(address.Longitude.Value, 6)
                       != address.Longitude.Value))
            {
                return BadRequest(new
                {
                    message = "Tọa độ chỉ được có tối đa 6 chữ số thập phân."
                });
            }
        }

        var customerCode = "KH-" + Guid.NewGuid()
            .ToString("N")[..27]
            .ToUpperInvariant();

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE @RoleId INT;

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
                    THROW 54201,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1 FROM dbo.TaiKhoan tk
                    JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @AccountId
                      AND (vt.KyHieuVaiTro = 'ADMIN' OR tk.MaBuuCuc IS NOT NULL)
                )
                    THROW 54202, N'Tài khoản chưa được gắn với bưu cục.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DONHANG_TAO'
                )
                    THROW 54202,
                        N'Bạn không có quyền tạo khách hàng.', 1;

                IF @HasAddress = 1
                   AND @AreaId IS NOT NULL
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.KhuVuc WITH (HOLDLOCK)
                       WHERE MaKhuVuc = @AreaId
                         AND DangHoatDong = 1
                   )
                    THROW 54203,
                        N'Khu vực không tồn tại hoặc đã ngừng hoạt động.', 1;

                INSERT INTO dbo.KhachHang (
                    KyHieuKhachHang,
                    HoTen,
                    SoDienThoai,
                    Email,
                    LoaiKhachHang,
                    DangHoatDong
                )
                VALUES (
                    @CustomerCode,
                    @FullName,
                    @Phone,
                    @Email,
                    @Type,
                    1
                );

                DECLARE @CustomerId BIGINT =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                IF @HasAddress = 1
                BEGIN
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
                        COALESCE(@ContactName, @FullName),
                        COALESCE(@ContactPhone, @Phone),
                        @Address,
                        @AreaId,
                        @Latitude,
                        @Longitude,
                        1,
                        1
                    );
                END;

                DECLARE @Result NVARCHAR(MAX);

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
                        CONVERT(VARBINARY(8), kh.PhienBan) AS version,
                        JSON_QUERY(COALESCE((
                            SELECT
                                dc.MaDiaChiKhachHang AS id,
                                dc.NhanDiaChi AS label,
                                dc.TenNguoiLienHe AS contactName,
                                dc.SoDienThoaiLienHe AS phone,
                                dc.DiaChi AS address,
                                dc.MaKhuVuc AS areaId,
                                dc.ViDo AS latitude,
                                dc.KinhDo AS longitude,
                                dc.LaMacDinh AS isDefault,
                                CONVERT(VARBINARY(8), dc.PhienBan) AS version
                            FROM dbo.DiaChiKhachHang dc
                            WHERE dc.MaKhachHang = @CustomerId
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        ), N'[]')) AS addresses,
                        N'Tạo khách hàng thành công.' AS message
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
                    DuLieuMoiJson
                )
                VALUES (
                    @AccountId,
                    'CREATE_CUSTOMER',
                    'KhachHang',
                    CONVERT(VARCHAR(100), @CustomerId),
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
            "@CustomerCode", SqlDbType.VarChar, 30).Value =
            customerCode;

        command.Parameters.Add(
            "@FullName", SqlDbType.NVarChar, 150).Value = fullName;

        command.Parameters.Add(
            "@Phone", SqlDbType.VarChar, 20).Value =
            request.Phone;

        command.Parameters.Add(
            "@Email", SqlDbType.VarChar, 150).Value =
            OptionalText(request.Email);

        command.Parameters.Add(
            "@Type", SqlDbType.VarChar, 20).Value = request.Type;

        command.Parameters.Add(
            "@HasAddress", SqlDbType.Bit).Value = address is not null;

        command.Parameters.Add(
            "@Label", SqlDbType.NVarChar, 100).Value =
            OptionalText(address?.Label);

        command.Parameters.Add(
            "@ContactName", SqlDbType.NVarChar, 150).Value =
            OptionalText(address?.ContactName);

        command.Parameters.Add(
            "@ContactPhone", SqlDbType.VarChar, 20).Value =
            OptionalText(address?.Phone);

        command.Parameters.Add(
            "@Address", SqlDbType.NVarChar, 300).Value =
            OptionalText(address?.Address);

        command.Parameters.Add(
            "@AreaId", SqlDbType.Int).Value =
            (object?)address?.AreaId ?? DBNull.Value;

        var latitudeParameter = command.Parameters.Add(
            "@Latitude", SqlDbType.Decimal);

        latitudeParameter.Precision = 9;
        latitudeParameter.Scale = 6;
        latitudeParameter.Value =
            (object?)address?.Latitude ?? DBNull.Value;

        var longitudeParameter = command.Parameters.Add(
            "@Longitude", SqlDbType.Decimal);

        longitudeParameter.Precision = 10;
        longitudeParameter.Scale = 6;
        longitudeParameter.Value =
            (object?)address?.Longitude ?? DBNull.Value;

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
        catch (SqlException ex) when (ex.Number == 54201)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54202)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54203)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message = "Mã khách hàng bị trùng. Hãy thử lại."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy thử lại."
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
