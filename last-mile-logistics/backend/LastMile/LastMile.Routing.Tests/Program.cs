using System.Text.Json;
using LastMile.Api.Services.Routing;

var checks=new List<string>();
void Assert(bool condition,string message="Assertion failed"){if(!condition)throw new Exception(message);}
void Check(string name,Action action){action();checks.Add(name);Console.WriteLine("PASS "+name);}
var nodes=new Dictionary<long,GeoPoint>{{1,new(10,106)},{2,new(10.001,106)},{3,new(10.002,106)},{4,new(10.002,106.001)},{5,new(11,107)}};
Dictionary<long,List<RoadGraph.Edge>> Edges()=>new(){{1,[new(2,100,10),new(3,500,50)]},{2,[new(3,100,10)]},{3,[new(1,200,20),new(4,50,5)]},{4,[new(1,100,10)]}};
var graph=new RoadGraph(nodes,new(){{"motorcycle",Edges()},{"hgv",new(){{1,[new(3,1000,100)]},{3,[new(1,1000,100)]}}}},"KNOWN_TEST_GRAPH");
var start=DateTimeOffset.UtcNow.AddHours(1);var solver=new VrpPlanner();
PlanningOrder Order(long id,decimal kg=6,int? area=11,decimal? volume=.01m,GeoPoint? point=null,DateTimeOffset? deadline=null)=>new(id,"AAAA","TEST-"+id,"Test contact","Test address",id,area,kg,volume,3,deadline,point??nodes[id]);
PlanningVehicle Vehicle(long id,decimal capacity=10,string type="MOTORBIKE",decimal? volume=1,int[]? areas=null,string? reason=null)=>new(id,"Driver "+id,id,"TEST-"+id,type,capacity,volume,areas??[11],reason);
PlanRequest Request(params long[] ids)=>new(){WarehouseId=1,OrderIds=ids.ToList(),ShipperIds=[1],DepartureAt=start,ReturnToDepot=true,ServiceMinutes=5};
PlanningInput Input(PlanningOrder[] orders,params PlanningVehicle[] vehicles)=>new(1,1,"Test depot",nodes[1],orders,vehicles,"TEST");
Proposal Solve(PlanningInput input,PlanRequest request)=>solver.Solve(input,request,graph,50,CancellationToken.None);

Check("Depot validation distinguishes missing, malformed and unverified coordinates",()=>{
    Assert(DepotCoordinates.Check(null,null).State=="MISSING");
    foreach(var pair in new (double?,double?)[]{(10,null),(null,106),(91,106),(10,181),(double.NaN,106),(0,0)})
        Assert(DepotCoordinates.Check(pair.Item1,pair.Item2).State=="INVALID");
    Assert(DepotCoordinates.Check(10,106,null,true).State=="UNVERIFIED");
    Assert(DepotCoordinates.Check(10,106,"Verified fixture",true).State=="CONFIGURED");
});
Check("A configured depot outside road coverage reports road connectivity, not missing coordinates",()=>{
    var input=Input([Order(3)],Vehicle(1)) with{Depot=new(12,108)};
    var result=Solve(input,Request(3));Assert(result.Routes.Length==0&&result.Unplanned.Single().Reason.Contains("mạng đường"));
    Assert(!result.Unplanned.Single().Reason.Contains("chưa có tọa độ"));
});

