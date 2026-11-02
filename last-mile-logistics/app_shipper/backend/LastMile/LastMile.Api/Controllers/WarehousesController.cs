using System.Data;
using System.Security.Claims;
using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/v1/warehouses")]
public class WarehousesController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public WarehousesController(IConfiguration configuration)
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

    private static async Task<bool> CanAccessWarehouse(
        SqlConnection connection,
        int id,
        (bool IsAdmin, int? BranchId) scope)
    {
        const string sql = """
            SELECT COUNT(*)
            FROM dbo.Kho k
            JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = k.MaBuuCuc
            WHERE k.MaKho = @Id
              AND k.DangHoatDong = 1
              AND bc.DangHoatDong = 1
              AND (@IsAdmin = 1 OR k.MaBuuCuc = @BranchId);
            """;

        await using var command = new SqlCommand(sql, connection);

        AddScope(command, scope);
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;

        return Convert.ToInt32(
            await command.ExecuteScalarAsync()) > 0;
    }

    [HttpGet]
    public async Task<IActionResult> GetWarehouses()
    {
        await using var connection = CreateConnection();
        await connection.OpenAsync();

        var scope = await GetScope(connection);

        if (scope is null)
            return Forbid();

        const string sql = """
            SELECT COALESCE((
                SELECT
                    k.MaKho AS id,
                    k.KyHieuKho AS code,
                    k.TenKho AS name,
                    k.MaBuuCuc AS branchId,
                    bc.TenBuuCuc AS branchName,
                    k.DiaChi AS address,
                    (
                        SELECT COUNT_BIG(*)
                        FROM dbo.ViTriLuuKho vt
                        WHERE vt.MaKho = k.MaKho
                          AND vt.DangHoatDong = 1
                    ) AS activeLocationCount
                FROM dbo.Kho k
                JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = k.MaBuuCuc
                WHERE k.DangHoatDong = 1
                  AND bc.DangHoatDong = 1
                  AND (@IsAdmin = 1 OR k.MaBuuCuc = @BranchId)
                ORDER BY k.MaBuuCuc, k.MaKho
                FOR JSON PATH, INCLUDE_NULL_VALUES
            ), N'[]');
            """;

        await using var command = new SqlCommand(sql, connection);
        AddScope(command, scope.Value);

        var json = (string)(await command.ExecuteScalarAsync())!;

        return Content(json, "application/json");
    }

    [HttpGet("{id:int}/locations")]
    public async Task<IActionResult> GetLocations(
        int id,
        [FromQuery, StringLength(100)] string? keyword = null,
        [FromQuery, RegularExpression("^(ACTIVE|INACTIVE|ALL)$")] string status = "ACTIVE")
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã kho phải lớn hơn 0." });

        keyword = string.IsNullOrWhiteSpace(keyword) ? null : keyword.Trim();

        await using var connection = CreateConnection();
        await connection.OpenAsync();

        var scope = await GetScope(connection);

        if (scope is null)
            return Forbid();

        if (!await CanAccessWarehouse(connection, id, scope.Value))
            return NotFound(new
            {
                message = "Không tìm thấy kho hoạt động trong phạm vi được xem."
            });

        const string sql = """
            SELECT COALESCE((
                SELECT
                    vt.MaViTriLuuKho AS id,
                    vt.MaKho AS warehouseId,
                    vt.KyHieuViTri AS code,
                    vt.TenKhuLuu AS storageArea,
                    vt.MaKe AS rack,
                    vt.MaO AS slot,
                    vt.DangHoatDong AS isActive
                FROM dbo.ViTriLuuKho vt
                WHERE vt.MaKho = @Id
                  AND (@Status = 'ALL'
                       OR (@Status = 'ACTIVE' AND vt.DangHoatDong = 1)
                       OR (@Status = 'INACTIVE' AND vt.DangHoatDong = 0))
                  AND (@Keyword IS NULL
                       OR CHARINDEX(@Keyword, vt.KyHieuViTri) > 0
                       OR CHARINDEX(@Keyword, vt.TenKhuLuu) > 0
                       OR CHARINDEX(@Keyword, vt.MaKe) > 0
                       OR CHARINDEX(@Keyword, vt.MaO) > 0)
                ORDER BY vt.KyHieuViTri, vt.MaViTriLuuKho
                FOR JSON PATH, INCLUDE_NULL_VALUES
            ), N'[]');
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
        command.Parameters.Add("@Status", SqlDbType.VarChar, 10).Value = status;
        command.Parameters.Add("@Keyword", SqlDbType.NVarChar, 100).Value = (object?)keyword ?? DBNull.Value;

        var json = (string)(await command.ExecuteScalarAsync())!;

        return Content(json, "application/json");
    }

    [HttpGet("{id:int}/inventory")]
    public async Task<IActionResult> GetInventory(
        int id,
        [FromQuery] string? keyword = null,
        [FromQuery] long? locationId = null,
        [FromQuery] string? orderStatus = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã kho phải lớn hơn 0." });

        orderStatus = string.IsNullOrWhiteSpace(orderStatus) ? null : orderStatus.Trim();
        if (locationId is <= 0 || orderStatus?.Length > 40)
            return BadRequest(new { message = "Vị trí hoặc trạng thái lọc không hợp lệ." });

        if (page < 1 || page > 100000
            || pageSize < 1 || pageSize > 100)
        {
            return BadRequest(new
            {
                message = "page từ 1–100000; pageSize từ 1–100."
            });
        }

        keyword = string.IsNullOrWhiteSpace(keyword)
            ? null : keyword.Trim();

        if (keyword?.Length > 100)
            return BadRequest(new
            {
                message = "Từ khóa tối đa 100 ký tự."
            });

        await using var connection = CreateConnection();
        await connection.OpenAsync();

        var scope = await GetScope(connection);

        if (scope is null)
            return Forbid();

        if (!await CanAccessWarehouse(connection, id, scope.Value))
            return NotFound(new
            {
                message = "Không tìm thấy kho hoạt động trong phạm vi được xem."
            });

        const string sql = """
            ;WITH Inventory AS (
                SELECT
                    d.MaDonHang AS orderId,
                    d.KyHieuDonHang AS orderCode,
                    d.MaVanDon AS trackingNumber,
                    tk.MaKho AS warehouseId,
                    tk.MaViTriLuuKho AS locationId,
                    vt.KyHieuViTri AS locationCode,
                    tk.TrangThaiTonKho AS inventoryStatus,
                    tt.KyHieuTrangThai AS orderStatus,
                    tt.TenTrangThai AS orderStatusName,
                    d.TongKhoiLuongKg AS weightKg,
                    tk.ThoiGianNhapKho AS receivedAt,
                    tk.ThoiGianDiChuyenCuoi AS lastMovedAt
                FROM dbo.TonKhoDonHang tk
                JOIN dbo.DonHang d ON d.MaDonHang = tk.MaDonHang
                JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                LEFT JOIN dbo.ViTriLuuKho vt
                    ON vt.MaViTriLuuKho = tk.MaViTriLuuKho
                WHERE tk.MaKho = @Id
                  AND d.MaKhoHienTai = tk.MaKho
                  AND (@LocationId IS NULL OR tk.MaViTriLuuKho = @LocationId)
                  AND (@OrderStatus IS NULL OR tt.KyHieuTrangThai = @OrderStatus)
                  AND tk.TrangThaiTonKho IN (
                      'RECEIVED', 'STORED', 'ALLOCATED', 'RETURNED'
                  )
                  AND (
                      @Keyword IS NULL
                      OR d.MaVanDon LIKE '%' + @Keyword + '%'
                      OR d.KyHieuDonHang LIKE '%' + @Keyword + '%'
                  )
            )
            SELECT (
                SELECT
                    @Id AS warehouseId,
                    @Page AS page,
                    @PageSize AS pageSize,
                    (SELECT COUNT_BIG(*) FROM Inventory) AS totalItems,
                    JSON_QUERY(COALESCE((
                        SELECT *
                        FROM Inventory
                        ORDER BY receivedAt DESC, orderId DESC
                        OFFSET @Offset ROWS
                        FETCH NEXT @PageSize ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;

        command.Parameters.Add("@LocationId", SqlDbType.BigInt).Value =
            (object?)locationId ?? DBNull.Value;
        command.Parameters.Add("@OrderStatus", SqlDbType.VarChar, 40).Value =
            (object?)orderStatus ?? DBNull.Value;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;

        command.Parameters.Add("@Page", SqlDbType.Int).Value = page;
        command.Parameters.Add("@PageSize", SqlDbType.Int).Value = pageSize;
        command.Parameters.Add("@Offset", SqlDbType.Int).Value =
            (page - 1) * pageSize;

        var json = (string)(await command.ExecuteScalarAsync())!;

        return Content(json, "application/json");
    }
}
