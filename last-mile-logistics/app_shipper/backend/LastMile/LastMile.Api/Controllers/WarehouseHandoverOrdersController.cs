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
public class WarehouseHandoverOrdersController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public WarehouseHandoverOrdersController(
        IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("{id:int}/handover-orders")]
    public async Task<IActionResult> GetHandoverOrders(
        int id,
        [FromQuery, StringLength(100)] string? keyword = null,
        [FromQuery, Range(1, long.MaxValue)] long? shipperId = null,
        [FromQuery] bool acceptedOnly = false,
        [FromQuery, Range(1, long.MaxValue)] long? locationId = null,
        [FromQuery, RegularExpression("^(PENDING|ACCEPTED)$")] string? assignmentStatus = null,
        [FromQuery, Range(1, 100000)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 10)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã kho không hợp lệ."
            });
        }

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        keyword = string.IsNullOrWhiteSpace(keyword)
            ? null
            : keyword.Trim();

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @Now DATETIME2(0) = SYSUTCDATETIME(),
                @Role VARCHAR(50),
                @RoleId INT,
                @AccountBranchId INT,
                @WarehouseName NVARCHAR(150),
                @WarehouseBranchId INT;

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
                THROW 51301,
                    N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vtq
                INNER JOIN dbo.Quyen q
                    ON q.MaQuyen = vtq.MaQuyen
                WHERE vtq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen = 'KHO_XEM'
            )
                THROW 51302,
                    N'Bạn không có quyền xem dữ liệu kho.',
                    1;

            IF @Role <> 'ADMIN'
               AND @AccountBranchId IS NULL
                THROW 51302,
                    N'Tài khoản chưa được gán bưu cục.',
                    1;

            SELECT
                @WarehouseName = k.TenKho,
                @WarehouseBranchId = k.MaBuuCuc
            FROM dbo.Kho k
            INNER JOIN dbo.BuuCuc b
                ON b.MaBuuCuc = k.MaBuuCuc
            WHERE k.MaKho = @WarehouseId
              AND k.DangHoatDong = 1
              AND b.DangHoatDong = 1
              AND (
                  @Role = 'ADMIN'
                  OR k.MaBuuCuc = @AccountBranchId
              );

            IF @WarehouseBranchId IS NULL
                THROW 51303,
                    N'Không tìm thấy kho đang hoạt động trong phạm vi được phép.',
                    1;

            SELECT
                d.MaDonHang AS orderId,
                d.PhienBan AS version,
                d.KyHieuDonHang AS orderCode,
                d.MaVanDon AS trackingNumber,
                d.MaBuuCuc AS branchId,
                tt.KyHieuTrangThai AS orderStatus,
                d.TongKhoiLuongKg AS weightKg,
                d.TienCOD AS codAmount,
                t.TrangThaiTonKho AS stockStatus,
                t.MaViTriLuuKho AS locationId,
                v.KyHieuViTri AS locationCode,
                gn.TenNguoiLienHe AS receiverName,
                gn.SoDienThoaiLienHe AS receiverPhone,
                gn.DiaChi AS deliveryAddress,
                pc.MaPhanCongGiaoHang AS assignmentId,
                pc.TrangThaiPhanCong AS assignmentStatus,
                pc.MaNhanVienGiaoHang AS shipperId,
                nv.MaNhanVien AS employeeCode,
                tk.HoTen AS shipperName,
                tk.SoDienThoai AS shipperPhone,
                pc.MaPhuongTien AS vehicleId,
                pt.LoaiXe AS vehicleType,
                pt.BienSo AS licensePlate,
                pc.MaChuyenGiao AS tripId,
                pc.ThoiGianPhanCong AS assignedAt,
                pc.ThoiGianChapNhan AS acceptedAt,
                CAST(
                    CASE
                        WHEN pc.TrangThaiPhanCong = 'ACCEPTED'
                         AND nv.DangHoatDong = 1
                         AND nv.TrangThaiSanSang IN (
                             'AVAILABLE', 'DELIVERING'
                         )
                         AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                         AND (
                             tk.KhoaDenLuc IS NULL
                             OR tk.KhoaDenLuc <= @Now
                         )
                         AND vt.KyHieuVaiTro = 'SHIPPER'
                         AND vt.DangHoatDong = 1
                         AND tk.MaBuuCuc = @WarehouseBranchId
                         AND (
                             nv.NgayHetHanBangLai IS NULL
                             OR nv.NgayHetHanBangLai >=
                                CAST(@Now AS DATE)
                         )
                         AND pt.DangHoatDong = 1
                         AND pt.TrangThaiPhuongTien IN (
                             'AVAILABLE', 'IN_USE'
                         )
                         AND pt.KhoiLuongDenKg IS NOT NULL
                         AND (vehicleLoad.totalWeight IS NULL
                              OR vehicleLoad.totalWeight <= pt.KhoiLuongDenKg)
                         AND (pt.TheTichToiDaM3 IS NULL
                              OR (vehicleVolume.missingDimensions = 0
                                  AND vehicleVolume.totalVolume <= pt.TheTichToiDaM3))
                         AND EXISTS (
                             SELECT 1
                             FROM dbo.PhanCongPhuongTien pcp
                             WHERE pcp.MaNhanVienGiaoHang =
                                   pc.MaNhanVienGiaoHang
                               AND pcp.MaPhuongTien =
                                   pc.MaPhuongTien
                               AND pcp.ThoiGianKetThuc IS NULL
                         )
                        THEN 1
                        ELSE 0
                    END
                    AS BIT
                ) AS canHandover
            INTO #HandoverOrders
            FROM dbo.DonHang d
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            INNER JOIN dbo.TonKhoDonHang t
                ON t.MaDonHang = d.MaDonHang
               AND t.MaKho = d.MaKhoHienTai
            INNER JOIN dbo.ViTriLuuKho v
                ON v.MaViTriLuuKho = t.MaViTriLuuKho
               AND v.MaKho = t.MaKho
            INNER JOIN dbo.PhanCongGiaoHang pc
                ON pc.MaDonHang = d.MaDonHang
               AND pc.ThoiGianKetThuc IS NULL
            INNER JOIN dbo.NhanVienGiaoHang nv
                ON nv.MaNhanVienGiaoHang =
                   pc.MaNhanVienGiaoHang
            INNER JOIN dbo.TaiKhoan tk
                ON tk.MaTaiKhoan = nv.MaTaiKhoan
            INNER JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            INNER JOIN dbo.DiemGiaoNhan gn
                ON gn.MaDonHang = d.MaDonHang
               AND gn.LoaiDiem = 'DELIVERY'
            LEFT JOIN dbo.PhuongTien pt
                ON pt.MaPhuongTien = pc.MaPhuongTien
            -- Same capacity checks as outbound; this is only a read-time hint.
            -- Outbound still rechecks all conditions under transaction locks.
            OUTER APPLY (
                SELECT SUM(loadOrder.TongKhoiLuongKg) AS totalWeight
                FROM dbo.PhanCongGiaoHang loadAssignment
                INNER JOIN dbo.DonHang loadOrder
                    ON loadOrder.MaDonHang = loadAssignment.MaDonHang
                WHERE loadAssignment.MaPhuongTien = pc.MaPhuongTien
                  AND loadAssignment.ThoiGianKetThuc IS NULL
            ) vehicleLoad
            OUTER APPLY (
                SELECT
                    COALESCE(MAX(CASE
                        WHEN detail.ChieuDaiCm IS NULL
                          OR detail.ChieuRongCm IS NULL
                          OR detail.ChieuCaoCm IS NULL THEN 1 ELSE 0
                    END), 0) AS missingDimensions,
                    COALESCE(SUM(
                        CAST(detail.SoLuong AS DECIMAL(18,6))
                        * detail.ChieuDaiCm * detail.ChieuRongCm
                        * detail.ChieuCaoCm / 1000000.0
                    ), 0) AS totalVolume
                FROM dbo.PhanCongGiaoHang volumeAssignment
                INNER JOIN dbo.ChiTietDonHang detail
                    ON detail.MaDonHang = volumeAssignment.MaDonHang
                WHERE volumeAssignment.MaPhuongTien = pc.MaPhuongTien
                  AND volumeAssignment.ThoiGianKetThuc IS NULL
            ) vehicleVolume
            WHERE d.MaKhoHienTai = @WarehouseId
              AND d.MaBuuCuc = @WarehouseBranchId
              AND tt.KyHieuTrangThai = 'ASSIGNED'
              AND t.TrangThaiTonKho IN ('STORED', 'ALLOCATED')
              AND v.DangHoatDong = 1
              AND pc.TrangThaiPhanCong IN ('PENDING', 'ACCEPTED')
              AND (@LocationId IS NULL OR t.MaViTriLuuKho = @LocationId)
              AND (@AssignmentStatus IS NULL OR pc.TrangThaiPhanCong = @AssignmentStatus)
              AND (
                  @AcceptedOnly = 0
                  OR pc.TrangThaiPhanCong = 'ACCEPTED'
              )
              AND (
                  @ShipperId IS NULL
                  OR pc.MaNhanVienGiaoHang = @ShipperId
              )
              AND (
                  @Keyword IS NULL
                  OR CHARINDEX(@Keyword, d.KyHieuDonHang) > 0
                  OR CHARINDEX(@Keyword, d.MaVanDon) > 0
                  OR CHARINDEX(@Keyword, tk.HoTen) > 0
                  OR CHARINDEX(@Keyword, nv.MaNhanVien) > 0
              );

            SELECT (
                SELECT
                    @WarehouseId AS warehouseId,
                    @WarehouseName AS warehouseName,
                    @Page AS page,
                    @PageSize AS pageSize,
                    (
                        SELECT COUNT_BIG(*)
                        FROM #HandoverOrders
                    ) AS totalItems,
                    JSON_QUERY(COALESCE((
                        SELECT *
                        FROM #HandoverOrders
                        ORDER BY assignedAt, assignmentId
                        OFFSET @Offset ROWS
                        FETCH NEXT @PageSize ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            DROP TABLE #HandoverOrders;
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@WarehouseId", SqlDbType.Int).Value = id;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value =
                (object?)shipperId ?? DBNull.Value;

        command.Parameters.Add(
            "@AcceptedOnly", SqlDbType.Bit).Value = acceptedOnly;

        command.Parameters.Add(
            "@LocationId", SqlDbType.BigInt).Value =
                (object?)locationId ?? DBNull.Value;

        command.Parameters.Add(
            "@AssignmentStatus", SqlDbType.VarChar, 20).Value =
                (object?)assignmentStatus ?? DBNull.Value;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = page;

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
            ex.Number is >= 51301 and <= 51303)
        {
            var statusCode = ex.Number switch
            {
                51301 => StatusCodes.Status401Unauthorized,
                51302 => StatusCodes.Status403Forbidden,
                _ => StatusCodes.Status404NotFound
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
    }
}
