using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using LastMile.Api.Services;

namespace LastMile.Api.Controllers;

public class SaveVehicleRequest
{
    [Range(1, long.MaxValue)]
    public long? Id { get; set; }

    [Required]
    [StringLength(20)]
    public string LicensePlate { get; set; } = "";

    [Required]
    [StringLength(30)]
    [RegularExpression(
        @"^[A-Za-z0-9_ -]+$",
        ErrorMessage = "VehicleType chỉ gồm chữ Latin, số, dấu gạch hoặc khoảng trắng.")]
    public string VehicleType { get; set; } = "";

    // Existing callers can still send individual capacity. New forms request
    // the backend preset and can omit these two values.
    public decimal MaxWeightKg { get; set; }

    public decimal? MaxVolumeM3 { get; set; }

    public bool UseTypeCapacity { get; set; }

    [Required]
    [RegularExpression(
        "^(AVAILABLE|MAINTENANCE|INACTIVE)$",
        ErrorMessage = "Status phải là AVAILABLE, MAINTENANCE hoặc INACTIVE.")]
    public string Status { get; set; } = "AVAILABLE";

    [Required]
    public bool? IsActive { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/vehicles")]
public class VehicleSaveController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly VehicleTypeCatalog _catalog;

    public VehicleSaveController(IConfiguration configuration, VehicleTypeCatalog catalog)
    {
        _configuration = configuration;
        _catalog = catalog;
    }

    [HttpPost]
    public async Task<IActionResult> Save(
        SaveVehicleRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        var licensePlate = request.LicensePlate.Trim().ToUpperInvariant();
        var vehicleType = request.VehicleType.Trim();
        var definition = _catalog.GetTypes().SingleOrDefault(t => t.Code == vehicleType);
        if (request.UseTypeCapacity)
        {
            if (definition is null)
            {
                ModelState.AddModelError(nameof(request.VehicleType), "Loại phương tiện không có trong danh mục cấu hình.");
                return ValidationProblem(ModelState);
            }
            request.MaxWeightKg = definition.MaxCargoWeightKg;
            request.MaxVolumeM3 = definition.MaxCargoVolumeM3;
        }

        // Validate effective values after applying the preset; keep the same
        // database precision/range checks for existing API clients.
        if (request.MaxWeightKg < 0.01m || request.MaxWeightKg > 99999999.99m)
            ModelState.AddModelError(nameof(request.MaxWeightKg), "Tải trọng hàng phải lớn hơn 0 và nằm trong phạm vi lưu trữ của hệ thống.");
        if (request.MaxVolumeM3.HasValue && (request.MaxVolumeM3 < 0.001m || request.MaxVolumeM3 > 9999999.999m))
            ModelState.AddModelError(nameof(request.MaxVolumeM3), "Sức chứa nếu nhập phải lớn hơn 0 và nằm trong phạm vi lưu trữ của hệ thống.");
        if (!ModelState.IsValid) return ValidationProblem(ModelState);

        if (string.IsNullOrWhiteSpace(licensePlate)
            || string.IsNullOrWhiteSpace(vehicleType))
        {
            if (string.IsNullOrWhiteSpace(licensePlate)) ModelState.AddModelError(nameof(request.LicensePlate), "Biển số không được để trống.");
            if (string.IsNullOrWhiteSpace(vehicleType)) ModelState.AddModelError(nameof(request.VehicleType), "Vui lòng chọn loại phương tiện.");
            return ValidationProblem(ModelState);
        }

        if (decimal.Round(request.MaxWeightKg, 2)
            != request.MaxWeightKg)
        {
            ModelState.AddModelError(nameof(request.MaxWeightKg), "Tải trọng hàng chỉ được có tối đa 2 chữ số thập phân.");
            return ValidationProblem(ModelState);
        }

        if (request.MaxVolumeM3.HasValue
            && decimal.Round(request.MaxVolumeM3.Value, 3)
               != request.MaxVolumeM3.Value)
        {
            ModelState.AddModelError(nameof(request.MaxVolumeM3), "Sức chứa chỉ được có tối đa 3 chữ số thập phân.");
            return ValidationProblem(ModelState);
        }

        if ((request.IsActive == false && request.Status != "INACTIVE")
            || (request.IsActive == true && request.Status == "INACTIVE"))
        {
            return BadRequest(new
            {
                message = "Xe ngừng hoạt động phải có status INACTIVE; xe hoạt động không được có status INACTIVE."
            });
        }

        var vehicleCode = "XE-" + Guid.NewGuid()
            .ToString("N")[..27]
            .ToUpperInvariant();

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @VehicleId BIGINT = @Id,
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @RoleId = tk.MaVaiTro
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

                IF @Role IS NULL
                    THROW 55201,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF @Role <> 'ADMIN'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vq
                       JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                       WHERE vq.MaVaiTro = @RoleId
                         AND q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                   )
                    THROW 55202,
                        N'API này dành cho admin quản lý phương tiện.', 1;

                -- Preserve existing legacy capacities/types only when all three
                -- fields are unchanged. The comparison shares the save lock.
                DECLARE @UnchangedCapacity BIT = 0;
                IF @Id IS NOT NULL AND EXISTS (
                    SELECT 1 FROM dbo.PhuongTien WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaPhuongTien = @Id
                      AND LoaiXe COLLATE Latin1_General_100_BIN2 = @VehicleType COLLATE Latin1_General_100_BIN2
                      AND KhoiLuongDenKg = @MaxWeightKg
                      AND (TheTichToiDaM3 = @MaxVolumeM3 OR (TheTichToiDaM3 IS NULL AND @MaxVolumeM3 IS NULL))
                ) SET @UnchangedCapacity = 1;

                IF @UnchangedCapacity = 0
                BEGIN
                    IF @KnownType = 0
                        THROW 55210, N'Loại phương tiện không có trong danh mục cấu hình. Hãy chọn loại hợp lệ.', 1;
                    IF @MaxWeightKg > @TypeMaxWeight
                        THROW 55211, N'Tải trọng hàng vượt giới hạn nghiệp vụ của loại phương tiện đã chọn.', 1;
                    IF @TypeMaxVolume IS NOT NULL AND @MaxVolumeM3 > @TypeMaxVolume
                        THROW 55212, N'Sức chứa vượt giới hạn nghiệp vụ của loại phương tiện đã chọn.', 1;
                END;

                IF @VehicleId IS NOT NULL
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.PhuongTien WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaPhuongTien = @VehicleId
                    )
                        THROW 55203,
                            N'Không tìm thấy phương tiện.', 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaPhuongTien = @VehicleId
                          AND ThoiGianKetThuc IS NULL
                    )
                        THROW 55204,
                            N'Xe còn phân công giao hàng đang hoạt động. Hãy xử lý trước khi sửa.', 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.ChuyenGiaoHang WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaPhuongTien = @VehicleId
                          AND TrangThaiChuyen IN (
                              'PLANNED', 'ASSIGNED',
                              'ACCEPTED', 'IN_PROGRESS'
                          )
                    )
                        THROW 55204,
                            N'Xe còn được sử dụng trong chuyến chưa kết thúc.', 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                        JOIN dbo.TrangThaiDonHang tt
                            ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                        CROSS APPLY (
                            SELECT TOP (1)
                                pc.MaPhuongTien
                            FROM dbo.PhanCongGiaoHang pc WITH (HOLDLOCK)
                            WHERE pc.MaDonHang = d.MaDonHang
                            ORDER BY
                                pc.ThoiGianPhanCong DESC,
                                pc.MaPhanCongGiaoHang DESC
                        ) latest
                        WHERE tt.KyHieuTrangThai = 'RETURNING'
                          AND latest.MaPhuongTien = @VehicleId
                    )
                        THROW 55204,
                            N'Xe còn được sử dụng để hoàn hàng.', 1;

                    IF (
                        @Status IN ('MAINTENANCE', 'INACTIVE')
                        OR @IsActive = 0
                    )
                       AND EXISTS (
                           SELECT 1
                           FROM dbo.PhanCongPhuongTien
                               WITH (UPDLOCK, HOLDLOCK)
                           WHERE MaPhuongTien = @VehicleId
                             AND ThoiGianKetThuc IS NULL
                       )
                        THROW 55204,
                            N'Hãy kết thúc phân công xe cho shipper trước khi bảo trì hoặc ngừng hoạt động.', 1;

                    SELECT @OldJson = (
                        SELECT
                            MaPhuongTien AS id,
                            KyHieuPhuongTien AS code,
                            BienSo AS licensePlate,
                            LoaiXe AS vehicleType,
                            KhoiLuongDenKg AS maxWeightKg,
                            TheTichToiDaM3 AS maxVolumeM3,
                            TrangThaiPhuongTien AS status,
                            DangHoatDong AS isActive
                        FROM dbo.PhuongTien
                        WHERE MaPhuongTien = @VehicleId
                        FOR JSON PATH,
                            INCLUDE_NULL_VALUES,
                            WITHOUT_ARRAY_WRAPPER
                    );

                    UPDATE dbo.PhuongTien
                    SET BienSo = @LicensePlate,
                        LoaiXe = @VehicleType,
                        KhoiLuongDenKg = @MaxWeightKg,
                        TheTichToiDaM3 = @MaxVolumeM3,
                        TrangThaiPhuongTien = @Status,
                        DangHoatDong = @IsActive
                    WHERE MaPhuongTien = @VehicleId;
                END
                ELSE
                BEGIN
                    INSERT INTO dbo.PhuongTien (
                        KyHieuPhuongTien,
                        BienSo,
                        LoaiXe,
                        KhoiLuongDenKg,
                        TheTichToiDaM3,
                        TrangThaiPhuongTien,
                        DangHoatDong
                    )
                    VALUES (
                        @VehicleCode,
                        @LicensePlate,
                        @VehicleType,
                        @MaxWeightKg,
                        @MaxVolumeM3,
                        @Status,
                        @IsActive
                    );

                    SET @VehicleId =
                        CONVERT(BIGINT, SCOPE_IDENTITY());
                END;

                SELECT @Result = (
                    SELECT
                        MaPhuongTien AS id,
                        KyHieuPhuongTien AS code,
                        BienSo AS licensePlate,
                        LoaiXe AS vehicleType,
                        KhoiLuongDenKg AS maxWeightKg,
                        TheTichToiDaM3 AS maxVolumeM3,
                        TrangThaiPhuongTien AS status,
                        DangHoatDong AS isActive,
                        CASE
                            WHEN @Id IS NULL
                                THEN N'Tạo phương tiện thành công.'
                            ELSE N'Cập nhật phương tiện thành công.'
                        END AS message
                    FROM dbo.PhuongTien
                    WHERE MaPhuongTien = @VehicleId
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
                    CASE
                        WHEN @Id IS NULL THEN 'CREATE_VEHICLE'
                        ELSE 'UPDATE_VEHICLE'
                    END,
                    'PhuongTien',
                    CONVERT(VARCHAR(100), @VehicleId),
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

        command.Parameters.Add("@KnownType", SqlDbType.Bit).Value = definition is not null;
        var typeWeight = command.Parameters.Add("@TypeMaxWeight", SqlDbType.Decimal);
        typeWeight.Precision = 10; typeWeight.Scale = 2;
        typeWeight.Value = (object?)definition?.MaxCargoWeightKg ?? DBNull.Value;
        var typeVolume = command.Parameters.Add("@TypeMaxVolume", SqlDbType.Decimal);
        typeVolume.Precision = 10; typeVolume.Scale = 3;
        typeVolume.Value = (object?)definition?.MaxCargoVolumeM3 ?? DBNull.Value;

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Id", SqlDbType.BigInt).Value =
            (object?)request.Id ?? DBNull.Value;

        command.Parameters.Add(
            "@VehicleCode", SqlDbType.VarChar, 30).Value =
            vehicleCode;

        command.Parameters.Add(
            "@LicensePlate", SqlDbType.NVarChar, 20).Value =
            licensePlate;

        command.Parameters.Add(
            "@VehicleType", SqlDbType.VarChar, 30).Value =
            vehicleType;

        var weight = command.Parameters.Add(
            "@MaxWeightKg", SqlDbType.Decimal);
        weight.Precision = 10;
        weight.Scale = 2;
        weight.Value = request.MaxWeightKg;

        var volume = command.Parameters.Add(
            "@MaxVolumeM3", SqlDbType.Decimal);
        volume.Precision = 10;
        volume.Scale = 3;
        volume.Value =
            (object?)request.MaxVolumeM3 ?? DBNull.Value;

        command.Parameters.Add(
            "@Status", SqlDbType.VarChar, 20).Value =
            request.Status;

        command.Parameters.Add(
            "@IsActive", SqlDbType.Bit).Value =
            request.IsActive!.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return new ContentResult
            {
                StatusCode = request.Id.HasValue
                    ? StatusCodes.Status200OK
                    : StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = result?.ToString() ?? "{}"
            };
        }
        catch (SqlException ex) when (ex.Number == 55201)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55202)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55203)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55204)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number is 55210 or 55211 or 55212)
        {
            var field = ex.Number == 55210 ? nameof(request.VehicleType)
                : ex.Number == 55211 ? nameof(request.MaxWeightKg) : nameof(request.MaxVolumeM3);
            ModelState.AddModelError(field, ex.Message);
            return ValidationProblem(ModelState);
        }
        catch (SqlException ex) when (ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message = "Biển số hoặc mã phương tiện đã tồn tại.",
                field = ex.Message.Contains("UQ_PhuongTien_BienSo", StringComparison.Ordinal) ? "licensePlate" : null
            });
        }
        catch (SqlException ex) when (
            ex.Number >= 51000 && ex.Number <= 51099)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy thử lại."
            });
        }
    }
}
