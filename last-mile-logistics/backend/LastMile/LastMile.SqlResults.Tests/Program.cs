using System.Data;
using System.Security.Claims;
using System.Text.Json;
using System.Text.RegularExpressions;
using LastMile.Api.Controllers;
using LastMile.Api.Services;
using LastMile.Api.Services.Routing;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Logging;

try { await Run(Path.GetFullPath(args.Single())); }
catch (Exception error) { Console.Error.WriteLine(error); Environment.ExitCode = 1; }

static async Task Run(string root)
{
    var checks = new List<string>();
    void Check(bool condition, string name)
    {
        if (!condition) throw new InvalidOperationException(name);
        checks.Add(name); Console.WriteLine("PASS " + name);
    }
    var project = Path.Combine(root, "backend/LastMile/LastMile.Api");
    var configuration = new ConfigurationBuilder().SetBasePath(project).AddJsonFile("appsettings.json")
        .AddJsonFile("appsettings.Development.json", optional: true).Build();
    var builder = new SqlConnectionStringBuilder(configuration.GetConnectionString("DefaultConnection"));
    if (!builder.DataSource.StartsWith("(localdb)", StringComparison.OrdinalIgnoreCase))
        throw new InvalidOperationException("SQL result tests require LocalDB");
    var database = "CodexSqlResults_" + Guid.NewGuid().ToString("N");
    builder.InitialCatalog = "master"; builder.Encrypt = SqlConnectionEncryptOption.Optional;
    var master = builder.ConnectionString;
    builder.InitialCatalog = database;
    var connectionString = builder.ConnectionString;
    var config = new ConfigurationBuilder().AddConfiguration(configuration)
        .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:DefaultConnection"] = connectionString }).Build();
    async Task Execute(string sql, bool useMaster = false)
    {
        await using var connection = new SqlConnection(useMaster ? master : connectionString);
        await connection.OpenAsync();
        await using var command = new SqlCommand(sql, connection) { CommandTimeout = 120 };
        await command.ExecuteNonQueryAsync();
    }
    async Task<T> Scalar<T>(string sql)
    {
        await using var connection = new SqlConnection(connectionString); await connection.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        var value = await command.ExecuteScalarAsync();
        return value is T typed ? typed : throw new InvalidOperationException("Fixture scalar contract failed");
    }
    async Task Reject(string sql, string[] columns, Func<SqlResult.Row, object> read, string name)
    {
        await using var connection = new SqlConnection(connectionString); await connection.OpenAsync();
        await using var command = new SqlCommand(sql, connection); await using var reader = await command.ExecuteReaderAsync();
        try { await SqlResult.ReadSingleAsync(reader, columns, read); }
        catch (SqlResultContractException) { Check(true, name); return; }
        throw new InvalidOperationException("Accepted invalid SQL result: " + name);
    }
    JsonElement Result(IActionResult response, int status)
    {
        if (response is not ObjectResult result || (result.StatusCode ?? 200) != status)
            throw new InvalidOperationException($"Expected status {status}, got {response.GetType().Name} {(response as ObjectResult)?.StatusCode}");
        return JsonSerializer.SerializeToElement(result.Value);
    }
    T Actor<T>(T controller, long accountId) where T : ControllerBase
    {
        controller.ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, accountId.ToString())], "SqlTest"))
        } };
        return controller;
    }
    bool Unknown(IActionResult response)
    {
        var data = Result(response, 500);
        return data.GetProperty("resultUnknown").GetBoolean() && data.GetProperty("message").GetString() == SqlResult.UnknownWriteMessage;
    }
    try
    {
        foreach (var file in new[] { "QLGiaoHangChangCuoi_SQLServer_V5 .sql", "DuLieuThucTe_QLGiaoHangChangCuoi_V5 .sql" })
        {
            var sql = (await File.ReadAllTextAsync(Path.Combine(root, "database", file))).Replace("QLGiaoHangChangCuoi", database);
            // Keep USE across batches on the same bootstrap connection.
            await using var connection = new SqlConnection(master); await connection.OpenAsync();
            foreach (var batch in Regex.Split(sql, @"(?im)^\s*GO\s*(?:--[^\r\n]*)?\r?$"))
            {
                if (string.IsNullOrWhiteSpace(batch)) continue;
                await using var command = new SqlCommand(batch, connection) { CommandTimeout = 120 };
                await command.ExecuteNonQueryAsync();
            }
        }
        // Test the shared boundary against real SQL/TDS, not a mocked reader.
        await Reject("SET NOCOUNT ON;", ["Id"], row => row.Id("Id"), "No result set is rejected");
        await Reject("SELECT CAST(1 AS BIGINT) Id WHERE 1=0", ["Id"], row => row.Id("Id"), "Empty result is rejected before accessing a column");
        await Reject("SELECT CAST(NULL AS BIGINT) Id", ["Id"], row => row.Id("Id"), "DBNull ID is rejected instead of converting to zero");
        await Reject("SELECT CAST(0 AS BIGINT) Id", ["Id"], row => row.Id("Id"), "Zero ID is rejected");
        await Reject("SELECT 1 Id", ["Id"], row => row.Id("Id"), "Unexpected numeric SQL type is rejected");
        await Reject("SELECT 'sensitive-result-must-not-be-logged' Other", ["Id"], row => row.Id("Id"), "Missing required column is rejected");
        await Reject("SELECT CAST(1 AS BIGINT) Id, 2 Extra", ["Id"], row => row.Id("Id"), "Unexpected column is rejected");
        await Reject("SELECT CAST(1 AS BIGINT) Id, CAST(2 AS BIGINT) Id", ["Id", "Id"], row => row.Id("Id"), "Duplicate column names are rejected");
        await Reject("SELECT CAST(1 AS BIGINT) Id UNION ALL SELECT 2", ["Id"], row => row.Id("Id"), "Multiple rows are rejected");
        await Reject("SELECT CAST(1 AS BIGINT) Id; SELECT CAST(2 AS BIGINT) Id", ["Id"], row => row.Id("Id"), "Extra result set is rejected, never silently skipped");
        await Reject("SELECT CAST(1 AS BIGINT) Id; SELECT 2 Unexpected WHERE 1=0", ["Id"], row => row.Id("Id"), "Extra empty result set is rejected");
        await Reject("SELECT CAST(NULL AS BINARY(8)) Version", ["Version"], row => row.Version(), "NULL rowversion is rejected");
        await Reject("SELECT CAST(1 AS BINARY(7)) Version", ["Version"], row => row.Version(), "Rowversion must contain exactly eight bytes");
        await Reject("SELECT CAST(NULL AS DECIMAL(18,2)) Fee", ["Fee"], row => row.NonNegative("Fee"), "NULL fee is rejected");
        await Reject("SELECT CAST(-1 AS DECIMAL(18,2)) Fee", ["Fee"], row => row.NonNegative("Fee"), "Negative result fee is rejected");
        await Reject("SELECT 'not-json' Points", ["Points"], row => row.JsonArray("Points"), "Malformed snapshot JSON is rejected without exposing contents");
        await Reject("SELECT '{}' Points", ["Points"], row => row.JsonArray("Points"), "Snapshot JSON must be an array");
        // No row is legitimate only for a detail lookup, not a successful write.
        await using (var connection = new SqlConnection(connectionString))
        {
            await connection.OpenAsync(); await using var command = new SqlCommand("SELECT CAST(1 AS BIGINT) Id WHERE 1=0", connection);
            await using var reader = await command.ExecuteReaderAsync();
            var value = await SqlResult.ReadSingleAsync(reader, ["Id"], row => (long?)row.Id("Id"), whenEmpty: () => null);
            Check(value is null, "An explicitly optional detail lookup retains its no-row contract");
        }
        // Demonstrate that a result failure does not imply rollback.
        await Execute("CREATE TABLE dbo.QaCommitted(Id INT NOT NULL)");
        await Reject("BEGIN TRAN; INSERT dbo.QaCommitted VALUES(1); COMMIT; SELECT CAST(NULL AS BIGINT) Id", ["Id"], row => row.Id("Id"), "Committed write with unreadable output is rejected");
        Check(await Scalar<int>("SELECT COUNT(*) FROM dbo.QaCommitted") == 1, "The committed write remains saved despite unreadable output");

        var admin = await Scalar<long>("SELECT MIN(t.MaTaiKhoan) FROM dbo.TaiKhoan t JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro WHERE v.KyHieuVaiTro='ADMIN'");
        var denied = await Scalar<long>("SELECT MIN(t.MaTaiKhoan) FROM dbo.TaiKhoan t JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro WHERE v.KyHieuVaiTro='ACCOUNTANT'");
        var updateLog = new TestLogger<OrderUpdateController>(); var confirmLog = new TestLogger<OrderConfirmController>();
        var moveLog = new TestLogger<WarehouseMoveController>(); var createLog = new TestLogger<OrderCreateController>(); var inboundLog = new TestLogger<WarehouseInboundController>();
        var network = new RoadNetwork(config, new TestEnvironment { ContentRootPath = project });
        var create = Actor(new OrderCreateController(config, createLog), admin);
        var update = Actor(new OrderUpdateController(config, updateLog), admin);
        var confirm = Actor(new OrderConfirmController(config, confirmLog, network), admin);
        var inbound = Actor(new WarehouseInboundController(config, inboundLog), admin);
        var move = Actor(new WarehouseMoveController(config, moveLog), admin);
        var branch = await Scalar<int>("SELECT MaBuuCuc FROM dbo.BuuCuc WHERE KyHieuBuuCuc='HCM-BT01'");
        var warehouse = await Scalar<int>($"SELECT MIN(MaKho) FROM dbo.Kho WHERE MaBuuCuc={branch} AND DangHoatDong=1");
        var from = await Scalar<long>($"SELECT MIN(MaViTriLuuKho) FROM dbo.ViTriLuuKho WHERE MaKho={warehouse} AND DangHoatDong=1");
        var to = await Scalar<long>($"SELECT MIN(MaViTriLuuKho) FROM dbo.ViTriLuuKho WHERE MaKho={warehouse} AND DangHoatDong=1 AND MaViTriLuuKho<>{from}");
        var addresses = JsonDocument.Parse(await Scalar<string>("SELECT TOP (2) MaDiaChiKhachHang id,MaKhachHang customer FROM dbo.DiaChiKhachHang WHERE DangHoatDong=1 AND ViDo IS NOT NULL AND KinhDo IS NOT NULL ORDER BY MaDiaChiKhachHang FOR JSON PATH"));
        var address = addresses.RootElement.EnumerateArray().ToArray();
        var request = new CreateOrderRequest
        {
            BranchId = branch, SenderId = address[0].GetProperty("customer").GetInt64(), ReceiverId = address[1].GetProperty("customer").GetInt64(),
            PickupAddressId = address[0].GetProperty("id").GetInt64(), DeliveryAddressId = address[1].GetProperty("id").GetInt64(),
            ServiceId = await Scalar<int>("SELECT MIN(MaLoaiDichVu) FROM dbo.LoaiDichVu WHERE DangHoatDong=1"),
            ExpectedDeliveryAt = DateTimeOffset.UtcNow.AddDays(10), Notes = "Isolated SQL result test",
            Items = [new() { Name = "Test parcel", Quantity = 1, UnitWeightKg = 1, LengthCm = 10, WidthCm = 10, HeightCm = 10 }]
        };
        var created = Result(await create.Create(request), 201);
        var orderId = created.GetProperty("id").GetInt64();
        Check(orderId > 0 && created.GetProperty("orderCode").GetString()?.Length > 0 && created.GetProperty("trackingNumber").GetString()?.Length > 0,
            "Create returns a positive real order ID and the existing success contract");
        var edit = JsonSerializer.Deserialize<UpdateOrderRequest>(JsonSerializer.Serialize(request))!;
        edit.ExpectedVersion = Convert.ToBase64String(await Scalar<byte[]>($"SELECT PhienBan FROM dbo.DonHang WHERE MaDonHang={orderId}"));
        edit.Notes = "Edited SQL result test";
        var edited = Result(await update.Update(orderId, edit), 200);
        Check(edited.GetProperty("id").GetInt64() == orderId && Convert.FromBase64String(edited.GetProperty("version").GetString()!).Length == 8 &&
            edited.GetProperty("weightKg").GetDecimal() == 1 && edited.GetProperty("shippingFee").GetDecimal() == 0,
            "Update returns the complete version/weight/fee contract");
        var audits = await Scalar<int>($"SELECT COUNT(*) FROM dbo.NhatKyHoatDong WHERE LoaiThaoTac='UPDATE_ORDER' AND MaDoiTuong='{orderId}'");
        Result(await update.Update(orderId, edit), 409);
        Check(await Scalar<int>($"SELECT COUNT(*) FROM dbo.NhatKyHoatDong WHERE LoaiThaoTac='UPDATE_ORDER' AND MaDoiTuong='{orderId}'") == audits,
            "Stale update version remains 409 and adds no successful audit");
        Result(await confirm.Confirm(orderId, new() { ExpectedVersion = edit.ExpectedVersion }, default), 409);
        Check(true, "Stale confirmation version remains 409");
        var confirmed = Result(await confirm.Confirm(orderId, new() { ExpectedVersion = edited.GetProperty("version").GetString() }, default), 200);
        Check(confirmed.GetProperty("ruleId").GetInt64() > 0 && confirmed.GetProperty("shippingFee").GetDecimal() >= 0 &&
            confirmed.GetProperty("calculatedShippingFee").GetDecimal() >= 0 && confirmed.GetProperty("weightKg").GetDecimal() == 1 &&
            confirmed.GetProperty("distanceKm").GetDecimal() > 0 && Convert.FromBase64String(confirmed.GetProperty("version").GetString()!).Length == 8,
            "Confirmation with real road routing/procedures returns complete fee/version data");
        var received = Result(await inbound.Inbound(new() { OrderId = orderId, WarehouseId = warehouse, LocationId = from }), 201);
        Check(received.GetProperty("transactionId").GetInt64() > 0 && received.GetProperty("orderStatus").GetString() == "IN_WAREHOUSE", "Inbound returns a positive transaction ID and existing state contract");
        var moved = Result(await move.Move(new() { OrderId = orderId, FromLocationId = from, ToLocationId = to }), 201);
        Check(moved.GetProperty("transactionId").GetInt64() > 0 && moved.GetProperty("warehouseId").GetInt32() == warehouse && moved.GetProperty("toLocationId").GetInt64() == to, "Move returns complete transaction/warehouse/location data");
        Result(await move.Move(new() { OrderId = orderId, FromLocationId = from, ToLocationId = to }), 409);
        Check(await Scalar<long>($"SELECT MaViTriLuuKho FROM dbo.TonKhoDonHang WHERE MaDonHang={orderId}") == to, "Stale source location remains 409 without moving stock again");
        Check(await Actor(new OrderUpdateController(config, updateLog), denied).Update(orderId, edit) is ForbidResult, "Live update permission checks remain enforced");
        Check(await Actor(new WarehouseMoveController(config, moveLog), denied).Move(new() { OrderId = orderId, FromLocationId = to, ToLocationId = from }) is ForbidResult, "Live warehouse permission checks remain enforced");
        Result(await confirm.Confirm(long.MaxValue, new(), default), 404);
        Check(true, "Missing confirmation snapshot retains 404 instead of becoming an unreadable success");

        // New order for controlled trigger/procedure result regressions. All fault
        // injection is confined to this GUID test database and never ships in API.
        var faultId = Result(await create.Create(request), 201).GetProperty("id").GetInt64();
        var shape = "CONVERT(BINARY(8),1) Version,CAST(1 AS DECIMAL(12,3)) WeightKg,CAST(0 AS DECIMAL(18,2)) ShippingFee";
        foreach (var (label, output) in new[]
        {
            ("empty", "SELECT " + shape + " WHERE 1=0;"),
            ("missing column", "SELECT CONVERT(BINARY(8),1) Version;"),
            ("NULL version", "SELECT CAST(NULL AS BINARY(8)) Version,CAST(1 AS DECIMAL(12,3)) WeightKg,CAST(0 AS DECIMAL(18,2)) ShippingFee;"),
            ("NULL weight", "SELECT CONVERT(BINARY(8),1) Version,CAST(NULL AS DECIMAL(12,3)) WeightKg,CAST(0 AS DECIMAL(18,2)) ShippingFee;"),
            ("NULL fee", "SELECT CONVERT(BINARY(8),1) Version,CAST(1 AS DECIMAL(12,3)) WeightKg,CAST(NULL AS DECIMAL(18,2)) ShippingFee;"),
            ("extra set", "SELECT " + shape + ";")
        })
        {
            await Execute($"CREATE OR ALTER TRIGGER dbo.QaUnexpectedResult ON dbo.NhatKyHoatDong AFTER INSERT AS BEGIN SET NOCOUNT ON; IF EXISTS(SELECT 1 FROM inserted WHERE LoaiThaoTac='UPDATE_ORDER') BEGIN {output} END; END");
            edit.ExpectedVersion = Convert.ToBase64String(await Scalar<byte[]>($"SELECT PhienBan FROM dbo.DonHang WHERE MaDonHang={faultId}"));
            Check(Unknown(await update.Update(faultId, edit)), "Update handles trigger " + label + " with a controlled 500 and uncertain-result guidance");
        }
        Check(updateLog.Messages.All(m => !m.Contains(request.Notes!) && !m.Contains("sensitive-result")) &&
            updateLog.Messages.Any(m => m.Contains("PUT /api/v1/orders/{id}") && m.Contains(faultId.ToString()) && m.Contains("reason")),
            "Result logs contain endpoint/object/reason without payload or result contents");
        await Execute("DROP TRIGGER dbo.QaUnexpectedResult");
        var procedure = await Scalar<string>("SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_XacNhanDonHang'))");
        procedure = Regex.Replace(procedure, @"^\s*(?:CREATE(?:\s+OR\s+ALTER)?|ALTER)\s+PROCEDURE", "CREATE OR ALTER PROCEDURE", RegexOptions.IgnoreCase);
        var brokenProcedure = Regex.Replace(procedure, @"\bSET\s+NOCOUNT\s+ON\s*;", "$0 SELECT 99 AS UnexpectedProcedureResult;", RegexOptions.IgnoreCase);
        Check(brokenProcedure != procedure, "Test-only procedure output fault was injected into the expected definition");
        await Execute(brokenProcedure);
        try
        {
            var version = Convert.ToBase64String(await Scalar<byte[]>($"SELECT PhienBan FROM dbo.DonHang WHERE MaDonHang={faultId}"));
            Check(Unknown(await confirm.Confirm(faultId, new() { ExpectedVersion = version }, default)), "Unexpected procedure result is rejected by WITH RESULT SETS NONE");
            Check(await Scalar<string>($"SELECT tt.KyHieuTrangThai FROM dbo.DonHang d JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai WHERE d.MaDonHang={faultId}") == "NEW", "Unexpected procedure output rolls back confirmation and its fee changes");
            Check(confirmLog.Messages.Any(m => m.Contains("POST /api/v1/orders/{id}/confirm") && m.Contains("SQL error 11535")), "SQL result-contract error logs preserve SQL number and endpoint");
        }
        finally { await Execute(procedure); }

        await Execute("CREATE OR ALTER TRIGGER dbo.QaUnexpectedResult ON dbo.NhatKyHoatDong AFTER INSERT AS BEGIN SET NOCOUNT ON; IF EXISTS(SELECT 1 FROM inserted WHERE LoaiThaoTac='WAREHOUSE_MOVE') SELECT CAST(NULL AS BIGINT) TransactionId,CAST(1 AS INT) WarehouseId; END");
        Check(Unknown(await move.Move(new() { OrderId = orderId, FromLocationId = to, ToLocationId = from })), "Move handles NULL transaction ID with controlled 500 guidance");
        await Execute("DROP TRIGGER dbo.QaUnexpectedResult");

        await Execute("CREATE OR ALTER TRIGGER dbo.QaUnexpectedResult ON dbo.DonHang AFTER INSERT AS BEGIN SET NOCOUNT ON; SELECT CAST(NULL AS BIGINT) OrderId; END");
        Check(Unknown(await create.Create(request)), "Create rejects NULL scalar output without returning an ID-zero success");
        await Execute("DROP TRIGGER dbo.QaUnexpectedResult");

        // Fresh confirmed order for the inbound malformed-result scenario.
        var inboundId = Result(await create.Create(request), 201).GetProperty("id").GetInt64();
        Result(await confirm.Confirm(inboundId, new(), default), 200);
        await Execute("CREATE OR ALTER TRIGGER dbo.QaUnexpectedResult ON dbo.NhatKyHoatDong AFTER INSERT AS BEGIN SET NOCOUNT ON; IF EXISTS(SELECT 1 FROM inserted WHERE LoaiThaoTac='WAREHOUSE_INBOUND') SELECT CAST(NULL AS BIGINT) TransactionId; END");
        Check(Unknown(await inbound.Inbound(new() { OrderId = inboundId, WarehouseId = warehouse, LocationId = from })), "Inbound rejects NULL scalar output without returning a transaction-zero success");
        await Execute("DROP TRIGGER dbo.QaUnexpectedResult");

        await File.WriteAllTextAsync(Path.Combine(root, "docs/sql-results-verification.json"), JsonSerializer.Serialize(new
        {
            mode = "Real SQL Server LocalDB/TDS and controller integration; temporary GUID database; no operational writes; HTTP/JWT middleware not part of this harness",
            checks, count = checks.Count, realRoadRouting = true, faults = "Test-only triggers/procedure result output; no production fault hooks", databaseCleanup = "Database dropped in finally"
        }, new JsonSerializerOptions { WriteIndented = true }) + "\n");
        Console.WriteLine($"SQL result checks: {checks.Count} passed");
    }
    finally
    {
        if (!Regex.IsMatch(database, "^CodexSqlResults_[a-f0-9]{32}$")) throw new InvalidOperationException("Unsafe database cleanup");
        SqlConnection.ClearAllPools();
        await Execute($"IF DB_ID(N'{database}') IS NOT NULL BEGIN ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{database}]; END", useMaster: true);
        Console.WriteLine("Isolated SQL result database removed");
    }
}

sealed class TestLogger<T> : ILogger<T>
{
    public List<string> Messages { get; } = [];
    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
    public bool IsEnabled(LogLevel logLevel) => true;
    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) => Messages.Add(formatter(state, exception));
}

sealed class TestEnvironment : IWebHostEnvironment
{
    public string ApplicationName { get; set; } = "SqlResultsTests";
    public string EnvironmentName { get; set; } = "Development";
    public string ContentRootPath { get; set; } = "";
    public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    public string WebRootPath { get; set; } = "";
    public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
}
