using System.Security.Claims;
using LastMile.Api.Services.Routing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace LastMile.Api.Controllers;

// Read-only navigation. Never creates a proposal or changes dispatcher stop order.
[ApiController, Authorize, TypeFilter(typeof(DispatchExceptionFilter))]
[Route("api/v1/my/tasks")]
public sealed class ShipperRouteController(DispatchData data, RoadNetwork network) : ControllerBase
{
    [HttpGet("{id:long}/route")]
    public async Task<IActionResult> RouteToTask(long id, [FromQuery] double? latitude,
        [FromQuery] double? longitude, [FromQuery] bool navigation, CancellationToken ct)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var account)) return Unauthorized();
        if (id <= 0 || latitude.HasValue != longitude.HasValue ||
            latitude.HasValue && !new GeoPoint(latitude.Value, longitude!.Value).IsValid)
            return BadRequest(new { message = "Tọa độ xuất phát hoặc mã nhiệm vụ không hợp lệ." });
        await using var connection = data.Connection();
        await connection.OpenAsync(ct);
        await DispatchData.EnsureSchema(connection, ct);
        await using var command = DispatchData.Command(connection, null, """
            SELECT pc.MaDonHang, tt.KyHieuTrangThai, pt.LoaiXe,
                CASE WHEN tt.KyHieuTrangThai IN ('ASSIGNED','HANDED_OVER') THEN k.ViDo ELSE gn.ViDo END,
                CASE WHEN tt.KyHieuTrangThai IN ('ASSIGNED','HANDED_OVER') THEN k.KinhDo ELSE gn.KinhDo END,
                g.RouteJson, seq.ThuTuDuKien, g.GraphVersion
            FROM dbo.PhanCongGiaoHang pc
            JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang=pc.MaNhanVienGiaoHang
            JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan=nv.MaTaiKhoan
            JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro
            JOIN dbo.DonHang d ON d.MaDonHang=pc.MaDonHang
            JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
            JOIN dbo.PhuongTien pt ON pt.MaPhuongTien=pc.MaPhuongTien
            LEFT JOIN dbo.ChuyenGiaoHang trip ON trip.MaChuyenGiao=pc.MaChuyenGiao
                AND trip.MaNhanVienGiaoHang=pc.MaNhanVienGiaoHang AND trip.MaPhuongTien=pc.MaPhuongTien
                AND trip.TrangThaiChuyen NOT IN ('CANCELLED','COMPLETED')
            LEFT JOIN dbo.Kho k ON k.MaKho=COALESCE(d.MaKhoHienTai,trip.MaKho)
            LEFT JOIN dbo.DiemGiaoNhan gn ON gn.MaDonHang=d.MaDonHang AND gn.LoaiDiem='DELIVERY'
            LEFT JOIN dbo.TripRouteGeometry g ON g.TripId=trip.MaChuyenGiao
            LEFT JOIN dbo.ChiTietChuyenGiao seq ON seq.MaChuyenGiao=trip.MaChuyenGiao AND seq.MaDonHang=d.MaDonHang
            WHERE pc.MaPhanCongGiaoHang=@id AND nv.MaTaiKhoan=@account AND nv.DangHoatDong=1
              AND vt.KyHieuVaiTro='SHIPPER' AND vt.DangHoatDong=1 AND tk.TrangThaiTaiKhoan='ACTIVE'
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc<=SYSUTCDATETIME())
              AND tk.MaBuuCuc=d.MaBuuCuc AND pc.ThoiGianKetThuc IS NULL
              AND EXISTS (SELECT 1 FROM dbo.BuuCuc b WHERE b.MaBuuCuc = tk.MaBuuCuc AND b.DangHoatDong = 1)
              AND EXISTS (SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                  WHERE vq.MaVaiTro = tk.MaVaiTro AND q.KyHieuQuyen = 'NHIEMVU_XEM')
              AND (pc.MaChuyenGiao IS NULL OR trip.MaChuyenGiao IS NOT NULL)
              AND pc.TrangThaiPhanCong IN ('ACCEPTED','IN_PROGRESS')
              AND tt.KyHieuTrangThai IN ('ASSIGNED','HANDED_OVER','PICKED_UP','IN_DELIVERY');
            """, ("@id", id), ("@account", account));
        long order; string status, vehicle; GeoPoint? destination; string? planned, plannedVersion; int? sequence;
        await using (var reader = await command.ExecuteReaderAsync(ct))
        {
            if (!await reader.ReadAsync(ct)) return NotFound(new { code = "TASK_UNAVAILABLE", message = "Nhiệm vụ không còn thuộc bạn hoặc không còn ở bước lấy/giao hàng." });
            order = reader.GetInt64(0); status = reader.GetString(1); vehicle = reader.GetString(2);
            destination = reader.IsDBNull(3) || reader.IsDBNull(4) ? null : new(Convert.ToDouble(reader.GetValue(3)), Convert.ToDouble(reader.GetValue(4)));
            planned = reader.IsDBNull(5) ? null : reader.GetString(5); sequence = reader.IsDBNull(6) ? null : Convert.ToInt32(reader.GetValue(6)); plannedVersion = reader.IsDBNull(7) ? null : reader.GetString(7);
        }
        var pickup = status is "ASSIGNED" or "HANDED_OVER";
        var graph = network.Graph;
        // Use the saved admin leg verbatim; do not send an optimization request.
        if (!navigation && !pickup && planned != null && plannedVersion == graph.Version)
        {
            var savedLeg = DriverRouteGeometry.SavedLeg(planned, order, sequence);
            if (savedLeg != null)
                return Ok(new { assignmentId = id, orderId = order, stage = "DELIVERY", source = "ADMIN_PLAN", leg = savedLeg, stopSequence = sequence });
        }
        if (destination?.IsValid != true) return Conflict(new { code = "DESTINATION_INVALID", message = "Điểm đến chưa có tọa độ hợp lệ. Hãy liên hệ điều phối cập nhật trên trang quản lý." });
        if (!latitude.HasValue) return Conflict(new { code = "ORIGIN_REQUIRED", message = "Hãy bật vị trí để xem tuyến đường từ chỗ bạn đến điểm lấy/giao." });
        var profile = RoadGraph.Profile(vehicle);
        if (profile is null) return Conflict(new { code = "VEHICLE_UNSUPPORTED", message = "Chưa hỗ trợ định tuyến cho loại xe được phân công." });
        var origin = new GeoPoint(latitude.Value, longitude!.Value);
        var leg = graph.FastestRoute(origin, destination, profile, network.MaxSnapMeters, ct);
        if (leg is null)
        {
            if (!graph.CanSnapToRoad(origin, profile, network.MaxSnapMeters))
                return Conflict(new { code = "ORIGIN_NOT_CONNECTED", message = "Vị trí GPS chưa nối được vào mạng đường hiện có. Kiểm tra GPS hoặc mở rộng dữ liệu đường tại vị trí xuất phát." });
            if (!graph.CanSnapToRoad(destination, profile, network.MaxSnapMeters))
                return Conflict(new { code = "DESTINATION_NOT_CONNECTED", message = "Điểm đến chưa nối được vào mạng đường hiện có. Nhờ điều phối kiểm tra tọa độ kho/điểm giao hoặc bổ sung dữ liệu đường." });
            return Conflict(new { code = "NO_DRIVABLE_ROUTE", message = "Hai điểm đã nối vào mạng đường nhưng chưa có tuyến hợp lệ cho xe được phân công. Nhờ điều phối kiểm tra đường một chiều, giới hạn xe và vùng dữ liệu." });
        }
        return Ok(new
        {
            assignmentId = id,
            orderId = order,
            stage = pickup ? "PICKUP" : "DELIVERY",
            source = navigation ? "LIVE_ROAD_GRAPH" : "ROAD_GRAPH",
            optimization = "ESTIMATED_TRAVEL_TIME",
            leg,
            stopSequence = sequence,
            planGeometryOutdated = planned != null && plannedVersion != graph.Version,
            originRoadDistanceMeters = RoadGraph.Meters(origin, leg.Geometry[0]),
            destinationRoadDistanceMeters = RoadGraph.Meters(destination, leg.Geometry[^1])
        });
    }
}