Check("Dijkstra chooses the known shortest path and reconstructs every road node",()=>{var leg=graph.ShortestPaths(1,[3],"motorcycle",default)[0]!;Assert(leg.DistanceMeters==200&&leg.TravelSeconds==20&&leg.Geometry.SequenceEqual(new[]{nodes[1],nodes[2],nodes[3]}));});
Check("Directed edges produce asymmetric distances and unreachable targets",()=>{Assert(graph.ShortestPaths(2,[1],"motorcycle",default)[0]!.DistanceMeters==250);Assert(graph.ShortestPaths(1,[5],"motorcycle",default)[0]==null);});
Check("Negative edge weights and invalid graph coordinates are rejected",()=>{try{_ =new RoadGraph(nodes,new(){{"motorcycle",new(){{1,[new(2,-1,1)]}}}},"bad");throw new Exception("Accepted negative edge");}catch(InvalidDataException){}});
Check("One vehicle, feasible capacity, correct total load and exact timing",()=>{var r=Solve(Input([Order(3),Order(4)],Vehicle(1,12)),Request(3,4));Assert(r.Routes.Length==1&&r.Unplanned.Length==0);var route=r.Routes[0];Assert(route.WeightKg==12&&route.DurationMinutes==route.Legs.Sum(l=>l.TravelSeconds)/60+10);var clock=start;foreach(var s in route.Stops){clock=clock.AddMinutes(s.TravelMinutes);Assert(Math.Abs((clock-s.ArrivalAt).TotalMilliseconds)<1);clock=clock.AddMinutes(5);}Assert(Math.Abs((route.EndAt-start).TotalMinutes-route.DurationMinutes)<.0001);});
Check("Multiple vehicles with different payloads respect each real capacity",()=>{var r=Solve(Input([Order(3,8),Order(4,6)],Vehicle(1,8),Vehicle(2,6)),Request(3,4));Assert(r.Routes.Length==2&&r.Routes.All(v=>v.WeightKg<=v.CapacityKg));Assert(r.Routes.SelectMany(v=>v.Stops).Select(s=>s.OrderId).Distinct().Count()==2);});
Check("Orders heavier than every vehicle remain unassigned with a load reason",()=>{var r=Solve(Input([Order(3,99)],Vehicle(1)),Request(3));Assert(r.Routes.Length==0&&r.Unplanned[0].Reason.Contains("tải trọng"));});
Check("Not enough vehicles or no selected shipper is reported without invented routes",()=>{Assert(Solve(Input([Order(3)],[]),Request(3)).Unplanned.Length==1);Assert(Solve(Input([Order(3),Order(4)],Vehicle(1,6)),Request(3,4)).Unplanned.Length==1);});
Check("Real service-area membership is required",()=>{var r=Solve(Input([Order(3,area:12)],Vehicle(1)),Request(3));Assert(r.Unplanned[0].Reason.Contains("khu vực"));});
Check("Impossible deadlines are rejected without inventing a window start",()=>{var r=Solve(Input([Order(3,deadline:start.AddSeconds(5))],Vehicle(1)),Request(3));Assert(r.Unplanned[0].Reason.Contains("thời hạn"));});
Check("Warehouse ready time is checked against departure without becoming a delivery window",()=>{var order=Order(3) with{ReadyAt=start.AddMinutes(1)};var r=Solve(Input([order],Vehicle(1)),Request(3));Assert(r.Unplanned[0].Reason.Contains("chưa sẵn sàng"));});
Check("Unknown parcel dimensions never become zero volume",()=>{var r=Solve(Input([Order(3,volume:null)],Vehicle(1)),Request(3));Assert(r.Unplanned[0].Reason.Contains("kích thước"));var withoutLimit=Solve(Input([Order(3,volume:null)],Vehicle(1,volume:null)),Request(3));Assert(withoutLimit.Routes[0].VolumeM3==null&&withoutLimit.Warnings.Any(w=>w.Contains("chưa kết luận")));});
Check("Vehicle volume limits and unavailable personnel are enforced",()=>{Assert(Solve(Input([Order(3,volume:2)],Vehicle(1)),Request(3)).Unplanned.Length==1);Assert(Solve(Input([Order(3)],Vehicle(1,reason:"Bận nhiệm vụ")),Request(3)).Routes.Length==0);});
Check("Missing/invalid GPS and coordinates outside the graph are explicit",()=>{Assert(Solve(Input([Order(3,point:new(double.NaN,106))],Vehicle(1)),Request(3)).Unplanned[0].Reason.Contains("tọa độ"));Assert(Solve(Input([Order(5)],Vehicle(1)),Request(5)).Unplanned[0].Reason.Contains("mạng đường"));});
Check("Vehicle routing profiles use separate directed road matrices",()=>{var motor=Solve(Input([Order(3)],Vehicle(1)),Request(3));var truck=Solve(Input([Order(3)],Vehicle(1,type:"TRUCK")),Request(3));Assert(motor.Routes[0].DistanceKm==.35&&truck.Routes[0].DistanceKm==2);});
Check("Return-to-depot is explicit and adds a reachable return leg",()=>{var req=Request(3);req.ReturnToDepot=false;var r=Solve(Input([Order(3)],Vehicle(1)),req);Assert(r.Routes[0].Legs.Length==1&&r.Routes[0].DistanceKm==.2);});
Check("Every order is assigned at most once and duplicate manual membership is rejected",()=>{var req=Request(3,4);req.ManualRoutes=[new(1,[3,4]),new(2,[3])];try{Solve(Input([Order(3),Order(4)],Vehicle(1,20),Vehicle(2,20)),req);throw new Exception("Accepted duplicate");}catch(DispatchProblem e){Assert(e.Status==400);}});
Check("Manual and heuristic solutions are compared on exactly the same matrix and constraints",()=>{var input=Input([Order(3),Order(4)],Vehicle(1,20));var automatic=Solve(input,Request(3,4));var req=Request(3,4);req.ManualRoutes=[new(1,[4,3])];var manual=Solve(input,req);Assert(automatic.Routes.Sum(r=>r.DistanceKm)<=manual.Routes.Sum(r=>r.DistanceKm));Assert(automatic.Routes[0].WeightKg==manual.Routes[0].WeightKg);});
// Fixed business clock, independent of OS time. The graph's rounded first leg is
// one minute, so departure 13:49 VN produces arrival exactly 13:50 VN.
var windowDeparture=DateTimeOffset.Parse("2030-10-19T13:49:00+07:00");
var windowStart=DateTimeOffset.Parse("2030-10-19T14:00:00+07:00");
PlanRequest WindowRequest(params long[] ids){var request=Request(ids);request.DepartureAt=windowDeparture;return request;}
Check("Arrival 13:50 VN waits ten minutes, starts 14:00 and departs 14:05",()=>{
    var request=WindowRequest(3);var order=Order(3) with{RequestedDeliveryAt=windowStart,Deadline=windowStart.AddHours(1)};
    var result=Solve(Input([order],Vehicle(1,20)),request);var route=result.Routes.Single();var stop=route.Stops.Single();
    Assert(stop.ArrivalAt==DateTimeOffset.Parse("2030-10-19T13:50:00+07:00")&&stop.ServiceStartAt==windowStart&&stop.WaitingMinutes==10&&stop.DepartureAt==windowStart.AddMinutes(5));
    Assert(route.EndAt==windowStart.AddMinutes(6)&&route.DurationMinutes==17&&route.DurationMinutes==(route.EndAt-request.DepartureAt).TotalMinutes);
    Assert(stop.ArrivalAt.Offset==TimeSpan.Zero&&stop.ServiceStartAt?.Offset==TimeSpan.Zero&&stop.DepartureAt.Offset==TimeSpan.Zero);
});
Check("Arrival 14:10 after an earliest 14:00 starts immediately without waiting",()=>{
    var request=WindowRequest(3);request.DepartureAt=windowStart.AddMinutes(9);
    var stop=Solve(Input([Order(3) with{RequestedDeliveryAt=windowStart}],Vehicle(1)),request).Routes.Single().Stops.Single();
    Assert(stop.ArrivalAt==windowStart.AddMinutes(10)&&stop.ServiceStartAt==stop.ArrivalAt&&stop.WaitingMinutes==0&&stop.DepartureAt==windowStart.AddMinutes(15));
});
Check("Service start exactly at the deadline is feasible even when service finishes later",()=>{
    var request=WindowRequest(3);request.ManualRoutes=[new(1,[3])];
    var stop=Solve(Input([Order(3) with{RequestedDeliveryAt=windowStart,Deadline=windowStart}],Vehicle(1)),request).Routes.Single().Stops.Single();
    Assert(stop.ServiceStartAt==windowStart&&stop.DepartureAt>windowStart);
});
Check("Service start after the deadline is unplanned automatically and rejected manually",()=>{
    var order=Order(3) with{RequestedDeliveryAt=windowStart,Deadline=windowStart.AddMinutes(9)};
    var request=WindowRequest(3);request.DepartureAt=windowStart.AddMinutes(9);
    var result=Solve(Input([order],Vehicle(1)),request);Assert(result.Routes.Length==0&&result.Unplanned.Single().Reason.Contains("bắt đầu giao"));
    request.ManualRoutes=[new(1,[3])];try{Solve(Input([order],Vehicle(1)),request);throw new Exception("Accepted late manual start");}catch(DispatchProblem e){Assert(e.Status==422);}
});
Check("Waiting at the first stop can invalidate a previously feasible next stop",()=>{
    var request=WindowRequest(3,4);request.ManualRoutes=[new(1,[3,4])];
    var first=Order(3) with{RequestedDeliveryAt=windowStart,Deadline=windowStart};var second=Order(4,deadline:windowStart.AddMinutes(-1));
    try{Solve(Input([first,second],Vehicle(1,20)),request);throw new Exception("Ignored waiting before next leg");}catch(DispatchProblem e){Assert(e.Status==422&&e.Message.Contains("thời hạn"));}
    var before=Solve(Input([first with{RequestedDeliveryAt=null},second],Vehicle(1,20)),request);Assert(before.Routes.Single().Stops.Length==2);
});
Check("Cheapest insertion and 2-opt retain the longer sequence required by delivery windows",()=>{
    var request=WindowRequest(3,4);var input=Input([Order(3) with{RequestedDeliveryAt=windowStart,Deadline=windowStart},Order(4,deadline:windowStart.AddMinutes(-1))],Vehicle(1,20));
    var result=Solve(input,request);Assert(result.Unplanned.Length==0&&result.Routes.Single().Stops.Select(s=>s.OrderId).SequenceEqual(new long[]{4,3}));
    var old=Solve(input with{Orders=input.Orders.Select(o=>o with{RequestedDeliveryAt=null,Deadline=null}).ToArray()},request);
    Assert(old.Routes.Single().DistanceKm<result.Routes.Single().DistanceKm);
});
Check("Relocation cannot merge two simultaneous service-start windows into a shorter infeasible route",()=>{
    var request=WindowRequest(3,4);request.ShipperIds=[1,2];
    var result=Solve(Input([Order(3) with{RequestedDeliveryAt=windowStart,Deadline=windowStart},Order(4) with{RequestedDeliveryAt=windowStart,Deadline=windowStart}],Vehicle(1,20),Vehicle(2,20)),request);
    Assert(result.Unplanned.Length==0&&result.Routes.Length==2&&result.Routes.All(r=>r.Stops.Length==1&&r.Stops[0].ServiceStartAt==windowStart));
});
Check("No requested time preserves the previous zero-wait timing and no synthetic deadline",()=>{
    var request=WindowRequest(3,4);var route=Solve(Input([Order(3),Order(4)],Vehicle(1,20)),request).Routes.Single();
    Assert(route.Stops.All(s=>s.ServiceStartAt==s.ArrivalAt&&s.WaitingMinutes==0&&s.RequestedDeliveryAt==null&&s.ExpectedDeliveryAt==null));
    Assert(route.DurationMinutes==route.Legs.Sum(l=>l.TravelSeconds)/60+2*request.ServiceMinutes);
});
Check("A null deadline remains null while an existing requested time still causes waiting",()=>{
    var route=Solve(Input([Order(3) with{RequestedDeliveryAt=windowStart,Deadline=null}],Vehicle(1)),WindowRequest(3)).Routes.Single();
    Assert(route.Stops[0].WaitingMinutes==10&&route.Stops[0].ExpectedDeliveryAt==null);
});
Check("Requested time later than deadline is explicitly invalid in automatic and manual planning",()=>{
    var input=Input([Order(3) with{RequestedDeliveryAt=windowStart,Deadline=windowStart.AddMinutes(-1)}],Vehicle(1));var request=WindowRequest(3);
    var result=Solve(input,request);Assert(result.Routes.Length==0&&result.Unplanned.Single().Reason.Contains("Lịch giao không hợp lệ"));
    request.ManualRoutes=[new(1,[3])];try{Solve(input,request);throw new Exception("Accepted reversed window");}catch(DispatchProblem e){Assert(e.Status==422&&e.Message.Contains("Lịch giao không hợp lệ"));}
});
Check("Invalid delivery windows remain explicit even when no vehicle was selected",()=>{
    var input=Input([Order(3) with{RequestedDeliveryAt=windowStart,Deadline=windowStart.AddMinutes(-1)}],[]);
    Assert(Solve(input,WindowRequest(3)).Unplanned.Single().Reason.Contains("Lịch giao không hợp lệ"));
});
Check("Added stop timing round-trips and legacy JSON keeps new fields unknown rather than fabricated",()=>{
    var route=Solve(Input([Order(3) with{RequestedDeliveryAt=windowStart}],Vehicle(1)),WindowRequest(3)).Routes.Single();
    var options=new JsonSerializerOptions(JsonSerializerDefaults.Web);var json=JsonSerializer.SerializeToNode(route.Stops[0],options)!;
    var restored=json.Deserialize<PlannedStop>(options)!;Assert(restored.ServiceStartAt==windowStart&&restored.WaitingMinutes==10);
    json.AsObject().Remove("serviceStartAt");json.AsObject().Remove("waitingMinutes");json.AsObject().Remove("requestedDeliveryAt");json.AsObject().Remove("expectedDeliveryAt");
    var legacy=json.Deserialize<PlannedStop>(options)!;Assert(legacy.ServiceStartAt==null&&legacy.WaitingMinutes==null&&legacy.ArrivalAt==restored.ArrivalAt&&legacy.DepartureAt==restored.DepartureAt);
});
Check("Sub-minute waiting is preserved and totals exclude the return leg when requested",()=>{
    var request=WindowRequest(3);request.ReturnToDepot=false;var earliest=windowStart.AddSeconds(30);
    var route=Solve(Input([Order(3) with{RequestedDeliveryAt=earliest}],Vehicle(1)),request).Routes.Single();
    Assert(route.Stops[0].WaitingMinutes==10.5&&route.EndAt==earliest.AddMinutes(5)&&route.DurationMinutes==16.5&&route.Legs.Length==1);
});
Check("Preview request rejects duplicate IDs and past departure",()=>{var req=Request(3,3);try{req.Validate();throw new Exception("Accepted duplicate");}catch(DispatchProblem e){Assert(e.Status==400);}req=Request(3);req.DepartureAt=DateTimeOffset.UtcNow.AddMinutes(-1);try{req.Validate();throw new Exception("Accepted past departure");}catch(DispatchProblem e){Assert(e.Status==400);}});
Check("OSM import respects oneway and explicit motor-vehicle restrictions",()=>{
    var path=Path.GetTempFileName();try{File.WriteAllText(path,"""
    <osm version="0.6"><node id="1" lat="10" lon="106"/><node id="2" lat="10.001" lon="106"/><node id="3" lat="10.002" lon="106"/>
    <way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/><tag k="oneway" v="yes"/></way>
    <way id="11"><nd ref="2"/><nd ref="3"/><tag k="highway" v="residential"/><tag k="motorcycle" v="no"/></way></osm>
    """);var osm=RoadGraph.Load(path);Assert(osm.ShortestPaths(2,[1],"motorcycle",default)[0]==null);Assert(osm.ShortestPaths(1,[2],"motorcycle",default)[0]!=null);Assert(osm.ShortestPaths(1,[3],"motorcycle",default)[0]==null);}finally{File.Delete(path);}});
