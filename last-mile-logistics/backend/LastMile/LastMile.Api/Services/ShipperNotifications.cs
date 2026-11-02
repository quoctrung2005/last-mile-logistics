using System.Data;
using System.Text.Json;
using LastMile.Api.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Services;

// Call only after commit. Notifications are hints; authenticated REST reads remain authoritative.
public sealed class ShipperNotifications(
    IConfiguration configuration, IHubContext<ShipperHub> hub, ILogger<ShipperNotifications> logger)
{
    public async Task AssignmentCreated(string? result)
    {
        if (string.IsNullOrWhiteSpace(result)) return;
        try
        {
            using var document = JsonDocument.Parse(result);
            await Publish("TaskAssigned", document.RootElement.GetProperty("id").GetInt64(), null);
        }
        catch (Exception ex) { logger.LogWarning(ex, "Could not notify shipper after assignment commit."); }
    }

    public Task TripsCreated(IEnumerable<long> tripIds) => Publish("TaskAssigned", null, tripIds.ToArray());

    public Task TaskUpdated(long assignmentId) => Publish("TaskUpdated", assignmentId, null);

    public Task OrderTasksUpdated(long orderId) => Publish("TaskUpdated", null, null, orderId);

    public Task HandoverCreated(long assignmentId) => Publish("HandoverReady", assignmentId, null);

    private async Task Publish(string eventName, long? assignmentId, long[]? tripIds, long? orderId = null)
    {
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await using var connection = new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
            await connection.OpenAsync(timeout.Token);
            await using var command = new SqlCommand("""
                SELECT n.MaTaiKhoan, p.MaPhanCongGiaoHang, p.MaDonHang,
                       d.KyHieuDonHang, d.MaVanDon, v.BienSo
                FROM dbo.PhanCongGiaoHang p
                JOIN dbo.NhanVienGiaoHang n ON n.MaNhanVienGiaoHang=p.MaNhanVienGiaoHang
                JOIN dbo.DonHang d ON d.MaDonHang=p.MaDonHang
                JOIN dbo.PhuongTien v ON v.MaPhuongTien=p.MaPhuongTien
                WHERE ((@assignment IS NOT NULL AND p.MaPhanCongGiaoHang=@assignment)
                    OR p.MaChuyenGiao IN (SELECT CONVERT(BIGINT, [value]) FROM OPENJSON(@trips)) OR (@orderId IS NOT NULL AND p.MaDonHang=@orderId))
                  AND p.ThoiGianKetThuc IS NULL AND n.DangHoatDong=1;
                """, connection);
            command.Parameters.Add("@orderId", SqlDbType.BigInt).Value = (object?)orderId ?? DBNull.Value;
            command.Parameters.Add("@assignment", SqlDbType.BigInt).Value = (object?)assignmentId ?? DBNull.Value;
            command.Parameters.Add("@trips", SqlDbType.NVarChar, -1).Value = JsonSerializer.Serialize(tripIds ?? []);
            await using var reader = await command.ExecuteReaderAsync(timeout.Token);
            while (await reader.ReadAsync(timeout.Token))
            {
                var payload = new
                {
                    id = reader.GetInt64(1),
                    assignmentId = reader.GetInt64(1),
                    orderId = reader.GetInt64(2),
                    orderCode = reader.GetString(3),
                    trackingNumber = reader.GetString(4),
                    licensePlate = reader.GetString(5)
                };
                await hub.Clients.Group(ShipperHub.AccountGroup(reader.GetInt64(0)))
                    .SendAsync(eventName, payload, timeout.Token);
            }
        }
        catch (Exception ex) { logger.LogWarning(ex, "Could not send {EventName}; shipper can refresh the list.", eventName); }
    }
}
