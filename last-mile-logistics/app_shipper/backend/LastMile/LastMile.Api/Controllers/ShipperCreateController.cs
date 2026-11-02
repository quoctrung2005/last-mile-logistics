using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CreateShipperRequest
{
    [Range(1, long.MaxValue)]
    public long AccountId { get; set; }

    [RegularExpression(
        @"^[0-9]{12}$",
        ErrorMessage = "CCCD phải có 12 chữ số.")]
    public string? IdentityNumber { get; set; }

    [StringLength(50)]
    [RegularExpression(
        @"^[A-Za-z0-9 -]+$",
        ErrorMessage = "Số bằng lái chỉ gồm chữ Latin, số, khoảng trắng hoặc dấu gạch ngang.")]
    public string? LicenseNumber { get; set; }

    public DateOnly? LicenseExpiresAt { get; set; }

    [Required]
    [MaxLength(100)]
    public List<CreateShipperAreaRequest> Areas { get; set; } = [];
}

public class CreateShipperAreaRequest
{
    [Range(1, int.MaxValue)]
    public int AreaId { get; set; }

    public bool IsPrimary { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/shippers")]
public class ShipperCreateController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public ShipperCreateController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost]
    public async Task<IActionResult> Create(
        CreateShipperRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        if (request.Areas.Any(x => x is null))
        {
            return BadRequest(new
            {
                message = "Danh sách khu vực không được chứa phần tử null."
            });
        }

        if (request.Areas.Select(x => x.AreaId).Distinct().Count()
            != request.Areas.Count)
        {
            return BadRequest(new
            {
                message = "Không được nhập trùng khu vực."
            });
        }

        if (request.Areas.Count(x => x.IsPrimary) > 1)
        {
            return BadRequest(new
            {
                message = "Chỉ được chọn một khu vực chính."
            });
        }

        var licenseNumber = request.LicenseNumber?.Trim();

        if (request.LicenseExpiresAt.HasValue
            && string.IsNullOrWhiteSpace(licenseNumber))
        {
            return BadRequest(new
            {
                message = "Phải nhập số bằng lái khi nhập ngày hết hạn."
            });
        }

        if (request.LicenseExpiresAt.HasValue
            && request.LicenseExpiresAt.Value
               < DateOnly.FromDateTime(DateTime.UtcNow))
        {
            return BadRequest(new
            {
                message = "Bằng lái đã hết hạn."
            });
        }

        var employeeCode = "NV-" + Guid.NewGuid()
            .ToString("N")[..27]
            .ToUpperInvariant();

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @ActorRole VARCHAR(50),
                    @ActorRoleId INT,
                    @ActorBranch INT,
                    @TargetBranch INT,
                    @TargetRole VARCHAR(50),
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
                    THROW 54801,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @ActorRoleId
                      AND q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                )
                    THROW 54802,
                        N'Bạn không có quyền tạo hồ sơ shipper.', 1;

                IF @ActorRole <> 'ADMIN' AND @ActorBranch IS NULL
                    THROW 54802,
                        N'Tài khoản chưa được gắn với bưu cục.', 1;

                SELECT
                    @TargetBranch = tk.MaBuuCuc,
                    @TargetRole = vt.KyHieuVaiTro
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @TargetAccountId
                  AND (
                      @ActorRole = 'ADMIN'
                      OR tk.MaBuuCuc = @ActorBranch
                  )
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @TargetRole IS NULL
                    THROW 54803,
                        N'Không tìm thấy tài khoản hợp lệ trong phạm vi quản lý.', 1;

                IF @TargetRole <> 'SHIPPER'
                    THROW 54804,
                        N'Tài khoản phải có vai trò SHIPPER.', 1;

