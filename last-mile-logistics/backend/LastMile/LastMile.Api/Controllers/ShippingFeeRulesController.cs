using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class SaveShippingFeeRuleRequest : IValidatableObject
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long? Id { get; set; }

    [Range(1, int.MaxValue)]
    public int ServiceId { get; set; }

    [Range(1, int.MaxValue)]
    public int? AreaId { get; set; }

    public decimal? DistanceFromKm { get; set; }

    public decimal? DistanceToKm { get; set; }

    public decimal? WeightFromKg { get; set; }

    public decimal? WeightToKg { get; set; }

    [Required]
    public decimal? BaseFee { get; set; }

    public decimal FeePerKm { get; set; }

    public decimal FeePerKg { get; set; }

    [Required]
    public DateTimeOffset? EffectiveFrom { get; set; }

    public DateTimeOffset? EffectiveTo { get; set; }

    [Required]
    public bool? IsActive { get; set; }

    public IEnumerable<ValidationResult> Validate(
        ValidationContext validationContext)
    {
        var ranges = new (string Name, decimal? Value)[]
        {
            (nameof(DistanceFromKm), DistanceFromKm),
            (nameof(DistanceToKm), DistanceToKm),
            (nameof(WeightFromKg), WeightFromKg),
            (nameof(WeightToKg), WeightToKg)
        };

        foreach (var field in ranges)
        {
            if (!field.Value.HasValue)
                continue;

            var value = field.Value.Value;

            if (value < 0 || value > 99999999.99m)
            {
                yield return new ValidationResult(
                    "Giá trị phải từ 0 đến 99999999.99.",
                    new[] { field.Name });
            }

            if (decimal.Round(value, 2) != value)
            {
                yield return new ValidationResult(
                    "Tối đa 2 chữ số thập phân.",
                    new[] { field.Name });
            }
        }

        var fees = new (string Name, decimal? Value)[]
        {
            (nameof(BaseFee), BaseFee),
            (nameof(FeePerKm), FeePerKm),
            (nameof(FeePerKg), FeePerKg)
        };

        foreach (var field in fees)
        {
            if (!field.Value.HasValue)
                continue;

            var value = field.Value.Value;

            if (value < 0 || value > 9999999999999999.99m)
            {
                yield return new ValidationResult(
                    "Phí phải từ 0 đến 9999999999999999.99.",
                    new[] { field.Name });
            }

            if (decimal.Round(value, 2) != value)
            {
                yield return new ValidationResult(
                    "Phí tối đa 2 chữ số thập phân.",
                    new[] { field.Name });
            }
        }

        if (DistanceFromKm.HasValue
            && DistanceToKm.HasValue
            && DistanceToKm.Value < DistanceFromKm.Value)
        {
            yield return new ValidationResult(
                "DistanceToKm phải lớn hơn hoặc bằng DistanceFromKm.",
                new[] { nameof(DistanceToKm) });
        }

        if (WeightFromKg.HasValue
            && WeightToKg.HasValue
            && WeightToKg.Value < WeightFromKg.Value)
        {
            yield return new ValidationResult(
                "WeightToKg phải lớn hơn hoặc bằng WeightFromKg.",
                new[] { nameof(WeightToKg) });
        }

        if (EffectiveFrom.HasValue
            && EffectiveTo.HasValue
            && EffectiveTo.Value <= EffectiveFrom.Value)
        {
            yield return new ValidationResult(
                "EffectiveTo phải sau EffectiveFrom.",
                new[] { nameof(EffectiveTo) });
        }
    }
}

