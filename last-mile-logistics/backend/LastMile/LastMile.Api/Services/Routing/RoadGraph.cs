using System.Globalization;
using System.Text;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Xml;
using System.Xml.Linq;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;

namespace LastMile.Api.Services.Routing;

// Edges follow consecutive nodes of OSM ways, never straight lines between delivery addresses.
// Dispatch minimizes distance; live navigation minimizes estimated time using configured/tagged speeds.
public sealed class RoadGraph
{
    public sealed record Edge(long To, double Meters, double Seconds, long WayId = 0, long? ArrivalPreviousNode = null, long? TurnToNode = null);
    public sealed record TurnRule(string Kind, HashSet<long> ToWays);
    readonly Dictionary<string, Dictionary<(long Via, long FromWay), List<TurnRule>>> turns;
    readonly Dictionary<string, long[]> snapNodes;
    public int TurnRuleCount => turns.Values.Sum(p => p.Values.Sum(r => r.Count));
    private readonly record struct State(long Node, long Previous, long Way);
    readonly Dictionary<long, GeoPoint> nodes;
    readonly Dictionary<string, Dictionary<long, List<Edge>>> profiles;
    public string Version { get; }
    public int NodeCount => nodes.Count;
    public int EdgeCount => profiles.Values.Sum(p => p.Values.Sum(e => e.Count));
    public int ExcludedRestrictedWays { get; }
    public RoadGraph(Dictionary<long, GeoPoint> nodes, Dictionary<string, Dictionary<long, List<Edge>>> profiles, string version, int excluded = 0, Dictionary<string, Dictionary<(long Via, long FromWay), List<TurnRule>>>? turnRules = null)
    {
        this.nodes = nodes; this.profiles = profiles; Version = version; ExcludedRestrictedWays = excluded;
        turns = turnRules ?? [];
        snapNodes = profiles.ToDictionary(p => p.Key, p => p.Value.Keys.Concat(p.Value.Values.SelectMany(e => e.Select(x => x.To))).Distinct().ToArray());
        if (nodes.Values.Any(p => !p.IsValid) || profiles.Values.SelectMany(p => p).Any(p => !nodes.ContainsKey(p.Key)
            || p.Value.Any(e => !nodes.ContainsKey(e.To) || !double.IsFinite(e.Meters) || e.Meters < 0 || !double.IsFinite(e.Seconds) || e.Seconds < 0)))
            throw new InvalidDataException("Đồ thị phải có tọa độ hợp lệ và trọng số không âm.");
    }
    public static string? Profile(string type) => type == "MOTORBIKE" ? "motorcycle" : type.StartsWith("TRUCK", StringComparison.Ordinal) ? "hgv" : null;
    public static double Meters(GeoPoint a, GeoPoint b)
    {
        const double r = Math.PI / 180;
        double dlat = (b.Latitude - a.Latitude) * r, dlon = (b.Longitude - a.Longitude) * r;
        double h = Math.Pow(Math.Sin(dlat / 2), 2) + Math.Cos(a.Latitude * r) * Math.Cos(b.Latitude * r) * Math.Pow(Math.Sin(dlon / 2), 2);
        return 6371000 * 2 * Math.Asin(Math.Sqrt(Math.Clamp(h, 0, 1)));
    }
    public (long Node, double Distance)? Snap(GeoPoint? point, string profile, double maxMeters)
    {
        if (point?.IsValid != true || !profiles.TryGetValue(profile, out var edges)) return null;
        // Include terminal vertices as well as vertices with outgoing edges.
        var candidates = snapNodes[profile];
        long best = 0; double distance = double.PositiveInfinity;
        foreach (long id in candidates) { double d = Meters(point, nodes[id]); if (d < distance) { best = id; distance = d; } }
        return distance <= maxMeters ? (best, distance) : null;
    }
    public RoadLeg?[] ShortestPaths(long source, long[] targets, string profile, CancellationToken ct)
        => FindPaths(source, targets, profile, false, ct);

    // Navigation minimizes estimated driving time; the dispatch planner keeps its distance objective.
    public RoadLeg? FastestPath(long source, long target, string profile, CancellationToken ct)
        => FindPaths(source, [target], profile, true, ct)[0];

