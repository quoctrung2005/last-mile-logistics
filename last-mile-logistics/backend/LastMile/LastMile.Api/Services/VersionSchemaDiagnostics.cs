using System.Text.Json;
using System.Security.Claims;
using LastMile.Api.Controllers;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration.Json;

namespace LastMile.Api.Services;

// Opt-in CLI only. Uses the API host's effective configuration, without starting
// HTTP, applying migrations or running mutation actions. Optional GET checks
// inspect records in memory but never emit their business data or identifiers.
public static class VersionSchemaDiagnostics
{
    public static async Task<int> RunAsync(IConfiguration configuration, IHostEnvironment environment)
    {
        var provider = (configuration as IConfigurationRoot)?.Providers.Reverse()
            .FirstOrDefault(p => p.TryGet("ConnectionStrings:DefaultConnection", out _));
        var source = provider is JsonConfigurationProvider json
            ? Path.GetFileName(json.Source.Path) : provider?.GetType().Name ?? "unknown";
        try
        {
            var connectionText = configuration.GetConnectionString("DefaultConnection");
            if (string.IsNullOrWhiteSpace(connectionText))
            {
                Console.WriteLine(JsonSerializer.Serialize(new { environment = environment.EnvironmentName, configurationSource = source, error = "DefaultConnection is not configured" }));
                return 1;
            }
            var target = new SqlConnectionStringBuilder(connectionText) { ConnectTimeout = 5 };
            await using var connection = new SqlConnection(target.ConnectionString);
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandTimeout = 10;
            command.CommandText = """
                SELECT DB_NAME() AS databaseName, CONVERT(nvarchar(128), SERVERPROPERTY('ServerName')) AS serverName;
                SELECT e.tableName, CONVERT(bit, CASE WHEN t.object_id IS NULL THEN 0 ELSE 1 END) AS tableExists,
                    CONVERT(bit, CASE WHEN c.column_id IS NULL THEN 0 ELSE 1 END) AS hasVersion,
                    TYPE_NAME(c.system_type_id) AS typeName, c.max_length, c.is_nullable,
                    CONVERT(bit, CASE WHEN c.system_type_id = 189 AND c.max_length = 8 AND c.is_nullable = 0 THEN 1 ELSE 0 END) AS validRowversion,
                    HAS_PERMS_BY_NAME(N'dbo.' + e.tableName, 'OBJECT', 'VIEW DEFINITION') AS canViewDefinition,
                    (SELECT v.name AS columnName FROM sys.columns v
                     WHERE v.object_id = t.object_id AND v.system_type_id = 189 FOR JSON PATH) AS rowversionColumns
                FROM (VALUES (N'NhanVienGiaoHang'), (N'PhuongTien'), (N'KhachHang'),
                    (N'DiaChiKhachHang'), (N'TaiKhoan'), (N'DonHang')) e(tableName)
                LEFT JOIN sys.tables t ON t.name = e.tableName AND t.schema_id = SCHEMA_ID(N'dbo')
                LEFT JOIN sys.columns c ON c.object_id = t.object_id AND c.name = N'PhienBan'
                ORDER BY e.tableName;
                """;
            string database, server;
            var tables = new List<object>();
            var missing = new List<string>();
            var existingTables = new HashSet<string>();
            await using (var reader = await command.ExecuteReaderAsync())
            {
                await reader.ReadAsync();
                database = reader.GetString(0); server = reader.GetString(1);
                await reader.NextResultAsync();
                while (await reader.ReadAsync())
                {
                    var table = reader.GetString(0);
                    if (reader.GetBoolean(1)) existingTables.Add(table);
                    var valid = reader.GetBoolean(6);
                    if (!valid) missing.Add(table);
                    tables.Add(new { table = "dbo." + table, tableExists = reader.GetBoolean(1), hasVersion = reader.GetBoolean(2),
                        type = reader.IsDBNull(3) ? null : reader.GetString(3), bytes = reader.IsDBNull(4) ? (int?)null : reader.GetInt16(4),
                        nullable = reader.IsDBNull(5) ? (bool?)null : reader.GetBoolean(5), validRowversion = valid,
                        canViewDefinition = !reader.IsDBNull(7) && reader.GetInt32(7) == 1,
                        rowversionColumns = JsonSerializer.Deserialize<JsonElement>(reader.IsDBNull(8) ? "[]" : reader.GetString(8)) });
                }
            }
            var probes = new List<object>();
            foreach (var (controller, table, alias, migration) in new[]
            {
                ("ShippersController.Get", "NhanVienGiaoHang", "nv", "20261019_shipper_vehicle_versions.sql"),
                ("ShipperUpdateController.Update", "NhanVienGiaoHang", "nv", "20261019_shipper_vehicle_versions.sql"),
                ("VehiclesController.Get", "PhuongTien", "pt", "20261019_shipper_vehicle_versions.sql"),
                ("VehicleSaveController.Save", "PhuongTien", "", "20261019_shipper_vehicle_versions.sql"),
                ("CustomerDetailController.Get", "KhachHang", "kh", "20261019_customer_versions.sql"),
                ("CustomerAddressUpdateController.Update", "DiaChiKhachHang", "dc", "20261019_customer_versions.sql")
            })
            {
                var reference = string.IsNullOrEmpty(alias) ? "PhienBan" : alias + ".PhienBan";
                var sql = $"SELECT TOP (0) CONVERT(VARBINARY(8), {reference}) AS version FROM dbo.{table}" + (alias.Length == 0 ? ";" : " " + alias + ";");
                command.CommandText = sql;
                int? errorNumber = null;
                try { await using var reader = await command.ExecuteReaderAsync(); }
                catch (SqlException error) { errorNumber = error.Number; }
                probes.Add(new { controller, table = "dbo." + table, alias, reference, sql, success = errorNumber is null, sqlError = errorNumber, migration });
            }
            var readControllers = new List<object>();
            if (configuration.GetValue<bool>("SchemaDiagnostics:ReadControllers"))
            {
                // Only invoke existing GET actions. No login/session write and no
                // mutation action is executed; business data is never reported.
                command.CommandText = """
                    SELECT TOP (1) tk.MaTaiKhoan FROM dbo.TaiKhoan tk
                    JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.TrangThaiTaiKhoan = 'ACTIVE' AND vt.DangHoatDong = 1
                      AND vt.KyHieuVaiTro = 'ADMIN'
                      AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME())
                    ORDER BY tk.MaTaiKhoan;
                    """;
                var actor = await command.ExecuteScalarAsync();
                if (actor is long actorId)
                {
                    var context = new ControllerContext { HttpContext = new DefaultHttpContext {
                        User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString(System.Globalization.CultureInfo.InvariantCulture))], "ReadOnlySchemaDiagnostic")) } };
                    var actions = new List<(string Name, string Mode, Func<Task<IActionResult>> Action)>
                    {
                        ("ShippersController.Get", "list", () => new ShippersController(configuration) { ControllerContext = context }.Get(pageSize: 1)),
                        ("VehiclesController.Get", "list", () => new VehiclesController(configuration) { ControllerContext = context }.Get(pageSize: 1))
                    };
                    // Obtain only identifiers to call the real detail branches.
                    // Do not invent an ID or print the row's contents.
                    foreach (var (table, key, name) in new[]
                    {
                        ("NhanVienGiaoHang", "MaNhanVienGiaoHang", "ShippersController.Get"),
                        ("PhuongTien", "MaPhuongTien", "VehiclesController.Get")
                    })
                    {
                        if (!existingTables.Contains(table))
                        {
                            readControllers.Add(new { controller = name, mode = "detail", skipped = "Table missing" });
                            continue;
                        }
                        command.CommandText = $"SELECT TOP (1) {key} FROM dbo.{table} ORDER BY {key};";
                        if (await command.ExecuteScalarAsync() is not long recordId)
                        {
                            readControllers.Add(new { controller = name, mode = "detail", skipped = "No existing record" });
                            continue;
                        }
                        if (table == "NhanVienGiaoHang")
                            actions.Add((name, "detail", () => new ShippersController(configuration) { ControllerContext = context }.Get(id: recordId)));
                        else
                            actions.Add((name, "detail", () => new VehiclesController(configuration) { ControllerContext = context }.Get(id: recordId)));
                    }
                    foreach (var (name, mode, action) in actions)
                    {
                        try
                        {
                            var result = await action();
                            var status = result switch
                            {
                                ObjectResult value => value.StatusCode ?? 200,
                                StatusCodeResult value => value.StatusCode,
                                ContentResult value => value.StatusCode ?? 200,
                                _ => 500
                            };
                            var validVersion = (bool?)null;
                            if (status == 200 && result is ContentResult { Content: { } body })
                            {
                                using var payload = JsonDocument.Parse(body);
                                validVersion = HasVersion8Bytes(payload.RootElement, mode == "detail");
                            }
                            readControllers.Add(new { controller = name, mode, success = status == 200 && validVersion != false, status,
                                firstRecordHasBase64Version8Bytes = validVersion });
                        }
                        catch (SqlException error)
                        {
                            readControllers.Add(new { controller = name, mode, success = false, sqlError = error.Number,
                                statementErrors = error.Errors.Cast<SqlError>().Select(e => new { number = e.Number, line = e.LineNumber }).ToArray() });
                        }
                    }
                }
                else readControllers.Add(new { skipped = "No active ADMIN account for GET-action permission checks" });
            }
            Console.WriteLine(JsonSerializer.Serialize(new { checkedAtUtc = DateTimeOffset.UtcNow, mode = "read-only schema metadata and optional list/detail GET actions; no migration or application writes",
                environment = environment.EnvironmentName, configurationSource = source, configuredServer = target.DataSource,
                configuredDatabase = target.InitialCatalog, server, database, tables, probes, readControllers, schemaReady = missing.Count == 0 }, new JsonSerializerOptions { WriteIndented = true }));
            return missing.Count == 0 ? 0 : 2;
        }
        catch (Exception error)
        {
            // Never print exception text/stack or configuration values: provider
            // failures may embed connection details. Type/SQL code suffice here.
            Console.WriteLine(JsonSerializer.Serialize(new { environment = environment.EnvironmentName, configurationSource = source,
                errorType = error.GetType().Name, sqlError = (error as SqlException)?.Number, schemaVerified = false }));
            return 1;
        }
    }

    // null means an empty list (no fabricated record/version to validate).
    public static bool? HasVersion8Bytes(JsonElement payload, bool detail)
    {
        if (payload.ValueKind != JsonValueKind.Object) return false;
        var record = payload;
        if (!detail)
        {
            if (!payload.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array) return false;
            if (items.GetArrayLength() == 0) return null;
            record = items[0];
        }
        if (record.ValueKind != JsonValueKind.Object) return false;
        if (!record.TryGetProperty("version", out var version) || version.ValueKind != JsonValueKind.String) return false;
        try { return Convert.FromBase64String(version.GetString() ?? "").Length == 8; }
        catch (FormatException) { return false; }
    }
}
