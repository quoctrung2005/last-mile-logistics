using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using LastMile.Api.Services.Routing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace LastMile.Api.Controllers;

public sealed class OptimizeTripRequest
{
    [Required,MinLength(1),MaxLength(1)] public List<long> ShipperIds { get; set; }=[];
    public DateTimeOffset DepartureAt { get; set; }
    [Range(0,60)] public int ServiceMinutesPerStop { get; set; }=5;
    public bool ReturnToBranch { get; set; }=true;
}

// The existing optimize endpoint now creates a road-based proposal; confirmation is explicit.
[ApiController,Authorize,TypeFilter(typeof(DispatchExceptionFilter))]
[Route("api/v1/trips")]
public sealed class TripOptimizationController(DispatchPlanningService planning) : ControllerBase
{
    [HttpPost("{id:long}/optimize")]
    public async Task<IActionResult> Optimize(long id,OptimizeTripRequest request,CancellationToken ct)
    {
        if(!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out long account))return Unauthorized();
        return Ok(await planning.PreviewExistingTrip(account,id,request.ShipperIds,request.DepartureAt,request.ServiceMinutesPerStop,request.ReturnToBranch,ct));
    }
}