                IF @TargetBranch IS NULL
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.BuuCuc WITH (HOLDLOCK)
                       WHERE MaBuuCuc = @TargetBranch
                         AND DangHoatDong = 1
                   )
                    THROW 54804,
                        N'Tài khoản shipper phải thuộc bưu cục đang hoạt động.', 1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.NhanVienGiaoHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaTaiKhoan = @TargetAccountId
                )
                    THROW 54805,
                        N'Tài khoản này đã có hồ sơ shipper.', 1;

                CREATE TABLE #Areas (
                    AreaId INT NOT NULL PRIMARY KEY,
                    IsPrimary BIT NOT NULL
                );

                INSERT INTO #Areas (AreaId, IsPrimary)
                SELECT AreaId, IsPrimary
                FROM OPENJSON(@AreasJson)
                WITH (
                    AreaId INT '$.AreaId',
                    IsPrimary BIT '$.IsPrimary'
                );

                IF EXISTS (
                    SELECT 1
                    FROM #Areas a
                    LEFT JOIN dbo.KhuVuc kv WITH (HOLDLOCK)
                        ON kv.MaKhuVuc = a.AreaId
                    WHERE kv.MaKhuVuc IS NULL
                       OR kv.DangHoatDong = 0
                )
                    THROW 54804,
                        N'Có khu vực không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF @LicenseExpiresAt IS NOT NULL
                   AND @LicenseExpiresAt
                       < CONVERT(DATE, SYSUTCDATETIME())
                    THROW 54804,
                        N'Bằng lái đã hết hạn.', 1;

                INSERT INTO dbo.NhanVienGiaoHang (
                    MaTaiKhoan,
                    MaNhanVien,
                    CCCD,
                    SoBangLai,
                    NgayHetHanBangLai,
                    TrangThaiSanSang,
                    DangHoatDong
                )
                VALUES (
                    @TargetAccountId,
                    @EmployeeCode,
                    @IdentityNumber,
                    @LicenseNumber,
                    @LicenseExpiresAt,
                    'OFFLINE',
                    1
                );

                DECLARE @ShipperId BIGINT =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.KhuVucNhanVienGiaoHang (
                    MaNhanVienGiaoHang,
                    MaKhuVuc,
                    LaChinh
                )
                SELECT
                    @ShipperId,
                    AreaId,
                    IsPrimary
                FROM #Areas;

                SELECT @Result = (
                    SELECT
                        nv.MaNhanVienGiaoHang AS id,
                        nv.MaNhanVien AS employeeCode,
                        nv.MaTaiKhoan AS accountId,
                        tk.TenDangNhap AS username,
                        tk.HoTen AS fullName,
                        tk.MaBuuCuc AS branchId,
                        nv.CCCD AS identityNumber,
                        nv.SoBangLai AS licenseNumber,
                        nv.NgayHetHanBangLai AS licenseExpiresAt,
                        nv.TrangThaiSanSang AS availability,
                        nv.DangHoatDong AS isActive,
                        JSON_QUERY(COALESCE((
                            SELECT
                                kv.MaKhuVuc AS id,
                                kv.TenKhuVuc AS name,
                                p.LaChinh AS isPrimary
                            FROM dbo.KhuVucNhanVienGiaoHang p
                            JOIN dbo.KhuVuc kv
                                ON kv.MaKhuVuc = p.MaKhuVuc
                            WHERE p.MaNhanVienGiaoHang = @ShipperId
                            ORDER BY p.LaChinh DESC, kv.MaKhuVuc
                            FOR JSON PATH
                        ), N'[]')) AS areas,
                        N'Tạo hồ sơ shipper thành công.' AS message
                    FROM dbo.NhanVienGiaoHang nv
                    JOIN dbo.TaiKhoan tk
                        ON tk.MaTaiKhoan = nv.MaTaiKhoan
                    WHERE nv.MaNhanVienGiaoHang = @ShipperId
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
                    @ActorId,
                    'CREATE_SHIPPER',
                    'NhanVienGiaoHang',
                    CONVERT(VARCHAR(100), @ShipperId),
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
            "@ActorId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@TargetAccountId", SqlDbType.BigInt).Value =
            request.AccountId;

        command.Parameters.Add(
            "@EmployeeCode", SqlDbType.VarChar, 30).Value =
            employeeCode;

        command.Parameters.Add(
            "@IdentityNumber", SqlDbType.VarChar, 20).Value =
            OptionalText(request.IdentityNumber);

        command.Parameters.Add(
            "@LicenseNumber", SqlDbType.VarChar, 50).Value =
            OptionalText(licenseNumber);

        command.Parameters.Add(
            "@LicenseExpiresAt", SqlDbType.Date).Value =
            request.LicenseExpiresAt.HasValue
                ? request.LicenseExpiresAt.Value.ToDateTime(TimeOnly.MinValue)
                : DBNull.Value;

        command.Parameters.Add(
            "@AreasJson", SqlDbType.NVarChar, -1).Value =
            JsonSerializer.Serialize(request.Areas);

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
        catch (SqlException ex) when (ex.Number == 54801)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54802)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54803)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54804)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54805)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message = "Tài khoản đã có hồ sơ shipper hoặc CCCD/mã nhân viên bị trùng."
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