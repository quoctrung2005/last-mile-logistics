using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CreateOrderRequest
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

    [StringLength(1000)]
    public string? Notes { get; set; }

    [Required, MinLength(1), MaxLength(100)]
    public List<CreateOrderItemRequest> Items { get; set; } = [];
}

public class CreateOrderItemRequest
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

    [Range(typeof(decimal), "0", "1000000000000",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal Value { get; set; }

    public bool Fragile { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }
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

        var totalWeight = request.Items.Sum(
            item => item.Quantity * item.UnitWeightKg);

        if (totalWeight > 999999999.999m)
            return BadRequest(new
            {
                message = "Tổng khối lượng vượt giới hạn database."
            });

        // Mã do backend sinh, không lấy từ người dùng.
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
                          JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                          WHERE vq.MaVaiTro = tk.MaVaiTro
                            AND q.KyHieuQuyen = 'DONHANG_TAO'
                      )
                )
                    THROW 52001, N'Không có quyền tạo đơn tại bưu cục này.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.BuuCuc WITH (HOLDLOCK)
                    WHERE MaBuuCuc = @BranchId AND DangHoatDong = 1
                )
                    THROW 52002, N'Bưu cục không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.LoaiDichVu WITH (HOLDLOCK)
                    WHERE MaLoaiDichVu = @ServiceId AND DangHoatDong = 1
                )
                    THROW 52003, N'Dịch vụ không tồn tại hoặc đã ngừng hoạt động.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.KhachHang WITH (HOLDLOCK)
                    WHERE MaKhachHang = @SenderId AND DangHoatDong = 1
                ) OR NOT EXISTS (
                    SELECT 1
                    FROM dbo.KhachHang WITH (HOLDLOCK)
                    WHERE MaKhachHang = @ReceiverId AND DangHoatDong = 1
                )
                    THROW 52004, N'Người gửi hoặc người nhận không hợp lệ.', 1;

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
                    THROW 52005, N'Địa chỉ không hoạt động hoặc không thuộc đúng khách hàng.', 1;

                DECLARE @NewStatus SMALLINT;

                SELECT @NewStatus = MaTrangThaiDonHang
                FROM dbo.TrangThaiDonHang
                WHERE KyHieuTrangThai = 'NEW';

                IF @NewStatus IS NULL
                    THROW 52006, N'Chưa có danh mục trạng thái NEW.', 1;

                EXEC sys.sp_set_session_context
                    @key = N'NguonCapNhat', @value = N'API';

                INSERT INTO dbo.DonHang (
                    KyHieuDonHang, MaVanDon, MaBuuCuc,
                    MaNguoiGui, MaNguoiNhan, MaLoaiDichVu,
                    MaTrangThaiHienTai, MucDoUuTien,
                    GiaTriKhaiBao, TienCOD, PhiVanChuyen,
                    GhiChuDacBiet,
                    MaTaiKhoanTao, MaTaiKhoanCapNhatCuoi
                )
                VALUES (
                    @OrderCode, @TrackingNumber, @BranchId,
                    @SenderId, @ReceiverId, @ServiceId,
                    @NewStatus, @Priority,
                    @DeclaredValue, @CodAmount, 0,
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
                    COALESCE(NULLIF(LTRIM(RTRIM(dc.TenNguoiLienHe)), ''),
                             kh.HoTen),
                    COALESCE(NULLIF(LTRIM(RTRIM(dc.SoDienThoaiLienHe)), ''),
                             kh.SoDienThoai),
                    dc.DiaChi, dc.MaKhuVuc, dc.ViDo, dc.KinhDo
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
                    MaDonHang, TenHang, LoaiHang, SoLuong,
                    KhoiLuongDonViKg, GiaTriHang, HangDeVo, GhiChu
                )
                SELECT
                    @OrderId, LTRIM(RTRIM(name)), type, quantity,
                    unitWeightKg, value, fragile, notes
                FROM OPENJSON(@Payload, '$.items')
                WITH (
                    name NVARCHAR(200),
                    type NVARCHAR(100),
                    quantity INT,
                    unitWeightKg DECIMAL(10,3),
                    value DECIMAL(18,2),
                    fragile BIT,
                    notes NVARCHAR(500)
                );

                EXEC sys.sp_set_session_context
                    @key = N'NguonCapNhat', @value = NULL;

                COMMIT;

                SELECT @OrderId;
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

            var orderId = Convert.ToInt64(
                await command.ExecuteScalarAsync());

            return Created($"/api/v1/orders/{orderId}", new
            {
                id = orderId,
                orderCode,
                trackingNumber,
                status = "NEW",
                weightKg = totalWeight,
                shippingFee = 0,
                message = "Tạo đơn thành công."
            });
        }
        catch (SqlException ex) when (ex.Number == 52001)
        {
            return Forbid();
        }
        catch (SqlException ex)
            when (ex.Number >= 52002 && ex.Number <= 52005)
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
            _logger.LogError(ex, "Không tạo được đơn hàng.");

            return StatusCode(500, new
            {
                message = "Không tạo được đơn hàng. Xem log trong Visual Studio."
            });
        }
    }
}