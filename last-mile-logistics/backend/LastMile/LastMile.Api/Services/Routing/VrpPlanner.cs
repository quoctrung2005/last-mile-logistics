using System.Diagnostics;

namespace LastMile.Api.Services.Routing;

// Heterogeneous capacitated VRP with real earliest/latest service-start times.
// Construction: priority/deadline ordered cheapest feasible insertion across vehicles.
// Improvement: feasible 2-opt within each route and relocation between routes.
public sealed class VrpPlanner
{
    sealed record Evaluation(double Meters, double Seconds, DateTimeOffset End, PlannedStop[] Stops, RoadLeg[] Legs, decimal Weight, decimal? Volume);
    static string? WindowProblem(PlanningOrder order) =>
        order.RequestedDeliveryAt.HasValue&&order.Deadline.HasValue&&order.RequestedDeliveryAt.Value>order.Deadline.Value
            ? "Lịch giao không hợp lệ: giờ bắt đầu giao sớm nhất sau hạn giao. Hãy sửa lịch đơn." : null;
    public Proposal Solve(PlanningInput input, PlanRequest request, RoadGraph graph, double maxSnap, CancellationToken ct)
    {
        var depotState=DepotCoordinates.Check(input.Depot?.Latitude,input.Depot?.Longitude);
        if (depotState.State!="CONFIGURED") throw new DispatchProblem(409,depotState.Message);
        if (input.Depot is null) throw new DispatchProblem(409,depotState.Message);
        var orders = input.Orders.ToDictionary(o => o.Id); var vehicles = input.Vehicles.ToDictionary(v => v.ShipperId);
        var problems = new Dictionary<long, HashSet<string>>(); var warnings = new HashSet<string>
        {
            "Dijkstra tìm đường ngắn nhất theo chiều dài cạnh; thời gian ước tính từ tốc độ OSM và cấu hình theo loại đường, không dùng giao thông trực tiếp.",
            "Mỗi điểm nối vào nút đường gần nhất trong giới hạn cho phép. Quãng đường/thời gian không gồm đoạn tiếp cận từ địa chỉ tới nút; cần dự phòng thời gian giao thực tế.",
            "Khách yêu cầu giao là giờ sớm nhất bắt đầu giao; hạn giao là giờ muộn nhất bắt đầu giao. Đến sớm thì chờ; thời gian phục vụ tính từ lúc bắt đầu giao. Giờ trống giữ nguyên, không tự tạo hạn giao.",
            "Heuristic cheapest insertion + 2-opt + relocation, không bảo đảm tối ưu toàn cục. Xe có nhiệm vụ/chuyến chưa kết thúc được coi là đang bận."
        };
        warnings.Add("Thời gian di chuyển được làm tròn lên từng phút cho mỗi chặng, phù hợp độ chính xác phút của dữ liệu tuyến đã lưu; tổng gồm di chuyển, chờ, phục vụ và quay về kho nếu chọn.");
        if(graph.ExcludedRestrictedWays>0)warnings.Add($"Mạng đường loại bảo thủ {graph.ExcludedRestrictedWays} đoạn có ràng buộc rẽ/điều kiện chưa hỗ trợ; một số điểm có thể không nối được.");
        void Reason(long id, string reason) { if (!problems.TryGetValue(id, out var reasons)) problems[id] = reasons = []; reasons.Add(reason); }
        var points = new List<GeoPoint> { input.Depot }; var indexes = new Dictionary<long, int>();
        foreach(var order in input.Orders)
        {
            if(WindowProblem(order) is { } problem){Reason(order.Id,problem);continue;}
            if(order.Point?.IsValid!=true){Reason(order.Id,"Thiếu tọa độ giao hợp lệ.");continue;}
            indexes[order.Id]=points.Count;points.Add(order.Point);
        }
        var matrices = new Dictionary<string, RoadLeg?[,]>(); var snapped = new Dictionary<string, (long Node,double Distance)?[]>();
        foreach(string profile in input.Vehicles.Where(v=>v.EligibilityReason==null).Select(v=>RoadGraph.Profile(v.VehicleType)).OfType<string>().Distinct())
        {
            ct.ThrowIfCancellationRequested();var snaps=points.Select(p=>graph.Snap(p,profile,maxSnap)).ToArray();snapped[profile]=snaps;
            if(snaps[0]==null){warnings.Add($"Kho không nối được vào mạng đường cho {profile} trong {maxSnap:0}m.");continue;}
            var matrix=new RoadLeg?[points.Count,points.Count];var valid=snaps.Select((v,i)=>(v,i)).Where(x=>x.v!=null).ToArray();
            var cache=new Dictionary<long,RoadLeg?[]>();long[] targets=valid.Select(x=>x.v!.Value.Node).ToArray();
            foreach(var (snap,index) in valid)
            {
                ct.ThrowIfCancellationRequested();long source=snap!.Value.Node;
                if(!cache.TryGetValue(source,out var legs))cache[source]=legs=graph.ShortestPaths(source,targets,profile,ct);
                for(int n=0;n<valid.Length;n++)matrix[index,valid[n].i]=legs[n] is { } leg ? leg with{TravelSeconds=Math.Ceiling(leg.TravelSeconds/60)*60}:null;
            }
            matrices[profile]=matrix;
        }
        Evaluation? Evaluate(PlanningVehicle vehicle,List<long> ids,out string reason)
        {
            reason=vehicle.EligibilityReason??"";if(reason.Length>0)return null;
            string? profile=RoadGraph.Profile(vehicle.VehicleType);if(profile==null){reason="Chưa cấu hình loại xe cho mạng đường.";return null;}
            if(!matrices.TryGetValue(profile,out var matrix)){reason="Kho không kết nối được mạng đường phù hợp với xe.";return null;}
            decimal weight=0,volume=0;bool volumeKnown=true;var stops=new List<PlannedStop>();var legs=new List<RoadLeg>();
            double meters=0,seconds=0;var clock=request.DepartureAt.ToUniversalTime();int previous=0;
            foreach(long id in ids)
            {
                var order=orders[id];
                if(WindowProblem(order) is { } problem){reason=problem;return null;}
                weight+=order.WeightKg;if(order.WeightKg<=0){reason="Khối lượng đơn chưa hợp lệ.";return null;}
                if(order.ReadyAt>request.DepartureAt){reason="Đơn chưa sẵn sàng tại thời điểm xuất phát.";return null;}
                if(weight+vehicle.CarriedReturnKg>vehicle.CapacityKg){reason="Vượt tải trọng xe, gồm cả kiện hoàn đang giữ chờ trả kho.";return null;}
                if(order.AreaId==null||!vehicle.Areas.Contains(order.AreaId.Value)){reason="Shipper không phụ trách khu vực giao của đơn.";return null;}
                if(order.VolumeM3==null)volumeKnown=false;else volume+=order.VolumeM3.Value;
                if(vehicle.CapacityM3!=null&&(!volumeKnown||vehicle.CarriedReturnM3==null||volume+vehicle.CarriedReturnM3>vehicle.CapacityM3)){reason=!volumeKnown||vehicle.CarriedReturnM3==null?"Thiếu kích thước hàng giao/hoàn để kiểm tra sức chứa m³.":"Vượt sức chứa m³ của xe, gồm kiện hoàn đang giữ.";return null;}
                if(!indexes.TryGetValue(id,out int index)){reason="Thiếu tọa độ giao hợp lệ.";return null;}
                if(snapped[profile][index]==null){reason=$"Điểm giao không nối được vào mạng đường trong {maxSnap:0}m.";return null;}
                var leg=matrix[previous,index];if(leg==null){reason="Không tìm được đường theo chiều lưu thông/loại xe.";return null;}
                var arrival=clock.AddSeconds(leg.TravelSeconds);
                var serviceStart=order.RequestedDeliveryAt is { } earliest&&earliest>arrival?earliest.ToUniversalTime():arrival;
                if(order.Deadline.HasValue&&serviceStart>order.Deadline.Value){reason="Không thể bắt đầu giao trong thời hạn giao.";return null;}
                var waiting=serviceStart-arrival;
                var depart=serviceStart.AddMinutes(request.ServiceMinutes);
                stops.Add(new(id,order.TrackingNumber,order.ReceiverName,order.Address,stops.Count+1,order.WeightKg,arrival,depart,
                    leg.DistanceMeters/1000,leg.TravelSeconds/60,order.Point!,snapped[profile][index]!.Value.Distance,
                    serviceStart,waiting.TotalMinutes,order.RequestedDeliveryAt?.ToUniversalTime(),order.Deadline?.ToUniversalTime()));
                meters+=leg.DistanceMeters;seconds+=leg.TravelSeconds+waiting.TotalSeconds+request.ServiceMinutes*60;clock=depart;previous=index;legs.Add(leg);
            }
            if(request.ReturnToDepot&&ids.Count>0){var leg=matrix[previous,0];if(leg==null){reason="Không tìm được đường quay về kho.";return null;}meters+=leg.DistanceMeters;seconds+=leg.TravelSeconds;clock=clock.AddSeconds(leg.TravelSeconds);legs.Add(leg);}
            return new(meters,seconds,clock,stops.ToArray(),legs.ToArray(),weight,volumeKnown?volume:null);
        }
        var routes=input.Vehicles.ToDictionary(v=>v.ShipperId,_=>new List<long>());bool timedOut=false;
        if(request.ManualRoutes!=null)
        {
            var seen=new HashSet<long>();
            foreach(var route in request.ManualRoutes)
            {
                if(!vehicles.ContainsKey(route.ShipperId)||route.OrderIds.Any(id=>!orders.ContainsKey(id)||!seen.Add(id)))throw new DispatchProblem(400,"Phương án thủ công có đơn/shipper ngoài lựa chọn hoặc đơn bị lặp.");
                if(routes[route.ShipperId].Count>0)throw new DispatchProblem(400,"Mỗi shipper chỉ có một tuyến trong phương án.");
                if(Evaluate(vehicles[route.ShipperId],route.OrderIds,out string reason)==null)throw new DispatchProblem(422,"Phương án điều chỉnh chưa hợp lệ: "+reason);
                routes[route.ShipperId]=route.OrderIds.ToList();
            }
            foreach(var order in input.Orders.Where(o=>!seen.Contains(o.Id)))Reason(order.Id,"Chưa đưa vào phương án thủ công.");
        }
        else
        {
            foreach(var order in input.Orders.OrderBy(o=>o.Priority).ThenBy(o=>o.Deadline??DateTimeOffset.MaxValue).ThenByDescending(o=>o.WeightKg).ThenBy(o=>o.Id))
            {
                ct.ThrowIfCancellationRequested();long? bestVehicle=null;List<long>? bestRoute=null;double bestCost=double.PositiveInfinity;
                foreach(var vehicle in input.Vehicles)
                {
                    var current=routes[vehicle.ShipperId];double old=Evaluate(vehicle,current,out _)?.Meters??0;
                    for(int pos=0;pos<=current.Count;pos++)
                    {
                        var trial=current.ToList();trial.Insert(pos,order.Id);var score=Evaluate(vehicle,trial,out string reason);
                        if(score==null){Reason(order.Id,reason);continue;}
                        if(score.Meters-old<bestCost){bestCost=score.Meters-old;bestVehicle=vehicle.ShipperId;bestRoute=trial;}
                    }
                }
                if(bestVehicle.HasValue)routes[bestVehicle.Value]=bestRoute!;else if(input.Vehicles.Length==0)Reason(order.Id,"Chưa chọn shipper/xe hoặc không có xe đủ điều kiện.");
            }
            // Bound improvement independently; always keep the last feasible solution.
            var watch=Stopwatch.StartNew();bool changed=true;int passes=0;
            while(changed&&passes++<8)
            {
                changed=false;
                foreach(var vehicle in input.Vehicles)
                {
                    var current=routes[vehicle.ShipperId];var baseScore=Evaluate(vehicle,current,out _);if(baseScore==null)continue;
                    for(int i=0;i<current.Count-1;i++)for(int j=i+1;j<current.Count;j++)
                    {
                        ct.ThrowIfCancellationRequested();if(watch.ElapsedMilliseconds>2500){timedOut=true;goto Done;}
                        var trial=current.ToList();trial.Reverse(i,j-i+1);var score=Evaluate(vehicle,trial,out _);
                        if(score!=null&&score.Meters+0.01<baseScore.Meters){routes[vehicle.ShipperId]=current=trial;baseScore=score;changed=true;}
                    }
                }
                foreach(var from in input.Vehicles)foreach(var to in input.Vehicles.Where(v=>v.ShipperId!=from.ShipperId))
                {
                    var source=routes[from.ShipperId];var dest=routes[to.ShipperId];var beforeA=Evaluate(from,source,out _);var beforeB=Evaluate(to,dest,out _);if(beforeA==null||beforeB==null)continue;
                    foreach(long id in source.ToArray())for(int pos=0;pos<=dest.Count;pos++)
                    {
                        ct.ThrowIfCancellationRequested();if(watch.ElapsedMilliseconds>2500){timedOut=true;goto Done;}
                        var trialA=source.Where(n=>n!=id).ToList();var trialB=dest.ToList();trialB.Insert(pos,id);var a=Evaluate(from,trialA,out _);var b=Evaluate(to,trialB,out _);
                        if(a!=null&&b!=null&&a.Meters+b.Meters+0.01<beforeA.Meters+beforeB.Meters){routes[from.ShipperId]=source=trialA;routes[to.ShipperId]=dest=trialB;beforeA=a;beforeB=b;changed=true;break;}
                    }
                }
            }
        }
        Done:
        var result=new List<ProposedRoute>();var assigned=new HashSet<long>();
        foreach(var vehicle in input.Vehicles)
        {
            var ids=routes[vehicle.ShipperId];if(ids.Count==0)continue;var evaluation=Evaluate(vehicle,ids,out string reason)??throw new InvalidOperationException(reason);
            foreach(long id in ids)if(!assigned.Add(id))throw new InvalidOperationException("Đơn xuất hiện nhiều lần.");
            if(vehicle.CapacityM3==null)warnings.Add($"Xe {vehicle.LicensePlate} chưa có giới hạn m³; chỉ xác nhận tải trọng kg, chưa kết luận đủ sức chứa theo thể tích.");
            if(vehicle.CarriedReturnCount>0)warnings.Add($"Xe {vehicle.LicensePlate} còn {vehicle.CarriedReturnCount} kiện hoàn ({vehicle.CarriedReturnKg:0.###} kg) chờ trả kho cuối ca; đã trừ phần tải/sức chứa này khi xếp chuyến mới.");
            result.Add(new(vehicle.ShipperId,vehicle.ShipperName,vehicle.VehicleId,vehicle.LicensePlate,vehicle.VehicleType,evaluation.Weight,vehicle.CapacityKg,evaluation.Volume,vehicle.CapacityM3,evaluation.Meters/1000,evaluation.Seconds/60,evaluation.End,evaluation.Stops,evaluation.Legs,input.Depot,vehicle.CarriedReturnCount,vehicle.CarriedReturnKg,vehicle.CarriedReturnM3));
        }
        return new(Guid.NewGuid(),request.ManualRoutes==null?"CHEAPEST_INSERTION_2OPT_RELOCATE":"MANUAL_VALIDATED","DIJKSTRA",graph.Version,DateTimeOffset.UtcNow.AddMinutes(15),input.Depot,input.WarehouseId,input.WarehouseName,request.DepartureAt.ToUniversalTime(),request.ServiceMinutes,request.ReturnToDepot,result.ToArray(),
            input.Orders.Where(o=>!assigned.Contains(o.Id)).Select(o=>new UnplannedOrder(o.Id,o.TrackingNumber,problems.TryGetValue(o.Id,out var reasons)?string.Join(" ",reasons.Order()):"Không có tuyến khả thi trong lựa chọn hiện tại.")).ToArray(),warnings.ToArray(),timedOut);
    }
}
