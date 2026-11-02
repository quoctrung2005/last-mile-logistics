using System.Text.Json;
using System.Text.RegularExpressions;
using LastMile.Api.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.FileProviders;

internal static class VersionSchemaChecks
{
    public static async Task Run(string root)
    {
        var checks = 0;
        void Check(bool value, string name) { if (!value) throw new InvalidOperationException(name); checks++; }
        foreach (var connectionText in new[] { "", "Password=diagnostic-secret;UnsupportedVersionDiagnosticKey=diagnostic-secret" })
        {
            var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:DefaultConnection"] = connectionText
            }).Build();
            var previous = Console.Out;
            using var output = new StringWriter();
            int status;
            try
            {
                Console.SetOut(output);
                // Empty/invalid connection strings fail before any SQL connection.
                status = await VersionSchemaDiagnostics.RunAsync(config, new TestEnvironment());
            }
            finally { Console.SetOut(previous); }
            var report = output.ToString();
            Check(status == 1, "diagnostic configuration failure has controlled exit code");
            Check(!report.Contains("diagnostic-secret") && !report.Contains("Password=") && !report.Contains("UnsupportedVersionDiagnosticKey"), "never expose credentials/connection strings/exception text");
            using var document = JsonDocument.Parse(report);
            Check(document.RootElement.GetProperty("environment").GetString() == "Development", "diagnostic identifies environment");
            Check(document.RootElement.GetProperty("configurationSource").GetString() == "MemoryConfigurationProvider", "diagnostic identifies effective provider without its value");
        }
        var script = await File.ReadAllTextAsync(Path.Combine(root, "database/migrations/20261019_shipper_vehicle_versions.sql"));
        Check(script.Contains("IF DB_NAME() <> @ExpectedDatabase") && script.Contains("N'QLGiaoHangChangCuoi'"), "migration checks inspected target database");
        foreach (var table in new[] { "NhanVienGiaoHang", "PhuongTien" })
            Check(script.Contains($"IF COL_LENGTH(N'dbo.{table}', N'PhienBan') IS NULL")
                && script.Contains($"ALTER TABLE dbo.{table} ADD PhienBan ROWVERSION NOT NULL;"), table + ": idempotent additive column migration");
        Check(script.Contains("system_type_id <> 189 OR max_length <> 8 OR is_nullable <> 0"), "migration checks correct rowversion shape");
        Check(script.Contains("system_type_id = 189 AND name <> N'PhienBan'"), "migration rejects an existing differently-named rowversion");
        Check(script.Contains("IF XACT_STATE() <> 0 ROLLBACK;"), "migration rolls back errors");
        Check(!Regex.IsMatch(script, @"\b(DROP\s+(TABLE|DATABASE)|TRUNCATE|DELETE\s+FROM|UPDATE\s+dbo\.)", RegexOptions.IgnoreCase), "migration cannot drop/recreate/delete/update business records");
        foreach (var detail in new[] { false, true })
        {
            foreach (var (recordJson, expected) in new[]
            {
                ("{\"version\":\"AAAAAAAAAAE=\"}", true),
                ("{\"version\":\"" + Convert.ToBase64String(new byte[7]) + "\"}", false),
                ("{\"version\":\"not-base64\"}", false),
                ("{\"version\":null}", false),
                ("{}", false),
                ("null", false)
            })
            {
                using var payload = JsonDocument.Parse(detail ? recordJson : "{\"items\":[" + recordJson + "]}");
                Check(VersionSchemaDiagnostics.HasVersion8Bytes(payload.RootElement, detail) == expected,
                    "validate actual " + (detail ? "detail" : "list") + " JSON version without inventing a fallback");
            }
        }
        using (var empty = JsonDocument.Parse("{\"items\":[]}"))
            Check(VersionSchemaDiagnostics.HasVersion8Bytes(empty.RootElement, false) is null, "empty list reports no record to validate");
        foreach (var name in new[] { "ShippersController", "VehiclesController" })
        {
            var source = await File.ReadAllTextAsync(Path.Combine(root, "backend/LastMile/LastMile.Api/Controllers/" + name + ".cs"));
            var alias = name == "ShippersController" ? "nv" : "pt";
            var temporary = name == "ShippersController" ? "Shippers" : "Vehicles";
            var outputAlias = name == "ShippersController" ? "s" : "v";
            Check(source.Contains($"CONVERT(BINARY(8), {alias}.PhienBan) AS Version,") && source.Contains($"INTO #{temporary}"), name + ": source version is projected into temporary table");
            Check(Regex.Matches(source, $@"{outputAlias}\.Version AS version").Count == 2 && !source.Contains(outputAlias + ".PhienBan"), name + ": list/detail use projected Version, not nonexistent temporary PhienBan");
        }
        Console.WriteLine($"Version schema diagnostics: {checks} checks passed; no database connected and no migration executed by these tests.");
    }
    private sealed class TestEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Development";
        public string ApplicationName { get; set; } = "OfflineVersionSchemaTest";
        public string ContentRootPath { get; set; } = "";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
