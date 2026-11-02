using LastMile.Api.Services.Routing;

internal static class RoadGraphRegression
{
    private const string Nodes = """
      <node id="1" lat="10" lon="106"/><node id="2" lat="10" lon="106.001"/>
      <node id="3" lat="10" lon="106.002"/><node id="4" lat="10.001" lon="106.001"/>
      <node id="5" lat="10.001" lon="106.002"/>
      """;
    static string Way(int id,string refs,string tags="") => $"<way id='{id}'>{string.Concat(refs.Split(',').Select(n=>$"<nd ref='{n}'/>"))}<tag k='highway' v='residential'/>{tags}</way>";
    static string Rule(string value,string extra="") => $"<relation id='100'><member type='way' ref='10' role='from'/><member type='node' ref='2' role='via'/><member type='way' ref='20' role='to'/><tag k='type' v='restriction'/><tag k='restriction' v='{value}'/>{extra}</relation>";
    static RoadGraph Load(string roads,string rules="",string? nodes=null,DateTimeOffset? at=null)
    {
        var file=Path.GetTempFileName();
        try { File.WriteAllText(file,$"<osm version='0.6'>{nodes??Nodes}{roads}{rules}</osm>"); return RoadGraph.Load(file,at); }
        finally { File.Delete(file); }
    }
    public static void Run(Action<string,Action> check,Action<bool,string> assert)
    {
        check("Road connection diagnosis uses drivable segments and rejects invalid, remote and unsupported points",()=>{
            var graph=Load(Way(10,"1,2,3"));
            assert(graph.CanSnapToRoad(new(10,106.0005),"motorcycle",20),"Interior of a road segment must be reachable for snapping");
            assert(!graph.CanSnapToRoad(new(40,-74),"motorcycle",200),"Remote GPS incorrectly connected");
            assert(!graph.CanSnapToRoad(new(double.NaN,106),"motorcycle",200),"Invalid GPS incorrectly connected");
            assert(!graph.CanSnapToRoad(new(10,106),"unsupported",200),"Unsupported vehicle profile incorrectly connected");
        });
        string junction=Way(10,"1,2")+Way(11,"2,3")+Way(20,"2,4")+Way(30,"3,5,4");
        check("Explicit April/September closures do not close the road in October",()=>{
            var road=Way(10,"1,2,3","<tag k='motor_vehicle:conditional' v='no @ (Apr 29 23:00-23:59; Apr 30 00:00-14:00); no @ (Sep 02 19:15-23:59)'/>")+Way(99,"4,5");
            var october=Load(road,at:DateTimeOffset.Parse("2026-10-31T10:00:00+07:00"));
            var april=Load(road,at:DateTimeOffset.Parse("2026-04-29T10:00:00+07:00"));
            assert(october.FastestPath(1,3,"motorcycle",default) is not null,"Inactive seasonal closures removed the road");
            assert(april.FastestPath(1,3,"motorcycle",default) is null,"Applicable calendar month was ignored");
            assert(october.Version!=april.Version,"Calendar applicability must participate in graph versioning");
        });
        check("Seasonal exclusions retain overnight boundaries, near-future closures and unknown mixed conditions",()=>{
            var seasonal=Way(10,"1,2,3","<tag k='motor_vehicle:conditional' v='no @ (Apr 30 23:00-02:00)'/>")+Way(99,"4,5");
            foreach(var date in new[]{"2026-03-26T10:00:00+07:00","2026-05-01T01:00:00+07:00"})
                assert(Load(seasonal,at:DateTimeOffset.Parse(date)).FastestPath(1,3,"motorcycle",default) is null,"Upcoming or overnight calendar condition was opened");
            foreach(var condition in new[]{"no @ (Apr 30 00:00-14:00; Sa-Su 18:30-23:00)","no @ (Apr-Oct)","no @ (Apr 30 25:00-26:00)","no @ (Apr 30 00:00-14:00) AND wet"}){
                var road=Way(10,"1,2,3",$"<tag k='motor_vehicle:conditional' v='{condition}'/>")+Way(99,"4,5");
                assert(Load(road,at:DateTimeOffset.Parse("2026-10-31T10:00:00+07:00")).FastestPath(1,3,"motorcycle",default) is null,"Unparsed condition silently allowed: "+condition);
            }
        });
        check("An off-road GPS can use a nearby connected road without fabricating a connector",()=>{
            const string points="<node id='1' lat='10' lon='106'/><node id='2' lat='10' lon='106.002'/><node id='3' lat='10.001' lon='106'/><node id='4' lat='10.001' lon='106.002'/>";
            var graph=Load(Way(10,"1,2")+Way(20,"3,4"),nodes:points);
            var leg=graph.FastestRoute(new(10.0003,106.0002),new(10.001,106.0018),"motorcycle",200,default);
            assert(leg is not null && leg.Geometry.All(p=>p.Latitude==10.001),"Nearest isolated road prevented using a connected road or a fake connector was added");
            assert(graph.FastestRoute(new(10,106.0002),new(10.001,106.0018),"motorcycle",200,default) is null,"An on-road fix escaped its disconnected road by jumping roads");
            assert(graph.FastestRoute(new(10.0003,106.0002),new(10.001,106.0018),"motorcycle",50,default) is null,"Snap radius was silently expanded");
        });
        check("Truck-only conditional access does not delete a motorcycle road",()=>{
            var graph=Load(Way(10,"1,2,3","<tag k='hgv:conditional' v='no @ (06:00-22:00)'/>"));
            assert(graph.FastestPath(1,3,"motorcycle",default) is not null,"Truck rule removed motorcycle connectivity");
            assert(graph.FastestPath(1,3,"hgv",default) is null,"Unsupported truck schedule was ignored");
        });
        check("Motorcycle and general motor-vehicle conditional access remain conservative for affected modes",()=>{
            var bike=Load(Way(10,"1,2,3","<tag k='motorcycle:conditional' v='no @ (06:00-22:00)'/>"));
            assert(bike.FastestPath(1,3,"motorcycle",default) is null,"Motorcycle conditional rule was ignored");
            assert(bike.FastestPath(1,3,"hgv",default) is not null,"Motorcycle-only rule removed truck road");
            var all=Load(Way(10,"1,2,3","<tag k='motor_vehicle:conditional' v='no @ (Sa-Su 18:30-23:00)'/>")+Way(99,"4,5"));
            assert(all.FastestPath(1,3,"motorcycle",default) is null && all.FastestPath(1,3,"hgv",default) is null,"General driving restriction was bypassed");
        });
        check("Parking and another mode's one-way condition do not ban motorcycle travel",()=>{
            var graph=Load(Way(10,"1,2,3","<tag k='parking:right:restriction:conditional' v='no_stopping @ (06:00-22:00)'/><tag k='oneway:motorcar:conditional' v='yes @ (06:00-08:00)'/>"));
            assert(graph.FastestPath(1,3,"motorcycle",default) is not null,"Parking/car rules removed motorcycle road");
        });
        check("Generic conditional one-way, unknown conditions and generic weight limits still block unsupported travel",()=>{
            foreach(var key in new[]{"oneway:conditional","unknown:conditional","maxweight:conditional"}){
                var graph=Load(Way(10,"1,2,3",$"<tag k='{key}' v='no @ (06:00-22:00)'/>")+Way(99,"4,5"));
                assert(graph.FastestPath(1,3,"motorcycle",default) is null,"Unsupported applicable condition silently allowed: "+key);
            }
        });
        check("Turn restriction keeps the roads and legal straight movements, blocking only the forbidden turn",()=>{
            var graph=Load(junction,Rule("no_left_turn"));
            assert(graph.ShortestPaths(1,[3],"motorcycle",default)[0]?.Geometry.Length==3,"Straight road was incorrectly deleted");
            var turn=graph.FastestPath(1,4,"motorcycle",default)!;
            assert(turn.Geometry.Length==5 && turn.Geometry[2].Longitude==106.002,"Forbidden direct left turn was used");
        });
        check("Only-turn restriction rejects other exits but does not restrict a journey starting at the junction",()=>{
            var graph=Load(junction,Rule("only_left_turn"));
            assert(graph.FastestPath(1,3,"motorcycle",default)!.Geometry[2].Latitude==10.001,"Mandatory turn was ignored");
            assert(graph.FastestPath(2,3,"motorcycle",default)!.Geometry.Length==2,"Origin has no incoming turn");
        });
        check("Motorcycle exceptions preserve roads for that mode without exempting trucks",()=>{
            var graph=Load(junction,Rule("no_left_turn","<tag k='except' v='motorcycle;bicycle'/>"));
            assert(graph.FastestPath(1,4,"motorcycle",default)!.Geometry.Length==3,"Motorcycle exception ignored");
            assert(graph.FastestPath(1,4,"hgv",default)!.Geometry.Length==5,"Truck illegally exempted");
        });
        check("A car-only turn relation does not remove motorcycle or truck roads",()=>{
            var graph=Load(junction,Rule("no_left_turn").Replace("k='restriction'","k='restriction:motorcar'"));
            assert(graph.FastestPath(1,4,"motorcycle",default)!.Geometry.Length==3,"Car rule leaked to motorcycle profile");
        });
        check("Unsupported conditional rules stay conservative only for affected profiles",()=>{
            var rules=Rule("no_left_turn","<tag k='except' v='motorcycle'/>").Replace("k='restriction'","k='restriction:conditional'");
            var graph=Load(junction,rules);
            assert(graph.FastestPath(1,4,"motorcycle",default)!.Geometry.Length==3,"Exempt mode lost a road");
            assert(graph.FastestPath(1,4,"hgv",default)==null,"Unsupported truck restriction silently allowed");
        });
        check("Search retains arrival state, forbids a U-turn and can revisit a junction through a legal approach",()=>{
            var points=new Dictionary<long,GeoPoint>{{9,new(10,106)},{1,new(10,106.001)},{2,new(10,106.002)},{3,new(10.001,106.001)},{4,new(10.001,106.002)}};
            var edges=new Dictionary<long,List<RoadGraph.Edge>>{{9,[new(1,1,1,99)]},{1,[new(2,1,1,10),new(3,1,1,30)]},{2,[new(1,1,1,10),new(4,2,2,40)]},{4,[new(1,2,2,41)]}};
            var turns=new Dictionary<string,Dictionary<(long,long),List<RoadGraph.TurnRule>>>{{"motorcycle",new(){{(1,99),[new("only_straight_on",[10])]},{(2,10),[new("no_u_turn",[10])]}}}};
            var graph=new RoadGraph(points,new(){{"motorcycle",edges}},"TEST",turnRules:turns);
            var leg=graph.FastestPath(9,3,"motorcycle",default)!;
            assert(leg.Geometry.SequenceEqual(new[]{points[9],points[1],points[2],points[4],points[1],points[3]}),"Node-only search pruned a legal arrival or allowed the U-turn");
        });
        check("Navigation projects onto a road segment instead of collapsing nearby endpoints to the same node",()=>{
            var graph=Load(Way(10,"1,2,3","<tag k='oneway' v='yes'/>"));
            var leg=graph.FastestRoute(new(10,106.0008),new(10,106.0012),"motorcycle",100,default)!;
            assert(leg.DistanceMeters>40 && leg.DistanceMeters<50 && Math.Abs(leg.Geometry[0].Longitude-106.0008)<1e-8,"Endpoints incorrectly snapped to one vertex");
            assert(Math.Abs(leg.Geometry[^1].Longitude-106.0012)<1e-8,"Destination is not on its actual road segment");
        });
        check("Same-segment movement uses only the travelled fraction and never drives against a one-way road",()=>{
            var graph=Load(Way(10,"1,2,3","<tag k='oneway' v='yes'/>"));
            var leg=graph.FastestRoute(new(10,106.0002),new(10,106.0008),"motorcycle",100,default)!;
            assert(leg.DistanceMeters>60 && leg.DistanceMeters<70,"A full segment detour was added");
            assert(graph.FastestRoute(new(10,106.0008),new(10,106.0002),"motorcycle",100,default)==null,"Invented a reverse edge");
        });
        check("Segment routing takes a real legal loop when the destination is behind the vehicle on a one-way road",()=>{
            var graph=Load(Way(10,"1,2,3","<tag k='oneway' v='yes'/>")+Way(20,"3,4,1","<tag k='oneway' v='yes'/>"));
            var leg=graph.FastestRoute(new(10,106.0008),new(10,106.0002),"motorcycle",100,default)!;
            assert(leg.DistanceMeters>400 && leg.Geometry.Any(p=>p.Latitude==10.001),"Skipped the legal return loop");
        });
        check("Explicit motorcycle permission through a barrier is respected without opening it for trucks",()=>{
            var graph=Load(Way(10,"1,2,3"),nodes:Nodes.Replace("<node id=\"2\" lat=\"10\" lon=\"106.001\"/>","<node id='2' lat='10' lon='106.001'><tag k='barrier' v='bollard'/><tag k='motorcycle' v='yes'/></node>"));
            assert(graph.FastestPath(1,3,"motorcycle",default)!=null,"Allowed motorcycle barrier blocked");
            assert(graph.FastestPath(1,3,"hgv",default)==null,"Truck barrier was bypassed");
        });
        check("Routing policy participates in a fixed-length graph version and distant endpoints remain unroutable",()=>{
            var graph=Load(Way(10,"1,2,3"));
            assert(graph.Version.Length==64,"Graph version no longer fits persisted VARCHAR(64)");
            assert(graph.FastestRoute(new(11,107),new(10,106),"motorcycle",100,default)==null,"Invented a link outside road coverage");
        });
    }
}
