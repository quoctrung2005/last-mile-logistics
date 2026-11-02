using System.Data;
using System.Security.Claims;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController, Authorize, Route("api/v1")]
public sealed class PickupReceiptReadController(IConfiguration configuration) : ControllerBase
{
    [HttpGet("orders/{orderId:long}/pickup-receipts")]
    public async Task<IActionResult> List(long orderId, CancellationToken ct)
    {
        if (orderId <= 0) return BadRequest(new { message = "Mã đơn không hợp lệ." });
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var account)) return Unauthorized();
        await using var connection = new SqlConnection(configuration.GetConnectionString("DefaultConnection")); await connection.OpenAsync(ct);
        await using var command = new SqlCommand(PickupReceiptReadSql.Authorize + "SELECT 1;", connection);
        command.Parameters.AddWithValue("@Account", account); command.Parameters.AddWithValue("@Order", orderId); command.Parameters.AddWithValue("@Assignment", DBNull.Value);
        try
        {
            await command.ExecuteScalarAsync(ct);
            command.CommandText = "SELECT OBJECT_ID(N'dbo.ShipperPickupReceipt',N'U');";
            if (await command.ExecuteScalarAsync(ct) is DBNull) return Ok(new { items = Array.Empty<object>() });
            command.CommandText = PickupReceiptReadSql.Authorize + PickupReceiptReadSql.Rows;
            var rows = (string?)await command.ExecuteScalarAsync(ct) ?? "[]";
            return Content("{\"items\":" + rows + "}", "application/json");
        }
        catch (SqlException e) when (e.Number is >= 55801 and <= 55803) { return StatusCode(e.Number == 55801 ? 401 : e.Number == 55802 ? 403 : 404, new { message = e.Message }); }
    }
}
