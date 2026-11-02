using System.Data;
using System.Security.Claims;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController, Authorize, Route("api/v1")]
public sealed class PickupIssueReadController(IConfiguration configuration) : ControllerBase
{
    [HttpGet("my/tasks/{id:long}/pickup-issues")]
    public Task<IActionResult> TaskIssues(long id, CancellationToken ct) => Read(id, null, ct);
    [HttpGet("orders/{orderId:long}/pickup-issues")]
    public Task<IActionResult> OrderIssues(long orderId, CancellationToken ct) => Read(null, orderId, ct);
    private async Task<IActionResult> Read(long? assignment, long? order, CancellationToken ct)
    {
        if (assignment is <= 0 || order is <= 0) return BadRequest(new { message = "Mã nhiệm vụ/đơn không hợp lệ." });
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var account)) return Unauthorized();
        await using var connection = new SqlConnection(configuration.GetConnectionString("DefaultConnection")); await connection.OpenAsync(ct);
        await using var command = new SqlCommand(PickupIssueSql.Actor + PickupIssueSql.TaskScope + "SELECT @OrderId;", connection);
        command.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = account;
        command.Parameters.Add("@AssignmentId", SqlDbType.BigInt).Value = (object?)assignment ?? DBNull.Value;
        command.Parameters.Add("@OrderId", SqlDbType.BigInt).Value = (object?)order ?? DBNull.Value;
        command.Parameters.Add("@IssueId", SqlDbType.BigInt).Value = 0;
        command.Parameters.Add("@Mode", SqlDbType.VarChar, 20).Value = "READ";
        try
        {
            var actualOrder = await command.ExecuteScalarAsync(ct);
            command.CommandText = "SELECT CASE WHEN OBJECT_ID(N'dbo.ShipperPickupIssue',N'U') IS NOT NULL AND OBJECT_ID(N'dbo.ShipperPickupIssueEvent',N'U') IS NOT NULL THEN 1 ELSE 0 END;";
            if (!Equals(await command.ExecuteScalarAsync(ct), 1)) return Ok(new { assignmentId = assignment, orderId = actualOrder, available = false, canReport = false, pickupBlocked = false, items = Array.Empty<object>() });
            var rows = PickupIssueSql.Rows.Trim().TrimEnd(';');
            command.CommandText = PickupIssueSql.Actor + PickupIssueSql.TaskScope + PickupIssueSql.LoadBlocked + $$"""
                SELECT (SELECT @AssignmentId assignmentId,@OrderId orderId,CAST(1 AS BIT) available,@PickupBlocked pickupBlocked,
                  CONVERT(BIT,CASE WHEN @Role='SHIPPER' AND @CurrentPending=1 AND @PickupBlocked=0
                    AND EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE vq.MaVaiTro=@RoleId AND q.KyHieuQuyen='NHIEMVU_CAPNHAT')
                    THEN 1 ELSE 0 END) canReport,
                  JSON_QUERY(COALESCE(({{rows}}),N'[]')) items FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
                """;
            var json = (string?)await command.ExecuteScalarAsync(ct);
            return Content(json ?? "{}", "application/json");
        }
        catch (SqlException e) when (e.Number is >= 55900 and <= 55905) { return StatusCode(e.Number switch { 55900 => 503, 55901 => 401, 55902 => 403, 55903 => 404, _ => 409 }, new { message = e.Message }); }
    }
}
