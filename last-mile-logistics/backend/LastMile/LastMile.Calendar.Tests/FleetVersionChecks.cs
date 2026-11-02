using System.Buffers.Binary;
using System.Data;
using System.Data.Common;
using System.Diagnostics.CodeAnalysis;
using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using System.Text.RegularExpressions;
using LastMile.Api.Controllers;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

internal static class FleetVersionChecks
{
    public static async Task Run(string root)
    {
        var checks = 0;
        void Check(bool value, string name) { if (!value) throw new InvalidOperationException(name); checks++; }
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["VehicleTypeCatalog:Types:0:Code"] = "MOTORBIKE", ["VehicleTypeCatalog:Types:0:Name"] = "Xe máy",
            ["VehicleTypeCatalog:Types:0:MaxCargoWeightKg"] = "100", ["VehicleTypeCatalog:Types:0:MaxCargoVolumeM3"] = "0.38"
        }).Build();

        foreach (var kind in new[] { "shipper", "vehicle" })
        foreach (var toggle in new[] { false, true })
        {
            var store = new Store(kind);
            async Task<IActionResult> Send(string? version, string value, bool active)
            {
                if (kind == "shipper") return await new Shipper(store, config).Update(3, new()
                {
                    ExpectedVersion = version!, LicenseNumber = value, LicenseExpiresAt = new DateOnly(2030, 1, 1), IsActive = active, Areas = []
                }, default);
                return await new Vehicle(store, config).Save(new()
                {
                    Id = 3, ExpectedVersion = version, LicensePlate = value, VehicleType = "MOTORBIKE", MaxWeightKg = 100,
                    MaxVolumeM3 = 0.38m, IsActive = active, Status = active ? "AVAILABLE" : "INACTIVE"
                }, default);
            }

            var openedA = store.Version;
            var openedB = store.Version;
            var a = await Send(openedA, "A-123", true);
            Check(Status(a) == 200 && Body(a).GetProperty("version").GetString() == store.Version && store.Version != openedA, kind + ": A receives new Base64 version");
            Check(Convert.FromBase64String(store.Version).Length == 8, kind + ": exact 8-byte version");
            var afterA = store.Version;
            var b = await Send(openedB, toggle ? "ORIGINAL" : "B-123", !toggle);
            Check(Status(b) == 409 && Body(b).GetProperty("code").GetString() == "VERSION_CONFLICT", kind + ": B rejected (toggle=" + toggle + ")");
            Check(store.Value == "A-123" && store.Version == afterA && store.Active && store.Audits == 1, kind + ": stale request changes neither record nor successful audit");
            var reopened = store.Version; // Explicit read/reopen, then intentional new edit.
            var c = await Send(reopened, "C-123", !toggle);
            Check(Status(c) == 200 && store.Value == "C-123" && store.Active == !toggle && store.Audits == 2 && store.Version != reopened, kind + ": deliberate edit after reload succeeds");
            Check(store.Commands == 3 && store.Disposals == 3, kind + ": exactly one command per attempt, all connections disposed");
            foreach (var bad in new string?[] { null, "", " ", "not-base64!", Convert.ToBase64String(new byte[7]), Convert.ToBase64String(new byte[9]) })
            {
                var before = store.Commands;
                Check(Status(await Send(bad, "BAD-123", true)) == 400 && store.Commands == before && store.Value == "C-123", kind + ": invalid/missing version rejected before any SQL");
            }
            Console.WriteLine($"PASS {kind}: A/B/reopen sequence; status toggle={toggle}; malformed versions rejected");
        }

        var created = new Store("vehicle");
        var createResult = await new Vehicle(created, config).Save(new()
        {
            LicensePlate = "NEW-123", VehicleType = "MOTORBIKE", UseTypeCapacity = true, IsActive = true, Status = "AVAILABLE"
        }, default);
        Check(Status(createResult) == 201 && created.Audits == 1 && Body(createResult).GetProperty("version").GetString() == created.Version, "create vehicle needs no ExpectedVersion and returns version");
        Check(created.CreationHadNoVersion && created.Capacity == 100, "create preserves catalog capacity rules");

        foreach (var (name, table, alias) in new[] { ("ShippersController", "NhanVienGiaoHang", "s"), ("VehiclesController", "PhuongTien", "v") })
        {
            var sql = await File.ReadAllTextAsync(Path.Combine(root, "backend/LastMile/LastMile.Api/Controllers/" + name + ".cs"));
            Check(sql.Contains(".PhienBan) AS Version") && sql.Contains(alias + ".Version AS version"), name + ": detail returns binary as JSON Base64");
            var migration = await File.ReadAllTextAsync(Path.Combine(root, "database/migrations/20261019_shipper_vehicle_versions.sql"));
            Check(migration.Contains("COL_LENGTH(N'dbo." + table + "', N'PhienBan') IS NULL") && migration.Contains("ROWVERSION NOT NULL"), table + ": guarded migration exists");
        }
        Console.WriteLine($"Fleet version: {checks} checks passed. Mock DbConnection only; migration and SQL Server were not executed.");
    }

    private static int Status(IActionResult result) => result is ContentResult c ? c.StatusCode ?? 200 : ((ObjectResult)result).StatusCode ?? 200;
    private static JsonElement Body(IActionResult result) => result is ContentResult c ? JsonSerializer.Deserialize<JsonElement>(c.Content!) : JsonSerializer.SerializeToElement(((ObjectResult)result).Value);
    private static ControllerContext Context() => new() { HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "7")], "Mock")) } };
    private sealed class Shipper : ShipperUpdateController
    {
        private readonly Store store;
        public Shipper(Store store, IConfiguration config) : base(config) { this.store = store; ControllerContext = Context(); }
        protected override DbConnection CreateConnection() => new Connection(store);
    }
    private sealed class Vehicle : VehicleSaveController
    {
        private readonly Store store;
        public Vehicle(Store store, IConfiguration config) : base(config, new VehicleTypeCatalog(config)) { this.store = store; ControllerContext = Context(); }
        protected override DbConnection CreateConnection() => new Connection(store);
    }
    private sealed class Store(string kind)
    {
        private ulong revision = 1;
        public string Value = "ORIGINAL";
        public bool Active = true, CreationHadNoVersion;
        public decimal Capacity;
        public int Audits, Commands, Disposals;
        public string Version { get { var bytes = new byte[8]; BinaryPrimitives.WriteUInt64BigEndian(bytes, revision); return Convert.ToBase64String(bytes); } }
        public object Execute(DbCommand command)
        {
            Commands++;
            var sql = Regex.Replace(command.CommandText, @"\s+", " ");
            var table = kind == "shipper" ? "NhanVienGiaoHang" : "PhuongTien";
            var conflict = kind == "shipper" ? "54906" : "55205";
            foreach (var required in new[] { "BEGIN TRAN;", "WITH (UPDLOCK, HOLDLOCK)", "@CurrentVersion <> @ExpectedVersion", "AND PhienBan = @ExpectedVersion; IF @@ROWCOUNT <> 1", "THROW " + conflict, "AS version", "INSERT INTO dbo.NhatKyHoatDong", "ROLLBACK;" })
                if (!sql.Contains(required)) throw new InvalidOperationException("Missing atomic SQL guard: " + required);
            if (!(sql.IndexOf("BEGIN TRAN;", StringComparison.Ordinal) < sql.IndexOf("@CurrentVersion <> @ExpectedVersion", StringComparison.Ordinal)
                && sql.IndexOf("@CurrentVersion <> @ExpectedVersion", StringComparison.Ordinal) < sql.IndexOf("UPDATE dbo." + table, StringComparison.Ordinal)
                && sql.IndexOf("IF @@ROWCOUNT <> 1", StringComparison.Ordinal) < sql.IndexOf("INSERT INTO dbo.NhatKyHoatDong", StringComparison.Ordinal)))
                throw new InvalidOperationException("Version check/update must precede success audit inside transaction");
            var create = kind == "vehicle" && command.Parameters["@Id"].Value is DBNull;
            var expected = (SqlParameter)command.Parameters["@ExpectedVersion"];
            if (expected.SqlDbType != SqlDbType.Binary || expected.Size != 8) throw new InvalidOperationException("ExpectedVersion binding must be BINARY(8)");
            if (!create && (expected.Value is not byte[] bytes || Convert.ToBase64String(bytes) != Version))
                throw Error(int.Parse(conflict));
            CreationHadNoVersion = create && expected.Value is DBNull;
            Value = command.Parameters[kind == "shipper" ? "@LicenseNumber" : "@LicensePlate"].Value as string ?? throw new InvalidOperationException("Missing record value");
            Active = command.Parameters["@IsActive"].Value is bool active ? active : throw new InvalidOperationException("Missing active flag");
            if (kind == "vehicle") Capacity = command.Parameters["@MaxWeightKg"].Value is decimal capacity ? capacity : throw new InvalidOperationException("Missing capacity");
            revision++; Audits++;
            return JsonSerializer.Serialize(new { id = 3, version = Version, isActive = Active });
        }
    }
    private sealed class Connection(Store store) : DbConnection
    {
        private ConnectionState state;
        [AllowNull] public override string ConnectionString { get; set; } = "";
        public override string Database => "MockOnly";
        public override string DataSource => "NoDatabase";
        public override string ServerVersion => "Mock";
        public override ConnectionState State => state;
        public override void Open() => state = ConnectionState.Open;
        public override void Close() => state = ConnectionState.Closed;
        public override void ChangeDatabase(string databaseName) => throw new NotSupportedException();
        protected override DbTransaction BeginDbTransaction(IsolationLevel isolationLevel) => throw new NotSupportedException();
        protected override DbCommand CreateDbCommand() => new Command(store, this);
        public override ValueTask DisposeAsync() { store.Disposals++; Close(); return ValueTask.CompletedTask; }
    }
    private sealed class Command(Store store, Connection connection) : DbCommand
    {
        private readonly SqlCommand parameters = new();
        [AllowNull] public override string CommandText { get; set; } = "";
        public override int CommandTimeout { get; set; }
        public override CommandType CommandType { get; set; }
        public override bool DesignTimeVisible { get; set; }
        public override UpdateRowSource UpdatedRowSource { get; set; }
        protected override DbConnection? DbConnection { get; set; } = connection;
        protected override DbTransaction? DbTransaction { get; set; }
        protected override DbParameterCollection DbParameterCollection => parameters.Parameters;
        public override void Cancel() { }
        public override void Prepare() { }
        protected override DbParameter CreateDbParameter() => new SqlParameter();
        public override int ExecuteNonQuery() => throw new NotSupportedException();
        protected override DbDataReader ExecuteDbDataReader(CommandBehavior behavior) => throw new NotSupportedException();
        public override object ExecuteScalar() => store.Execute(this);
        public override ValueTask DisposeAsync() { parameters.Dispose(); return ValueTask.CompletedTask; }
    }
    private static SqlException Error(int number)
    {
        var constructor = typeof(SqlError).GetConstructors(BindingFlags.NonPublic | BindingFlags.Instance).First(c => c.GetParameters().Length == 8);
        var error = constructor.Invoke([number, (byte)1, (byte)16, "MockOnly", "Version changed", "MockProcedure", 1, null]);
        var errors = (SqlErrorCollection)Activator.CreateInstance(typeof(SqlErrorCollection), nonPublic: true)!;
        typeof(SqlErrorCollection).GetMethod("Add", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(errors, [error]);
        return (SqlException)typeof(SqlException).GetMethod("CreateException", BindingFlags.NonPublic | BindingFlags.Static, null, [typeof(SqlErrorCollection), typeof(string)], null)!.Invoke(null, [errors, "Mock"])!;
    }
}
