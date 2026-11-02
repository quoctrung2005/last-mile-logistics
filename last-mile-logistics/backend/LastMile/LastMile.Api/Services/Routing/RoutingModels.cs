using System.ComponentModel.DataAnnotations;

namespace LastMile.Api.Services.Routing;

public sealed record GeoPoint(double Latitude, double Longitude)
{
    public bool IsValid => double.IsFinite(Latitude) && double.IsFinite(Longitude) && Math.Abs(Latitude) <= 90 && Math.Abs(Longitude) <= 180;
}
public sealed record RoadLeg(double DistanceMeters, double TravelSeconds, GeoPoint[] Geometry);
public sealed class DispatchProblem(int status, string message) : Exception(message)
{
    public int Status { get; } = status;
}
public sealed class PlanRequest
{
    [Range(1, int.MaxValue)] public int WarehouseId { get; set; }
    [Required, MinLength(1), MaxLength(60)] public List<long> OrderIds { get; set; } = [];
    [Required, MaxLength(15)] public List<long> ShipperIds { get; set; } = [];
    public DateTimeOffset DepartureAt { get; set; }
    [Range(0, 60)] public int ServiceMinutes { get; set; } = 5;
    public bool ReturnToDepot { get; set; } = true;
    // An explicitly edited/manual solution is always evaluated by the same routing/constraint engine.
    public List<ManualRoute>? ManualRoutes { get; set; }
    [Range(1, long.MaxValue)] public long? ExistingTripId { get; set; }
    public void Validate()
    {
        if(WarehouseId<=0||OrderIds==null||ShipperIds==null||OrderIds.Count is <1 or >60||OrderIds.Any(id=>id<=0)||OrderIds.Distinct().Count()!=OrderIds.Count
            ||ShipperIds.Count>15||ShipperIds.Any(id=>id<=0)||ShipperIds.Distinct().Count()!=ShipperIds.Count||ServiceMinutes is <0 or >60
            ||ManualRoutes?.Count>15||ManualRoutes?.Any(r=>r==null||r.OrderIds==null||r.OrderIds.Count>60)==true
            ||ManualRoutes!=null&&ManualRoutes.Select(r=>r.ShipperId).Distinct().Count()!=ManualRoutes.Count)
            throw new DispatchProblem(400,"Chọn 1–60 đơn không trùng, tối đa 15 shipper; thời gian phục vụ từ 0–60 phút.");
        if(DepartureAt<=DateTimeOffset.UtcNow||DepartureAt>DateTimeOffset.UtcNow.AddDays(7))throw new DispatchProblem(400,"Thời gian xuất phát phải trong tương lai và không quá 7 ngày.");
    }
}
public sealed record ManualRoute(long ShipperId, List<long> OrderIds);
public sealed record PlanningOrder(long Id, string Version, string TrackingNumber, string ReceiverName, string Address,
    long PointId, int? AreaId, decimal WeightKg, decimal? VolumeM3, int Priority, DateTimeOffset? Deadline, GeoPoint? Point,
    DateTimeOffset? ReadyAt = null, DateTimeOffset? RequestedDeliveryAt = null);
public sealed record PlanningVehicle(long ShipperId, string ShipperName, long VehicleId, string LicensePlate,
    string VehicleType, decimal CapacityKg, decimal? CapacityM3, int[] Areas, string? EligibilityReason,
    int CarriedReturnCount = 0, decimal CarriedReturnKg = 0, decimal? CarriedReturnM3 = 0);
public sealed record PlanningInput(int WarehouseId, int BranchId, string WarehouseName, GeoPoint? Depot,
    PlanningOrder[] Orders, PlanningVehicle[] Vehicles, string Fingerprint);
public sealed record UnplannedOrder(long OrderId, string TrackingNumber, string Reason);
public sealed record PlannedStop(long OrderId, string TrackingNumber, string ReceiverName, string Address, int Sequence,
    decimal WeightKg, DateTimeOffset ArrivalAt, DateTimeOffset DepartureAt, double DistanceFromPreviousKm,
    double TravelMinutes, GeoPoint Point, double SnapDistanceMeters,
    DateTimeOffset? ServiceStartAt = null, double? WaitingMinutes = null,
    DateTimeOffset? RequestedDeliveryAt = null, DateTimeOffset? ExpectedDeliveryAt = null);
public sealed record ProposedRoute(long ShipperId, string ShipperName, long VehicleId, string LicensePlate,
    string VehicleType, decimal WeightKg, decimal CapacityKg, decimal? VolumeM3, decimal? CapacityM3,
    double DistanceKm, double DurationMinutes, DateTimeOffset EndAt, PlannedStop[] Stops, RoadLeg[] Legs, GeoPoint? Depot = null,
    int CarriedReturnCount = 0, decimal CarriedReturnKg = 0, decimal? CarriedReturnM3 = 0);
public sealed record Proposal(Guid Id, string Method, string RoadAlgorithm, string GraphVersion, DateTimeOffset ExpiresAt,
    GeoPoint Depot, int WarehouseId, string WarehouseName, DateTimeOffset DepartureAt, int ServiceMinutes, bool ReturnToDepot,
    ProposedRoute[] Routes, UnplannedOrder[] Unplanned, string[] Warnings, bool TimeLimitReached);
