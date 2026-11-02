using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/warehouses")]
public class WarehouseReturnRequestsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public WarehouseReturnRequestsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    // Read-only candidates; ReturnIn rechecks these conditions under transaction locks.
    [HttpGet("{id:int}/return-requests")]
    public async Task<IActionResult> GetReturnRequests(
        int id,
        [FromQuery, StringLength(100)] string? keyword = null,
        [FromQuery, Range(1, long.MaxValue)] long? orderId = null,
        [FromQuery, Range(1, long.MaxValue)] long? returnRequestId = null,
        [FromQuery, Range(1, 100000)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 10,
        CancellationToken cancellationToken = default)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã kho phải lớn hơn 0." });

        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId))
            return Unauthorized();

        keyword = string.IsNullOrWhiteSpace(keyword) ? null : keyword.Trim();

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @Role VARCHAR(50),
                @RoleId INT,
                @AccountBranchId INT,
                @WarehouseBranchId INT,
                @WarehouseName NVARCHAR(150);

            SELECT
                @Role = vt.KyHieuVaiTro,
                @RoleId = tk.MaVaiTro,
                @AccountBranchId = tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());

            IF @Role IS NULL
                THROW 52401, N'Tài khoản không còn hoạt động hoặc đang bị khóa.', 1;

            IF (SELECT COUNT(DISTINCT q.KyHieuQuyen)
                FROM dbo.VaiTroQuyen vq
                JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen IN ('KHO_XEM', 'KHO_NHAP')) <> 2
               OR (@Role <> 'ADMIN' AND @AccountBranchId IS NULL)
                THROW 52402, N'Bạn cần quyền xem kho và nhập kho để xem yêu cầu hoàn.', 1;

            SELECT
                @WarehouseBranchId = k.MaBuuCuc,
                @WarehouseName = k.TenKho
            FROM dbo.Kho k
            JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = k.MaBuuCuc
            WHERE k.MaKho = @WarehouseId
              AND k.DangHoatDong = 1
              AND bc.DangHoatDong = 1
              AND (@Role = 'ADMIN' OR k.MaBuuCuc = @AccountBranchId);

            IF @WarehouseBranchId IS NULL
                THROW 52403, N'Không tìm thấy kho hoạt động trong phạm vi được phép.', 1;

            ;WITH EligibleReturns AS (
                SELECT
                    yc.MaYeuCauGiaoLaiHoacHoan AS returnRequestId,
                    d.MaDonHang AS orderId,
                    d.KyHieuDonHang AS orderCode,
                    d.MaVanDon AS trackingNumber,
                    d.MaBuuCuc AS branchId,
                    bc.TenBuuCuc AS branchName,
                    tt.KyHieuTrangThai AS orderStatus,
                    tt.TenTrangThai AS orderStatusName,
                    yc.TrangThaiYeuCau AS requestStatus,
                    yc.MaBuuCucHoan AS returnBranchId,
                    yc.LyDo AS reason,
                    yc.ThoiGianYeuCau AS requestedAt,
                    d.TongKhoiLuongKg AS weightKg,
                    t.MaKho AS previousWarehouseId,
                    t.TrangThaiTonKho AS stockStatus
                FROM dbo.YeuCauGiaoLaiHoacHoan yc
                JOIN dbo.DonHang d ON d.MaDonHang = yc.MaDonHang
                JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = d.MaBuuCuc
                JOIN dbo.TonKhoDonHang t ON t.MaDonHang = d.MaDonHang
                WHERE yc.LoaiYeuCau = 'RETURN'
                  AND yc.TrangThaiYeuCau = 'IN_PROGRESS'
                  AND tt.KyHieuTrangThai = 'RETURNING'
                  AND d.MaKhoHienTai IS NULL
                  AND d.MaBuuCuc = @WarehouseBranchId
                  AND yc.MaBuuCucHoan = d.MaBuuCuc
                  AND t.TrangThaiTonKho = 'HANDED_OVER'
                  AND NOT EXISTS (
                      SELECT 1 FROM dbo.PhanCongGiaoHang pc
                      WHERE pc.MaDonHang = d.MaDonHang AND pc.ThoiGianKetThuc IS NULL
                  )
                  AND (@OrderId IS NULL OR d.MaDonHang = @OrderId)
                  AND (@ReturnRequestId IS NULL OR yc.MaYeuCauGiaoLaiHoacHoan = @ReturnRequestId)
                  AND (@Keyword IS NULL
                       OR d.KyHieuDonHang LIKE '%' + @Keyword + '%'
                       OR d.MaVanDon LIKE '%' + @Keyword + '%')
            )
            SELECT (
                SELECT
                    @WarehouseId AS warehouseId,
                    @WarehouseName AS warehouseName,
                    CAST(1 AS BIT) AS canReturnIn,
                    @Page AS page,
                    @PageSize AS pageSize,
                    (SELECT COUNT_BIG(*) FROM EligibleReturns) AS totalItems,
                    JSON_QUERY(COALESCE((
                        SELECT * FROM EligibleReturns
                        ORDER BY requestedAt, returnRequestId
                        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            """;

        await using var connection = new SqlConnection(_configuration.GetConnectionString("DefaultConnection"));
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = accountId;
        command.Parameters.Add("@WarehouseId", SqlDbType.Int).Value = id;
        command.Parameters.Add("@Keyword", SqlDbType.NVarChar, 100).Value = (object?)keyword ?? DBNull.Value;
        command.Parameters.Add("@OrderId", SqlDbType.BigInt).Value = (object?)orderId ?? DBNull.Value;
        command.Parameters.Add("@ReturnRequestId", SqlDbType.BigInt).Value = (object?)returnRequestId ?? DBNull.Value;
        command.Parameters.Add("@Page", SqlDbType.Int).Value = page;
        command.Parameters.Add("@PageSize", SqlDbType.Int).Value = pageSize;
        command.Parameters.Add("@Offset", SqlDbType.Int).Value = (page - 1) * pageSize;

        try
        {
            await connection.OpenAsync(cancellationToken);
            var json = await command.ExecuteScalarAsync(cancellationToken) as string;
            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (ex.Number is >= 52401 and <= 52403)
        {
            return StatusCode(ex.Number switch { 52401 => 401, 52402 => 403, _ => 404 }, new { message = ex.Message });
        }
    }
}
