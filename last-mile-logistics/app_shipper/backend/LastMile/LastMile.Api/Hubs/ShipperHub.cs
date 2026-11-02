using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace LastMile.Api.Hubs;

[Authorize]
public sealed class ShipperHub : Hub
{
    public override async Task OnConnectedAsync()
    {
        var accountId = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier);
        if (long.TryParse(accountId, out var id) && id > 0)
            await Groups.AddToGroupAsync(Context.ConnectionId, AccountGroup(id));

        await base.OnConnectedAsync();
    }

    public static string AccountGroup(long accountId) => $"account:{accountId}";
}