    private bool CanTurn(string profile, State state, Edge edge)
    {
        if (state.Way == 0 || edge.WayId == 0 && edge.Meters == 0 || !turns.TryGetValue(profile, out var rules) ||
            !rules.TryGetValue((state.Node, state.Way), out var active)) return true;
        bool Matches(TurnRule rule) => rule.ToWays.Contains(edge.WayId) &&
            (state.Way != edge.WayId || !rule.Kind.EndsWith("u_turn", StringComparison.Ordinal)
                ? !(state.Way == edge.WayId && rule.Kind.EndsWith("straight_on", StringComparison.Ordinal) && (edge.TurnToNode ?? edge.To) == state.Previous)
                : (edge.TurnToNode ?? edge.To) == state.Previous);
        if (active.Any(r => r.Kind.StartsWith("no_", StringComparison.Ordinal) && Matches(r))) return false;
        var only = active.Where(r => r.Kind.StartsWith("only_", StringComparison.Ordinal)).ToArray();
        return only.Length == 0 || only.Any(Matches);
    }

    private RoadLeg?[] FindPaths(long source, long[] targets, string profile, bool fastest, CancellationToken ct,
        Dictionary<long, List<Edge>>? overlay = null, Dictionary<long, GeoPoint>? virtualPoints = null)
    {
        if (!profiles.TryGetValue(profile, out var graph) || !nodes.ContainsKey(source) && virtualPoints?.ContainsKey(source) != true)
            return new RoadLeg?[targets.Length];
        GeoPoint Point(long id) => virtualPoints != null && virtualPoints.TryGetValue(id, out var point) ? point : nodes[id];
        var first = new State(source, 0, 0);
        var pending = targets.ToHashSet();
        var ends = new Dictionary<long, State>();
        var costs = new Dictionary<State, double> { { first, 0 } };
        var meters = new Dictionary<State, double> { { first, 0 } };
        var seconds = new Dictionary<State, double> { { first, 0 } };
        var previous = new Dictionary<State, State>();
        var queue = new PriorityQueue<State, double>(); queue.Enqueue(first, 0); int count = 0;
        while (queue.TryDequeue(out var state, out double cost))
        {
            if ((++count & 255) == 0) ct.ThrowIfCancellationRequested();
            if (cost > costs[state]) continue;
            if (pending.Remove(state.Node)) ends[state.Node] = state;
            if (pending.Count == 0) break;
            IEnumerable<Edge> edges = graph.GetValueOrDefault(state.Node) ?? [];
            if (overlay != null && overlay.TryGetValue(state.Node, out var extra)) edges = edges.Concat(extra);
            foreach (var edge in edges)
            {
                if (!CanTurn(profile, state, edge)) continue;
                var next = new State(edge.To, edge.ArrivalPreviousNode ?? state.Node, edge.WayId);
                double candidate = cost + (fastest ? edge.Seconds : edge.Meters);
                if (costs.TryGetValue(next, out double known) && known <= candidate) continue;
                costs[next] = candidate; meters[next] = meters[state] + edge.Meters; seconds[next] = seconds[state] + edge.Seconds;
                previous[next] = state; queue.Enqueue(next, candidate);
            }
        }
        return targets.Select(target =>
        {
            if (!ends.TryGetValue(target, out var end)) return null;
            var path = new List<GeoPoint> { Point(end.Node) }; var cursor = end;
            while (cursor != first) { cursor = previous[cursor]; path.Add(Point(cursor.Node)); }
            path.Reverse(); return new RoadLeg(meters[end], seconds[end], path.ToArray());
        }).ToArray();
    }