Check("Driver navigation selects the admin leg by order and sequence without recalculating",()=>{
    const string saved = """
    {"stops":[{"orderId":20,"sequence":1},{"orderId":10,"sequence":2}],
     "legs":[{"distanceMeters":120,"travelSeconds":12,"geometry":[{"latitude":10,"longitude":106},{"latitude":10.001,"longitude":106}]},
             {"distanceMeters":340,"travelSeconds":34,"geometry":[{"latitude":10.001,"longitude":106},{"latitude":10.002,"longitude":106}]}]}
    """;
    var leg=DriverRouteGeometry.SavedLeg(saved,10,2);
    Assert(leg?.DistanceMeters==340 && leg.Geometry[0].Latitude==10.001);
    Assert(DriverRouteGeometry.SavedLeg(saved,20,1)?.DistanceMeters==120);
    Assert(DriverRouteGeometry.SavedLeg(saved,10,1)==null); // Admin changed order: old geometry must not be reused.
    Assert(DriverRouteGeometry.SavedLeg(saved,99,2)==null);
    Assert(DriverRouteGeometry.SavedLeg(null,10,2)==null);
});
Check("Navigation minimizes estimated time while dispatch still minimizes distance",()=>{
    var nav=new RoadGraph(nodes,new(){{"motorcycle",new(){
        {1,[new(2,100,100),new(3,300,15)]},{2,[new(4,100,100)]},{3,[new(4,100,5)]}
    }}} ,"NAV_TEST");
    var shortest=nav.ShortestPaths(1,[4],"motorcycle",default)[0];
    var fastest=nav.FastestPath(1,4,"motorcycle",default);
    Assert(shortest?.DistanceMeters==200 && shortest.TravelSeconds==200);
    Assert(fastest?.DistanceMeters==400 && fastest.TravelSeconds==20);
    Assert(nav.FastestPath(4,1,"motorcycle",default)==null); // never invent a reverse edge
    Assert(nav.FastestPath(1,1,"motorcycle",default)?.DistanceMeters==0);
});
Check("Deferred returns reserve payload without blocking an otherwise idle vehicle",()=>{
    var vehicle=Vehicle(1,10) with {CarriedReturnCount=1,CarriedReturnKg=4,CarriedReturnM3=.1m};
    var ok=Solve(Input([Order(3)],vehicle),Request(3));
    Assert(ok.Routes.Single().WeightKg==6 && ok.Routes.Single().CarriedReturnKg==4);
    Assert(ok.Warnings.Any(w=>w.Contains("kiện hoàn")));
    var over=Solve(Input([Order(3,7)],vehicle),Request(3));
    Assert(over.Routes.Length==0 && over.Unplanned.Single().Reason.Contains("tải trọng"));
    var manual=Request(3);manual.ManualRoutes=[new(1,[3])];
    try { Solve(Input([Order(3,7)],vehicle),manual);throw new Exception("Ignored held return payload"); }
    catch(DispatchProblem e) {Assert(e.Status==422);}
});
Check("Deferred return volume is retained and unknown dimensions never become free capacity",()=>{
    var vehicle=Vehicle(1,20,volume:.1m) with{CarriedReturnCount=1,CarriedReturnM3=.1m};
    Assert(Solve(Input([Order(3)],vehicle),Request(3)).Routes.Length==0);
    var unknown=Solve(Input([Order(3)],vehicle with{CarriedReturnM3=null}),Request(3));
    Assert(unknown.Routes.Length==0 && unknown.Unplanned.Single().Reason.Contains("kích thước"));
});
RoadGraphRegression.Run(Check, Assert);
if(args.Length>0)
Check("Downloaded OSM snapshot contains real roads and a reconstructable HCMC path",()=>{
    var osm=RoadGraph.Load(Path.GetFullPath(args[0]));Assert(osm.NodeCount>1000&&osm.EdgeCount>1000);var a=osm.Snap(new(10.8105,106.6048),"motorcycle",200);var b=osm.Snap(new(10.8143,106.6032),"motorcycle",200);Assert(a.HasValue&&b.HasValue);var leg=osm.ShortestPaths(a!.Value.Node,[b!.Value.Node],"motorcycle",default)[0];Assert(leg!=null&&leg.Geometry.Length>2&&leg.DistanceMeters>0);Console.WriteLine(JsonSerializer.Serialize(new{osm.Version,osm.NodeCount,osm.EdgeCount,osm.ExcludedRestrictedWays,leg!.DistanceMeters,points=leg.Geometry.Length}));
    var school=osm.Snap(new(10.80692,106.62868),"motorcycle",200);
    Assert(school.HasValue,"University must connect to the configured road graph");
    var universityShortest=osm.ShortestPaths(school!.Value.Node,[a.Value.Node],"motorcycle",default)[0];
    var universityFastest=osm.FastestPath(school.Value.Node,a.Value.Node,"motorcycle",default);
    Assert(universityShortest!=null && universityFastest!=null,"University to sample depot must be reachable");
    Assert(universityFastest!.TravelSeconds<=universityShortest!.TravelSeconds+0.001);
    Console.WriteLine(JsonSerializer.Serialize(new{route="HUIT_TO_SAMPLE_DEPOT",shortestMeters=universityShortest.DistanceMeters,
        shortestSeconds=universityShortest.TravelSeconds,fastestMeters=universityFastest.DistanceMeters,fastestSeconds=universityFastest.TravelSeconds}));
    var segmentRoute=osm.FastestRoute(new(10.80692,106.62868),new(10.8105,106.6048),"motorcycle",200,default);
    Assert(segmentRoute!=null,"Actual university/depot road segments must be connected");
    Console.WriteLine(JsonSerializer.Serialize(new{route="HUIT_TO_SAMPLE_DEPOT_SEGMENTS",segmentRoute!.DistanceMeters,segmentRoute.TravelSeconds,points=segmentRoute.Geometry.Length,osm.TurnRuleCount}));


});
if(args.Length>2)
{
    var before=RoadGraph.Load(Path.GetFullPath(args[2]));
    var after=RoadGraph.Load(Path.GetFullPath(args[0]));
    var reportedGps=new GeoPoint(10.7769,106.7009);
    Check("Reported GPS is outside the old drivable road coverage and connects to the expanded snapshot",()=>{
        Assert(!before.CanSnapToRoad(reportedGps,"motorcycle",200),"Original dataset unexpectedly covers the reported GPS");
        Assert(after.CanSnapToRoad(reportedGps,"motorcycle",200),"Expanded dataset still cannot snap the reported GPS");
    });
    foreach(var stop in new[]{(Code:"CURRENT_PICKUP_DEPOT",Point:new GeoPoint(10.8105,106.6048)),(Code:"CURRENT_DELIVERY_POINT",Point:new GeoPoint(10.7289,106.6152))})
        Check("Reported GPS reaches "+stop.Code+" without altering direction/access rules",()=>{
            Assert(before.FastestRoute(reportedGps,stop.Point,"motorcycle",200,default)==null,"Original dataset unexpectedly provides this route");
            var watch=System.Diagnostics.Stopwatch.StartNew();
            var leg=after.FastestRoute(reportedGps,stop.Point,"motorcycle",200,default);
            watch.Stop();
            Assert(leg is not null && leg.DistanceMeters>0 && leg.Geometry.Length>2,"Expanded roads are not connected to the real task destination");
            Console.WriteLine(JsonSerializer.Serialize(new{route=stop.Code,origin=reportedGps,destination=stop.Point,leg!.DistanceMeters,leg.TravelSeconds,points=leg.Geometry.Length,originRoadDistanceMeters=RoadGraph.Meters(reportedGps,leg.Geometry[0]),elapsedMs=watch.ElapsedMilliseconds}));
        });
}
if(args.Length>1){Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[1]))!);File.WriteAllText(args[1],JsonSerializer.Serialize(new{checks,errors=Array.Empty<string>()},new JsonSerializerOptions{WriteIndented=true}));}
Console.WriteLine(JsonSerializer.Serialize(new{passed=checks.Count,failed=0}));
