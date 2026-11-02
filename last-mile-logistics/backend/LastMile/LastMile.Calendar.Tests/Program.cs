using System.Data;
using System.Globalization;
using System.Text.Json;
using LastMile.Api.Services;
using Microsoft.Data.SqlClient;

try
{
    if (args.Length == 2 && args[0] == "--shipper-update")
        await ShipperUpdateChecks.Run(args[1]);
    else if (args.Length == 2 && args[0] == "--fleet-version")
        await FleetVersionChecks.Run(args[1]);
    else if (args.Length == 2 && args[0] == "--version-schema-tests")
        await VersionSchemaChecks.Run(args[1]);
    else
        await Run(args.Single());
}
catch (Exception ex) { Console.Error.WriteLine(ex); Environment.ExitCode = 1; }

static async Task Run(string root)
{
    var records = new List<object>();
    var points = new[]
    {
        ("2026-10-19T23:59:00+07:00", "2026-10-19"),
        ("2026-10-20T00:00:00+07:00", "2026-10-20"),
        ("2026-10-20T06:59:00+07:00", "2026-10-20"),
        ("2026-10-20T23:59:59+07:00", "2026-10-20"),
        ("2028-03-01T00:00:00+07:00", "2028-03-01"),
    };
    // Read only: connect to LocalDB master, never change the application database.
    var project = Path.Combine(root, "backend/LastMile/LastMile.Api");
    using var settings = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(project, "appsettings.Development.json")));
    using var fallback = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(project, "appsettings.json")));
    var config = settings.RootElement.TryGetProperty("ConnectionStrings", out var section) && section.TryGetProperty("DefaultConnection", out _)
        ? section : fallback.RootElement.GetProperty("ConnectionStrings");
    var builder = new SqlConnectionStringBuilder(config.GetProperty("DefaultConnection").GetString()) { InitialCatalog = "master" };
    if (!builder.DataSource.StartsWith("(localdb)", StringComparison.OrdinalIgnoreCase)) throw new Exception("Read-only LocalDB test required");
    await using var connection = new SqlConnection(builder.ConnectionString);
    await connection.OpenAsync();
    var checks = 0;
    foreach (var (instantText, todayText) in points)
    {
        var instant = DateTimeOffset.Parse(instantText, CultureInfo.InvariantCulture);
        var today = DateOnly.ParseExact(todayText, "yyyy-MM-dd", CultureInfo.InvariantCulture);
        if (VietnamDate.FromInstant(instant) != today || VietnamDate.FromInstant(instant.ToOffset(TimeSpan.FromHours(-8))) != today)
            throw new Exception("Backend calendar date mismatch");
        foreach (var expiry in new DateOnly?[] { new(2026, 10, 19), new(2026, 10, 20), new(2028, 2, 29), null })
        {
            var expectedExpired = expiry.HasValue && expiry.Value < today;
            if (VietnamDate.IsLicenseExpired(expiry, instant) != expectedExpired) throw new Exception("Backend expiry mismatch");
            // Execute both SQL predicate styles used in production: invalid IF/CASE and eligible WHERE.
            await using var command = new SqlCommand($"""
                SELECT {VietnamDate.SqlDate("@Now")},
                  CONVERT(BIT, CASE WHEN @Expiry IS NOT NULL AND @Expiry < {VietnamDate.SqlDate("@Now")} THEN 1 ELSE 0 END),
                  CONVERT(BIT, CASE WHEN @Expiry IS NULL OR @Expiry >= {VietnamDate.SqlDate("@departure")} THEN 1 ELSE 0 END);
                """, connection);
            command.Parameters.Add("@Now", SqlDbType.DateTime2).Value = instant.UtcDateTime;
            command.Parameters.Add("@departure", SqlDbType.DateTime2).Value = instant.UtcDateTime;
            command.Parameters.Add("@Expiry", SqlDbType.Date).Value = expiry.HasValue ? expiry.Value.ToDateTime(TimeOnly.MinValue) : DBNull.Value;
            await using var reader = await command.ExecuteReaderAsync();
            if (!await reader.ReadAsync() || DateOnly.FromDateTime(reader.GetDateTime(0)) != today
                || reader.GetBoolean(1) != expectedExpired || reader.GetBoolean(2) == expectedExpired)
                throw new Exception("SQL/backend expiry mismatch");
            records.Add(new { instant = instantText, today = todayText, expiry = expiry?.ToString("yyyy-MM-dd"), expired = expectedExpired });
            checks++;
        }
    }
    // Route departure may be later than today; retain that additional future-date check.
    if (!VietnamDate.IsLicenseExpired(new DateOnly(2026, 10, 20), DateTimeOffset.Parse("2026-10-21T00:00:00+07:00")))
        throw new Exception("Departure date must use the same end-of-day rule");
    var report = new { checks, sql = "Real read-only LocalDB master queries, controlled UTC parameters", systemClockChanged = false, records };
    await File.WriteAllTextAsync(Path.Combine(root, "docs/license-date-verification.json"), JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }) + "\n");
    Console.WriteLine($"Backend/SQL controlled-date cases passed: {checks}; future departure rule passed");
}
