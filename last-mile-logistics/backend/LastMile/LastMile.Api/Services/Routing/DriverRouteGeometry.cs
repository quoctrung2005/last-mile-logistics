using System.Text.Json;

namespace LastMile.Api.Services.Routing;

public static class DriverRouteGeometry
{
    // A saved route is valid for this stop only while both order and sequence match.
    public static RoadLeg? SavedLeg(string? json, long orderId, int? sequence)
    {
        if (json == null || sequence == null) return null;
        var route = JsonSerializer.Deserialize<ProposedRoute>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (route == null) return null;
        var index = Array.FindIndex(route.Stops, s => s.OrderId == orderId && s.Sequence == sequence);
        return index >= 0 && index < route.Legs.Length ? route.Legs[index] : null;
    }
}
