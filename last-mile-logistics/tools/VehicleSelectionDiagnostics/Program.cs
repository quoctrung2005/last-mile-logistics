using System.Text.Json;
using LastMile.Api.Services;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using LastMile.Api.Controllers;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

// Read-only application-database diagnostics. Never change a vehicle/assignment.
var root = Path.GetFullPath(args.Single());
var configuration = new ConfigurationBuilder()
    .SetBasePath(Path.Combine(root, "backend/LastMile/LastMile.Api"))
    .AddJsonFile("appsettings.json").AddJsonFile("appsettings.Development.json", optional: true)
    .AddUserSecrets(typeof(AuthTokenService).Assembly, optional: true).AddEnvironmentVariables().Build();
var builder = new SqlConnectionStringBuilder(configuration.GetConnectionString("DefaultConnection"));
var source = configuration.Providers.Reverse().First(p => p.TryGet("ConnectionStrings:DefaultConnection", out _));
await using var connection = new SqlConnection(builder.ConnectionString);
await connection.OpenAsync();
await using var command = new SqlCommand("""
    SELECT (
      SELECT DB_NAME() AS databaseName,
        JSON_QUERY((SELECT name,TYPE_NAME(system_type_id) AS type FROM sys.columns WHERE object_id=OBJECT_ID('dbo.PhuongTien') ORDER BY column_id FOR JSON PATH)) vehicleColumns,
        (SELECT COUNT_BIG(*) FROM dbo.PhuongTien) totalVehicles,
        (SELECT COUNT_BIG(*) FROM dbo.PhuongTien WHERE DangHoatDong=1 AND TrangThaiPhuongTien='AVAILABLE') activeAvailable,
        JSON_QUERY((SELECT pt.MaPhuongTien id,pt.KyHieuPhuongTien code,pt.BienSo licensePlate,pt.LoaiXe vehicleType,pt.TrangThaiPhuongTien status,pt.DangHoatDong isActive,
          pc.MaNhanVienGiaoHang currentShipperId,tk.MaBuuCuc branchId,
          CASE WHEN pt.DangHoatDong=0 THEN 'INACTIVE'
            WHEN pt.TrangThaiPhuongTien<>'AVAILABLE' THEN 'NOT_AVAILABLE'
            WHEN pc.MaPhanCongPhuongTien IS NOT NULL THEN 'ALREADY_LINKED'
            WHEN EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang p WHERE p.MaPhuongTien=pt.MaPhuongTien AND p.ThoiGianKetThuc IS NULL) THEN 'ACTIVE_ASSIGNMENT'
            WHEN EXISTS(SELECT 1 FROM dbo.ChuyenGiaoHang c WHERE c.MaPhuongTien=pt.MaPhuongTien AND c.TrangThaiChuyen IN('PLANNED','ASSIGNED','ACCEPTED','IN_PROGRESS')) THEN 'OPEN_TRIP'
            WHEN EXISTS(SELECT 1 FROM dbo.DonHang d JOIN dbo.TrangThaiDonHang s ON s.MaTrangThaiDonHang=d.MaTrangThaiHienTai
              CROSS APPLY(SELECT TOP(1) p.MaPhuongTien FROM dbo.PhanCongGiaoHang p WHERE p.MaDonHang=d.MaDonHang ORDER BY p.ThoiGianPhanCong DESC,p.MaPhanCongGiaoHang DESC)p
              WHERE s.KyHieuTrangThai='RETURNING' AND p.MaPhuongTien=pt.MaPhuongTien) THEN 'RETURN_TASK'
            ELSE 'ELIGIBLE' END eligibility
          FROM dbo.PhuongTien pt LEFT JOIN dbo.PhanCongPhuongTien pc ON pc.MaPhuongTien=pt.MaPhuongTien AND pc.ThoiGianKetThuc IS NULL
          LEFT JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang=pc.MaNhanVienGiaoHang
          LEFT JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan=nv.MaTaiKhoan
          ORDER BY pt.MaPhuongTien FOR JSON PATH,INCLUDE_NULL_VALUES)) vehicles
      FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    """, connection);
using var data = JsonDocument.Parse((string)(await command.ExecuteScalarAsync())!);
command.CommandText = """
    SELECT TOP (1) tk.MaTaiKhoan FROM dbo.TaiKhoan tk JOIN dbo.VaiTro vt ON vt.MaVaiTro=tk.MaVaiTro
    WHERE vt.KyHieuVaiTro='ADMIN' AND tk.TrangThaiTaiKhoan='ACTIVE' ORDER BY tk.MaTaiKhoan;
    """;
var actor = Convert.ToInt64(await command.ExecuteScalarAsync());
command.CommandText = "SELECT MaNhanVienGiaoHang,tk.MaBuuCuc FROM dbo.NhanVienGiaoHang nv JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan=nv.MaTaiKhoan WHERE tk.MaBuuCuc IS NOT NULL ORDER BY nv.MaNhanVienGiaoHang";
var targets = new List<(long Id, int Branch)>();
await using (var reader = await command.ExecuteReaderAsync())
    while (await reader.ReadAsync()) targets.Add((reader.GetInt64(0), reader.GetInt32(1)));
var controller = new VehiclesController(configuration)
{
    ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext
    {
        User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actor.ToString())], "ReadOnlyDiagnostic"))
    } }
};
var controllerResults = new List<JsonElement>();
foreach (var target in targets)
{
    var response = await controller.Get(assignableOnly: true, forShipperId: target.Id, branchId: target.Branch, includeUnavailable: true, pageSize: 100);
    if (response is not ContentResult { Content: { } body }) throw new InvalidOperationException($"Read-only lookup returned {response.GetType().Name}");
    using var result = JsonDocument.Parse(body);
    foreach (var row in result.RootElement.GetProperty("items").EnumerateArray())
    {
        if (!row.GetProperty("canSelect").GetBoolean() && string.IsNullOrWhiteSpace(row.GetProperty("unavailableReason").GetString()))
            throw new InvalidOperationException("Unavailable vehicle has no explanation");
        if (row.GetProperty("currentShipperBranchId") is { ValueKind: JsonValueKind.Number } branch && branch.GetInt32() != target.Branch)
            throw new InvalidOperationException("Vehicle from another branch leaked into picker");
    }
    controllerResults.Add(result.RootElement.Clone());
}
var report = new { mode = "Read-only Development configuration including user secrets/environment; no database writes", server = builder.DataSource,
    configurationSource = source.ToString(), data = data.RootElement,
    verificationLayer = "Updated controller and real SQL with live permission checks; JWT middleware covered separately in isolated HTTP tests",
    selectionResults = controllerResults };
var json = JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });
await File.WriteAllTextAsync(Path.Combine(root, "docs/vehicle-picker-database-diagnostic.json"), json + "\n");
Console.WriteLine(json);
