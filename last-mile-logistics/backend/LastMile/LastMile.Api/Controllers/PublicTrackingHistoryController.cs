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
public class PublicTrackingHistoryController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public PublicTrackingHistoryController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("{trackingNumber}/history")]
    public async Task<IActionResult> GetHistory(
        string trackingNumber,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default)
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

        if (page < 1 || pageSize < 1 || pageSize > 100)
        {
            return BadRequest(new
            {
                message = "Page phải từ 1; pageSize từ 1 đến 100."
            });
        }

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @OrderId BIGINT,
                @CurrentStatus VARCHAR(40),
                @CurrentStatusName NVARCHAR(100);

            SELECT
                @OrderId = d.MaDonHang,
                @CurrentStatus = tt.KyHieuTrangThai,
                @CurrentStatusName = tt.TenTrangThai
            FROM dbo.DonHang d
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            WHERE d.MaVanDon = @TrackingNumber;

            IF @OrderId IS NULL
                THROW 56303,
                    N'Không tìm thấy vận đơn.', 1;

            SELECT
                ls.MaLichSuTrangThai AS HistoryId,
                previousStatus.KyHieuTrangThai AS PreviousStatus,
                currentStatus.KyHieuTrangThai AS Status,
                currentStatus.TenTrangThai AS StatusName,
                ls.ThoiGianThayDoi AS ChangedAt
            INTO #History
            FROM dbo.LichSuTrangThaiDonHang ls
            LEFT JOIN dbo.TrangThaiDonHang previousStatus
                ON previousStatus.MaTrangThaiDonHang =
                    ls.MaTrangThaiCu
            INNER JOIN dbo.TrangThaiDonHang currentStatus
                ON currentStatus.MaTrangThaiDonHang =
                    ls.MaTrangThaiMoi
            WHERE ls.MaDonHang = @OrderId;

            SELECT
                @TrackingNumber AS trackingNumber,
                @CurrentStatus AS currentStatus,
                @CurrentStatusName AS currentStatusName,
                @Page AS page,
                @PageSize AS pageSize,
                (
                    SELECT COUNT(*)
                    FROM #History
                ) AS totalItems,

                JSON_QUERY((
                    SELECT
                        PreviousStatus AS previousStatus,
                        Status AS status,
                        StatusName AS statusName,
                        ChangedAt AS changedAt
                    FROM #History
                    ORDER BY ChangedAt ASC, HistoryId ASC
                    OFFSET @Offset ROWS
                    FETCH NEXT @PageSize ROWS ONLY
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                )) AS items

            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@TrackingNumber", SqlDbType.VarChar, 50).Value =
            trackingNumber;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value = pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.BigInt).Value =
            ((long)page - 1) * pageSize;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 56303)
        {
            return NotFound(new { message = ex.Message });
        }
    }
}