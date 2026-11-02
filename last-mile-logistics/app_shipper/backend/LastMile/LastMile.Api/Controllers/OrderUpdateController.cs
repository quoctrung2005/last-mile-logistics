using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

// Dùng lại các trường và kiểm tra dữ liệu của CreateOrderRequest.
public class UpdateOrderRequest : CreateOrderRequest
{
    [Required, StringLength(16)]
    public string ExpectedVersion { get; set; } = "";
}

[Authorize]
[ApiController]
[Route("api/v1/orders")]
public class OrderUpdateController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<OrderUpdateController> _logger;

    public OrderUpdateController(
        IConfiguration configuration,
        ILogger<OrderUpdateController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPut("{id:long}")]
    public async Task<IActionResult> Update(
        long id,
        UpdateOrderRequest request)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã đơn phải lớn hơn 0." });

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        byte[] expectedVersion;

        try
        {
            expectedVersion =
                Convert.FromBase64String(request.ExpectedVersion);
        }
        catch (FormatException)
        {
            return BadRequest(new
            {
                message = "expectedVersion phải là chuỗi lấy từ API chi tiết."
            });
        }

        if (expectedVersion.Length != 8)
            return BadRequest(new
            {
                message = "Phiên bản dữ liệu không hợp lệ."
            });

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
                message = "Số tiền tối đa 2 số lẻ."
            });
        }

        var totalWeight = request.Items.Sum(
            item => item.Quantity * item.UnitWeightKg);

        if (totalWeight > 999999999.999m)
            return BadRequest(new
            {
                message = "Tổng khối lượng vượt giới hạn database."
            });

        var payload = JsonSerializer.Serialize(
            request,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Allowed BIT = 0,
                    @IsAdmin BIT = 0,
                    @AccountBranchId INT;

                SELECT
                    @Allowed = 1,
                    @IsAdmin = CASE
                        WHEN vt.KyHieuVaiTro = 'ADMIN' THEN 1 ELSE 0 END,
                    @AccountBranchId = tk.MaBuuCuc
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
                  AND EXISTS (
                      SELECT 1
                      FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                      JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                      WHERE vq.MaVaiTro = tk.MaVaiTro
                        AND q.KyHieuQuyen = 'DONHANG_CAPNHAT'
                  );

                IF @Allowed = 0
                   OR (@IsAdmin = 0 AND @AccountBranchId IS NULL)
                    THROW 52401, N'Không có quyền sửa đơn.', 1;

                DECLARE
                    @Status VARCHAR(40),
                    @CurrentVersion BINARY(8),
                    @OldData NVARCHAR(MAX);

                SELECT
                    @Status = tt.KyHieuTrangThai,
                    @CurrentVersion = d.PhienBan
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (@IsAdmin = 1 OR d.MaBuuCuc = @AccountBranchId);

                IF @Status IS NULL
                    THROW 52402, N'Không tìm thấy đơn trong phạm vi được xem.', 1;

                IF @Status <> 'NEW'
                    THROW 52403, N'Chỉ được sửa đơn ở trạng thái NEW.', 1;

                IF @CurrentVersion <> @ExpectedVersion
                    THROW 52403, N'Đơn đã thay đổi. Hãy tải lại chi tiết trước khi sửa.', 1;

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

                IF @IsAdmin = 0 AND @BranchId <> @AccountBranchId
                    THROW 52401, N'Không được chuyển đơn sang bưu cục khác.', 1;

                IF NOT EXISTS (
                    SELECT 1 FROM dbo.BuuCuc WITH (HOLDLOCK)
                    WHERE MaBuuCuc = @BranchId AND DangHoatDong = 1
                ) OR NOT EXISTS (
                    SELECT 1 FROM dbo.LoaiDichVu WITH (HOLDLOCK)
                    WHERE MaLoaiDichVu = @ServiceId AND DangHoatDong = 1
                )
                    THROW 52404, N'Bưu cục hoặc dịch vụ không hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1 FROM dbo.KhachHang WITH (HOLDLOCK)
                    WHERE MaKhachHang = @SenderId AND DangHoatDong = 1
                ) OR NOT EXISTS (
                    SELECT 1 FROM dbo.KhachHang WITH (HOLDLOCK)
                    WHERE MaKhachHang = @ReceiverId AND DangHoatDong = 1
                )
                    THROW 52404, N'Người gửi hoặc người nhận không hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1 FROM dbo.DiaChiKhachHang WITH (HOLDLOCK)
                    WHERE MaDiaChiKhachHang = @PickupAddressId
                      AND MaKhachHang = @SenderId
                      AND DangHoatDong = 1
                ) OR NOT EXISTS (
                    SELECT 1 FROM dbo.DiaChiKhachHang WITH (HOLDLOCK)
                    WHERE MaDiaChiKhachHang = @DeliveryAddressId
                      AND MaKhachHang = @ReceiverId
                      AND DangHoatDong = 1
                )
                    THROW 52404, N'Địa chỉ không thuộc đúng khách hàng hoặc đã ngừng hoạt động.', 1;

                -- Không cho chuyển bưu cục nếu đơn đã gắn kho.
                IF EXISTS (
                    SELECT 1 FROM dbo.DonHang
                    WHERE MaDonHang = @OrderId
                      AND MaKhoHienTai IS NOT NULL
                      AND MaBuuCuc <> @BranchId
                )
                    THROW 52403, N'Đơn đã gắn kho, không được đổi bưu cục bằng API này.', 1;

                SET @OldData = (
                    SELECT
                        d.*,
                        JSON_QUERY((
                            SELECT ct.*
                            FROM dbo.ChiTietDonHang ct
                            WHERE ct.MaDonHang = d.MaDonHang
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        )) AS items,
                        JSON_QUERY((
                            SELECT
                                p.LoaiDiem,
                                p.TenNguoiLienHe,
                                p.SoDienThoaiLienHe,
                                p.DiaChi,
                                p.MaKhuVuc,
                                p.ViDo,
                                p.KinhDo
                            FROM dbo.DiemGiaoNhan p
                            WHERE p.MaDonHang = d.MaDonHang
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        )) AS deliveryPoints
                    FROM dbo.DonHang d
                    WHERE d.MaDonHang = @OrderId
                    FOR JSON PATH, INCLUDE_NULL_VALUES,
                             WITHOUT_ARRAY_WRAPPER
                );

                -- Phí SHIPPING cũ không còn phù hợp sau khi sửa.
                DELETE FROM dbo.KhoanPhiDonHang
                WHERE MaDonHang = @OrderId
                  AND LoaiKhoanPhi = 'SHIPPING';

                DECLARE @RemainingFee DECIMAL(18,2);

                SELECT @RemainingFee = COALESCE(SUM(SoTien), 0)
                FROM dbo.KhoanPhiDonHang WITH (HOLDLOCK)
                WHERE MaDonHang = @OrderId;

                IF @RemainingFee < 0
                    THROW 52403, N'Cần điều chỉnh khoản giảm giá trước khi sửa đơn.', 1;

                UPDATE dbo.DonHang
                SET MaBuuCuc = @BranchId,
                    MaNguoiGui = @SenderId,
                    MaNguoiNhan = @ReceiverId,
                    MaLoaiDichVu = @ServiceId,
                    MucDoUuTien = @Priority,
                    TienCOD = @CodAmount,
                    GiaTriKhaiBao = @DeclaredValue,
                    GhiChuDacBiet = @Notes,
                    PhiVanChuyen = @RemainingFee,
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = SYSUTCDATETIME()
                WHERE MaDonHang = @OrderId;

                DELETE FROM dbo.DiemGiaoNhan
                WHERE MaDonHang = @OrderId;

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

                DELETE FROM dbo.ChiTietDonHang
                WHERE MaDonHang = @OrderId;

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

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan, LoaiThaoTac, TenDoiTuong,
                    MaDoiTuong, DuLieuCuJson, DuLieuMoiJson
                )
                VALUES (
                    @AccountId, 'UPDATE_ORDER', 'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    @OldData, @Payload
                );

                DECLARE
                    @FinalVersion BINARY(8),
                    @FinalWeight DECIMAL(12,3);

                SELECT
                    @FinalVersion = PhienBan,
                    @FinalWeight = TongKhoiLuongKg
                FROM dbo.DonHang
                WHERE MaDonHang = @OrderId;

                COMMIT;

                SELECT
                    @FinalVersion AS Version,
                    @FinalWeight AS WeightKg,
                    @RemainingFee AS ShippingFee;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0
                    ROLLBACK;

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
                "@OrderId", SqlDbType.BigInt).Value = id;

            command.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value = accountId;

            command.Parameters.Add(
                "@ExpectedVersion", SqlDbType.Binary, 8
            ).Value = expectedVersion;

            command.Parameters.Add(
                "@Payload", SqlDbType.NVarChar, -1).Value = payload;

            await using var reader = await command.ExecuteReaderAsync();
            await reader.ReadAsync();

            return Ok(new
            {
                id,
                status = "NEW",
                version = Convert.ToBase64String(
                    (byte[])reader["Version"]),
                weightKg = Convert.ToDecimal(reader["WeightKg"]),
                shippingFee = Convert.ToDecimal(reader["ShippingFee"]),
                message = "Đã sửa đơn. Phí vận chuyển sẽ tính lại khi xác nhận."
            });
        }
        catch (SqlException ex) when (ex.Number == 52401)
        {
            return Forbid();
        }
        catch (SqlException ex) when (ex.Number == 52402)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52403)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52404)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (SqlException ex)
        {
            _logger.LogError(ex, "Không sửa được đơn {OrderId}.", id);

            return StatusCode(500, new
            {
                message = "Không sửa được đơn. Xem log Visual Studio."
            });
        }
    }
}