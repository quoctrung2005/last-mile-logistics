using System.Data;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[AllowAnonymous]
[EnableRateLimiting("public-tracking")]
[Route("api/v1/tracking")]
public class PublicTrackingController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public PublicTrackingController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("{trackingNumber}")]
    public async Task<IActionResult> Get(
        string trackingNumber,
        CancellationToken cancellationToken)
    {
        trackingNumber = trackingNumber.Trim().ToUpperInvariant();

        if (trackingNumber.Length is < 6 or > 50
            || !Regex.IsMatch(
                trackingNumber,
                @"^[A-Z0-9-]+$",
                RegexOptions.CultureInvariant))
        {
            return BadRequest(new
            {
                message = "Mã vận đơn không hợp lệ."
            });
        }

        const string sql = """
            SET NOCOUNT ON;

            SELECT
                d.MaVanDon AS trackingNumber,
                tt.KyHieuTrangThai AS status,
                tt.TenTrangThai AS statusName,
                d.ThoiGianTao AS createdAt,
                d.ThoiGianDuKienGiao AS expectedDeliveryAt,
                d.ThoiGianCapNhat AS updatedAt,

                CASE
                    WHEN EXISTS (
                        SELECT 1
                        FROM dbo.LichSuTrangThaiDonHang ls
                        INNER JOIN dbo.TrangThaiDonHang historyStatus
                            ON historyStatus.MaTrangThaiDonHang =
                                ls.MaTrangThaiMoi
                        WHERE ls.MaDonHang = d.MaDonHang
                          AND historyStatus.KyHieuTrangThai = 'RETURNED'
                    )
                        THEN 'RETURNED'

                    WHEN EXISTS (
                        SELECT 1
                        FROM dbo.LichSuTrangThaiDonHang ls
                        INNER JOIN dbo.TrangThaiDonHang historyStatus
                            ON historyStatus.MaTrangThaiDonHang =
                                ls.MaTrangThaiMoi
                        WHERE ls.MaDonHang = d.MaDonHang
                          AND historyStatus.KyHieuTrangThai = 'DELIVERED'
                    )
                        THEN 'DELIVERED'

                    ELSE NULL
                END AS deliveryOutcome

            FROM dbo.DonHang d
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            WHERE d.MaVanDon = @TrackingNumber

            FOR JSON PATH,
                INCLUDE_NULL_VALUES,
                WITHOUT_ARRAY_WRAPPER;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@TrackingNumber", SqlDbType.VarChar, 50).Value =
            trackingNumber;

        await connection.OpenAsync(cancellationToken);

        var result = await command.ExecuteScalarAsync(
            cancellationToken);

        var json = result?.ToString();

        if (string.IsNullOrWhiteSpace(json))
        {
            return NotFound(new
            {
                message = "Không tìm thấy vận đơn."
            });
        }

        return Content(json, "application/json");
    }
}