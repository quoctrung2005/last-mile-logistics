using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/v1")]
public class OrderFormController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public OrderFormController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    private SqlConnection CreateConnection()
    {
        return new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
    }

    private async Task<(bool IsAdmin, int? BranchId)?> GetScope(
        SqlConnection connection, bool allowRead = false)
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
                    AND (q.KyHieuQuyen IN ('DONHANG_TAO', 'DONHANG_CAPNHAT')
                         OR (@AllowRead = 1 AND q.KyHieuQuyen = 'DONHANG_XEM'))
              );
            """;

        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@AllowRead", SqlDbType.Bit).Value = allowRead;

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

    [HttpGet("customers")]
    public async Task<IActionResult> GetCustomers(
        [FromQuery] string? keyword = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] string? type = null,
        [FromQuery] string status = "ACTIVE")
    {
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

        if (type is not null && type is not ("INDIVIDUAL" or "BUSINESS")
            || status is not ("ACTIVE" or "INACTIVE" or "ALL"))
            return BadRequest(new { message = "Loại hoặc trạng thái khách hàng không hợp lệ." });

        await using var connection = CreateConnection();
        await connection.OpenAsync();

        if (await GetScope(connection, allowRead: true) is null)
            return Forbid();

        const string sql = """
            SELECT (
                SELECT
                    @Page AS page,
                    @PageSize AS pageSize,
                    (
                        SELECT COUNT_BIG(*)
                        FROM dbo.KhachHang kh
                        WHERE (@Status = 'ALL' OR kh.DangHoatDong = CASE WHEN @Status = 'ACTIVE' THEN 1 ELSE 0 END)
                          AND (@Type IS NULL OR kh.LoaiKhachHang = @Type)
                          AND (
                              @Keyword IS NULL
                              OR kh.HoTen LIKE '%' + @Keyword + '%'
                              OR kh.SoDienThoai LIKE '%' + @Keyword + '%'
                              OR kh.KyHieuKhachHang LIKE '%' + @Keyword + '%'
                          )
                    ) AS totalItems,
                    JSON_QUERY(COALESCE((
                        SELECT
                            kh.MaKhachHang AS id,
                            kh.KyHieuKhachHang AS customerCode,
                            kh.HoTen AS fullName,
                            kh.SoDienThoai AS phone,
                            kh.Email AS email,
                            kh.LoaiKhachHang AS type,
                            kh.DangHoatDong AS isActive,
                            CONVERT(VARBINARY(8), kh.PhienBan) AS version
                        FROM dbo.KhachHang kh
                        WHERE (@Status = 'ALL' OR kh.DangHoatDong = CASE WHEN @Status = 'ACTIVE' THEN 1 ELSE 0 END)
                          AND (@Type IS NULL OR kh.LoaiKhachHang = @Type)
                          AND (
                              @Keyword IS NULL
                              OR kh.HoTen LIKE '%' + @Keyword + '%'
                              OR kh.SoDienThoai LIKE '%' + @Keyword + '%'
                              OR kh.KyHieuKhachHang LIKE '%' + @Keyword + '%'
                          )
                        ORDER BY kh.HoTen, kh.MaKhachHang
                        OFFSET @Offset ROWS
                        FETCH NEXT @PageSize ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;

        command.Parameters.Add("@Page", SqlDbType.Int).Value = page;
        command.Parameters.Add("@Type", SqlDbType.VarChar, 20).Value = (object?)type ?? DBNull.Value;
        command.Parameters.Add("@Status", SqlDbType.VarChar, 10).Value = status;
        command.Parameters.Add("@PageSize", SqlDbType.Int).Value = pageSize;
        command.Parameters.Add("@Offset", SqlDbType.Int).Value =
            (page - 1) * pageSize;

        var json = (string)(await command.ExecuteScalarAsync())!;

        return Content(json, "application/json");
    }

    [HttpGet("customers/{id:long}/addresses")]
    public async Task<IActionResult> GetAddresses(long id)
    {
        if (id <= 0)
            return BadRequest(new
            {
                message = "Mã khách hàng phải lớn hơn 0."
            });

        await using var connection = CreateConnection();
        await connection.OpenAsync();

        if (await GetScope(connection) is null)
            return Forbid();

        const string sql = """
            SELECT (
                SELECT
                    kh.MaKhachHang AS customerId,
                    kh.HoTen AS customerName,
                    JSON_QUERY(COALESCE((
                        SELECT
                            dc.MaDiaChiKhachHang AS id,
                            dc.NhanDiaChi AS label,
                            COALESCE(dc.TenNguoiLienHe, kh.HoTen)
                                AS contactName,
                            COALESCE(dc.SoDienThoaiLienHe, kh.SoDienThoai)
                                AS phone,
                            dc.DiaChi AS address,
                            dc.MaKhuVuc AS areaId,
                            dc.ViDo AS latitude,
                            dc.KinhDo AS longitude,
                            dc.LaMacDinh AS isDefault,
                            CONVERT(VARBINARY(8), dc.PhienBan) AS version
                        FROM dbo.DiaChiKhachHang dc
                        WHERE dc.MaKhachHang = kh.MaKhachHang
                          AND dc.DangHoatDong = 1
                        ORDER BY dc.LaMacDinh DESC,
                                 dc.MaDiaChiKhachHang
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS addresses
                FROM dbo.KhachHang kh
                WHERE kh.MaKhachHang = @Id
                  AND kh.DangHoatDong = 1
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add("@Id", SqlDbType.BigInt).Value = id;

        var json = await command.ExecuteScalarAsync() as string;

        if (string.IsNullOrWhiteSpace(json))
            return NotFound(new
            {
                message = "Không tìm thấy khách hàng đang hoạt động."
            });

        return Content(json, "application/json");
    }

    [HttpGet("order-form/options")]
    public async Task<IActionResult> GetOptions()
    {
        await using var connection = CreateConnection();
        await connection.OpenAsync();

        var scope = await GetScope(connection);

        if (scope is null)
            return Forbid();

        const string sql = """
            SELECT (
                SELECT
                    JSON_QUERY(COALESCE((
                        SELECT
                            bc.MaBuuCuc AS id,
                            bc.KyHieuBuuCuc AS code,
                            bc.TenBuuCuc AS name,
                            bc.DiaChi AS address,
                            bc.MaKhuVuc AS areaId
                        FROM dbo.BuuCuc bc
                        WHERE bc.DangHoatDong = 1
                          AND (@IsAdmin = 1 OR bc.MaBuuCuc = @BranchId)
                        ORDER BY bc.TenBuuCuc, bc.MaBuuCuc
                        FOR JSON PATH
                    ), N'[]')) AS branches,

                    JSON_QUERY(COALESCE((
                        SELECT
                            dv.MaLoaiDichVu AS id,
                            dv.KyHieuDichVu AS code,
                            dv.TenDichVu AS name
                        FROM dbo.LoaiDichVu dv
                        WHERE dv.DangHoatDong = 1
                        ORDER BY dv.MaLoaiDichVu
                        FOR JSON PATH
                    ), N'[]')) AS services,

                    JSON_QUERY(COALESCE((
                        SELECT
                            kv.MaKhuVuc AS id,
                            kv.KyHieuKhuVuc AS code,
                            kv.TenKhuVuc AS name,
                            kv.MaKhuVucCha AS parentId,
                            kv.LoaiKhuVuc AS type
                        FROM dbo.KhuVuc kv
                        WHERE kv.DangHoatDong = 1
                        ORDER BY kv.MaKhuVuc
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS areas

                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@IsAdmin", SqlDbType.Bit).Value = scope.Value.IsAdmin;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
                (object?)scope.Value.BranchId ?? DBNull.Value;

        var json = (string)(await command.ExecuteScalarAsync())!;

        return Content(json, "application/json");
    }
}