[ApiController]
[Authorize]
[Route("api/v1/shipping-fees/rules")]
public class ShippingFeeRulesController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public ShippingFeeRulesController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost]
    public async Task<IActionResult> Save(
        SaveShippingFeeRuleRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        // Database lưu DATETIME2(0), dùng UTC và bỏ phần mili giây.
        var effectiveFrom = ToUtcSeconds(
            request.EffectiveFrom!.Value);

        DateTime? effectiveTo = request.EffectiveTo.HasValue
            ? ToUtcSeconds(request.EffectiveTo.Value)
            : null;

        if (effectiveTo.HasValue
            && effectiveTo.Value <= effectiveFrom)
        {
            return BadRequest(new
            {
                message =
                    "Thời gian kết thúc phải sau thời gian bắt đầu "
                    + "ít nhất 1 giây."
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
                    @RuleId BIGINT = @Id,
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT
                    @ActorRole = vt.KyHieuVaiTro,
                    @ActorRoleId = tk.MaVaiTro
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @ActorRole IS NULL
                    THROW 56601,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF @ActorRole <> 'ADMIN'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                       JOIN dbo.Quyen q WITH (HOLDLOCK)
                           ON q.MaQuyen = vq.MaQuyen
                       WHERE vq.MaVaiTro = @ActorRoleId
                         AND q.KyHieuQuyen = 'BANGGIA_QUANLY'
                   )
                    THROW 56602,
                        N'Bạn không có quyền quản lý quy tắc tính phí.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.LoaiDichVu WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaLoaiDichVu = @ServiceId
                      AND (
                          @IsActive = 0
                          OR DangHoatDong = 1
                      )
                )
                    THROW 56605,
                        N'Dịch vụ không tồn tại hoặc không hoạt động.', 1;

                IF @AreaId IS NOT NULL
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.KhuVuc WITH (UPDLOCK, HOLDLOCK)
                       WHERE MaKhuVuc = @AreaId
                         AND (
                             @IsActive = 0
                             OR DangHoatDong = 1
                         )
                   )
                    THROW 56605,
                        N'Khu vực không tồn tại hoặc không hoạt động.', 1;

                IF @RuleId IS NOT NULL
                BEGIN
                    SELECT @OldJson = (
                        SELECT
                            MaQuyTacTinhPhi AS id,
                            MaLoaiDichVu AS serviceId,
                            MaKhuVuc AS areaId,
                            KhoangCachTuKm AS distanceFromKm,
                            KhoangCachDenKm AS distanceToKm,
                            KhoiLuongTuKg AS weightFromKg,
                            KhoiLuongDenKg AS weightToKg,
                            PhiCoBan AS baseFee,
                            PhiMoiKm AS feePerKm,
                            PhiMoiKg AS feePerKg,
                            HieuLucTu AS effectiveFrom,
                            HieuLucDen AS effectiveTo,
                            DangHoatDong AS isActive
                        FROM dbo.QuyTacTinhPhi WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaQuyTacTinhPhi = @RuleId
                        FOR JSON PATH,
                            INCLUDE_NULL_VALUES,
                            WITHOUT_ARRAY_WRAPPER
                    );

                    IF NULLIF(@OldJson, N'') IS NULL
                        THROW 56603,
                            N'Không tìm thấy quy tắc tính phí.', 1;
                END;

                -- Khóa phạm vi kiểm tra để tránh hai yêu cầu
                -- cùng tạo quy tắc đang hoạt động bị chồng lấn.
                IF @IsActive = 1
                   AND EXISTS (
                       SELECT 1
                       FROM dbo.QuyTacTinhPhi q WITH (UPDLOCK, HOLDLOCK)
                       WHERE (
                           @RuleId IS NULL
                           OR q.MaQuyTacTinhPhi <> @RuleId
                       )
                         AND q.MaLoaiDichVu = @ServiceId
                         AND ISNULL(q.MaKhuVuc, -1)
                             = ISNULL(@AreaId, -1)
                         AND q.DangHoatDong = 1

                         AND q.HieuLucTu < ISNULL(
                             @EffectiveTo,
                             CONVERT(
                                 DATETIME2(0),
                                 '9999-12-31T23:59:59'
                             )
                         )
                         AND @EffectiveFrom < ISNULL(
                             q.HieuLucDen,
                             CONVERT(
                                 DATETIME2(0),
                                 '9999-12-31T23:59:59'
                             )
                         )

                         AND ISNULL(q.KhoangCachTuKm, 0)
                             <= ISNULL(@DistanceToKm, 999999999)
                         AND ISNULL(@DistanceFromKm, 0)
                             <= ISNULL(
                                 q.KhoangCachDenKm, 999999999
                             )

                         AND ISNULL(q.KhoiLuongTuKg, 0)
                             <= ISNULL(@WeightToKg, 999999999)
                         AND ISNULL(@WeightFromKg, 0)
                             <= ISNULL(
                                 q.KhoiLuongDenKg, 999999999
                             )
                   )
                    THROW 56604,
                        N'Quy tắc bị chồng lấn với quy tắc đang hoạt động.', 1;

                IF @RuleId IS NULL
                BEGIN
                    INSERT INTO dbo.QuyTacTinhPhi (
                        MaLoaiDichVu,
                        MaKhuVuc,
                        KhoangCachTuKm,
                        KhoangCachDenKm,
                        KhoiLuongTuKg,
                        KhoiLuongDenKg,
                        PhiCoBan,
                        PhiMoiKm,
                        PhiMoiKg,
                        HieuLucTu,
                        HieuLucDen,
                        DangHoatDong
                    )
                    VALUES (
                        @ServiceId,
                        @AreaId,
                        @DistanceFromKm,
                        @DistanceToKm,
                        @WeightFromKg,
                        @WeightToKg,
                        @BaseFee,
                        @FeePerKm,
                        @FeePerKg,
                        @EffectiveFrom,
                        @EffectiveTo,
                        @IsActive
                    );

                    SET @RuleId =
                        CONVERT(BIGINT, SCOPE_IDENTITY());
                END
                ELSE
                BEGIN
                    UPDATE dbo.QuyTacTinhPhi
                    SET MaLoaiDichVu = @ServiceId,
                        MaKhuVuc = @AreaId,
                        KhoangCachTuKm = @DistanceFromKm,
                        KhoangCachDenKm = @DistanceToKm,
                        KhoiLuongTuKg = @WeightFromKg,
                        KhoiLuongDenKg = @WeightToKg,
                        PhiCoBan = @BaseFee,
                        PhiMoiKm = @FeePerKm,
                        PhiMoiKg = @FeePerKg,
                        HieuLucTu = @EffectiveFrom,
                        HieuLucDen = @EffectiveTo,
                        DangHoatDong = @IsActive
                    WHERE MaQuyTacTinhPhi = @RuleId;
                END;

                SELECT @Result = (
                    SELECT
                        MaQuyTacTinhPhi AS id,
                        MaLoaiDichVu AS serviceId,
                        MaKhuVuc AS areaId,
                        KhoangCachTuKm AS distanceFromKm,
                        KhoangCachDenKm AS distanceToKm,
                        KhoiLuongTuKg AS weightFromKg,
                        KhoiLuongDenKg AS weightToKg,
                        PhiCoBan AS baseFee,
                        PhiMoiKm AS feePerKm,
                        PhiMoiKg AS feePerKg,
                        HieuLucTu AS effectiveFrom,
                        HieuLucDen AS effectiveTo,
                        DangHoatDong AS isActive
                    FROM dbo.QuyTacTinhPhi
                    WHERE MaQuyTacTinhPhi = @RuleId
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
                    CASE
                        WHEN @Id IS NULL THEN 'CREATE_FEE_RULE'
                        ELSE 'UPDATE_FEE_RULE'
                    END,
                    'QuyTacTinhPhi',
                    CONVERT(VARCHAR(100), @RuleId),
                    @OldJson,
                    @Result
                );

                COMMIT;
                SELECT @Result;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK;
                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = actorId;

        command.Parameters.Add(
            "@Id", SqlDbType.BigInt).Value =
            (object?)request.Id ?? DBNull.Value;

        command.Parameters.Add(
            "@ServiceId", SqlDbType.Int).Value = request.ServiceId;

        command.Parameters.Add(
            "@AreaId", SqlDbType.Int).Value =
            (object?)request.AreaId ?? DBNull.Value;

        AddDecimal(
            command, "@DistanceFromKm",
            10, 2, request.DistanceFromKm);

        AddDecimal(
            command, "@DistanceToKm",
            10, 2, request.DistanceToKm);

        AddDecimal(
            command, "@WeightFromKg",
            10, 2, request.WeightFromKg);

        AddDecimal(
            command, "@WeightToKg",
            10, 2, request.WeightToKg);

        AddDecimal(
            command, "@BaseFee",
            18, 2, request.BaseFee);

        AddDecimal(
            command, "@FeePerKm",
            18, 2, request.FeePerKm);

        AddDecimal(
            command, "@FeePerKg",
            18, 2, request.FeePerKg);

        var fromParameter = command.Parameters.Add(
            "@EffectiveFrom", SqlDbType.DateTime2);

        fromParameter.Scale = 0;
        fromParameter.Value = effectiveFrom;

        var toParameter = command.Parameters.Add(
            "@EffectiveTo", SqlDbType.DateTime2);

        toParameter.Scale = 0;
        toParameter.Value =
            (object?)effectiveTo ?? DBNull.Value;

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
        catch (SqlException ex) when (ex.Number == 56601)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56602)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56603)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex)
            when (ex.Number is 56604 or 51047)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56605)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 547)
        {
            return Conflict(new
            {
                message =
                    "Dữ liệu không thỏa mãn ràng buộc của database."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Bảng giá đang được cập nhật đồng thời. Hãy thử lại."
            });
        }
    }

    private static void AddDecimal(
        SqlCommand command,
        string name,
        byte precision,
        byte scale,
        decimal? value)
    {
        var parameter = command.Parameters.Add(
            name, SqlDbType.Decimal);

        parameter.Precision = precision;
        parameter.Scale = scale;
        parameter.Value = (object?)value ?? DBNull.Value;
    }

    private static DateTime ToUtcSeconds(DateTimeOffset value)
    {
        var utc = value.UtcDateTime;

        return new DateTime(
            utc.Ticks - utc.Ticks % TimeSpan.TicksPerSecond,
            DateTimeKind.Utc);
    }
}