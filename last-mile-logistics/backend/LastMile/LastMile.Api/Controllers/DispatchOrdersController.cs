using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/dispatch")]
public class DispatchOrdersController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public DispatchOrdersController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("orders")]
    public async Task<IActionResult> GetOrders(
        [FromQuery, StringLength(100)] string? keyword = null,
        [FromQuery, Range(1, int.MaxValue)] int? branchId = null,
        [FromQuery, Range(1, int.MaxValue)] int? warehouseId = null,
        [FromQuery, Range(1, int.MaxValue)] int? areaId = null,
        [FromQuery, Range(1, 5)] int? priority = null,
        [FromQuery] DateOnly? deadlineDate = null,
        [FromQuery, StringLength(1300)] string? ids = null,
        [FromQuery, Range(1, 100000)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 10)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        keyword = string.IsNullOrWhiteSpace(keyword)
            ? null
            : keyword.Trim();

        if (deadlineDate == DateOnly.MaxValue) return BadRequest(new { message = "Ngày thời hạn giao không hợp lệ." });
        long[]? selected = null;
        if (!string.IsNullOrEmpty(ids))
        {
            var parts=ids.Split(',');
            if(parts.Length>60||parts.Any(p=>!long.TryParse(p,out var id)||id<=0))return BadRequest(new{message="Danh sách chọn không hợp lệ hoặc quá 60 đơn."});
            selected=parts.Select(long.Parse).Distinct().ToArray();
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @Role VARCHAR(50),
                @RoleId INT,
                @AccountBranchId INT,
                @Now DATETIME2(0) = SYSUTCDATETIME();

            SELECT
                @Role = vt.KyHieuVaiTro,
                @RoleId = tk.MaVaiTro,
                @AccountBranchId = tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
            INNER JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= @Now
              );

            IF @Role IS NULL
                THROW 51001,
                    N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vtq
                INNER JOIN dbo.Quyen q
                    ON q.MaQuyen = vtq.MaQuyen
                WHERE vtq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen = 'DIEUPHOI_GOMDON'
            )
                THROW 51002,
                    N'Bạn không có quyền xem danh sách đơn chờ điều phối.',
                    1;

            IF @Role <> 'ADMIN'
               AND @AccountBranchId IS NULL
                THROW 51002,
                    N'Tài khoản chưa được gán bưu cục.',
                    1;

            IF @Role <> 'ADMIN'
               AND @BranchId IS NOT NULL
               AND @BranchId <> @AccountBranchId
                THROW 51002,
                    N'Bạn chỉ được xem đơn thuộc bưu cục của mình.',
                    1;

            SELECT
                d.MaDonHang AS id,
                d.PhienBan AS version,
                d.KyHieuDonHang AS orderCode,
                d.MaVanDon AS trackingNumber,
                d.MaBuuCuc AS branchId,
                b.TenBuuCuc AS branchName,
                d.MaKhoHienTai AS warehouseId,
                k.TenKho AS warehouseName,
                t.MaViTriLuuKho AS locationId,
                v.KyHieuViTri AS locationCode,
                ng.HoTen AS senderName,
                gn.TenNguoiLienHe AS receiverName,
                gn.SoDienThoaiLienHe AS receiverPhone,
                gn.DiaChi AS deliveryAddress,
                gn.MaKhuVuc AS deliveryAreaId,
                (SELECT TenKhuVuc FROM dbo.KhuVuc WHERE MaKhuVuc=gn.MaKhuVuc) AS deliveryAreaName,
                CAST(CASE WHEN EXISTS (
                    SELECT 1
                    FROM dbo.KhuVucNhanVienGiaoHang kp
                    JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang = kp.MaNhanVienGiaoHang
                    JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan = nv.MaTaiKhoan
                    WHERE tk.MaBuuCuc = d.MaBuuCuc
                      AND nv.DangHoatDong = 1
                      AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                      AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= @Now)
                      AND kp.MaKhuVuc = gn.MaKhuVuc
                ) THEN 1 ELSE 0 END AS BIT) AS hasEligibleShipper,
                gn.ViDo AS latitude,
                gn.KinhDo AS longitude,
                tt.KyHieuTrangThai AS status,
                tt.TenTrangThai AS statusName,
                d.MucDoUuTien AS priority,
                d.TongKhoiLuongKg AS weightKg,
                d.TienCOD AS codAmount,
                d.PhiVanChuyen AS shippingFee,
                d.ThoiGianSanSang AS readyAt,
                d.ThoiGianDuKienGiao AS expectedDeliveryAt,
                d.ThoiGianYeuCauGiao AS requestedDeliveryAt,
                d.ThoiGianTao AS createdAt
            INTO #EligibleOrders
            FROM dbo.DonHang d
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            INNER JOIN dbo.BuuCuc b
                ON b.MaBuuCuc = d.MaBuuCuc
            INNER JOIN dbo.KhachHang ng
                ON ng.MaKhachHang = d.MaNguoiGui
            INNER JOIN dbo.DiemGiaoNhan gn
                ON gn.MaDonHang = d.MaDonHang
               AND gn.LoaiDiem = 'DELIVERY'
            LEFT JOIN dbo.Kho k
                ON k.MaKho = d.MaKhoHienTai
            LEFT JOIN dbo.TonKhoDonHang t
                ON t.MaDonHang = d.MaDonHang
            LEFT JOIN dbo.ViTriLuuKho v
                ON v.MaViTriLuuKho = t.MaViTriLuuKho
               AND v.MaKho = t.MaKho
            WHERE tt.KyHieuTrangThai = 'WAITING_ASSIGNMENT'
              AND d.TongKhoiLuongKg > 0
              AND (@Ids IS NULL OR d.MaDonHang IN(SELECT CONVERT(BIGINT,value) FROM OPENJSON(@Ids)))
              AND EXISTS(SELECT 1 FROM dbo.KhuVuc a WHERE a.MaKhuVuc=gn.MaKhuVuc AND a.DangHoatDong=1)
              AND (@AreaId IS NULL OR gn.MaKhuVuc=@AreaId)
              AND (@Priority IS NULL OR d.MucDoUuTien=@Priority)
              AND (@DeadlineDate IS NULL OR d.ThoiGianDuKienGiao < DATEADD(HOUR,-7,DATEADD(DAY,1,CAST(@DeadlineDate AS DATETIME2))))
              AND NOT EXISTS (
                SELECT 1
                FROM dbo.ChiTietChuyenGiao ct
                INNER JOIN dbo.ChuyenGiaoHang cg
                    ON cg.MaChuyenGiao = ct.MaChuyenGiao
                WHERE ct.MaDonHang = d.MaDonHang
                  AND cg.TrangThaiChuyen NOT IN ('COMPLETED', 'CANCELLED')
            )
              AND b.DangHoatDong = 1
              AND (
                  @Role = 'ADMIN'
                  OR d.MaBuuCuc = @AccountBranchId
              )
              AND (
                  @BranchId IS NULL
                  OR d.MaBuuCuc = @BranchId
              )
              AND (
                  @WarehouseId IS NULL
                  OR d.MaKhoHienTai = @WarehouseId
              )
              AND (
                  @Keyword IS NULL
                  OR CHARINDEX(@Keyword, d.KyHieuDonHang) > 0
                  OR CHARINDEX(@Keyword, d.MaVanDon) > 0
                  OR CHARINDEX(@Keyword, gn.TenNguoiLienHe) > 0
                  OR CHARINDEX(@Keyword, gn.SoDienThoaiLienHe) > 0
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.PhanCongGiaoHang pc
                  WHERE pc.MaDonHang = d.MaDonHang
                    AND pc.ThoiGianKetThuc IS NULL
              )
              AND (
                  (
                      d.MaKhoHienTai IS NULL
                      AND t.MaDonHang IS NULL
                  )
                  OR
                  (
                      t.MaKho = d.MaKhoHienTai
                      AND k.MaBuuCuc = d.MaBuuCuc
                      AND k.DangHoatDong = 1
                      AND t.TrangThaiTonKho = 'STORED'
                      AND v.DangHoatDong = 1
                  )
              );

            SELECT (
                SELECT
                    @Page AS page,
                    @PageSize AS pageSize,
                    (
                        SELECT COUNT_BIG(*)
                        FROM #EligibleOrders
                    ) AS totalItems,
                    JSON_QUERY(COALESCE((
                        SELECT *
                        FROM #EligibleOrders
                        ORDER BY
                            priority ASC,
                            COALESCE(readyAt, createdAt) ASC,
                            id ASC
                        OFFSET @Offset ROWS
                        FETCH NEXT @PageSize ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ),N'[]')) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            DROP TABLE #EligibleOrders;
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
                (object?)branchId ?? DBNull.Value;

        command.Parameters.Add(
            "@WarehouseId", SqlDbType.Int).Value =
                (object?)warehouseId ?? DBNull.Value;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = page;
        command.Parameters.Add("@AreaId", SqlDbType.Int).Value = (object?)areaId ?? DBNull.Value;
        command.Parameters.Add("@Ids", SqlDbType.NVarChar, -1).Value = selected == null ? DBNull.Value : System.Text.Json.JsonSerializer.Serialize(selected);
        command.Parameters.Add("@Priority", SqlDbType.Int).Value = (object?)priority ?? DBNull.Value;
        command.Parameters.Add("@DeadlineDate", SqlDbType.Date).Value = deadlineDate.HasValue ? deadlineDate.Value.ToDateTime(TimeOnly.MinValue) : DBNull.Value;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value = pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.Int).Value =
                (page - 1) * pageSize;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is 51001 or 51002)
        {
            return StatusCode(
                ex.Number == 51001
                    ? StatusCodes.Status401Unauthorized
                    : StatusCodes.Status403Forbidden,
                new { message = ex.Message });
        }
    }
}
