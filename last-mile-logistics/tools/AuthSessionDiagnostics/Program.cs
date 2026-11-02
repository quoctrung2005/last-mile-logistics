using System.Data;
using System.Security.Cryptography;
using System.Text.Json;
using LastMile.Api.Services;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

// Inspect uses the same Development configuration precedence as the API. Never
// print configuration values, password hashes, refresh tokens or JWT keys.
var root = Path.GetFullPath(args[0]);
var mode = args.Length > 1 ? args[1] : "inspect";
if (mode is not ("inspect" or "apply" or "apply-registration")) throw new ArgumentException("Use inspect, apply or apply-registration.");
var apiPath = Path.Combine(root, "backend/LastMile/LastMile.Api");
var configuration = new ConfigurationBuilder().SetBasePath(apiPath)
    .AddJsonFile("appsettings.json")
    .AddJsonFile("appsettings.Development.json", optional: true)
    .AddUserSecrets(typeof(AuthTokenService).Assembly, optional: true)
    .AddEnvironmentVariables().Build();
var source = configuration.Providers.Reverse().First(p => p.TryGet("ConnectionStrings:DefaultConnection", out _));
var builder = new SqlConnectionStringBuilder(configuration.GetConnectionString("DefaultConnection"));
Console.WriteLine(JsonSerializer.Serialize(new { environment = "Development", configurationSource = source.ToString(), server = builder.DataSource, database = builder.InitialCatalog, integratedSecurity = builder.IntegratedSecurity }));
await using var connection = new SqlConnection(builder.ConnectionString);
await connection.OpenAsync();
Console.WriteLine("Connected database: " + connection.Database + "; server: " + connection.DataSource);
if (mode == "apply-registration")
{
    var expected = args.Length > 2 ? args[2] : "";
    if (!builder.DataSource.StartsWith("(localdb)\\", StringComparison.OrdinalIgnoreCase)
        || !builder.IntegratedSecurity || expected != "QLGiaoHangChangCuoi" || connection.Database != expected)
        throw new InvalidOperationException("Registration migration requires the explicitly named local application database with Windows authentication.");
    async Task<string> ExistingRows()
    {
        await using var count = new SqlCommand("""
            SELECT (SELECT COUNT_BIG(*) FROM dbo.TaiKhoan) AS accounts,
              (SELECT COUNT_BIG(*) FROM dbo.TokenLamMoi) AS refreshTokens,
              (SELECT COUNT_BIG(*) FROM dbo.DonHang) AS orders,
              (SELECT COUNT_BIG(*) FROM dbo.TonKhoDonHang) AS inventory
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
            """, connection);
        return (string)(await count.ExecuteScalarAsync())!;
    }
    var before = await ExistingRows();
    await using (var migration = new SqlCommand(await File.ReadAllTextAsync(
        Path.Combine(root, "database/migrations/20261030_shipper_registrations.sql")), connection) { CommandTimeout = 120 })
        await migration.ExecuteNonQueryAsync();
    var after = await ExistingRows();
    if (before != after) throw new InvalidOperationException("Existing row counts changed; check concurrent application activity.");
    await using var verify = new SqlCommand("""
        SELECT COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID('dbo')
          AND name IN ('ShipperRegistration','ShipperRegistrationDocument','ShipperRegistrationEvent');
        """, connection);
    if (Convert.ToInt32(await verify.ExecuteScalarAsync()) != 3) throw new InvalidOperationException("Registration schema is incomplete.");
    Console.WriteLine("Registration schema ready; existing accounts, tokens, orders and inventory row counts preserved.");
    return;
}
await ShowSchema();

