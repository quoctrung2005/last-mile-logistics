using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class UpdateShipperRequest
{
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
    public bool? IsActive { get; set; }

    [Required]
    [MaxLength(100)]
    public List<UpdateShipperAreaRequest> Areas { get; set; } = [];
}

public class UpdateShipperAreaRequest
{
    [Range(1, int.MaxValue)]
    public int AreaId { get; set; }

    public bool IsPrimary { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/shippers")]
public class ShipperUpdateController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public ShipperUpdateController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPut("{id:long}")]
    public async Task<IActionResult> Update(
        long id,
        UpdateShipperRequest request,
        CancellationToken cancellationToken)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã shipper không hợp lệ." });

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
                message = "Ngày hết hạn bằng lái không được nằm trong quá khứ."
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
                    @TargetAccountId BIGINT,
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
                    THROW 54901,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @ActorRoleId
                      AND q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                )
                    THROW 54902,
                        N'Bạn không có quyền sửa hồ sơ shipper.', 1;

                IF @ActorRole <> 'ADMIN' AND @ActorBranch IS NULL
                    THROW 54902,
                        N'Tài khoản chưa được gắn với bưu cục.', 1;

                SELECT @TargetAccountId = nv.MaTaiKhoan
                FROM dbo.NhanVienGiaoHang nv WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                    ON tk.MaTaiKhoan = nv.MaTaiKhoan
                WHERE nv.MaNhanVienGiaoHang = @ShipperId
                  AND (
                      @ActorRole = 'ADMIN'
                      OR tk.MaBuuCuc = @ActorBranch
                  );

                IF @TargetAccountId IS NULL
                    THROW 54903,
                        N'Không tìm thấy shipper.', 1;

                IF @IsActive = 1
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                       JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                           ON vt.MaVaiTro = tk.MaVaiTro
                       JOIN dbo.BuuCuc bc WITH (HOLDLOCK)
                           ON bc.MaBuuCuc = tk.MaBuuCuc
                       WHERE tk.MaTaiKhoan = @TargetAccountId
                         AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                         AND vt.KyHieuVaiTro = 'SHIPPER'
                         AND vt.DangHoatDong = 1
                         AND bc.DangHoatDong = 1
                         AND (
                             tk.KhoaDenLuc IS NULL
                             OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                         )
                   )
                    THROW 54904,
                        N'Chỉ được kích hoạt hồ sơ khi tài khoản SHIPPER và bưu cục còn hoạt động.', 1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaNhanVienGiaoHang = @ShipperId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 54905,
                        N'Shipper còn phân công đang hoạt động. Hãy xử lý hoặc điều phối lại trước.', 1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.ChuyenGiaoHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaNhanVienGiaoHang = @ShipperId
                      AND TrangThaiChuyen IN (
                          'ASSIGNED', 'ACCEPTED', 'IN_PROGRESS'
                      )
                )
                    THROW 54905,
                        N'Shipper còn chuyến chưa kết thúc.', 1;

                -- Hoàn hàng có thể vẫn đang thực hiện dù
                -- phân công giao hàng đã được đóng.
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
                    THROW 54905,
                        N'Shipper còn nhiệm vụ hoàn hàng chưa hoàn tất.', 1;

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
                    THROW 54904,
                        N'Có khu vực không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF @LicenseExpiresAt IS NOT NULL
                   AND @LicenseExpiresAt
                       < CONVERT(DATE, SYSUTCDATETIME())
                    THROW 54904,
                        N'Ngày hết hạn bằng lái không được nằm trong quá khứ.', 1;

                SELECT @OldJson = (
                    SELECT
                        nv.MaNhanVienGiaoHang AS id,
                        nv.CCCD AS identityNumber,
                        nv.SoBangLai AS licenseNumber,
                        nv.NgayHetHanBangLai AS licenseExpiresAt,
                        nv.DangHoatDong AS isActive,
                        nv.TrangThaiSanSang AS availability,
                        JSON_QUERY(COALESCE((
                            SELECT
                                p.MaKhuVuc AS areaId,
                                p.LaChinh AS isPrimary
                            FROM dbo.KhuVucNhanVienGiaoHang p
                            WHERE p.MaNhanVienGiaoHang = @ShipperId
                            ORDER BY p.MaKhuVuc
                            FOR JSON PATH
                        ), N'[]')) AS areas
                    FROM dbo.NhanVienGiaoHang nv
                    WHERE nv.MaNhanVienGiaoHang = @ShipperId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                UPDATE dbo.NhanVienGiaoHang
                SET CCCD = @IdentityNumber,
                    SoBangLai = @LicenseNumber,
                    NgayHetHanBangLai = @LicenseExpiresAt,
                    DangHoatDong = @IsActive,
                    TrangThaiSanSang = CASE
                        WHEN @IsActive = 0 THEN 'OFFLINE'
                        ELSE TrangThaiSanSang
                    END
                WHERE MaNhanVienGiaoHang = @ShipperId;

                DELETE FROM dbo.KhuVucNhanVienGiaoHang
                WHERE MaNhanVienGiaoHang = @ShipperId;

                INSERT INTO dbo.KhuVucNhanVienGiaoHang (
                    MaNhanVienGiaoHang,
                    MaKhuVuc,
                    LaChinh
                )
                SELECT @ShipperId, AreaId, IsPrimary
                FROM #Areas;

                SELECT @Result = (
                    SELECT
                        nv.MaNhanVienGiaoHang AS id,
                        nv.MaNhanVien AS employeeCode,
                        nv.MaTaiKhoan AS accountId,
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
                        N'Cập nhật hồ sơ shipper thành công.' AS message
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
                    DuLieuCuJson,
                    DuLieuMoiJson
                )
                VALUES (
                    @ActorId,
                    'UPDATE_SHIPPER',
                    'NhanVienGiaoHang',
                    CONVERT(VARCHAR(100), @ShipperId),
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
            "@ActorId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value = id;

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
            "@IsActive", SqlDbType.Bit).Value =
            request.IsActive!.Value;

        command.Parameters.Add(
            "@AreasJson", SqlDbType.NVarChar, -1).Value =
            JsonSerializer.Serialize(request.Areas);

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 54901)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54902)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54903)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54904)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54905)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message = "CCCD đã được sử dụng hoặc dữ liệu khu vực bị trùng."
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