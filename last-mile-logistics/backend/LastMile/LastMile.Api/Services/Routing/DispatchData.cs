using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Services.Routing;

public sealed class DispatchData(IConfiguration configuration)
{
    // Reject unconfirmed proposals computed under the previous deadline-only policy.
    public const string SchedulePolicy = "DELIVERY_WINDOW_DEFERRED_RETURN_LOAD_V2";
    // One coordinate source and unambiguous ordering for options, depot reads,
    // preview and the transactional re-read during confirmation.
    public const string DepotColumns = "k.ViDo latitude,k.KinhDo longitude";
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public SqlConnection Connection() => new(configuration.GetConnectionString("DefaultConnection"));
    public static SqlCommand Command(SqlConnection connection, SqlTransaction? transaction, string sql, params (string Name, object? Value)[] parameters)
    {
        var command=new SqlCommand(sql,connection,transaction){CommandTimeout=30};
        foreach(var (name,value) in parameters)command.Parameters.AddWithValue(name,value??DBNull.Value);
        return command;
    }
    public sealed record Access(string Role, int? BranchId);
    public static async Task<Access> Authorize(SqlConnection connection, SqlTransaction? transaction, long accountId, string[] permissions, CancellationToken ct, bool any = false)
    {
        await using var command=Command(connection,transaction,"""
            SELECT v.KyHieuVaiTro,t.MaBuuCuc,
              (SELECT COUNT(*) FROM dbo.VaiTroQuyen p JOIN dbo.Quyen q ON q.MaQuyen=p.MaQuyen
               WHERE p.MaVaiTro=t.MaVaiTro AND q.KyHieuQuyen IN (SELECT value FROM OPENJSON(@permissions)))
            FROM dbo.TaiKhoan t WITH(HOLDLOCK) JOIN dbo.VaiTro v WITH(HOLDLOCK) ON v.MaVaiTro=t.MaVaiTro
            WHERE t.MaTaiKhoan=@account AND t.TrangThaiTaiKhoan='ACTIVE' AND v.DangHoatDong=1
              AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=SYSUTCDATETIME());
            """,("@account",accountId),("@permissions",JsonSerializer.Serialize(permissions)));
        await using var reader=await command.ExecuteReaderAsync(ct);
        if(!await reader.ReadAsync(ct))throw new DispatchProblem(401,"Tài khoản không còn hoạt động.");
        string role=reader.GetString(0);int? branch=reader.IsDBNull(1)?null:reader.GetInt32(1);int count=reader.GetInt32(2);
        if(role=="SHIPPER"||(any?count==0:count!=permissions.Length)||role!="ADMIN"&&branch==null)throw new DispatchProblem(403,"Bạn không có quyền thực hiện thao tác điều phối này.");
        return new(role,branch);
    }
    public static async Task EnsureSchema(SqlConnection connection, CancellationToken ct)
    {
        await using var command=Command(connection,null,"SELECT CASE WHEN OBJECT_ID('dbo.DispatchRoutePlan','U') IS NULL OR OBJECT_ID('dbo.TripRouteGeometry','U') IS NULL OR COL_LENGTH('dbo.Kho','ViDo') IS NULL OR COL_LENGTH('dbo.Kho','KinhDo') IS NULL OR COL_LENGTH('dbo.Kho','NguonToaDo') IS NULL THEN 0 ELSE 1 END;");
        if(Convert.ToInt32(await command.ExecuteScalarAsync(ct))!=1)
            throw new DispatchProblem(503,"Chưa chạy migration 20261017_dispatch_planning.sql cho cơ sở dữ liệu này.");
    }
    public async Task<string> Options(long accountId,CancellationToken ct,int? branchId = null)
    {
        await using var connection=Connection();await connection.OpenAsync(ct);await EnsureSchema(connection,ct);
        var access=await Authorize(connection,null,accountId,["DIEUPHOI_GOMDON","DIEUPHOI_PHANCONG","DIEUPHOI_GIAMSAT","DIEUPHOI_TOIUUTUYEN"],ct,true);
        await using var command=Command(connection,null,$$"""
            SELECT (SELECT
                JSON_QUERY(COALESCE((SELECT b.MaBuuCuc id,b.TenBuuCuc name FROM dbo.BuuCuc b WHERE b.DangHoatDong=1 AND (@admin=1 OR b.MaBuuCuc=@branch) ORDER BY b.MaBuuCuc FOR JSON PATH),N'[]')) branches,
                JSON_QUERY(COALESCE((SELECT k.MaKho id,k.KyHieuKho code,k.MaBuuCuc branchId,k.TenKho name,k.DiaChi address,{{DepotColumns}},k.NguonToaDo coordinateSource,
                  CONVERT(BIT,CASE WHEN @admin=1 AND EXISTS(SELECT 1 FROM dbo.TaiKhoan a JOIN dbo.VaiTroQuyen p ON p.MaVaiTro=a.MaVaiTro JOIN dbo.Quyen q ON q.MaQuyen=p.MaQuyen WHERE a.MaTaiKhoan=@account AND q.KyHieuQuyen='BUUCUC_QUANLY') THEN 1 ELSE 0 END) canManageDepot
                  FROM dbo.Kho k JOIN dbo.BuuCuc b ON b.MaBuuCuc=k.MaBuuCuc WHERE k.DangHoatDong=1 AND b.DangHoatDong=1 AND (@admin=1 OR k.MaBuuCuc=@branch) AND (@filterBranch IS NULL OR k.MaBuuCuc=@filterBranch) ORDER BY k.MaKho FOR JSON PATH,INCLUDE_NULL_VALUES),N'[]')) warehouses,
                JSON_QUERY(COALESCE((SELECT DISTINCT a.MaKhuVuc id,a.TenKhuVuc name,p.MaBuuCuc branchId FROM dbo.KhuVuc a JOIN dbo.KhuVucPhucVuBuuCuc p ON p.MaKhuVuc=a.MaKhuVuc
                  WHERE a.DangHoatDong=1 AND (@admin=1 OR p.MaBuuCuc=@branch) FOR JSON PATH),N'[]')) areas,
                JSON_QUERY(COALESCE((SELECT n.MaNhanVienGiaoHang id,t.HoTen name,t.MaBuuCuc branchId,n.TrangThaiSanSang availability,
                    v.MaPhuongTien vehicleId,v.BienSo licensePlate,v.LoaiXe vehicleType,v.KhoiLuongDenKg capacityKg,v.TheTichToiDaM3 capacityM3,
                    held.carriedReturnCount,held.carriedReturnKg,held.carriedReturnM3,
                    CASE WHEN n.DangHoatDong=0 OR t.TrangThaiTaiKhoan<>'ACTIVE' OR r.DangHoatDong=0 OR r.KyHieuVaiTro<>'SHIPPER' OR t.KhoaDenLuc>SYSUTCDATETIME() THEN N'Shipper/tài khoản không hoạt động.'
                      WHEN n.TrangThaiSanSang NOT IN('AVAILABLE','DELIVERING') THEN N'Shipper chưa sẵn sàng.'
                      WHEN n.NgayHetHanBangLai<{{VietnamDate.SqlDate("SYSUTCDATETIME()")}} THEN N'Giấy phép lái xe đã hết hạn.'
                      WHEN v.MaPhuongTien IS NULL THEN N'Chưa được phân phương tiện.'
                      WHEN v.DangHoatDong=0 OR v.TrangThaiPhuongTien NOT IN('AVAILABLE','IN_USE') THEN N'Xe không hoạt động hoặc đang bảo dưỡng.'
                      WHEN EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang pc WHERE pc.ThoiGianKetThuc IS NULL AND (pc.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang OR pc.MaPhuongTien=v.MaPhuongTien))
                        OR EXISTS(SELECT 1 FROM dbo.ChuyenGiaoHang c WHERE c.TrangThaiChuyen NOT IN('COMPLETED','CANCELLED') AND NOT ({{DeferredReturnSql.DeliveryFinishedTrip}}) AND (c.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang OR c.MaPhuongTien=v.MaPhuongTien)) THEN N'Shipper/xe có nhiệm vụ hoặc chuyến chưa kết thúc.' END eligibilityReason,
                    JSON_QUERY((SELECT p.MaKhuVuc id FROM dbo.KhuVucNhanVienGiaoHang p JOIN dbo.KhuVuc a ON a.MaKhuVuc=p.MaKhuVuc AND a.DangHoatDong=1 WHERE p.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang FOR JSON PATH)) areas
                 FROM dbo.NhanVienGiaoHang n JOIN dbo.TaiKhoan t ON t.MaTaiKhoan=n.MaTaiKhoan JOIN dbo.VaiTro r ON r.MaVaiTro=t.MaVaiTro
                 LEFT JOIN dbo.PhanCongPhuongTien p ON p.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang AND p.ThoiGianKetThuc IS NULL LEFT JOIN dbo.PhuongTien v ON v.MaPhuongTien=p.MaPhuongTien
                OUTER APPLY (
                    SELECT COUNT(*) carriedReturnCount,COALESCE(SUM(h.TongKhoiLuongKg),0) carriedReturnKg,
                      CASE WHEN COALESCE(MAX(vol.missing),0)=0 THEN COALESCE(SUM(vol.volume),0) END carriedReturnM3
                    FROM ({{DeferredReturnSql.HeldOrders(false)}}) h
                    OUTER APPLY (SELECT CASE WHEN COUNT(*)=0 OR MAX(CASE WHEN ct.ChieuDaiCm IS NULL OR ct.ChieuRongCm IS NULL OR ct.ChieuCaoCm IS NULL THEN 1 ELSE 0 END)=1 THEN 1 ELSE 0 END missing,
                      SUM(CONVERT(DECIMAL(28,9),ct.SoLuong)*ct.ChieuDaiCm*ct.ChieuRongCm*ct.ChieuCaoCm/1000000.0) volume
                      FROM dbo.ChiTietDonHang ct  WHERE ct.MaDonHang=h.MaDonHang) vol
                    WHERE h.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang OR h.MaPhuongTien=v.MaPhuongTien
                ) held
                 WHERE (@admin=1 OR t.MaBuuCuc=@branch) ORDER BY n.MaNhanVienGiaoHang FOR JSON PATH,INCLUDE_NULL_VALUES),N'[]')) shippers
              FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
            """,("@admin",access.Role=="ADMIN"),("@branch",access.BranchId),("@filterBranch",branchId),("@account",accountId));
        return (string)(await command.ExecuteScalarAsync(ct))!;
    }
    public static async Task<PlanningInput> Load(SqlConnection connection,SqlTransaction transaction,Access access,PlanRequest request,CancellationToken ct)
    {
        if(request.ExistingTripId.HasValue)
        {
            await using var trip=Command(connection,transaction,"""
                SELECT (SELECT c.* FROM dbo.ChuyenGiaoHang c WITH(UPDLOCK,HOLDLOCK)
                WHERE c.MaChuyenGiao=@id AND c.MaKho=@warehouse AND c.TrangThaiChuyen='PLANNED'
                  AND NOT EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang p WITH(UPDLOCK,HOLDLOCK) WHERE p.MaChuyenGiao=c.MaChuyenGiao)
                  AND (SELECT COUNT(*) FROM dbo.ChiTietChuyenGiao ct WITH(UPDLOCK,HOLDLOCK) WHERE ct.MaChuyenGiao=c.MaChuyenGiao)=@count
                  AND NOT EXISTS(SELECT 1 FROM dbo.ChiTietChuyenGiao ct WHERE ct.MaChuyenGiao=c.MaChuyenGiao AND ct.MaDonHang NOT IN(SELECT CONVERT(BIGINT,value) FROM OPENJSON(@orders)))
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
                """,("@id",request.ExistingTripId),("@warehouse",request.WarehouseId),("@orders",JsonSerializer.Serialize(request.OrderIds)),("@count",request.OrderIds.Count));
            if(string.IsNullOrEmpty(await trip.ExecuteScalarAsync(ct) as string))throw new DispatchProblem(409,"Chỉ tính lại chuyến nháp chưa phân công, giữ đầy đủ danh sách đơn. Chuyến đã nhận/đang giao phải dùng đúng nghiệp vụ hiện có.");
            if(request.ShipperIds.Count!=1)throw new DispatchProblem(400,"Chuyến nháp hiện có cần chọn đúng một shipper/xe.");
        }
        await using var command=Command(connection,transaction,$$"""
            SET NOCOUNT ON;
            SELECT (SELECT k.MaKho warehouseId,k.MaBuuCuc branchId,k.TenKho warehouseName,
              JSON_QUERY((SELECT {{DepotColumns}} FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER)) depot,
              k.NguonToaDo depotSource,
              JSON_QUERY((SELECT cg.*,JSON_QUERY((SELECT ct.MaDonHang,ct.ThuTuDuKien FROM dbo.ChiTietChuyenGiao ct WITH(HOLDLOCK) WHERE ct.MaChuyenGiao=cg.MaChuyenGiao ORDER BY ct.ThuTuDuKien FOR JSON PATH)) existingOrders
                FROM dbo.ChuyenGiaoHang cg WITH(HOLDLOCK) WHERE cg.MaChuyenGiao=@existing FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) existingTrip,
              JSON_QUERY((SELECT d.MaDonHang id,d.PhienBan version,d.MaVanDon trackingNumber,g.TenNguoiLienHe receiverName,g.DiaChi address,
                g.MaDiemGiaoNhan pointId,g.MaKhuVuc areaId,d.TongKhoiLuongKg weightKg,
                CASE WHEN vol.countItems>0 AND vol.missing=0 THEN vol.volume END volumeM3,d.MucDoUuTien priority,
                CASE WHEN d.ThoiGianDuKienGiao IS NULL THEN NULL ELSE CONCAT(CONVERT(VARCHAR(33),d.ThoiGianDuKienGiao,126),'Z') END deadline,
                CASE WHEN d.ThoiGianYeuCauGiao IS NULL THEN NULL ELSE CONCAT(CONVERT(VARCHAR(33),d.ThoiGianYeuCauGiao,126),'Z') END requestedDeliveryAt,
                CASE WHEN d.ThoiGianSanSang IS NULL THEN NULL ELSE CONCAT(CONVERT(VARCHAR(33),d.ThoiGianSanSang,126),'Z') END readyAt,
                JSON_QUERY(CASE WHEN g.ViDo IS NULL OR g.KinhDo IS NULL THEN NULL ELSE (SELECT g.ViDo latitude,g.KinhDo longitude FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END) point
                FROM dbo.DonHang d WITH(UPDLOCK,HOLDLOCK) JOIN dbo.TrangThaiDonHang s ON s.MaTrangThaiDonHang=d.MaTrangThaiHienTai
                JOIN dbo.DiemGiaoNhan g WITH(HOLDLOCK) ON g.MaDonHang=d.MaDonHang AND g.LoaiDiem='DELIVERY'
                CROSS APPLY(SELECT COUNT(*) countItems,MAX(CASE WHEN c.ChieuDaiCm IS NULL OR c.ChieuRongCm IS NULL OR c.ChieuCaoCm IS NULL THEN 1 ELSE 0 END) missing,
                  SUM(CONVERT(DECIMAL(28,9),c.SoLuong)*c.ChieuDaiCm*c.ChieuRongCm*c.ChieuCaoCm/1000000.0) volume FROM dbo.ChiTietDonHang c WITH(HOLDLOCK) WHERE c.MaDonHang=d.MaDonHang)vol
                WHERE d.MaDonHang IN(SELECT CONVERT(BIGINT,value) FROM OPENJSON(@orders)) AND d.MaBuuCuc=k.MaBuuCuc AND d.MaKhoHienTai=k.MaKho AND s.KyHieuTrangThai='WAITING_ASSIGNMENT'
                  AND EXISTS(SELECT 1 FROM dbo.TonKhoDonHang t WITH(UPDLOCK,HOLDLOCK) JOIN dbo.ViTriLuuKho v WITH(HOLDLOCK) ON v.MaViTriLuuKho=t.MaViTriLuuKho AND v.MaKho=t.MaKho AND v.DangHoatDong=1 WHERE t.MaDonHang=d.MaDonHang AND t.MaKho=k.MaKho AND t.TrangThaiTonKho='STORED')
                  AND NOT EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang p WITH(UPDLOCK,HOLDLOCK) WHERE p.MaDonHang=d.MaDonHang AND p.ThoiGianKetThuc IS NULL)
                  AND NOT EXISTS(SELECT 1 FROM dbo.ChiTietChuyenGiao ct WITH(UPDLOCK,HOLDLOCK) JOIN dbo.ChuyenGiaoHang cg WITH(UPDLOCK,HOLDLOCK) ON cg.MaChuyenGiao=ct.MaChuyenGiao WHERE ct.MaDonHang=d.MaDonHang AND cg.TrangThaiChuyen NOT IN('COMPLETED','CANCELLED') AND cg.MaChuyenGiao<>COALESCE(@existing,0))
                ORDER BY d.MaDonHang FOR JSON PATH,INCLUDE_NULL_VALUES)) orders,
              JSON_QUERY(COALESCE((SELECT n.MaNhanVienGiaoHang shipperId,t.HoTen shipperName,v.MaPhuongTien vehicleId,v.BienSo licensePlate,v.LoaiXe vehicleType,
                v.KhoiLuongDenKg capacityKg,v.TheTichToiDaM3 capacityM3,
                    held.carriedReturnCount,held.carriedReturnKg,held.carriedReturnM3,
                JSON_QUERY((SELECT p.MaKhuVuc FROM dbo.KhuVucNhanVienGiaoHang p WITH(HOLDLOCK) JOIN dbo.KhuVuc a WITH(HOLDLOCK) ON a.MaKhuVuc=p.MaKhuVuc AND a.DangHoatDong=1
                  JOIN dbo.KhuVucPhucVuBuuCuc bp WITH(HOLDLOCK) ON bp.MaKhuVuc=p.MaKhuVuc AND bp.MaBuuCuc=k.MaBuuCuc WHERE p.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang ORDER BY p.MaKhuVuc FOR JSON PATH)) areaRows,
                n.TrangThaiSanSang availability,n.NgayHetHanBangLai licenseExpiry,n.DangHoatDong shipperActive,t.TrangThaiTaiKhoan accountStatus,t.KhoaDenLuc lockedUntil,r.DangHoatDong roleActive,
                v.TrangThaiPhuongTien vehicleStatus,v.DangHoatDong vehicleActive,
                CASE WHEN n.DangHoatDong=0 OR t.TrangThaiTaiKhoan<>'ACTIVE' OR r.DangHoatDong=0 OR r.KyHieuVaiTro<>'SHIPPER' OR t.KhoaDenLuc>SYSUTCDATETIME() THEN N'Shipper/tài khoản không hoạt động.'
                  WHEN n.TrangThaiSanSang NOT IN('AVAILABLE','DELIVERING') THEN N'Shipper chưa sẵn sàng.'
                  WHEN n.NgayHetHanBangLai<{{VietnamDate.SqlDate("@departure")}} THEN N'Giấy phép lái xe hết hạn trước ngày xuất phát.'
                  WHEN v.DangHoatDong=0 OR v.TrangThaiPhuongTien NOT IN('AVAILABLE','IN_USE') THEN N'Xe không hoạt động hoặc đang bảo dưỡng.'
                  WHEN EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang pc WITH(UPDLOCK,HOLDLOCK) WHERE pc.ThoiGianKetThuc IS NULL AND (pc.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang OR pc.MaPhuongTien=v.MaPhuongTien))
                    OR EXISTS(SELECT 1 FROM dbo.ChuyenGiaoHang c WITH(UPDLOCK,HOLDLOCK) WHERE c.TrangThaiChuyen NOT IN('COMPLETED','CANCELLED') AND NOT ({{DeferredReturnSql.DeliveryFinishedTrip}}) AND (c.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang OR c.MaPhuongTien=v.MaPhuongTien)) THEN N'Shipper/xe có nhiệm vụ hoặc chuyến chưa kết thúc.' END eligibilityReason
                FROM dbo.NhanVienGiaoHang n WITH(UPDLOCK,HOLDLOCK) JOIN dbo.TaiKhoan t WITH(HOLDLOCK) ON t.MaTaiKhoan=n.MaTaiKhoan JOIN dbo.VaiTro r WITH(HOLDLOCK) ON r.MaVaiTro=t.MaVaiTro
                JOIN dbo.PhanCongPhuongTien p WITH(UPDLOCK,HOLDLOCK) ON p.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang AND p.ThoiGianKetThuc IS NULL
                JOIN dbo.PhuongTien v WITH(UPDLOCK,HOLDLOCK) ON v.MaPhuongTien=p.MaPhuongTien
                OUTER APPLY (
                    SELECT COUNT(*) carriedReturnCount,COALESCE(SUM(h.TongKhoiLuongKg),0) carriedReturnKg,
                      CASE WHEN COALESCE(MAX(vol.missing),0)=0 THEN COALESCE(SUM(vol.volume),0) END carriedReturnM3
                    FROM ({{DeferredReturnSql.HeldOrders(true)}}) h
                    OUTER APPLY (SELECT CASE WHEN COUNT(*)=0 OR MAX(CASE WHEN ct.ChieuDaiCm IS NULL OR ct.ChieuRongCm IS NULL OR ct.ChieuCaoCm IS NULL THEN 1 ELSE 0 END)=1 THEN 1 ELSE 0 END missing,
                      SUM(CONVERT(DECIMAL(28,9),ct.SoLuong)*ct.ChieuDaiCm*ct.ChieuRongCm*ct.ChieuCaoCm/1000000.0) volume
                      FROM dbo.ChiTietDonHang ct WITH(UPDLOCK,HOLDLOCK) WHERE ct.MaDonHang=h.MaDonHang) vol
                    WHERE h.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang OR h.MaPhuongTien=v.MaPhuongTien
                ) held
                WHERE n.MaNhanVienGiaoHang IN(SELECT CONVERT(BIGINT,value) FROM OPENJSON(@shippers)) AND t.MaBuuCuc=k.MaBuuCuc
                ORDER BY n.MaNhanVienGiaoHang FOR JSON PATH,INCLUDE_NULL_VALUES),N'[]')) vehicles
              FROM dbo.Kho k WITH(HOLDLOCK) JOIN dbo.BuuCuc b WITH(HOLDLOCK) ON b.MaBuuCuc=k.MaBuuCuc AND b.DangHoatDong=1
              WHERE k.MaKho=@warehouse AND k.DangHoatDong=1 AND (@admin=1 OR k.MaBuuCuc=@branch)
              FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
            """,("@orders",JsonSerializer.Serialize(request.OrderIds.Order())),("@shippers",JsonSerializer.Serialize(request.ShipperIds.Order())),("@warehouse",request.WarehouseId),("@admin",access.Role=="ADMIN"),("@branch",access.BranchId),("@departure",request.DepartureAt.UtcDateTime),("@existing",request.ExistingTripId));
        string? raw=await command.ExecuteScalarAsync(ct) as string;if(string.IsNullOrEmpty(raw))throw new DispatchProblem(404,"Không tìm thấy kho trong phạm vi được phép.");
        using var document=JsonDocument.Parse(raw);var root=document.RootElement;
        var orders=root.GetProperty("orders").Deserialize<PlanningOrder[]>(Json)??[];
        var vehicles=root.GetProperty("vehicles").EnumerateArray().Select(v=>
        {
            var vehicle=v.Deserialize<PlanningVehicle>(Json)!;
            return vehicle with{Areas=v.GetProperty("areaRows").EnumerateArray().Select(a=>a.GetProperty("MaKhuVuc").GetInt32()).ToArray()};
        }).ToArray();
        if(orders.Length!=request.OrderIds.Count)throw new DispatchProblem(409,"Có đơn không còn đủ điều kiện tại kho: trạng thái, tồn kho hoặc chuyến/phân công đã thay đổi. Hãy tải lại hàng chờ.");
        if(vehicles.Length!=request.ShipperIds.Count)throw new DispatchProblem(409,"Có shipper không thuộc bưu cục hoặc chưa có xe được phân hợp lệ.");
        var coordinates=root.GetProperty("depot");
        var lat=coordinates.GetProperty("latitude");var lon=coordinates.GetProperty("longitude");
        double? latitude=lat.ValueKind==JsonValueKind.Null?null:lat.GetDouble(),longitude=lon.ValueKind==JsonValueKind.Null?null:lon.GetDouble();
        var depotState=DepotCoordinates.Check(latitude,longitude);
        if(depotState.State!="CONFIGURED")throw new DispatchProblem(409,depotState.Message);
        var depot=new GeoPoint(latitude!.Value,longitude!.Value);
        return new(request.WarehouseId,root.GetProperty("branchId").GetInt32(),root.GetProperty("warehouseName").GetString()!,depot,orders,vehicles,Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(SchedulePolicy+"\n"+raw))));
    }
}