    private sealed record Segment(long A, long B, List<(long From, Edge Edge)> Directions);
    private sealed record Attachment(Segment Segment, GeoPoint Point, double Fraction, double Distance);
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, Segment[]> segmentCache = new();
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, Dictionary<long, long>> componentCache = new();
    private Dictionary<long, long> Components(string profile) => componentCache.GetOrAdd(profile, key =>
    {
        var parent = snapNodes[key].ToDictionary(n => n, n => n);
        long Root(long n) { while (parent[n] != n) { parent[n] = parent[parent[n]]; n = parent[n]; } return n; }
        foreach (var pair in profiles[key]) foreach (var edge in pair.Value)
        {
            long a = Root(pair.Key), b = Root(edge.To);
            if (a != b) parent[a] = b;
        }
        return parent.Keys.ToArray().ToDictionary(n => n, Root);
    });
    public bool CanSnapToRoad(GeoPoint point, string profile, double maxMeters) =>
        SnapSegment(point, profile, maxMeters) is not null;
    private Attachment? SnapSegment(GeoPoint point, string profile, double maxMeters) => SnapSegments(point, profile, maxMeters, 1).FirstOrDefault();
    private Attachment[] SnapSegments(GeoPoint point, string profile, double maxMeters, int limit)
    {
        if (!point.IsValid || !profiles.ContainsKey(profile)) return [];
        var segments = segmentCache.GetOrAdd(profile, key =>
        {
            var result = new Dictionary<(long, long), Segment>();
            foreach (var pair in profiles[key]) foreach (var edge in pair.Value)
            {
                var id = (Math.Min(pair.Key, edge.To), Math.Max(pair.Key, edge.To));
                if (!result.TryGetValue(id, out var segment)) result[id] = segment = new(pair.Key, edge.To, []);
                segment.Directions.Add((pair.Key, edge));
            }
            return result.Values.ToArray();
        });
        var candidates = new List<Attachment>();
        double scale = Math.Cos(point.Latitude * Math.PI / 180);
        foreach (var segment in segments)
        {
            var a = nodes[segment.A]; var b = nodes[segment.B];
            double x = (b.Longitude - a.Longitude) * scale, y = b.Latitude - a.Latitude, den = x * x + y * y;
            double fraction = den == 0 ? 0 : Math.Clamp(((point.Longitude - a.Longitude) * scale * x + (point.Latitude - a.Latitude) * y) / den, 0, 1);
            var projected = new GeoPoint(a.Latitude + (b.Latitude - a.Latitude) * fraction, a.Longitude + (b.Longitude - a.Longitude) * fraction);
            double distance = Meters(point, projected);
            if (distance <= maxMeters) candidates.Add(new(segment, projected, fraction, distance));
        }
        var ordered = candidates.OrderBy(c => c.Distance);
        if (limit == 1) return ordered.Take(1).ToArray();
        return ordered.DistinctBy(c => string.Join(',', c.Segment.Directions.Select(d => d.Edge.WayId).Distinct().Order())).Take(limit).ToArray();
    }

    // Virtual endpoints split existing directed edges. No invented connecting road is added.
    public RoadLeg? FastestRoute(GeoPoint origin, GeoPoint destination, string profile, double maxSnap, CancellationToken ct)
    {
        var start = SnapSegment(origin, profile, maxSnap); var end = SnapSegment(destination, profile, maxSnap);
        if (start is null || end is null) return null;
        var primary = RouteBetween(start, end, profile, ct);
        if (primary is not null) return primary;
        // Only an off-road fix/address may choose another nearby existing road.
        // A fix already on a road cannot jump roads to bypass driving rules.
        var starts = start.Distance > 15 ? SnapSegments(origin, profile, maxSnap, int.MaxValue) : [start];
        var ends = end.Distance > 15 ? SnapSegments(destination, profile, maxSnap, int.MaxValue) : [end];
        var components = Components(profile);
        foreach (var pair in starts.SelectMany(a => ends.Select(b => (Start: a, End: b)))
            .Where(p => p.Start.Segment != start.Segment || p.End.Segment != end.Segment)
            .Where(p => components[p.Start.Segment.A] == components[p.End.Segment.A])
            .OrderBy(p => p.Start.Distance + p.End.Distance).Take(32))
        {
            ct.ThrowIfCancellationRequested();
            var alternative = RouteBetween(pair.Start, pair.End, profile, ct);
            if (alternative is not null) return alternative;
        }
        return null;
    }
    private RoadLeg? RouteBetween(Attachment start, Attachment end, string profile, CancellationToken ct)
    {
        const long source = long.MinValue, target = long.MinValue + 1;
        var overlay = new Dictionary<long, List<Edge>>();
        void Add(long from, Edge edge) { if (!overlay.TryGetValue(from, out var list)) overlay[from] = list = []; list.Add(edge); }
        foreach (var direction in start.Segment.Directions)
        {
            double f = direction.From == start.Segment.A ? start.Fraction : 1 - start.Fraction;
            var edge = direction.Edge;
            Add(source, new(edge.To, edge.Meters * (1 - f), edge.Seconds * (1 - f), (1 - f) < 1e-10 ? 0 : edge.WayId, direction.From));
        }
        foreach (var direction in end.Segment.Directions)
        {
            double f = direction.From == end.Segment.A ? end.Fraction : 1 - end.Fraction;
            var edge = direction.Edge;
            Add(direction.From, new(target, edge.Meters * f, edge.Seconds * f, f < 1e-10 ? 0 : edge.WayId, null, edge.To));
        }
        if (start.Segment == end.Segment) foreach (var direction in start.Segment.Directions)
        {
            double a = direction.From == start.Segment.A ? start.Fraction : 1 - start.Fraction;
            double b = direction.From == start.Segment.A ? end.Fraction : 1 - end.Fraction;
            if (b >= a) Add(source, new(target, direction.Edge.Meters * (b - a), direction.Edge.Seconds * (b - a), direction.Edge.WayId));
        }
        return FindPaths(source, [target], profile, true, ct, overlay, new() { { source, start.Point }, { target, end.Point } })[0];
    }

