using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class ConfirmOrderRequest
{
    [Range(typeof(decimal), "0", "1000000",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal DistanceKm { get; set; }
}

[Authorize]
[ApiController]
[Route("api/v1/orders")]
public class OrderConfirmController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<OrderConfirmController> _logger;

    public OrderConfirmController(
        IConfiguration configuration,
        ILogger<OrderConfirmController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPost("{id:long}/confirm")]
    public async Task<IActionResult> Confirm(
        long id,
        ConfirmOrderRequest request)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã đơn phải lớn hơn 0." });

        if (decimal.Round(request.DistanceKm, 2) != request.DistanceKm)
            return BadRequest(new
            {
                message = "Khoảng cách tối đa 2 số lẻ."
            });

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @IsAdmin BIT = 0,
                    @AccountBranchId INT,
                    @Allowed BIT = 0;

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
                    THROW 52201, N'Không có quyền xác nhận đơn.', 1;

                DECLARE
                    @BranchId INT,
                    @ServiceId INT,
                    @Status VARCHAR(40),
                    @WeightKg DECIMAL(12,3),
                    @OldFee DECIMAL(18,2);

                SELECT
                    @BranchId = d.MaBuuCuc,
                    @ServiceId = d.MaLoaiDichVu,
                    @Status = tt.KyHieuTrangThai,
                    @WeightKg = d.TongKhoiLuongKg,
                    @OldFee = d.PhiVanChuyen
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (@IsAdmin = 1 OR d.MaBuuCuc = @AccountBranchId);

                IF @Status IS NULL
                    THROW 52202, N'Không tìm thấy đơn trong phạm vi được xem.', 1;

                IF @Status <> 'NEW'
                    THROW 52203, N'Chỉ được xác nhận đơn ở trạng thái NEW.', 1;

                IF @WeightKg <= 0
                    THROW 52205, N'Đơn phải có hàng hóa với khối lượng lớn hơn 0.', 1;

                IF NOT EXISTS (
                    SELECT 1 FROM dbo.BuuCuc WITH (HOLDLOCK)
                    WHERE MaBuuCuc = @BranchId AND DangHoatDong = 1
                ) OR NOT EXISTS (
                    SELECT 1 FROM dbo.LoaiDichVu WITH (HOLDLOCK)
                    WHERE MaLoaiDichVu = @ServiceId AND DangHoatDong = 1
                )
                    THROW 52205, N'Bưu cục hoặc dịch vụ đã ngừng hoạt động.', 1;

                DECLARE
                    @RuleId BIGINT,
                    @BaseFee DECIMAL(18,2),
                    @FeePerKm DECIMAL(18,2),
                    @FeePerKg DECIMAL(18,2),
                    @Now DATETIME2(0) = SYSUTCDATETIME();

                SELECT TOP (1)
                    @RuleId = q.MaQuyTacTinhPhi,
                    @BaseFee = q.PhiCoBan,
                    @FeePerKm = q.PhiMoiKm,
                    @FeePerKg = q.PhiMoiKg
                FROM dbo.QuyTacTinhPhi q WITH (HOLDLOCK)
                JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = @BranchId
                WHERE q.MaLoaiDichVu = @ServiceId
                  AND q.DangHoatDong = 1
                  AND (q.MaKhuVuc = bc.MaKhuVuc OR q.MaKhuVuc IS NULL)
                  AND q.HieuLucTu <= @Now
                  AND (q.HieuLucDen IS NULL OR @Now < q.HieuLucDen)
                  AND (q.KhoangCachTuKm IS NULL
                       OR @DistanceKm >= q.KhoangCachTuKm)
                  AND (q.KhoangCachDenKm IS NULL
                       OR @DistanceKm <= q.KhoangCachDenKm)
                  AND (q.KhoiLuongTuKg IS NULL
                       OR @WeightKg >= q.KhoiLuongTuKg)
                  AND (q.KhoiLuongDenKg IS NULL
                       OR @WeightKg <= q.KhoiLuongDenKg)
                ORDER BY
                    CASE WHEN q.MaKhuVuc = bc.MaKhuVuc THEN 0 ELSE 1 END,
                    q.HieuLucTu DESC,
                    q.MaQuyTacTinhPhi;

                IF @RuleId IS NULL
                    THROW 52204, N'Chưa có quy tắc tính phí phù hợp.', 1;

                DECLARE @CalculatedFee DECIMAL(18,2) =
                    ROUND(
                        @BaseFee
                        + @DistanceKm * @FeePerKm
                        + @WeightKg * @FeePerKg,
                        0
                    );

                DELETE FROM dbo.KhoanPhiDonHang
                WHERE MaDonHang = @OrderId
                  AND LoaiKhoanPhi = 'SHIPPING';

                INSERT INTO dbo.KhoanPhiDonHang (
                    MaDonHang, LoaiKhoanPhi, SoTien, MoTa
                )
                VALUES (
                    @OrderId,
                    'SHIPPING',
                    @CalculatedFee,
                    CONCAT(
                        N'Quy tắc #', @RuleId,
                        N'; khoảng cách ', @DistanceKm,
                        N' km; khối lượng ', @WeightKg, N' kg.'
                    )
                );

                DECLARE @TotalFee DECIMAL(18,2);

                SELECT @TotalFee = SUM(SoTien)
                FROM dbo.KhoanPhiDonHang WITH (HOLDLOCK)
                WHERE MaDonHang = @OrderId;

                IF @TotalFee < 0
                    THROW 52206, N'Tổng phí sau giảm giá không được âm.', 1;

                UPDATE dbo.DonHang
                SET PhiVanChuyen = @TotalFee,
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = SYSUTCDATETIME()
                WHERE MaDonHang = @OrderId;

                EXEC dbo.sp_XacNhanDonHang
                    @MaDonHang = @OrderId,
                    @MaTaiKhoan = @AccountId;

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan, LoaiThaoTac, TenDoiTuong,
                    MaDoiTuong, DuLieuCuJson, DuLieuMoiJson
                )
                VALUES (
                    @AccountId,
                    'CONFIRM_ORDER',
                    'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    (
                        SELECT 'NEW' AS status, @OldFee AS shippingFee
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    ),
                    (
                        SELECT
                            'CONFIRMED' AS status,
                            @TotalFee AS shippingFee,
                            @RuleId AS ruleId,
                            @DistanceKm AS distanceKm
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )
                );

                COMMIT;

                SELECT
                    @OrderId AS OrderId,
                    @RuleId AS RuleId,
                    @WeightKg AS WeightKg,
                    @CalculatedFee AS CalculatedFee,
                    @TotalFee AS TotalFee;
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

            var distance =
                command.Parameters.Add("@DistanceKm", SqlDbType.Decimal);

            distance.Precision = 10;
            distance.Scale = 2;
            distance.Value = request.DistanceKm;

            await using var reader = await command.ExecuteReaderAsync();
            await reader.ReadAsync();

            return Ok(new
            {
                id,
                status = "CONFIRMED",
                ruleId = Convert.ToInt64(reader["RuleId"]),
                distanceKm = request.DistanceKm,
                weightKg = Convert.ToDecimal(reader["WeightKg"]),
                calculatedShippingFee =
                    Convert.ToDecimal(reader["CalculatedFee"]),
                shippingFee = Convert.ToDecimal(reader["TotalFee"]),
                message = "Đã tính phí và xác nhận đơn thành công."
            });
        }
        catch (SqlException ex) when (ex.Number == 52201)
        {
            return Forbid();
        }
        catch (SqlException ex) when (ex.Number == 52202)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52204)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex)
            when (ex.Number == 52205 || ex.Number == 51002)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (SqlException ex)
            when (ex.Number == 52203
                  || ex.Number == 52206
                  || ex.Number == 51110
                  || ex.Number == 51001)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex)
        {
            _logger.LogError(ex, "Không xác nhận được đơn {OrderId}.", id);

            return StatusCode(500, new
            {
                message = "Không xác nhận được đơn. Xem log Visual Studio."
            });
        }
    }
}