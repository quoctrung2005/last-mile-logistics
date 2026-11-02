using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController, Authorize, Route("api/v1/my/trips")]
public sealed class MyTripsController(IConfiguration configuration) : ControllerBase
{
    [HttpGet]
    public Task<IActionResult> List(
        [FromQuery, RegularExpression("^(ACTIVE|HISTORY)$")] string group = "ACTIVE",
        [FromQuery, StringLength(100)] string? keyword = null,
        [FromQuery, Range(1, 100000)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 10,
        [FromQuery] DateOnly? date = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        CancellationToken ct = default)
    {
        DateTime? fromDate = from;
        DateTime? toDate = to;

        if (date.HasValue)
        {
            fromDate = date.Value.ToDateTime(TimeOnly.MinValue);
            toDate = date.Value.AddDays(1).ToDateTime(TimeOnly.MinValue);
        }

        return Read(null, group, keyword, page, pageSize, fromDate, toDate, ct);
    }

    [HttpGet("{id:long}")]
    public Task<IActionResult> Detail(long id, CancellationToken ct) =>
        id <= 0
            ? Task.FromResult<IActionResult>(BadRequest(new { message = "Mã chuyến không hợp lệ." }))
            : Read(id, "ACTIVE", null, 1, 1, null, null, ct);

    private async Task<IActionResult> Read(
        long? id,
        string group,
        string? keyword,
        int page,
        int pageSize,
        DateTime? fromDate,
        DateTime? toDate,
        CancellationToken ct)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var account)) return Unauthorized();
        await using var connection = new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
        await connection.OpenAsync(ct);
        await using var command = new SqlCommand(Sql, connection) { CommandTimeout = 30 };
        command.Parameters.Add("@Account", SqlDbType.BigInt).Value = account;
        command.Parameters.Add("@Id", SqlDbType.BigInt).Value = (object?)id ?? DBNull.Value;
        command.Parameters.Add("@Group", SqlDbType.VarChar, 10).Value = group;
        command.Parameters.Add("@Keyword", SqlDbType.NVarChar, 100).Value = string.IsNullOrWhiteSpace(keyword) ? DBNull.Value : keyword.Trim();
        command.Parameters.Add("@Page", SqlDbType.Int).Value = page;
        command.Parameters.Add("@Size", SqlDbType.Int).Value = pageSize;
        command.Parameters.Add("@FromDate", SqlDbType.DateTime2).Value = (object?)fromDate ?? DBNull.Value;
        command.Parameters.Add("@ToDate", SqlDbType.DateTime2).Value = (object?)toDate ?? DBNull.Value;
        try
        {
            var json = (string?)await command.ExecuteScalarAsync(ct);
            Response.Headers.CacheControl = "no-store";
            return Content(json ?? "{}", "application/json");
        }
        catch (SqlException e) when (e.Number is >= 56001 and <= 56003)
        {
            return StatusCode(e.Number == 56001 ? 401 : e.Number == 56002 ? 403 : 404, new { message = e.Message });
        }
    }

    private static string Sql => $$"""
        SET NOCOUNT ON;
        DECLARE @Now DATETIME2(0)=SYSUTCDATETIME(),@Role VARCHAR(50),@RoleId INT,@Branch INT,@Shipper BIGINT;
        SELECT @Role=v.KyHieuVaiTro,@RoleId=t.MaVaiTro,@Branch=t.MaBuuCuc
        FROM dbo.TaiKhoan t JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro
        WHERE t.MaTaiKhoan=@Account AND t.TrangThaiTaiKhoan='ACTIVE' AND v.DangHoatDong=1
          AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=@Now);
        IF @Role IS NULL THROW 56001,N'Tài khoản không còn hoạt động.',1;
        IF @Role<>'SHIPPER' OR NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen
          WHERE vq.MaVaiTro=@RoleId AND q.KyHieuQuyen='NHIEMVU_XEM')
            THROW 56002,N'Chức năng dành cho tài xế xem chuyến của mình.',1;
        SELECT @Shipper=MaNhanVienGiaoHang FROM dbo.NhanVienGiaoHang WHERE MaTaiKhoan=@Account AND DangHoatDong=1;
        IF @Shipper IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.BuuCuc WHERE MaBuuCuc=@Branch AND DangHoatDong=1)
            THROW 56002,N'Hồ sơ tài xế hoặc bưu cục không còn hoạt động.',1;
        SELECT c.MaChuyenGiao id,c.KyHieuChuyenGiao tripCode,c.MaNhanVienGiaoHang shipperId,c.MaKho warehouseId,k.TenKho warehouseName,
          c.MaPhuongTien vehicleId,v.BienSo licensePlate,c.TrangThaiChuyen status,c.PhuongPhapToiUu optimizationMethod,
          c.TongQuangDuongKm plannedDistanceKm,c.ThoiGianDuKienPhut plannedDurationMinutes,
          c.ThoiGianBatDauDuKien plannedStartAt,c.ThoiGianBatDauThucTe startedAt,c.ThoiGianKetThucThucTe endedAt,c.ThoiGianTao createdAt
        INTO #Mine FROM dbo.ChuyenGiaoHang c JOIN dbo.Kho k ON k.MaKho=c.MaKho AND k.MaBuuCuc=c.MaBuuCuc
          LEFT JOIN dbo.PhuongTien v ON v.MaPhuongTien=c.MaPhuongTien
        WHERE c.MaNhanVienGiaoHang=@Shipper AND c.MaBuuCuc=@Branch
          AND ((@Id IS NOT NULL AND c.MaChuyenGiao=@Id) OR (@Id IS NULL AND
            ((@Group='ACTIVE' AND c.TrangThaiChuyen NOT IN('COMPLETED','CANCELLED')) OR(@Group='HISTORY' AND c.TrangThaiChuyen IN('COMPLETED','CANCELLED')))
            AND (@FromDate IS NULL OR COALESCE(c.ThoiGianKetThucThucTe, c.ThoiGianBatDauThucTe, c.ThoiGianTao) >= @FromDate)
            AND (@ToDate IS NULL OR COALESCE(c.ThoiGianKetThucThucTe, c.ThoiGianBatDauThucTe, c.ThoiGianTao) < @ToDate)
            AND(@Keyword IS NULL OR CHARINDEX(@Keyword,c.KyHieuChuyenGiao)>0 OR CHARINDEX(@Keyword,k.TenKho)>0 OR CHARINDEX(@Keyword,v.BienSo)>0)));
        IF @Id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM #Mine)THROW 56003,N'Không tìm thấy chuyến của bạn trong bưu cục hiện tại.',1;
        SELECT * INTO #Page FROM #Mine ORDER BY CASE status WHEN 'IN_PROGRESS' THEN 0 WHEN 'ACCEPTED' THEN 1 WHEN 'ASSIGNED' THEN 2 ELSE 3 END,
          CASE WHEN @Group='ACTIVE' THEN COALESCE(plannedStartAt,createdAt) END ASC,
          CASE WHEN @Group='HISTORY' THEN COALESCE(endedAt,startedAt,createdAt) END DESC,id DESC OFFSET (CONVERT(BIGINT,@Page)-1)*@Size ROWS FETCH NEXT @Size ROWS ONLY;
        CREATE TABLE #Blocked(OrderId BIGINT PRIMARY KEY);
        IF OBJECT_ID(N'dbo.ShipperPickupIssue',N'U') IS NOT NULL
            EXEC(N'INSERT #Blocked SELECT OrderId FROM dbo.ShipperPickupIssue WHERE ClosedAt IS NULL;');
        SELECT c.id tripId,ct.MaDonHang orderId,ct.ThuTuDuKien sequence,d.KyHieuDonHang orderCode,
          CASE WHEN owned.value=1 THEN p.MaPhanCongGiaoHang END assignmentId,
          CASE WHEN owned.value=1 THEN p.TrangThaiPhanCong END assignmentStatus,
          CASE WHEN owned.value=1 THEN s.KyHieuTrangThai END orderStatus,
          CASE WHEN owned.value=1 THEN g.TenNguoiLienHe END receiverName,
          CASE WHEN owned.value=1 THEN g.DiaChi END deliveryAddress,
          ct.ThoiGianDenDuKien plannedArrivalAt,
          CASE WHEN owned.value=1 THEN lg.ThoiGianThuGiao END lastAttemptAt,
          CASE WHEN owned.value=1 THEN lg.KetQua END lastAttemptResult,
          CASE WHEN owned.value=1 THEN p.ThoiGianChapNhan END acceptedAt,
          CONVERT(BIT,CASE WHEN owned.value=1 AND b.OrderId IS NOT NULL THEN 1 ELSE 0 END) pickupBlocked,
          stage.value stage,
          CONVERT(BIT,CASE WHEN stage.value IN('DELIVERED','RETURNED','RETURN_PENDING','WITHDRAWN') THEN 1 ELSE 0 END) handled,
          CONVERT(BIT,owned.value) canOpenTask,
          CONVERT(BIT,CASE WHEN owned.value=1 AND c.status NOT IN('COMPLETED','CANCELLED') AND p.ThoiGianKetThuc IS NULL
            AND p.MaPhuongTien=c.vehicleId AND stage.value IN('PICKUP','DELIVERING') AND b.OrderId IS NULL THEN 1 ELSE 0 END) canNavigate
        INTO #Stops FROM #Page c JOIN dbo.ChiTietChuyenGiao ct ON ct.MaChuyenGiao=c.id
          JOIN dbo.DonHang d ON d.MaDonHang=ct.MaDonHang JOIN dbo.TrangThaiDonHang s ON s.MaTrangThaiDonHang=d.MaTrangThaiHienTai
          LEFT JOIN dbo.DiemGiaoNhan g ON g.MaDonHang=d.MaDonHang AND g.LoaiDiem='DELIVERY'
          LEFT JOIN #Blocked b ON b.OrderId=d.MaDonHang
          OUTER APPLY(SELECT TOP(1)pc.* FROM dbo.PhanCongGiaoHang pc WHERE pc.MaChuyenGiao=c.id AND pc.MaDonHang=d.MaDonHang
            AND pc.MaNhanVienGiaoHang=@Shipper ORDER BY pc.MaPhanCongGiaoHang DESC)p
          OUTER APPLY(SELECT TOP(1)pc.MaPhanCongGiaoHang id FROM dbo.PhanCongGiaoHang pc WHERE pc.MaDonHang=d.MaDonHang ORDER BY pc.MaPhanCongGiaoHang DESC)latest
          OUTER APPLY(SELECT TOP(1)l.KetQua,l.ThoiGianThuGiao FROM dbo.LanGiaoHang l WHERE l.MaPhanCongGiaoHang=p.MaPhanCongGiaoHang
            AND l.MaDonHang=d.MaDonHang ORDER BY l.SoLanThu DESC,l.MaLanGiaoHang DESC)lg
          OUTER APPLY(SELECT TOP(1)y.TrangThaiYeuCau FROM dbo.YeuCauGiaoLaiHoacHoan y WHERE y.MaDonHang=d.MaDonHang AND y.LoaiYeuCau='RETURN'
            ORDER BY y.MaYeuCauGiaoLaiHoacHoan DESC)ret
          CROSS APPLY(SELECT CASE WHEN p.MaPhanCongGiaoHang=latest.id AND p.TrangThaiPhanCong NOT IN('REASSIGNED','REJECTED','CANCELLED')
            AND d.MaBuuCuc=@Branch THEN 1 ELSE 0 END value)owned
          CROSS APPLY(SELECT CASE
            WHEN p.MaPhanCongGiaoHang IS NULL THEN 'UNASSIGNED'
            WHEN owned.value=0 OR s.KyHieuTrangThai='CANCELLED' THEN 'WITHDRAWN'
            WHEN p.TrangThaiPhanCong='COMPLETED' AND lg.KetQua='SUCCESS' THEN 'DELIVERED'
            WHEN s.KyHieuTrangThai='RETURNED' AND p.TrangThaiPhanCong='ATTEMPT_FAILED' THEN 'RETURNED'
            WHEN s.KyHieuTrangThai='RETURNING' AND p.TrangThaiPhanCong='ATTEMPT_FAILED' AND ret.TrangThaiYeuCau='IN_PROGRESS' THEN 'RETURN_PENDING'
            WHEN s.KyHieuTrangThai IN('FAILED','RETRY_WAITING','RETURNING') OR p.TrangThaiPhanCong='ATTEMPT_FAILED' THEN 'ISSUE'
            WHEN p.TrangThaiPhanCong='PENDING' AND s.KyHieuTrangThai='ASSIGNED' THEN 'OFFER'
            WHEN p.TrangThaiPhanCong='ACCEPTED' AND s.KyHieuTrangThai IN('ASSIGNED','HANDED_OVER') THEN 'PICKUP'
            WHEN p.TrangThaiPhanCong='IN_PROGRESS' AND s.KyHieuTrangThai IN('PICKED_UP','IN_DELIVERY') THEN 'DELIVERING'
            ELSE 'ISSUE' END value)stage;
        SELECT c.*,
          (SELECT COUNT(*) FROM #Stops s WHERE s.tripId=c.id) stopCount,
          (SELECT COUNT(*) FROM #Stops s WHERE s.tripId=c.id AND s.handled=1) handledCount,
          (SELECT COUNT(*) FROM #Stops s WHERE s.tripId=c.id AND s.stage='DELIVERED') deliveredCount,
          (SELECT COUNT(*) FROM #Stops s WHERE s.tripId=c.id AND s.stage='PICKUP') pickupCount,
          (SELECT COUNT(*) FROM #Stops s WHERE s.tripId=c.id AND s.stage='DELIVERING') deliveringCount,
          (SELECT COUNT(*) FROM #Stops s WHERE s.tripId=c.id AND s.stage='OFFER') offerCount,
          (SELECT COUNT(*) FROM #Stops s WHERE s.tripId=c.id AND s.stage='RETURN_PENDING') pendingReturnCount,
          (SELECT COUNT(*) FROM #Stops s WHERE s.tripId=c.id AND(s.stage IN('ISSUE','UNASSIGNED') OR s.pickupBlocked=1)) attentionCount
        INTO #Overview FROM #Page c;
        IF @Id IS NOT NULL
          SELECT (SELECT @Shipper shipperId,@Now readAt,
            JSON_QUERY((SELECT * FROM #Overview FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER)) trip,
            JSON_QUERY(COALESCE((SELECT * FROM #Stops ORDER BY sequence FOR JSON PATH,INCLUDE_NULL_VALUES),N'[]')) stops
            FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
        ELSE
          SELECT (SELECT @Shipper shipperId,@Now readAt,@Group [group],@Page page,@Size pageSize,(SELECT COUNT(*) FROM #Mine) totalItems,
            (SELECT COUNT(*) FROM dbo.PhanCongGiaoHang p JOIN dbo.DonHang d ON d.MaDonHang=p.MaDonHang
              WHERE p.MaNhanVienGiaoHang=@Shipper AND p.MaChuyenGiao IS NULL AND p.ThoiGianKetThuc IS NULL AND d.MaBuuCuc=@Branch) unplannedTaskCount,
            (SELECT COUNT(*) FROM ({{DeferredReturnSql.HeldOrders(false)}}) held JOIN dbo.DonHang d ON d.MaDonHang=held.MaDonHang
              WHERE held.MaNhanVienGiaoHang=@Shipper AND d.MaBuuCuc=@Branch) heldReturnCount,
            JSON_QUERY((SELECT 
              (SELECT COUNT(*) FROM #Mine) AS totalTrips,
              COALESCE(SUM(plannedDistanceKm), 0) AS totalDistanceKm,
              COALESCE(SUM(plannedDurationMinutes), 0) AS totalDurationMinutes,
              (SELECT COUNT(*) FROM dbo.ChiTietChuyenGiao ct WHERE ct.MaChuyenGiao IN (SELECT id FROM #Mine)) AS totalOrders,
              (SELECT COUNT(*) FROM dbo.LanGiaoHang lg WHERE lg.KetQua='SUCCESS' AND lg.MaPhanCongGiaoHang IN (
                SELECT pc.MaPhanCongGiaoHang FROM dbo.PhanCongGiaoHang pc WHERE pc.MaChuyenGiao IN (SELECT id FROM #Mine)
              )) AS totalDelivered
              FROM #Mine FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS historySummary,
            JSON_QUERY(COALESCE((SELECT * FROM #Overview ORDER BY CASE status WHEN 'IN_PROGRESS' THEN 0 WHEN 'ACCEPTED' THEN 1 WHEN 'ASSIGNED' THEN 2 ELSE 3 END,
              CASE WHEN @Group='ACTIVE' THEN COALESCE(plannedStartAt,createdAt) END ASC,
              CASE WHEN @Group='HISTORY' THEN COALESCE(endedAt,startedAt,createdAt) END DESC,id DESC FOR JSON PATH,INCLUDE_NULL_VALUES),N'[]')) items
            FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
        """;
}
