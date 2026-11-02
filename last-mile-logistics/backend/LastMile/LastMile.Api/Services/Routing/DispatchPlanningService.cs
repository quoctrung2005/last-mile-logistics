using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using static LastMile.Api.Services.Routing.DispatchData;

namespace LastMile.Api.Services.Routing;

public sealed class DispatchPlanningService(DispatchData data,RoadNetwork network,VrpPlanner planner,ShipperNotifications notifications)
{
    static readonly string[] PreviewPermissions=["DIEUPHOI_GOMDON","DIEUPHOI_TOIUUTUYEN"];
    static readonly string[] ConfirmPermissions=["DIEUPHOI_GOMDON","DIEUPHOI_TOIUUTUYEN","DIEUPHOI_PHANCONG"];
    public static void Validate(PlanRequest request)
    {
        request.Validate();
    }
    public async Task<Proposal> PreviewExistingTrip(long accountId,long tripId,List<long> shipperIds,DateTimeOffset departure,int serviceMinutes,bool returnToDepot,CancellationToken ct)
    {
        PlanRequest request;
        await using(var connection=data.Connection())
        {
            await connection.OpenAsync(ct);await EnsureSchema(connection,ct);
            var access=await Authorize(connection,null,accountId,PreviewPermissions,ct);
            await using var command=Command(connection,null,"""
                SELECT(SELECT c.MaKho warehouseId,JSON_QUERY((SELECT ct.MaDonHang orderId FROM dbo.ChiTietChuyenGiao ct WHERE ct.MaChuyenGiao=c.MaChuyenGiao ORDER BY ct.ThuTuDuKien FOR JSON PATH)) orders
                FROM dbo.ChuyenGiaoHang c WHERE c.MaChuyenGiao=@id AND c.TrangThaiChuyen='PLANNED' AND (@admin=1 OR c.MaBuuCuc=@branch) FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
                """,("@id",tripId),("@admin",access.Role=="ADMIN"),("@branch",access.BranchId));
            string? raw=await command.ExecuteScalarAsync(ct) as string;if(string.IsNullOrEmpty(raw))throw new DispatchProblem(409,"Chỉ tính lại tuyến cho chuyến nháp chưa phân công trong phạm vi của bạn.");
            using var document=JsonDocument.Parse(raw);var root=document.RootElement;
            request=new PlanRequest{WarehouseId=root.GetProperty("warehouseId").GetInt32(),OrderIds=root.GetProperty("orders").EnumerateArray().Select(o=>o.GetProperty("orderId").GetInt64()).ToList(),
                ExistingTripId=tripId,ShipperIds=shipperIds,DepartureAt=departure,ServiceMinutes=serviceMinutes,ReturnToDepot=returnToDepot};
        }
        return await Preview(accountId,request,ct);
    }
    public async Task<Proposal> Preview(long accountId,PlanRequest request,CancellationToken ct)
    {
        Validate(request);request.DepartureAt=request.DepartureAt.ToUniversalTime();
        await using var connection=data.Connection();await connection.OpenAsync(ct);await EnsureSchema(connection,ct);
        PlanningInput input;
        await using(var tx=(SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable,ct))
        {
            var access=await Authorize(connection,tx,accountId,PreviewPermissions,ct);
            input=await Load(connection,tx,access,request,ct);await tx.CommitAsync(ct);
        }
        using var limit=CancellationTokenSource.CreateLinkedTokenSource(ct);limit.CancelAfter(TimeSpan.FromSeconds(20));
        Proposal result;
        try{result=planner.Solve(input,request,network.Graph,network.MaxSnapMeters,limit.Token);}
        catch(OperationCanceledException)when(!ct.IsCancellationRequested){throw new DispatchProblem(422,"Hết thời gian tính 20 giây. Hãy giảm số đơn hoặc số xe và thử lại.");}
        await using var command=Command(connection,null,"""
            INSERT dbo.DispatchRoutePlan(Id,AccountId,WarehouseId,RequestJson,SnapshotHash,GraphVersion,ResultJson,ExpiresAt)
            VALUES(@id,@account,@warehouse,@request,@snapshot,@graph,@result,@expires);
            """,("@id",result.Id),("@account",accountId),("@warehouse",request.WarehouseId),("@request",JsonSerializer.Serialize(request,Json)),("@snapshot",input.Fingerprint),("@graph",result.GraphVersion),("@result",JsonSerializer.Serialize(result,Json)),("@expires",result.ExpiresAt.UtcDateTime));
        await command.ExecuteNonQueryAsync(ct);return result;
    }
    public async Task<string> GetPlan(long accountId,Guid id,CancellationToken ct)
    {
        await using var connection=data.Connection();await connection.OpenAsync(ct);await EnsureSchema(connection,ct);
        var access=await Authorize(connection,null,accountId,PreviewPermissions,ct);
        await using var command=Command(connection,null,"""
            SELECT p.ResultJson FROM dbo.DispatchRoutePlan p JOIN dbo.Kho k ON k.MaKho=p.WarehouseId
            WHERE p.Id=@id AND p.AccountId=@account AND (@admin=1 OR k.MaBuuCuc=@branch);
            """,("@id",id),("@account",accountId),("@admin",access.Role=="ADMIN"),("@branch",access.BranchId));
        return (string?)await command.ExecuteScalarAsync(ct)??throw new DispatchProblem(404,"Không tìm thấy phương án của bạn.");
    }
    public async Task<string> Geometry(long accountId,long tripId,CancellationToken ct)
    {
        await using var connection=data.Connection();await connection.OpenAsync(ct);await EnsureSchema(connection,ct);
        var access=await Authorize(connection,null,accountId,["DIEUPHOI_GIAMSAT"],ct);
        await using var command=Command(connection,null,"""
            SELECT g.RouteJson FROM dbo.ChuyenGiaoHang c LEFT JOIN dbo.TripRouteGeometry g ON g.TripId=c.MaChuyenGiao
            WHERE c.MaChuyenGiao=@trip AND (@admin=1 OR c.MaBuuCuc=@branch);
            """,("@trip",tripId),("@admin",access.Role=="ADMIN"),("@branch",access.BranchId));
        var value=await command.ExecuteScalarAsync(ct);if(value==null)throw new DispatchProblem(404,"Không tìm thấy chuyến trong phạm vi được phép.");
        return value is DBNull?"null":(string)value;
    }
    public async Task<string> Confirm(long accountId,Guid id,CancellationToken ct)
    {
        await using var connection=data.Connection();await connection.OpenAsync(ct);await EnsureSchema(connection,ct);
        await using var tx=(SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        var access=await Authorize(connection,tx,accountId,ConfirmPermissions,ct);
        string requestJson,resultJson,snapshot,graph;DateTime expires;string? confirmed;
        await using(var command=Command(connection,tx,"""
            SELECT p.RequestJson,p.ResultJson,p.SnapshotHash,p.GraphVersion,p.ExpiresAt,p.ConfirmedJson
            FROM dbo.DispatchRoutePlan p WITH(UPDLOCK,HOLDLOCK) JOIN dbo.Kho k WITH(HOLDLOCK) ON k.MaKho=p.WarehouseId
            WHERE p.Id=@id AND p.AccountId=@account AND (@admin=1 OR k.MaBuuCuc=@branch);
            """,("@id",id),("@account",accountId),("@admin",access.Role=="ADMIN"),("@branch",access.BranchId)))
        {
            await using var reader=await command.ExecuteReaderAsync(ct);if(!await reader.ReadAsync(ct))throw new DispatchProblem(404,"Không tìm thấy phương án của bạn.");
            requestJson=reader.GetString(0);resultJson=reader.GetString(1);snapshot=reader.GetString(2);graph=reader.GetString(3);expires=reader.GetDateTime(4);confirmed=reader.IsDBNull(5)?null:reader.GetString(5);
        }
        if(confirmed!=null){await tx.CommitAsync(ct);return confirmed;}
        if(expires<=DateTime.UtcNow)throw new DispatchProblem(409,"Phương án hết hạn sau 15 phút. Hãy tính lại.");
        var request=JsonSerializer.Deserialize<PlanRequest>(requestJson,Json)!;
        if(request.DepartureAt<=DateTimeOffset.UtcNow)throw new DispatchProblem(409,"Thời điểm xuất phát đã qua. Hãy tính lại phương án.");
        // Serialize planning confirmations; other existing assignment APIs are also protected by shared order/vehicle locks and the unique active-assignment index.
        await using(var gate=Command(connection,tx,"""
            DECLARE @r INT;EXEC @r=sys.sp_getapplock @Resource='TVD_DISPATCH_CONFIRM',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
            IF @r<0 THROW 54809,N'Đang có người xác nhận phương án. Hãy thử lại.',1;
            """))await gate.ExecuteNonQueryAsync(ct);
        var input=await Load(connection,tx,access,request,ct);
        if(input.Fingerprint!=snapshot||network.Graph.Version!=graph)throw new DispatchProblem(409,"Đơn, lịch giao, tồn kho, khu vực, xe, lịch nhiệm vụ hoặc quy tắc tính tuyến/mạng đường đã thay đổi. Hãy tính lại phương án.");
        var saved=JsonSerializer.Deserialize<Proposal>(resultJson,Json)!;
        if(saved.Routes.Length==0)throw new DispatchProblem(409,"Phương án chưa có tuyến khả thi để xác nhận.");
        if(request.ExistingTripId.HasValue&&(saved.Unplanned.Length>0||saved.Routes.Length!=1))throw new DispatchProblem(409,"Chuyến nháp phải xếp được toàn bộ đơn vào một tuyến trước khi xác nhận.");
        // Re-evaluate server-stored sequences, service-start windows, waiting and
        // totals with current data; the browser sends only the plan ID. Arrival
        // columns below retain their meaning; all timing fields persist in RouteJson.
        request.ManualRoutes=saved.Routes.Select(r=>new ManualRoute(r.ShipperId,r.Stops.Select(s=>s.OrderId).ToList())).ToList();
        using var limit=CancellationTokenSource.CreateLinkedTokenSource(ct);limit.CancelAfter(TimeSpan.FromSeconds(20));
        Proposal validated;
        try{validated=planner.Solve(input,request,network.Graph,network.MaxSnapMeters,limit.Token);}
        catch(DispatchProblem e){throw new DispatchProblem(409,"Phương án không còn hợp lệ: "+e.Message);}
        catch(OperationCanceledException)when(!ct.IsCancellationRequested){throw new DispatchProblem(409,"Kiểm tra lại phương án quá thời gian. Hãy tính lại với ít đơn hơn.");}
        var trips=new List<object>();
        var createdTripIds=new List<long>();
        foreach(var route in validated.Routes)
        {
            string code="CG-"+id.ToString("N")[..22]+"-"+(trips.Count+1);long tripId;
            if(request.ExistingTripId.HasValue)
            {
                tripId=request.ExistingTripId.Value;
                await using var update=Command(connection,tx,"""
                    UPDATE dbo.ChuyenGiaoHang SET MaNhanVienGiaoHang=@shipper,MaPhuongTien=@vehicle,TrangThaiChuyen='ASSIGNED',PhuongPhapToiUu='VRP',
                      TongQuangDuongKm=@distance,ThoiGianDuKienPhut=@duration,ThoiGianBatDauDuKien=@start
                    WHERE MaChuyenGiao=@trip AND TrangThaiChuyen='PLANNED';
                    SELECT KyHieuChuyenGiao FROM dbo.ChuyenGiaoHang WHERE MaChuyenGiao=@trip;
                    DELETE dbo.DiemDungTuyen WHERE MaChuyenGiao=@trip;DELETE dbo.ChiTietChuyenGiao WHERE MaChuyenGiao=@trip;
                    """,("@trip",tripId),("@shipper",route.ShipperId),("@vehicle",route.VehicleId),("@distance",Math.Round(route.DistanceKm,2)),("@duration",(int)Math.Ceiling(route.DurationMinutes)),("@start",request.DepartureAt.UtcDateTime));
                code=(string)(await update.ExecuteScalarAsync(ct))!;
            }
            else
            {
                await using var insert=Command(connection,tx,"""
                    INSERT dbo.ChuyenGiaoHang(KyHieuChuyenGiao,MaBuuCuc,MaKho,MaNhanVienGiaoHang,MaPhuongTien,TrangThaiChuyen,PhuongPhapToiUu,TongQuangDuongKm,ThoiGianDuKienPhut,ThoiGianBatDauDuKien,MaTaiKhoanTao)
                    VALUES(@code,@branch,@warehouse,@shipper,@vehicle,'ASSIGNED','VRP',@distance,@duration,@start,@account);
                    SELECT CONVERT(BIGINT,SCOPE_IDENTITY());
                    """,("@code",code),("@branch",input.BranchId),("@warehouse",input.WarehouseId),("@shipper",route.ShipperId),("@vehicle",route.VehicleId),("@distance",Math.Round(route.DistanceKm,2)),("@duration",(int)Math.Ceiling(route.DurationMinutes)),("@start",request.DepartureAt.UtcDateTime),("@account",accountId));
                tripId=Convert.ToInt64(await insert.ExecuteScalarAsync(ct));
            }
            int sequence=1;
            await SaveStop(connection,tx,tripId,null,null,sequence++,"BRANCH",input.Depot!,request.DepartureAt,0,0,ct);
            foreach(var stop in route.Stops)
            {
                var order=input.Orders.Single(o=>o.Id==stop.OrderId);
                await using var assign=Command(connection,tx,"""
                    INSERT dbo.ChiTietChuyenGiao(MaChuyenGiao,MaDonHang,ThuTuDuKien,ThoiGianDenDuKien)VALUES(@trip,@order,@sequence,@arrival);
                    INSERT dbo.PhanCongGiaoHang(MaDonHang,MaChuyenGiao,MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,TrangThaiPhanCong,BoQuaQuyTacKhuVuc)
                    VALUES(@order,@trip,@shipper,@vehicle,@account,'PENDING',0);
                    EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@order,@KyHieuTrangThaiMoi='ASSIGNED',@MaTaiKhoan=@account,@LyDo=N'Xác nhận phương án giao hàng.',@NguonCapNhat='API';
                    """,("@trip",tripId),("@order",order.Id),("@sequence",stop.Sequence),("@arrival",stop.ArrivalAt.UtcDateTime),("@shipper",route.ShipperId),("@vehicle",route.VehicleId),("@account",accountId));
                await assign.ExecuteNonQueryAsync(ct);
                await SaveStop(connection,tx,tripId,order.Id,order.PointId,sequence++,"DELIVERY",order.Point!,stop.ArrivalAt,stop.DistanceFromPreviousKm,stop.TravelMinutes,ct);
            }
            if(request.ReturnToDepot){var leg=route.Legs[^1];await SaveStop(connection,tx,tripId,null,null,sequence,"BRANCH",input.Depot!,route.EndAt,leg.DistanceMeters/1000,leg.TravelSeconds/60,ct);}
            await using var geometry=Command(connection,tx,"""
                DELETE dbo.TripRouteGeometry WHERE TripId=@trip;
                INSERT dbo.TripRouteGeometry(TripId,GraphVersion,RouteJson,SettingsJson)VALUES(@trip,@graph,@route,@settings);
                INSERT dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuMoiJson)
                VALUES(@account,'CONFIRM_ROUTE_PLAN','ChuyenGiaoHang',CONVERT(VARCHAR(100),@trip),@route);
                """,("@trip",tripId),("@graph",graph),("@route",JsonSerializer.Serialize(route,Json)),("@settings",requestJson),("@account",accountId));
            await geometry.ExecuteNonQueryAsync(ct);trips.Add(new{id=tripId,tripCode=code,status="ASSIGNED"});createdTripIds.Add(tripId);
        }
        string result=JsonSerializer.Serialize(new{planId=id,trips,message="Đã tạo/phân công chuyến. Shipper cần nhận nhiệm vụ và kho bàn giao theo quy trình hiện có."},Json);
        await using(var save=Command(connection,tx,"UPDATE dbo.DispatchRoutePlan SET ConfirmedJson=@result WHERE Id=@id;",("@result",result),("@id",id)))await save.ExecuteNonQueryAsync(ct);
        await tx.CommitAsync(ct);
        await notifications.TripsCreated(createdTripIds);
        return result;
    }
    static async Task SaveStop(SqlConnection c,SqlTransaction t,long trip,long? order,long? point,int sequence,string type,GeoPoint geo,DateTimeOffset arrival,double km,double minutes,CancellationToken ct)
    {
        await using var command=Command(c,t,"""
            INSERT dbo.DiemDungTuyen(MaChuyenGiao,MaDonHang,MaDiemGiaoNhan,ThuTuDiemDung,LoaiDiem,ViDo,KinhDo,ThoiGianDenDuKien,KhoangCachTuDiemTruocKm,ThoiGianTuDiemTruocPhut)
            VALUES(@trip,@order,@point,@sequence,@type,@lat,@lon,@arrival,@km,@minutes);
            """,("@trip",trip),("@order",order),("@point",point),("@sequence",sequence),("@type",type),("@lat",geo.Latitude),("@lon",geo.Longitude),("@arrival",arrival.UtcDateTime),("@km",Math.Round(km,2)),("@minutes",(int)Math.Ceiling(minutes)));
        await command.ExecuteNonQueryAsync(ct);
    }
}
