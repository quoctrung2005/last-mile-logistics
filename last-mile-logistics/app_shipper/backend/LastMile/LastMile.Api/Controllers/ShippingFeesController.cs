using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class ShippingFeeQuoteRequest
{
    [Range(1, int.MaxValue)]
    public int BranchId { get; set; }

    [Range(1, int.MaxValue)]
    public int ServiceId { get; set; }

    [Range(typeof(decimal), "0", "1000000",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal DistanceKm { get; set; }

    [Range(typeof(decimal), "0.001", "1000000",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal WeightKg { get; set; }
}

[Authorize]
[ApiController]
[Route("api/v1/shipping-fees")]
public class ShippingFeesController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public ShippingFeesController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("quote")]
    public async Task<IActionResult> Quote(
        ShippingFeeQuoteRequest request)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        if (decimal.Round(request.DistanceKm, 2) != request.DistanceKm
            || decimal.Round(request.WeightKg, 3) != request.WeightKg)
        {
            return BadRequest(new
            {
                message = "Khoảng cách tối đa 2 số lẻ; "
                    + "khối lượng tối đa 3 số lẻ."
            });
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string permissionSql = """
            SELECT COUNT(*)
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
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
                  FROM dbo.VaiTroQuyen vq
                  JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                  WHERE vq.MaVaiTro = tk.MaVaiTro
                    AND (q.KyHieuQuyen = 'DONHANG_TAO' OR (vt.KyHieuVaiTro = 'ADMIN' AND q.KyHieuQuyen = 'BANGGIA_QUANLY'))
              );
            """;

        await using var permissionCommand =
            new SqlCommand(permissionSql, connection);

        permissionCommand.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        permissionCommand.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value = request.BranchId;

        var allowed = Convert.ToInt32(
            await permissionCommand.ExecuteScalarAsync()) > 0;

        if (!allowed)
            return Forbid();

        const string sql = """
            IF NOT EXISTS (
                SELECT 1 FROM dbo.BuuCuc
                WHERE MaBuuCuc = @BranchId AND DangHoatDong = 1
            )
                THROW 52101, N'Bưu cục không tồn tại hoặc đã ngừng hoạt động.', 1;

            IF NOT EXISTS (
                SELECT 1 FROM dbo.LoaiDichVu
                WHERE MaLoaiDichVu = @ServiceId AND DangHoatDong = 1
            )
                THROW 52102, N'Dịch vụ không tồn tại hoặc đã ngừng hoạt động.', 1;

            DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

            SELECT TOP (1)
                q.MaQuyTacTinhPhi,
                bc.MaKhuVuc AS MaKhuVucBuuCuc,
                q.MaKhuVuc AS MaKhuVucQuyTac,
                dv.TenDichVu,
                q.PhiCoBan,
                q.PhiMoiKm,
                q.PhiMoiKg,
                @Now AS ThoiDiemTinhPhi
            FROM dbo.QuyTacTinhPhi q
            JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = @BranchId
            JOIN dbo.LoaiDichVu dv
                ON dv.MaLoaiDichVu = q.MaLoaiDichVu
            WHERE q.MaLoaiDichVu = @ServiceId
              AND q.DangHoatDong = 1
              AND bc.DangHoatDong = 1
              AND dv.DangHoatDong = 1
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
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value = request.BranchId;

        command.Parameters.Add(
            "@ServiceId", SqlDbType.Int).Value = request.ServiceId;

        var distanceParameter =
            command.Parameters.Add("@DistanceKm", SqlDbType.Decimal);

        distanceParameter.Precision = 10;
        distanceParameter.Scale = 2;
        distanceParameter.Value = request.DistanceKm;

        var weightParameter =
            command.Parameters.Add("@WeightKg", SqlDbType.Decimal);

        weightParameter.Precision = 10;
        weightParameter.Scale = 3;
        weightParameter.Value = request.WeightKg;

        try
        {
            await using var reader = await command.ExecuteReaderAsync();

            if (!await reader.ReadAsync())
            {
                return UnprocessableEntity(new
                {
                    message = "Chưa có quy tắc phí phù hợp với dịch vụ, "
                        + "khu vực, khoảng cách, khối lượng và thời điểm hiện tại."
                });
            }

            var baseFee = Convert.ToDecimal(reader["PhiCoBan"]);
            var feePerKm = Convert.ToDecimal(reader["PhiMoiKm"]);
            var feePerKg = Convert.ToDecimal(reader["PhiMoiKg"]);

            var distanceFee = request.DistanceKm * feePerKm;
            var weightFee = request.WeightKg * feePerKg;

            var shippingFee = decimal.Round(
                baseFee + distanceFee + weightFee,
                0,
                MidpointRounding.AwayFromZero);

            return Ok(new
            {
                branchId = request.BranchId,
                serviceId = request.ServiceId,
                serviceName = reader["TenDichVu"].ToString(),
                ruleId = Convert.ToInt64(reader["MaQuyTacTinhPhi"]),
                branchAreaId = Convert.ToInt32(reader["MaKhuVucBuuCuc"]),
                ruleAreaId = reader["MaKhuVucQuyTac"] == DBNull.Value
                    ? (int?)null
                    : Convert.ToInt32(reader["MaKhuVucQuyTac"]),
                distanceKm = request.DistanceKm,
                weightKg = request.WeightKg,
                baseFee,
                feePerKm,
                feePerKg,
                distanceFee,
                weightFee,
                shippingFee,
                baseFeeExact = baseFee.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture),
                distanceFeeExact = distanceFee.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture),
                weightFeeExact = weightFee.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture),
                shippingFeeExact = shippingFee.ToString("0", System.Globalization.CultureInfo.InvariantCulture),
                currency = "VND",
                quotedAt = DateTime.SpecifyKind(
                    Convert.ToDateTime(reader["ThoiDiemTinhPhi"]),
                    DateTimeKind.Utc)
            });
        }
        catch (SqlException ex)
            when (ex.Number == 52101 || ex.Number == 52102)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}