    // Conditional access is still conservative, but another mode or parking
    // metadata must not delete a road for every vehicle type.
    private static bool ConditionalAffectsProfile(string key, string profile)
    {
        if (!key.EndsWith(":conditional", StringComparison.Ordinal)) return false;
        var parts = key[..^12].Split(':');
        if (parts[0] == "parking" || parts[0] == "maxspeed") return false;
        string[] modes = ["motorcycle", "hgv", "hgv_articulated", "goods", "bus", "psv", "taxi", "coach", "bicycle", "foot", "motorcar"];
        var mode = parts.FirstOrDefault(p => modes.Contains(p));
        if (mode is not null) return mode == profile || profile == "hgv" && mode is "goods" or "hgv_articulated";
        return true;
    }

    // Only prove inactivity for explicit month/day/time clauses. Other opening-
    // hours syntax stays blocked. Include yesterday for overnight intervals and
    // the full seven-day planning horizon so a future closure is never ignored.
    private static bool SeasonalConditionInactive(string value, DateOnly date)
    {
        var clauses = Regex.Matches(value, @"no\s*@\s*\(([^()]*)\)");
        if (clauses.Count == 0 || Regex.Replace(value, @"no\s*@\s*\(([^()]*)\)", "").Trim(' ', ';', '\t', '\r', '\n').Length > 0) return false;
        var months = Enumerable.Range(-1, 10).Select(day => date.AddDays(day).Month).ToHashSet();
        string[] names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        foreach (Match clause in clauses) foreach (var part in clause.Groups[1].Value.Split([';', ',']))
        {
            var match = Regex.Match(part, @"^\s*(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+([0-2]?\d):([0-5]\d)-([0-2]?\d):([0-5]\d)\s*$");
            if (!match.Success) return false;
            int month = Array.IndexOf(names, match.Groups[1].Value) + 1;
            int day = int.Parse(match.Groups[2].Value), from = int.Parse(match.Groups[3].Value), to = int.Parse(match.Groups[5].Value);
            if (day < 1 || day > DateTime.DaysInMonth(2000, month) || from > 24 || to > 24 ||
                from == 24 && match.Groups[4].Value != "00" || to == 24 && match.Groups[6].Value != "00" || months.Contains(month)) return false;
        }
        return true;
    }

