using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace LastMile.Api.Hubs;

[Authorize(Roles = "SHIPPER")]
public sealed class ShipperHub : Hub
{
    public static string AccountGroup(long accountId) => $"account:{accountId}";

    public override async Task OnConnectedAsync()
    {
        if (long.TryParse(Context.User?.FindFirstValue(ClaimTypes.NameIdentifier), out var id) && id > 0)
            await Groups.AddToGroupAsync(Context.ConnectionId, AccountGroup(id));
        else
            throw new HubException("Phiên đăng nhập không hợp lệ.");
        await base.OnConnectedAsync();
    }
}
