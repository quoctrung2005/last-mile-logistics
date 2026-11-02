using LastMile.Api.Services;
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
public class DispatchShippersController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public DispatchShippersController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("shippers")]
    public async Task<IActionResult> GetShippers(
        [FromQuery, Required, Range(1, long.MaxValue)]
        long? orderId,
        [FromQuery, StringLength(100)]
        string? keyword = null,
        [FromQuery, Range(1, long.MaxValue)] long? vehicleId = null,
        [FromQuery, Range(1, long.MaxValue)] long? assignmentId = null)
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

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        var sql = $$"""
            SET NOCOUNT ON;

            DECLARE
                @Now DATETIME2(0) = SYSUTCDATETIME(),
                @Role VARCHAR(50),
                @RoleId INT,
                @AccountBranchId INT,
                @OrderBranchId INT,
                @DeliveryAreaId INT,
                @OrderStatus VARCHAR(40),
                @OrderWeight DECIMAL(12,3),
                @OrderVolume DECIMAL(28,6),
                @MissingDimensions BIT = 0;

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
                  AND q.KyHieuQuyen = 'DIEUPHOI_PHANCONG'
            )
                THROW 51002,
                    N'Bạn không có quyền phân công giao hàng.',
                    1;

            IF @Role <> 'ADMIN'
               AND @AccountBranchId IS NULL
                THROW 51002,
                    N'Tài khoản chưa được gán bưu cục.',
                    1;

            SELECT
                @OrderBranchId = d.MaBuuCuc,
                @OrderStatus = tt.KyHieuTrangThai,
                @OrderWeight = d.TongKhoiLuongKg
            FROM dbo.DonHang d
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            WHERE d.MaDonHang = @OrderId
              AND (
                  @Role = 'ADMIN'
                  OR d.MaBuuCuc = @AccountBranchId
              );

            IF @OrderBranchId IS NULL
                THROW 51003,
                    N'Không tìm thấy đơn hàng.',
                    1;

            IF @AssignmentId IS NOT NULL AND NOT EXISTS(
                SELECT 1 FROM dbo.PhanCongGiaoHang pc WHERE pc.MaPhanCongGiaoHang=@AssignmentId AND pc.MaDonHang=@OrderId
                AND pc.ThoiGianKetThuc IS NULL AND pc.MaChuyenGiao IS NULL AND pc.TrangThaiPhanCong IN('PENDING','ACCEPTED') AND @OrderStatus='ASSIGNED')
                THROW 51004,N'Phân công không còn được phép đổi người giao.',1;

            IF @OrderStatus <> 'WAITING_ASSIGNMENT' AND @AssignmentId IS NULL
                THROW 51004,
                    N'Đơn phải ở trạng thái WAITING_ASSIGNMENT.',
                    1;

            IF EXISTS (
                SELECT 1
                FROM dbo.PhanCongGiaoHang
                WHERE MaDonHang = @OrderId
                  AND ThoiGianKetThuc IS NULL
                  AND (@AssignmentId IS NULL OR MaPhanCongGiaoHang<>@AssignmentId)
            )
                THROW 51004,
                    N'Đơn đang có phân công chưa kết thúc.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.BuuCuc
                WHERE MaBuuCuc = @OrderBranchId
                  AND DangHoatDong = 1
            )
                THROW 51004,
                    N'Bưu cục của đơn đã ngừng hoạt động.',
                    1;

            SELECT @DeliveryAreaId = gn.MaKhuVuc
            FROM dbo.DiemGiaoNhan gn
            INNER JOIN dbo.KhuVuc kv
                ON kv.MaKhuVuc = gn.MaKhuVuc
               AND kv.DangHoatDong = 1
            WHERE gn.MaDonHang = @OrderId
              AND gn.LoaiDiem = 'DELIVERY';

            IF @DeliveryAreaId IS NULL
                THROW 51005,
                    N'Điểm giao chưa có khu vực hợp lệ để chọn shipper.',
                    1;

            IF @OrderWeight <= 0
                THROW 51004,
                    N'Khối lượng đơn phải lớn hơn 0.',
                    1;

            IF EXISTS (
                SELECT 1
                FROM dbo.ChiTietDonHang
                WHERE MaDonHang = @OrderId
                  AND (
                      ChieuDaiCm IS NULL
                      OR ChieuRongCm IS NULL
                      OR ChieuCaoCm IS NULL
                  )
            )
                SET @MissingDimensions = 1;

            SELECT @OrderVolume = COALESCE(SUM(
                CAST(SoLuong AS DECIMAL(18,6))
                * ChieuDaiCm
                * ChieuRongCm
                * ChieuCaoCm
                / 1000000.0
            ), 0)
            FROM dbo.ChiTietDonHang
            WHERE MaDonHang = @OrderId;

            ;WITH VehicleLoads AS (
                SELECT
                    pc.MaPhuongTien,
                    COUNT_BIG(*) AS activeOrderCount,
                    SUM(d.TongKhoiLuongKg) AS assignedWeightKg,
                    SUM(vol.volumeM3) AS assignedVolumeM3,
                    MAX(vol.missingDimensions) AS missingDimensions
                FROM (
                    SELECT pc.MaPhuongTien,pc.MaDonHang FROM dbo.PhanCongGiaoHang pc
                    WHERE pc.ThoiGianKetThuc IS NULL AND (@AssignmentId IS NULL OR pc.MaPhanCongGiaoHang<>@AssignmentId)
                    UNION
                    SELECT held.MaPhuongTien,held.MaDonHang FROM ({{DeferredReturnSql.HeldOrders(false)}}) held
                ) pc
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = pc.MaDonHang
                OUTER APPLY (
                    SELECT
                        COALESCE(SUM(
                            CAST(ct.SoLuong AS DECIMAL(18,6))
                            * ct.ChieuDaiCm
                            * ct.ChieuRongCm
                            * ct.ChieuCaoCm
                            / 1000000.0
                        ), 0) AS volumeM3,
                        COALESCE(MAX(
                            CASE
                                WHEN ct.ChieuDaiCm IS NULL
                                  OR ct.ChieuRongCm IS NULL
                                  OR ct.ChieuCaoCm IS NULL
                                THEN 1
                                ELSE 0
                            END
                        ), 0) AS missingDimensions
                    FROM dbo.ChiTietDonHang ct
                    WHERE ct.MaDonHang = d.MaDonHang
                ) vol
                WHERE pc.MaPhuongTien IS NOT NULL
                GROUP BY pc.MaPhuongTien
            )
            SELECT
                nv.MaNhanVienGiaoHang AS id,
                nv.MaNhanVien AS employeeCode,
                tk.HoTen AS fullName,
                tk.SoDienThoai AS phone,
                tk.MaBuuCuc AS branchId,
                nv.TrangThaiSanSang AS availability,
                nv.ViDoHienTai AS latitude,
                nv.KinhDoHienTai AS longitude,
                nv.ThoiGianCapNhatViTri AS locationUpdatedAt,
                pt.MaPhuongTien AS vehicleId,
                pt.BienSo AS licensePlate,
                pt.LoaiXe AS vehicleType,
                pt.KhoiLuongDenKg AS maxWeightKg,
                pt.TheTichToiDaM3 AS maxVolumeM3,
                COALESCE(loads.activeOrderCount, 0)
                    AS activeOrderCount,
                COALESCE(loads.assignedWeightKg, 0)
                    AS assignedWeightKg,
                pt.KhoiLuongDenKg
                    - COALESCE(loads.assignedWeightKg, 0)
                    AS remainingWeightKg,
                CASE
                    WHEN pt.DangHoatDong = 0 OR pt.TrangThaiPhuongTien NOT IN ('AVAILABLE', 'IN_USE')
                        THEN N'Xe ngừng sử dụng hoặc không ở trạng thái cho phép nhận phân công.'
                    WHEN COALESCE(loads.assignedWeightKg, 0) + @OrderWeight > pt.KhoiLuongDenKg
                        THEN N'Tổng khối lượng các đơn đang phân công cộng đơn mới vượt tải trọng thực tế đã lưu của xe.'
                    WHEN pt.TheTichToiDaM3 IS NOT NULL AND (@MissingDimensions = 1 OR COALESCE(loads.missingDimensions, 0) = 1)
                        THEN N'Chưa đủ kích thước hàng để kiểm tra sức chứa m³ của xe.'
                    WHEN pt.TheTichToiDaM3 IS NOT NULL AND COALESCE(loads.assignedVolumeM3, 0) + @OrderVolume > pt.TheTichToiDaM3
                        THEN N'Tổng thể tích các đơn đang phân công cộng đơn mới vượt sức chứa thực tế đã lưu của xe.'
                END AS eligibilityReason
            INTO #Candidates
            FROM dbo.NhanVienGiaoHang nv
            INNER JOIN dbo.TaiKhoan tk
                ON tk.MaTaiKhoan = nv.MaTaiKhoan
            INNER JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            INNER JOIN dbo.PhanCongPhuongTien pcp
                ON pcp.MaNhanVienGiaoHang =
                   nv.MaNhanVienGiaoHang
               AND pcp.ThoiGianKetThuc IS NULL
            INNER JOIN dbo.PhuongTien pt
                ON pt.MaPhuongTien = pcp.MaPhuongTien
            LEFT JOIN VehicleLoads loads
                ON loads.MaPhuongTien = pt.MaPhuongTien
            WHERE nv.DangHoatDong = 1
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
              AND tk.MaBuuCuc = @OrderBranchId
              AND (@VehicleId IS NULL OR pt.MaPhuongTien = @VehicleId)
              AND (
                  nv.NgayHetHanBangLai IS NULL
                  OR nv.NgayHetHanBangLai >= {{VietnamDate.SqlDate("@Now")}}
              )
              AND EXISTS (
                  SELECT 1
                  FROM dbo.KhuVucNhanVienGiaoHang kvnv
                  WHERE kvnv.MaNhanVienGiaoHang =
                        nv.MaNhanVienGiaoHang
                    AND kvnv.MaKhuVuc = @DeliveryAreaId
              )
              AND (
                  @Keyword IS NULL
                  OR CHARINDEX(@Keyword, nv.MaNhanVien) > 0
                  OR CHARINDEX(@Keyword, tk.HoTen) > 0
                  OR CHARINDEX(@Keyword, tk.SoDienThoai) > 0
              )
              ;

            SELECT (
                SELECT
                    @OrderId AS orderId,
                    @OrderBranchId AS branchId,
                    @DeliveryAreaId AS deliveryAreaId,
                    @OrderWeight AS orderWeightKg,
                    (
                        SELECT COUNT_BIG(*)
                        FROM #Candidates
                        WHERE eligibilityReason IS NULL
                    ) AS totalItems,
                    JSON_QUERY(COALESCE((
                        SELECT *
                        FROM #Candidates
                        WHERE eligibilityReason IS NULL
                        ORDER BY activeOrderCount, id
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS items,
                    JSON_QUERY(COALESCE((
                        SELECT * FROM #Candidates WHERE eligibilityReason IS NOT NULL
                        ORDER BY id FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS excludedVehicles,
                    JSON_QUERY(COALESCE((
                        SELECT nv.MaNhanVienGiaoHang AS id, tk.HoTen AS fullName, reason.eligibilityReason
                        FROM dbo.NhanVienGiaoHang nv
                        JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan=nv.MaTaiKhoan
                        JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro
                        CROSS APPLY (VALUES(CASE
                            WHEN nv.DangHoatDong=0 OR tk.TrangThaiTaiKhoan<>'ACTIVE' OR tk.KhoaDenLuc>@Now
                              OR vt.KyHieuVaiTro<>'SHIPPER' OR vt.DangHoatDong=0
                                THEN N'Shipper/tài khoản không hoạt động hoặc đang bị khóa.'
                            WHEN nv.TrangThaiSanSang NOT IN('AVAILABLE','DELIVERING') THEN N'Shipper chưa sẵn sàng nhận phân công.'
                            WHEN nv.NgayHetHanBangLai<{{VietnamDate.SqlDate("@Now")}} THEN N'Giấy phép lái xe đã hết hạn.'
                            WHEN NOT EXISTS(SELECT 1 FROM dbo.KhuVucNhanVienGiaoHang p WHERE p.MaNhanVienGiaoHang=nv.MaNhanVienGiaoHang AND p.MaKhuVuc=@DeliveryAreaId)
                                THEN N'Shipper không phụ trách khu vực giao của đơn.'
                            WHEN NOT EXISTS(SELECT 1 FROM dbo.PhanCongPhuongTien p WHERE p.MaNhanVienGiaoHang=nv.MaNhanVienGiaoHang AND p.ThoiGianKetThuc IS NULL)
                                THEN N'Shipper chưa được phân phương tiện.'
                        END)) reason(eligibilityReason)
                        WHERE tk.MaBuuCuc=@OrderBranchId AND reason.eligibilityReason IS NOT NULL
                        ORDER BY nv.MaNhanVienGiaoHang FOR JSON PATH
                    ), N'[]')) AS excludedShippers
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            DROP TABLE #Candidates;
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt).Value = orderId!.Value;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;
        command.Parameters.Add("@VehicleId", SqlDbType.BigInt).Value = (object?)vehicleId ?? DBNull.Value;
        command.Parameters.Add("@AssignmentId", SqlDbType.BigInt).Value = (object?)assignmentId ?? DBNull.Value;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 51001 and <= 51005)
        {
            var statusCode = ex.Number switch
            {
                51001 => StatusCodes.Status401Unauthorized,
                51002 => StatusCodes.Status403Forbidden,
                51003 => StatusCodes.Status404NotFound,
                51005 => StatusCodes.Status422UnprocessableEntity,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
    }
}