    public static RoadGraph Load(string path, DateTimeOffset? at = null)
    {
        var calendarDate = DateOnly.FromDateTime((at ?? DateTimeOffset.UtcNow).ToOffset(TimeSpan.FromHours(7)).Date);
        if (!File.Exists(path)) throw new DispatchProblem(503, "Chưa có dữ liệu mạng đường. Hãy chuẩn bị tệp OSM và cấu hình Routing:GraphPath.");
        if (new FileInfo(path).Length > 100_000_000) throw new DispatchProblem(503, "Tệp mạng đường vượt giới hạn 100 MB.");
        using var file = File.OpenRead(path); string version = Convert.ToHexString(SHA256.HashData(file)); file.Position = 0;
        using Stream data = path.EndsWith(".gz", StringComparison.OrdinalIgnoreCase) ? new GZipStream(file, CompressionMode.Decompress) : file;
        using var reader = XmlReader.Create(data, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, MaxCharactersInDocument = 250_000_000 });
        var doc = XDocument.Load(reader); if (doc.Root?.Name != "osm" || doc.Root.Element("remark") != null) throw new InvalidDataException("Tệp OSM không đầy đủ hoặc máy chủ nguồn trả lỗi.");
        version = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(version + $":turn-node-edge-snap-v4-mode-calendar-offroad:{calendarDate:yyyyMMdd}")));
        var nodes = doc.Root.Elements("node").ToDictionary(n => (long)n.Attribute("id")!, n => new GeoPoint((double)n.Attribute("lat")!, (double)n.Attribute("lon")!));
        var profiles = new Dictionary<string, Dictionary<long, List<Edge>>> { ["motorcycle"] = [], ["hgv"] = [] };
        var highway = new HashSet<string> { "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link", "residential", "unclassified", "living_street", "service" };
        var restrictions = new Dictionary<string, Dictionary<(long, long), List<TurnRule>>>();
        var excludedByProfile = profiles.Keys.ToDictionary(p => p, _ => new HashSet<long>());
        static Dictionary<string, string> Tags(XElement e) => e.Elements("tag").ToDictionary(t => (string)t.Attribute("k")!, t => (string)t.Attribute("v")!);
        var wayNodes = doc.Root.Elements("way").ToDictionary(w => (long)w.Attribute("id")!, w => w.Elements("nd").Select(n => (long)n.Attribute("ref")!).ToHashSet());
        var supported = new HashSet<string> { "no_left_turn", "no_right_turn", "no_u_turn", "no_straight_on", "no_entry", "no_exit", "only_left_turn", "only_right_turn", "only_u_turn", "only_straight_on" };
        foreach (var relation in doc.Root.Elements("relation"))
        {
            var tags = Tags(relation); string type = tags.GetValueOrDefault("type", "");
            if (type != "restriction" && !type.StartsWith("restriction:", StringComparison.Ordinal)) continue;
            var members = relation.Elements("member").ToArray();
            var from = members.Where(m => (string?)m.Attribute("role") == "from" && (string?)m.Attribute("type") == "way").Select(m => (long)m.Attribute("ref")!).ToArray();
            var to = members.Where(m => (string?)m.Attribute("role") == "to" && (string?)m.Attribute("type") == "way").Select(m => (long)m.Attribute("ref")!).ToHashSet();
            var via = members.Where(m => (string?)m.Attribute("role") == "via").ToArray();
            foreach (string profile in profiles.Keys)
            {
                var exceptions = tags.GetValueOrDefault("except", "").Split(';', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
                if (!tags.ContainsKey("restriction:" + profile) && !tags.ContainsKey("restriction:" + profile + ":conditional") && exceptions.Any(e => e == profile || e is "vehicle" or "motor_vehicle")) continue;
                if (type != "restriction" && type != "restriction:" + profile) continue;
                string key = (tags.ContainsKey("restriction:" + profile) || tags.ContainsKey("restriction:" + profile + ":conditional")) ? "restriction:" + profile :
                    (tags.ContainsKey("restriction:motor_vehicle") || tags.ContainsKey("restriction:motor_vehicle:conditional")) ? "restriction:motor_vehicle" : "restriction";
                string value = tags.GetValueOrDefault(key, "");
                bool conditional = tags.ContainsKey(key + ":conditional") || value.Contains('@');
                if (value.Length == 0 && !conditional) continue; // e.g. motorcar-only rule does not apply to motorcycles.
                bool valid = !conditional && supported.Contains(value) && from.Length > 0 && to.Count > 0 && via.Length == 1 &&
                    (string?)via[0].Attribute("type") == "node";
                long node = valid ? (long)via[0].Attribute("ref")! : 0;
                valid = valid && from.Concat(to).All(w => wayNodes.TryGetValue(w, out var ids) && ids.Contains(node));
                if (!valid) { foreach (var m in members.Where(m => (string?)m.Attribute("type") == "way")) excludedByProfile[profile].Add((long)m.Attribute("ref")!); continue; }
                if (!restrictions.TryGetValue(profile, out var table)) restrictions[profile] = table = [];
                foreach (long way in from) { if (!table.TryGetValue((node, way), out var list)) table[(node, way)] = list = []; list.Add(new(value, to)); }
            }
        }
        int excluded = 0;
        foreach (var way in doc.Root.Elements("way"))
        {
            var tags = way.Elements("tag").ToDictionary(t => (string)t.Attribute("k")!, t => (string)t.Attribute("v")!);
            string Get(string key, string fallback = "") => tags.GetValueOrDefault(key, fallback);
            if (!highway.Contains(Get("highway")) || Get("area") == "yes") continue;
            if (tags.ContainsKey("reversible")) { excluded++; continue; }
            var ids = way.Elements("nd").Select(n => (long)n.Attribute("ref")!).ToArray();
            foreach (string profile in profiles.Keys)
            {
                if (excludedByProfile[profile].Contains((long)way.Attribute("id")!)) continue;
                if (tags.Any(t => ConditionalAffectsProfile(t.Key, profile) && !SeasonalConditionInactive(t.Value, calendarDate))) { excluded++; continue; }
                string access = Get(profile, Get("motor_vehicle", Get("vehicle", Get("access", "yes"))));
                if (!new[] { "yes", "designated", "permissive" }.Contains(access)) continue;
                if (profile == "motorcycle" && Get("highway") is "motorway" or "motorway_link" && Get(profile) != "yes") continue;
                if (profile == "hgv" && tags.Keys.Any(k => k.StartsWith("maxweight") || k.StartsWith("maxheight") || k.StartsWith("maxwidth") || k.StartsWith("maxlength") || k.StartsWith("maxaxleload"))) continue;
                string oneWay = Get("oneway:" + profile, Get("oneway", Get("junction") == "roundabout" || Get("highway") == "motorway" ? "yes" : "no"));
                if (!new[] { "yes", "1", "true", "-1", "no", "0", "false" }.Contains(oneWay)) continue;
                bool forward = oneWay != "-1", backward = oneWay is "no" or "0" or "false";
                double defaultSpeed = Get("highway") switch { "living_street" or "service" => 12, "residential" => 20, _ => profile == "motorcycle" ? 30 : 25 };
                double Speed(string direction)
                {
                    string text = Get("maxspeed:" + direction, Get("maxspeed")); double value;
                    bool mph = text.EndsWith(" mph"); text = text.Replace(" mph", "");
                    return double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value) && value > 0 ? Math.Min(defaultSpeed, value * (mph ? 1.609344 : 1)) : defaultSpeed;
                }
                for (int i = 1; i < ids.Length; i++)
                {
                    if (!nodes.TryGetValue(ids[i - 1], out var a) || !nodes.TryGetValue(ids[i], out var b)) continue;
                    // Exclude restricted barrier nodes rather than inventing passability.
                    double meters = Meters(a, b); if (meters <= 0) continue;
                    void Add(long from, long to, double speed) { if (!profiles[profile].TryGetValue(from, out var list)) profiles[profile][from] = list = []; list.Add(new(to, meters, meters / (speed / 3.6), (long)way.Attribute("id")!)); }
                    if (forward) Add(ids[i - 1], ids[i], Speed("forward"));
                    if (backward || !forward) Add(ids[i], ids[i - 1], Speed("backward"));
                }
            }
        }
        // Barrier access is mode-specific. Explicit permission overrides a generic barrier default.
        foreach (var profile in profiles)
        {
            var barriers = doc.Root.Elements("node").Where(n =>
            {
                var t = Tags(n); string access = t.GetValueOrDefault(profile.Key, t.GetValueOrDefault("motor_vehicle", t.GetValueOrDefault("vehicle", t.GetValueOrDefault("access", ""))));
                if (new[] { "yes", "designated", "permissive" }.Contains(access)) return false;
                if (access.Length > 0) return true;
                return t.TryGetValue("barrier", out var barrier) && barrier is not ("no" or "entrance" or "toll_booth");
            }).Select(n => (long)n.Attribute("id")!).ToHashSet();
            foreach (long id in barriers) profile.Value.Remove(id);
            foreach (var list in profile.Value.Values) list.RemoveAll(e => barriers.Contains(e.To));
        }
        excluded += excludedByProfile.Values.SelectMany(v => v).Distinct().Count();
        if (profiles.Values.All(p => p.Count == 0)) throw new InvalidDataException("Tệp OSM không có cạnh đường đi được.");
        return new RoadGraph(nodes, profiles, version, excluded, restrictions);
    }
}

public sealed class RoadNetwork(IConfiguration config, IWebHostEnvironment environment)
{
    readonly object gate = new(); RoadGraph? graph; DateOnly? graphDate;
    public RoadGraph Graph
    {
        get
        {
            lock (gate)
            {
                var now = DateTimeOffset.UtcNow; var date = DateOnly.FromDateTime(now.ToOffset(TimeSpan.FromHours(7)).Date);
                if (graph is null || graphDate != date) { graph = RoadGraph.Load(Path.GetFullPath(config["Routing:GraphPath"] ?? "Data/roads.osm.gz", environment.ContentRootPath), now); graphDate = date; }
                return graph;
            }
        }
    }
    public double MaxSnapMeters => Math.Clamp(config.GetValue("Routing:MaxSnapMeters", 200d), 10, 500);
    public object Status() { try { return new { available = true, version = Graph.Version, nodes = Graph.NodeCount, edges = Graph.EdgeCount }; } catch (Exception e) when (e is DispatchProblem or InvalidDataException or IOException or XmlException or ArgumentException or UnauthorizedAccessException) { return new { available = false, message = e is DispatchProblem ? e.Message : "Không đọc được mạng đường. Kiểm tra Routing:GraphPath và tệp OSM." }; } }
}
