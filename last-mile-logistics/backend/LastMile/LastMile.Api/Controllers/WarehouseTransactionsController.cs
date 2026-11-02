using System.Data;
using System.Security.Claims;
using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/v1/warehouse-transactions")]
public class WarehouseTransactionsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public WarehouseTransactionsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    private SqlConnection CreateConnection()
    {
        return new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
    }

    private async Task<(bool IsAdmin, int? BranchId)?> GetScope(
        SqlConnection connection)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return null;
        }

        const string sql = """
            SELECT vt.KyHieuVaiTro, tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
              )
              AND EXISTS (
                  SELECT 1
                  FROM dbo.VaiTroQuyen vq
                  JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                  WHERE vq.MaVaiTro = tk.MaVaiTro
                    AND q.KyHieuQuyen = 'KHO_XEM'
              );
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        await using var reader = await command.ExecuteReaderAsync();

        if (!await reader.ReadAsync())
            return null;

        var isAdmin = reader["KyHieuVaiTro"].ToString() == "ADMIN";

        int? branchId = reader["MaBuuCuc"] == DBNull.Value
            ? null
            : Convert.ToInt32(reader["MaBuuCuc"]);

        if (!isAdmin && branchId is null)
            return null;

        return (isAdmin, branchId);
    }

    private static void AddScope(
        SqlCommand command,
        (bool IsAdmin, int? BranchId) scope)
    {
        command.Parameters.Add(
            "@IsAdmin", SqlDbType.Bit).Value = scope.IsAdmin;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
                (object?)scope.BranchId ?? DBNull.Value;
    }

    [HttpGet]
    public async Task<IActionResult> GetTransactions(
        [FromQuery] int? warehouseId = null,
        [FromQuery] string? type = null,
        [FromQuery] long? orderId = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery, StringLength(100)] string? keyword = null,
        [FromQuery] DateOnly? fromDate = null,
        [FromQuery] DateOnly? toDate = null)
    {
        if (warehouseId.HasValue && warehouseId.Value <= 0
            || orderId.HasValue && orderId.Value <= 0)
        {
            return BadRequest(new
            {
                message = "Mã kho và mã đơn phải lớn hơn 0."
            });
        }

        if (page < 1 || page > 100000
            || pageSize < 1 || pageSize > 100)
        {
            return BadRequest(new
            {
                message = "page từ 1–100000; pageSize từ 1–100."
            });
        }

        type = string.IsNullOrWhiteSpace(type)
            ? null : type.Trim().ToUpperInvariant();

        if (type is not null
            && type is not ("INBOUND" or "MOVE" or "OUTBOUND" or "RETURN_IN"))
        {
            return BadRequest(new
            {
                message = "type phải là INBOUND, MOVE, OUTBOUND hoặc RETURN_IN."
            });
        }

        keyword = string.IsNullOrWhiteSpace(keyword) ? null : keyword.Trim();
        if (fromDate.HasValue && toDate.HasValue && fromDate > toDate)
            return BadRequest(new { message = "Từ ngày không được sau đến ngày." });

        DateTime? fromUtc;
        DateTime? toUtcExclusive;
        try
        {
            // Date filters are calendar days in Vietnam (UTC+7); stored DATETIME2 is UTC.
            fromUtc = fromDate?.ToDateTime(TimeOnly.MinValue).AddHours(-7);
            toUtcExclusive = toDate?.ToDateTime(TimeOnly.MinValue).AddDays(1).AddHours(-7);
        }
        catch (ArgumentOutOfRangeException)
        {
            return BadRequest(new { message = "Khoảng ngày vượt giới hạn được hỗ trợ." });
        }

        await using var connection = CreateConnection();
        await connection.OpenAsync();

        var scope = await GetScope(connection);

        if (scope is null)
            return Forbid();

        const string sql = """
            ;WITH Transactions AS (
                SELECT
                    gd.MaGiaoDichKho AS id,
                    gd.KyHieuGiaoDich AS transactionCode,
                    gd.MaKho AS warehouseId,
                    k.TenKho AS warehouseName,
                    k.MaBuuCuc AS branchId,
                    gd.LoaiGiaoDich AS type,
                    gd.TrangThaiGiaoDich AS status,
                    gd.MaTaiKhoanThucHien AS performedBy,
                    tk.HoTen AS performedByName,
                    gd.ThoiGianThucHien AS performedAt,
                    gd.GhiChu AS notes,
                    (
                        SELECT COUNT_BIG(*)
                        FROM dbo.ChiTietGiaoDichKho ct
                        WHERE ct.MaGiaoDichKho = gd.MaGiaoDichKho
                    ) AS orderCount
                FROM dbo.GiaoDichKho gd
                JOIN dbo.Kho k ON k.MaKho = gd.MaKho
                JOIN dbo.TaiKhoan tk
                    ON tk.MaTaiKhoan = gd.MaTaiKhoanThucHien
                WHERE (@IsAdmin = 1 OR k.MaBuuCuc = @BranchId)
                  AND (@WarehouseId IS NULL OR gd.MaKho = @WarehouseId)
                  AND (@Type IS NULL OR gd.LoaiGiaoDich = @Type)
                  AND (@FromUtc IS NULL OR gd.ThoiGianThucHien >= @FromUtc)
                  AND (@ToUtcExclusive IS NULL OR gd.ThoiGianThucHien < @ToUtcExclusive)
                  AND (
                      @Keyword IS NULL
                      OR CHARINDEX(@Keyword, gd.KyHieuGiaoDich) > 0
                      OR EXISTS (
                          SELECT 1
                          FROM dbo.ChiTietGiaoDichKho searchDetail
                          JOIN dbo.DonHang searchOrder ON searchOrder.MaDonHang = searchDetail.MaDonHang
                          WHERE searchDetail.MaGiaoDichKho = gd.MaGiaoDichKho
                            AND (CHARINDEX(@Keyword, searchOrder.KyHieuDonHang) > 0
                                 OR CHARINDEX(@Keyword, searchOrder.MaVanDon) > 0)
                      )
                  )
                  AND (
                      @OrderId IS NULL
                      OR EXISTS (
                          SELECT 1
                          FROM dbo.ChiTietGiaoDichKho ct
                          WHERE ct.MaGiaoDichKho = gd.MaGiaoDichKho
                            AND ct.MaDonHang = @OrderId
                      )
                  )
            )
            SELECT (
                SELECT
                    @Page AS page,
                    @PageSize AS pageSize,
                    (SELECT COUNT_BIG(*) FROM Transactions) AS totalItems,
                    JSON_QUERY(COALESCE((
                        SELECT *
                        FROM Transactions
                        ORDER BY performedAt DESC, id DESC
                        OFFSET @Offset ROWS
                        FETCH NEXT @PageSize ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            """;

        await using var command = new SqlCommand(sql, connection);
        AddScope(command, scope.Value);

        command.Parameters.Add(
            "@WarehouseId", SqlDbType.Int).Value =
                (object?)warehouseId ?? DBNull.Value;

        command.Parameters.Add(
            "@Type", SqlDbType.VarChar, 20).Value =
                (object?)type ?? DBNull.Value;

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt).Value =
                (object?)orderId ?? DBNull.Value;

        command.Parameters.Add("@Keyword", SqlDbType.NVarChar, 100).Value = (object?)keyword ?? DBNull.Value;
        command.Parameters.Add("@FromUtc", SqlDbType.DateTime2).Value = (object?)fromUtc ?? DBNull.Value;
        command.Parameters.Add("@ToUtcExclusive", SqlDbType.DateTime2).Value = (object?)toUtcExclusive ?? DBNull.Value;

        command.Parameters.Add("@Page", SqlDbType.Int).Value = page;
        command.Parameters.Add("@PageSize", SqlDbType.Int).Value = pageSize;
        command.Parameters.Add("@Offset", SqlDbType.Int).Value =
            (page - 1) * pageSize;

        var json = (string)(await command.ExecuteScalarAsync())!;

        return Content(json, "application/json");
    }

    [HttpGet("{id:long}")]
    public async Task<IActionResult> GetTransaction(long id)
    {
        if (id <= 0)
            return BadRequest(new
            {
                message = "Mã giao dịch phải lớn hơn 0."
            });

        await using var connection = CreateConnection();
        await connection.OpenAsync();

        var scope = await GetScope(connection);

        if (scope is null)
            return Forbid();

        const string sql = """
            SELECT (
                SELECT
                    gd.MaGiaoDichKho AS id,
                    gd.KyHieuGiaoDich AS transactionCode,
                    gd.MaKho AS warehouseId,
                    k.TenKho AS warehouseName,
                    k.MaBuuCuc AS branchId,
                    bc.TenBuuCuc AS branchName,
                    gd.LoaiGiaoDich AS type,
                    gd.TrangThaiGiaoDich AS status,
                    gd.MaTaiKhoanThucHien AS performedBy,
                    tk.HoTen AS performedByName,
                    gd.ThoiGianThucHien AS performedAt,
                    gd.GhiChu AS notes,
                    JSON_QUERY(COALESCE((
                        SELECT
                            ct.MaDonHang AS orderId,
                            d.KyHieuDonHang AS orderCode,
                            d.MaVanDon AS trackingNumber,
                            ct.MaViTriNguon AS fromLocationId,
                            nguon.KyHieuViTri AS fromLocationCode,
                            ct.MaViTriDich AS toLocationId,
                            dich.KyHieuViTri AS toLocationCode,
                            ct.TinhTrangHang AS condition,
                            ct.GhiChu AS notes
                        FROM dbo.ChiTietGiaoDichKho ct
                        JOIN dbo.DonHang d
                            ON d.MaDonHang = ct.MaDonHang
                        LEFT JOIN dbo.ViTriLuuKho nguon
                            ON nguon.MaViTriLuuKho = ct.MaViTriNguon
                        LEFT JOIN dbo.ViTriLuuKho dich
                            ON dich.MaViTriLuuKho = ct.MaViTriDich
                        WHERE ct.MaGiaoDichKho = gd.MaGiaoDichKho
                        ORDER BY ct.MaDonHang
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS items
                FROM dbo.GiaoDichKho gd
                JOIN dbo.Kho k ON k.MaKho = gd.MaKho
                JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = k.MaBuuCuc
                JOIN dbo.TaiKhoan tk
                    ON tk.MaTaiKhoan = gd.MaTaiKhoanThucHien
                WHERE gd.MaGiaoDichKho = @Id
                  AND (@IsAdmin = 1 OR k.MaBuuCuc = @BranchId)
                FOR JSON PATH, INCLUDE_NULL_VALUES,
                         WITHOUT_ARRAY_WRAPPER
            );
            """;

        await using var command = new SqlCommand(sql, connection);
        AddScope(command, scope.Value);

        command.Parameters.Add("@Id", SqlDbType.BigInt).Value = id;

        var json = await command.ExecuteScalarAsync() as string;

        if (string.IsNullOrWhiteSpace(json))
            return NotFound(new
            {
                message = "Không tìm thấy giao dịch trong phạm vi được xem."
            });

        return Content(json, "application/json");
    }
}