if (mode == "apply")
{
    var expected = args.Length > 2 ? args[2] : "";
    if (!builder.DataSource.StartsWith("(localdb)\\", StringComparison.OrdinalIgnoreCase)
        || !builder.IntegratedSecurity || string.IsNullOrEmpty(expected)
        || !string.Equals(expected, connection.Database, StringComparison.Ordinal)
        || new[] { "master", "model", "tempdb", "msdb" }.Contains(expected, StringComparer.OrdinalIgnoreCase))
        throw new InvalidOperationException("Apply requires an explicitly verified LocalDB application database using Windows authentication.");
    var before = await Counts();
    var migration = Path.Combine(root, "database/migrations/20261019_auth_sessions.sql");
    for (var pass = 1; pass <= 2; pass++)
    {
        await using var command = new SqlCommand(await File.ReadAllTextAsync(migration), connection) { CommandTimeout = 120 };
        await command.ExecuteNonQueryAsync();
        Console.WriteLine("Migration pass " + pass + " succeeded: 20261019_auth_sessions.sql");
    }
    var after = await Counts();
    if (before != after) throw new InvalidOperationException("Account or refresh-token row counts changed; inspect concurrent activity.");
    Console.WriteLine(JsonSerializer.Serialize(new { dataRowCountsPreserved = true, accounts = after.Accounts, refreshTokens = after.Tokens }));
    await ShowSchema();
    await using var verify = new SqlCommand("""
        SELECT CASE WHEN OBJECT_ID('dbo.PhienDangNhap','U') IS NOT NULL
          AND EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.TokenLamMoi') AND name='MaPhien' AND system_type_id=36 AND is_nullable=1)
          AND EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name='FK_TokenLamMoi_PhienDangNhap' AND is_disabled=0 AND is_not_trusted=0)
          THEN 1 ELSE 0 END;
        """, connection);
    if (Convert.ToInt32(await verify.ExecuteScalarAsync()) != 1) throw new InvalidOperationException("Session schema verification failed.");
}

// Exercise the exact Microsoft.Data.SqlClient/reader/transaction code reported
// in AuthTokenService, without touching any existing real credential.
try
{
    var unknown = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    await new AuthTokenService(configuration).RefreshAsync(unknown);
    throw new InvalidOperationException("An unknown diagnostic token was unexpectedly accepted.");
}
catch (UnauthorizedAccessException)
{
    Console.WriteLine("Unknown/legacy refresh rejected as authentication failure; lookup completed without a SQL error.");
}
catch (Exception error)
{
    // ToString includes the complete stack and nested InnerException chain.
    Console.WriteLine("Full runtime exception (no request credentials):");
    Console.WriteLine(error.ToString());
    if (error.InnerException is null) Console.WriteLine("InnerException: <none>");
    for (Exception? inner = error; inner is not null; inner = inner.InnerException)
        Console.WriteLine("Exception chain: " + inner.GetType().FullName + ": " + inner.Message);
    Environment.ExitCode = 1;
}

async Task ShowSchema()
{
    await using var command = new SqlCommand("""
        SELECT OBJECT_NAME(c.object_id) AS tableName, c.name AS columnName,
            TYPE_NAME(c.system_type_id) AS dataType, c.max_length, c.is_nullable
        FROM sys.columns c WHERE c.object_id IN (OBJECT_ID('dbo.TokenLamMoi'),OBJECT_ID('dbo.PhienDangNhap'))
        ORDER BY tableName,c.column_id;
        """, connection);
    await using var reader = await command.ExecuteReaderAsync();
    while (await reader.ReadAsync())
        Console.WriteLine(JsonSerializer.Serialize(new { table = reader.GetString(0), column = reader.GetString(1), type = reader.GetString(2), maxLength = reader.GetInt16(3), nullable = reader.GetBoolean(4) }));
}
async Task<(long Accounts, long Tokens)> Counts()
{
    await using var command = new SqlCommand("SELECT (SELECT COUNT_BIG(*) FROM dbo.TaiKhoan),(SELECT COUNT_BIG(*) FROM dbo.TokenLamMoi);", connection);
    await using var reader = await command.ExecuteReaderAsync();
    await reader.ReadAsync();
    return (reader.GetInt64(0), reader.GetInt64(1));
}
