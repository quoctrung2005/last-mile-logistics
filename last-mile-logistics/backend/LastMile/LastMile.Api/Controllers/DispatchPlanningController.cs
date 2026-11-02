using System.Security.Claims;
using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using LastMile.Api.Services.Routing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public sealed class DispatchExceptionFilter(ILogger<DispatchExceptionFilter> logger) : IExceptionFilter
{
    public void OnException(ExceptionContext context)
    {
        int status;string message;
        switch(context.Exception)
        {
            case DispatchProblem problem:status=problem.Status;message=problem.Message;break;
            case SqlException sql when sql.Number is 1205 or 2601 or 2627 or 54809:
                status=409;message="Dữ liệu vừa được người khác thay đổi hoặc đang được xác nhận. Hãy tải lại/tính lại phương án.";break;
            case Exception e when e is InvalidDataException or System.Xml.XmlException or IOException:
                status=503;message="Dữ liệu mạng đường không hợp lệ. Kiểm tra tệp OSM và cấu hình định tuyến.";break;
            case OperationCanceledException when context.HttpContext.RequestAborted.IsCancellationRequested:return;
            default:logger.LogError(context.Exception,"Dispatch operation failed");status=500;message="Không thực hiện được thao tác điều phối. Hãy thử lại hoặc kiểm tra cấu hình máy chủ.";break;
        }
        context.Result=new ObjectResult(new{message}){StatusCode=status};context.ExceptionHandled=true;
    }
}

[ApiController,Authorize,TypeFilter(typeof(DispatchExceptionFilter))]
[Route("api/v1")]
public sealed class DispatchPlanningController(DispatchData data,DispatchPlanningService planning,RoadNetwork network) : ControllerBase
{
    long AccountId => long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out long id)?id:throw new DispatchProblem(401,"Phiên đăng nhập không hợp lệ.");
    [HttpGet("dispatch/options")]
    public async Task<IActionResult> Options(CancellationToken ct, [FromQuery, Range(1, int.MaxValue)] int? branchId = null)
    {
        var options=JsonSerializer.Deserialize<Dictionary<string,JsonElement>>(await data.Options(AccountId,ct,branchId))!;
        return Ok(new{branches=options["branches"],warehouses=options["warehouses"],areas=options["areas"],shippers=options["shippers"],routing=network.Status(),maxOrders=60,maxShippers=15});
    }
    [HttpPost("dispatch/plans")]
    public async Task<IActionResult> Preview(PlanRequest request,CancellationToken ct)=>Ok(await planning.Preview(AccountId,request,ct));
    [HttpGet("dispatch/plans/{id:guid}")]
    public async Task<IActionResult> Get(Guid id,CancellationToken ct)=>Content(await planning.GetPlan(AccountId,id,ct),"application/json");
    [HttpPost("dispatch/plans/{id:guid}/confirm")]
    public async Task<IActionResult> Confirm(Guid id,CancellationToken ct)=>Content(await planning.Confirm(AccountId,id,ct),"application/json");
    [HttpGet("trips/{id:long}/route")]
    public async Task<IActionResult> Geometry(long id,CancellationToken ct)=>Ok(new{route=JsonSerializer.Deserialize<JsonElement>(await planning.Geometry(AccountId,id,ct))});
}
