using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using LastMile.Api.Services;

namespace LastMile.Api.Controllers;

public class CreateOrderRequest : IValidatableObject
{
    [Range(1, int.MaxValue)]
    public int BranchId { get; set; }

    [Range(1, long.MaxValue)]
    public long SenderId { get; set; }

    [Range(1, long.MaxValue)]
    public long ReceiverId { get; set; }

    [Range(1, long.MaxValue)]
    public long PickupAddressId { get; set; }

    [Range(1, long.MaxValue)]
    public long DeliveryAddressId { get; set; }

    [Range(1, int.MaxValue)]
    public int ServiceId { get; set; }

    [Range(1, 5)]
    public int Priority { get; set; } = 3;

    [Range(typeof(decimal), "0", "1000000000000",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal CodAmount { get; set; }

    [Range(typeof(decimal), "0", "1000000000000",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal DeclaredValue { get; set; }

    // Thời điểm khách mong muốn giao, không phải đầu khung giờ VRP.
    [JsonConverter(typeof(OrderDateTimeOffsetConverter))]
    public DateTimeOffset? RequestedDeliveryAt { get; set; }

    // Hạn đến điểm giao; VRP hiện đọc từ ThoiGianDuKienGiao.
    [Required(ErrorMessage = "Phải nhập hạn giao hàng.")]
    [JsonConverter(typeof(OrderDateTimeOffsetConverter))]
    public DateTimeOffset? ExpectedDeliveryAt { get; set; }

    [StringLength(1000)]
    public string? Notes { get; set; }

    [Required, MinLength(1), MaxLength(100)]
    public List<CreateOrderItemRequest> Items { get; set; } = [];

    public IEnumerable<ValidationResult> Validate(
        ValidationContext validationContext)
    {
        if (RequestedDeliveryAt.HasValue
            && ExpectedDeliveryAt.HasValue
            && ExpectedDeliveryAt.Value < RequestedDeliveryAt.Value)
        {
            yield return new ValidationResult(
                "Hạn giao không được trước thời điểm khách yêu cầu giao.",
                [nameof(ExpectedDeliveryAt)]);
        }
    }
}

public class CreateOrderItemRequest : IValidatableObject
{
    [Required, StringLength(200)]
    public string Name { get; set; } = "";

    [StringLength(100)]
    public string? Type { get; set; }

    [Range(1, 100000)]
    public int Quantity { get; set; }

    [Range(typeof(decimal), "0.001", "1000000",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal UnitWeightKg { get; set; }

    // Kích thước đóng gói của một đơn vị hàng, tính bằng cm.
    [Required(ErrorMessage = "Phải nhập chiều dài hàng hóa.")]
    [Range(typeof(decimal), "0.01", "99999999.99",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true,
        ErrorMessage = "Chiều dài phải từ 0,01 đến 99.999.999,99 cm.")]
    public decimal? LengthCm { get; set; }

    [Required(ErrorMessage = "Phải nhập chiều rộng hàng hóa.")]
    [Range(typeof(decimal), "0.01", "99999999.99",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true,
        ErrorMessage = "Chiều rộng phải từ 0,01 đến 99.999.999,99 cm.")]
    public decimal? WidthCm { get; set; }

    [Required(ErrorMessage = "Phải nhập chiều cao hàng hóa.")]
    [Range(typeof(decimal), "0.01", "99999999.99",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true,
        ErrorMessage = "Chiều cao phải từ 0,01 đến 99.999.999,99 cm.")]
    public decimal? HeightCm { get; set; }

    [Range(typeof(decimal), "0", "1000000000000",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal Value { get; set; }

    public bool Fragile { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }

    public IEnumerable<ValidationResult> Validate(
        ValidationContext validationContext)
    {
        (string Field, decimal? Value)[] dimensions =
        [
            (nameof(LengthCm), LengthCm),
            (nameof(WidthCm), WidthCm),
            (nameof(HeightCm), HeightCm)
        ];

        foreach (var (field, value) in dimensions)
        {
            if (value.HasValue
                && decimal.Round(value.Value, 2) != value.Value)
            {
                yield return new ValidationResult(
                    "Kích thước hàng chỉ được có tối đa 2 số lẻ.",
                    [field]);
            }
        }
    }
}

// Yêu cầu ngày giờ ISO 8601 có múi giờ rõ ràng:
// 2026-10-20T17:00:00+07:00 hoặc 2026-10-20T10:00:00Z.
public sealed class OrderDateTimeOffsetConverter
    : JsonConverter<DateTimeOffset?>
{
    public override DateTimeOffset? Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null)
        {
            return null;
        }

        if (reader.TokenType != JsonTokenType.String)
        {
            throw new JsonException(
                "Ngày giờ phải là chuỗi ISO 8601 có múi giờ.");
        }

        var raw = reader.GetString();

        if (string.IsNullOrWhiteSpace(raw))
        {
            throw new JsonException(
                "Ngày giờ không được là chuỗi rỗng; hãy gửi null nếu bỏ trống.");
        }

        var hasTimeZone =
            raw.EndsWith("Z", StringComparison.Ordinal)
            || (
                raw.Length >= 6
                && (raw[^6] == '+' || raw[^6] == '-')
                && raw[^3] == ':'
            );

        if (!hasTimeZone
            || !reader.TryGetDateTimeOffset(out var value))
        {
            throw new JsonException(
                "Ngày giờ không hợp lệ. Hãy gửi ISO 8601 "
                + "có +07:00 hoặc Z, ví dụ 2026-10-20T17:00:00+07:00.");
        }

        return value;
    }

    public override void Write(
        Utf8JsonWriter writer,
        DateTimeOffset? value,
        JsonSerializerOptions options)
    {
        if (value.HasValue)
        {
            writer.WriteStringValue(value.Value);
        }
        else
        {
            writer.WriteNullValue();
        }
    }
}

[Authorize]
[ApiController]
[Route("api/v1/orders")]
public class OrderCreateController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<OrderCreateController> _logger;

    public OrderCreateController(
        IConfiguration configuration,
        ILogger<OrderCreateController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPost]
    public async Task<IActionResult> Create(CreateOrderRequest request)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        if (request.Items.Any(item =>
            item is null
            || string.IsNullOrWhiteSpace(item.Name)
            || decimal.Round(item.UnitWeightKg, 3) != item.UnitWeightKg
            || decimal.Round(item.Value, 2) != item.Value))
        {
            return BadRequest(new
            {
                message = "Tên hàng không được trống; khối lượng tối đa "
                    + "3 số lẻ; giá trị hàng tối đa 2 số lẻ."
            });
        }

        if (decimal.Round(request.CodAmount, 2) != request.CodAmount
            || decimal.Round(request.DeclaredValue, 2)
                != request.DeclaredValue)
        {
            return BadRequest(new
            {
                message = "Số tiền chỉ được có tối đa 2 số lẻ."
            });
        }

        if (!request.ExpectedDeliveryAt.HasValue)
        {
            return BadRequest(new
            {
                message = "Phải nhập hạn giao hàng."
            });
        }

        DateTime? requestedDeliveryUtc =
            request.RequestedDeliveryAt.HasValue
                ? ToUtcSeconds(request.RequestedDeliveryAt.Value)
                : null;

        var expectedDeliveryUtc =
            ToUtcSeconds(request.ExpectedDeliveryAt.Value);

        var nowUtc = DateTime.UtcNow;

        if (expectedDeliveryUtc <= nowUtc)
        {
            return BadRequest(new
            {
                message = "Hạn giao hàng phải nằm trong tương lai."
            });
        }

        if (requestedDeliveryUtc.HasValue
            && requestedDeliveryUtc.Value <= nowUtc)
        {
            return BadRequest(new
            {
                message = "Thời điểm khách yêu cầu giao phải nằm trong tương lai."
            });
        }

        if (requestedDeliveryUtc.HasValue
            && expectedDeliveryUtc < requestedDeliveryUtc.Value)
        {
            return BadRequest(new
            {
                message = "Hạn giao không được trước thời điểm khách yêu cầu giao."
            });
        }

        var totalWeight = request.Items.Sum(
            item => item.Quantity * item.UnitWeightKg);

        if (totalWeight > 999999999.999m)
        {
            return BadRequest(new
            {
                message = "Tổng khối lượng vượt giới hạn database."
            });
        }

        var uniqueCode = Guid.NewGuid().ToString("N").ToUpperInvariant();
        var orderCode = $"DH-{uniqueCode}";
        var trackingNumber = $"LM-{uniqueCode}";

        var payload = JsonSerializer.Serialize(
            request,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @BranchId INT,
                    @SenderId BIGINT,
                    @ReceiverId BIGINT,
                    @PickupAddressId BIGINT,
                    @DeliveryAddressId BIGINT,
                    @ServiceId INT,
                    @Priority INT,
                    @CodAmount DECIMAL(18,2),
                    @DeclaredValue DECIMAL(18,2),
                    @Notes NVARCHAR(1000);

                SELECT
                    @BranchId = branchId,
                    @SenderId = senderId,
                    @ReceiverId = receiverId,
                    @PickupAddressId = pickupAddressId,
                    @DeliveryAddressId = deliveryAddressId,
                    @ServiceId = serviceId,
                    @Priority = priority,
                    @CodAmount = codAmount,
                    @DeclaredValue = declaredValue,
                    @Notes = notes
                FROM OPENJSON(@Payload)
                WITH (
                    branchId INT,
                    senderId BIGINT,
                    receiverId BIGINT,
                    pickupAddressId BIGINT,
                    deliveryAddressId BIGINT,
                    serviceId INT,
                    priority INT,
                    codAmount DECIMAL(18,2),
                    declaredValue DECIMAL(18,2),
                    notes NVARCHAR(1000)
                );

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                    JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                        ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.MaTaiKhoan = @AccountId
                      AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                      AND vt.DangHoatDong = 1
                      AND (
                          tk.KhoaDenLuc IS NULL
                          OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                      )
                      AND (
                          vt.KyHieuVaiTro = 'ADMIN'
                          OR tk.MaBuuCuc = @BranchId
                      )
                      AND EXISTS (
                          SELECT 1
                          FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                          JOIN dbo.Quyen q
                              ON q.MaQuyen = vq.MaQuyen
                          WHERE vq.MaVaiTro = tk.MaVaiTro
                            AND q.KyHieuQuyen = 'DONHANG_TAO'
                      )
                )
                    THROW 52001,
                        N'Không có quyền tạo đơn tại bưu cục này.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.BuuCuc WITH (HOLDLOCK)
                    WHERE MaBuuCuc = @BranchId
                      AND DangHoatDong = 1
                )
                    THROW 52002,
                        N'Bưu cục không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.LoaiDichVu WITH (HOLDLOCK)
                    WHERE MaLoaiDichVu = @ServiceId
                      AND DangHoatDong = 1
                )
                    THROW 52003,
                        N'Dịch vụ không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.KhachHang WITH (HOLDLOCK)
                    WHERE MaKhachHang = @SenderId
                      AND DangHoatDong = 1
                ) OR NOT EXISTS (
                    SELECT 1
                    FROM dbo.KhachHang WITH (HOLDLOCK)
                    WHERE MaKhachHang = @ReceiverId
                      AND DangHoatDong = 1
                )
                    THROW 52004,
                        N'Người gửi hoặc người nhận không hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.DiaChiKhachHang WITH (HOLDLOCK)
                    WHERE MaDiaChiKhachHang = @PickupAddressId
                      AND MaKhachHang = @SenderId
                      AND DangHoatDong = 1
                ) OR NOT EXISTS (
                    SELECT 1
                    FROM dbo.DiaChiKhachHang WITH (HOLDLOCK)
                    WHERE MaDiaChiKhachHang = @DeliveryAddressId
                      AND MaKhachHang = @ReceiverId
                      AND DangHoatDong = 1
                )
                    THROW 52005,
                        N'Địa chỉ không hoạt động hoặc không thuộc đúng khách hàng.', 1;

                -- Kiểm tra lại sau khi đã chờ các khóa dữ liệu.
                DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

                IF @ExpectedDeliveryAt IS NULL
                   OR @ExpectedDeliveryAt <= @Now
                    THROW 52007,
                        N'Hạn giao hàng phải nằm trong tương lai.', 1;

                IF @RequestedDeliveryAt IS NOT NULL
                   AND @RequestedDeliveryAt <= @Now
                    THROW 52007,
                        N'Thời điểm khách yêu cầu giao phải nằm trong tương lai.', 1;

                IF @RequestedDeliveryAt IS NOT NULL
                   AND @ExpectedDeliveryAt < @RequestedDeliveryAt
                    THROW 52007,
                        N'Hạn giao không được trước thời điểm khách yêu cầu giao.', 1;

                DECLARE @NewStatus SMALLINT;

                SELECT @NewStatus = MaTrangThaiDonHang
                FROM dbo.TrangThaiDonHang
                WHERE KyHieuTrangThai = 'NEW';

                IF @NewStatus IS NULL
                    THROW 52006,
                        N'Chưa có danh mục trạng thái NEW.', 1;

                EXEC sys.sp_set_session_context
                    @key = N'NguonCapNhat', @value = N'API';

                INSERT INTO dbo.DonHang (
                    KyHieuDonHang, MaVanDon, MaBuuCuc,
                    MaNguoiGui, MaNguoiNhan, MaLoaiDichVu,
                    MaTrangThaiHienTai, MucDoUuTien,
                    GiaTriKhaiBao, TienCOD, PhiVanChuyen,
                    ThoiGianYeuCauGiao, ThoiGianDuKienGiao,
                    GhiChuDacBiet,
                    MaTaiKhoanTao, MaTaiKhoanCapNhatCuoi
                )
                VALUES (
                    @OrderCode, @TrackingNumber, @BranchId,
                    @SenderId, @ReceiverId, @ServiceId,
                    @NewStatus, @Priority,
                    @DeclaredValue, @CodAmount, 0,
                    @RequestedDeliveryAt, @ExpectedDeliveryAt,
                    @Notes,
                    @AccountId, @AccountId
                );

                DECLARE @OrderId BIGINT =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.DiemGiaoNhan (
                    MaDonHang, LoaiDiem,
                    TenNguoiLienHe, SoDienThoaiLienHe,
                    DiaChi, MaKhuVuc, ViDo, KinhDo
                )
                SELECT
                    @OrderId,
                    p.LoaiDiem,
                    COALESCE(
                        NULLIF(LTRIM(RTRIM(dc.TenNguoiLienHe)), ''),
                        kh.HoTen
                    ),
                    COALESCE(
                        NULLIF(LTRIM(RTRIM(dc.SoDienThoaiLienHe)), ''),
                        kh.SoDienThoai
                    ),
                    dc.DiaChi,
                    dc.MaKhuVuc,
                    dc.ViDo,
                    dc.KinhDo
                FROM (
                    VALUES
                        (@PickupAddressId, 'PICKUP'),
                        (@DeliveryAddressId, 'DELIVERY')
                ) p(MaDiaChi, LoaiDiem)
                JOIN dbo.DiaChiKhachHang dc
                    ON dc.MaDiaChiKhachHang = p.MaDiaChi
                JOIN dbo.KhachHang kh
                    ON kh.MaKhachHang = dc.MaKhachHang;

                INSERT INTO dbo.ChiTietDonHang (
                    MaDonHang,
                    TenHang,
                    LoaiHang,
                    SoLuong,
                    KhoiLuongDonViKg,
                    ChieuDaiCm,
                    ChieuRongCm,
                    ChieuCaoCm,
                    GiaTriHang,
                    HangDeVo,
                    GhiChu
                )
                SELECT
                    @OrderId,
                    LTRIM(RTRIM(name)),
                    type,
                    quantity,
                    unitWeightKg,
                    lengthCm,
                    widthCm,
                    heightCm,
                    value,
                    fragile,
                    notes
                FROM OPENJSON(@Payload, '$.items')
                WITH (
                    name NVARCHAR(200),
                    type NVARCHAR(100),
                    quantity INT,
                    unitWeightKg DECIMAL(10,3),
                    lengthCm DECIMAL(10,2),
                    widthCm DECIMAL(10,2),
                    heightCm DECIMAL(10,2),
                    value DECIMAL(18,2),
                    fragile BIT,
                    notes NVARCHAR(500)
                );

                EXEC sys.sp_set_session_context
                    @key = N'NguonCapNhat', @value = NULL;

                COMMIT;

                SELECT @OrderId AS OrderId;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0
                    ROLLBACK;

                EXEC sys.sp_set_session_context
                    @key = N'NguonCapNhat', @value = NULL;

                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
        var writeAttempted = false;

        try
        {
            await connection.OpenAsync();

            await using var command = new SqlCommand(sql, connection);

            command.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value = accountId;

            command.Parameters.Add(
                "@Payload", SqlDbType.NVarChar, -1).Value = payload;

            command.Parameters.Add(
                "@OrderCode", SqlDbType.VarChar, 40).Value = orderCode;

            command.Parameters.Add(
                "@TrackingNumber", SqlDbType.VarChar, 50
            ).Value = trackingNumber;

            var requestedParameter = command.Parameters.Add(
                "@RequestedDeliveryAt", SqlDbType.DateTime2);

            requestedParameter.Scale = 0;
            requestedParameter.Value =
                (object?)requestedDeliveryUtc ?? DBNull.Value;

            var expectedParameter = command.Parameters.Add(
                "@ExpectedDeliveryAt", SqlDbType.DateTime2);

            expectedParameter.Scale = 0;
            expectedParameter.Value = expectedDeliveryUtc;

            writeAttempted = true;
            await using var reader = await command.ExecuteReaderAsync();
            var orderId = await SqlResult.ReadSingleAsync(reader, ["OrderId"], row => row.Id("OrderId"));

            return Created($"/api/v1/orders/{orderId}", new
            {
                id = orderId,
                orderCode,
                trackingNumber,
                status = "NEW",
                weightKg = totalWeight,
                shippingFee = 0,
                requestedDeliveryAt = requestedDeliveryUtc,
                expectedDeliveryAt = expectedDeliveryUtc,
                message = "Tạo đơn thành công."
            });
        }
        catch (SqlException ex) when (ex.Number == 52001)
        {
            return Forbid();
        }
        catch (SqlException ex)
            when ((ex.Number >= 52002 && ex.Number <= 52005)
                || ex.Number == 52007)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (SqlException ex)
            when (ex.Number == 2601 || ex.Number == 2627)
        {
            return Conflict(new
            {
                message = "Mã đơn hoặc mã vận đơn bị trùng."
            });
        }
        catch (SqlException ex)
        {
            return SqlResult.Failure(_logger, "POST /api/v1/orders", orderCode, SqlResult.ErrorReason(ex), writeAttempted);
        }
        catch (SqlResultContractException ex)
        {
            return SqlResult.Failure(_logger, "POST /api/v1/orders", orderCode, ex.Message, writeAttempted);
        }
    }

    private static DateTime ToUtcSeconds(DateTimeOffset value)
    {
        var utc = value.UtcDateTime;

        // Database lưu DATETIME2(0), thống nhất độ chính xác tới giây.
        return utc.AddTicks(
            -(utc.Ticks % TimeSpan.TicksPerSecond));
    }
}
