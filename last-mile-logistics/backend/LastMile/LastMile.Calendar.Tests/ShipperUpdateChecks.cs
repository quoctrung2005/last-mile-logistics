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

// Offline mode only: no settings/connection string is read, no SqlConnection is
// constructed. SQL structure and parameter binding are checked at the command
// boundary; the fake models locked-row/task rules, not a SQL Server execution.
internal static class ShipperUpdateChecks
{
    public static async Task Run(string root)
    {
        var checks = 0;
        var scenarios = 0;
        void Check(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
            checks++;
        }

        async Task Case(string name, State state, UpdateShipperRequest request, int expected)
        {
            scenarios++;
            var oldExpiry = state.Expiry;
            var controller = new Controller(state);
            var result = await controller.Update(3, request, CancellationToken.None);
            var status = result is ContentResult content ? content.StatusCode ?? 200 : ((ObjectResult)result).StatusCode;
            Check(status == expected, name + ": HTTP status " + status);
            Check(state.Executions == (expected == 400 ? 0 : 1), name + ": exactly one command, no write retry");
            Check(state.Saved == (expected == 200), name + ": expected committed/unchanged fake state");
            Check(state.ConnectionDisposed == (expected == 400 ? 0 : 1) && state.CommandDisposed == (expected == 400 ? 0 : 1), name + ": resources disposed");
            if (expected == 200)
            {
                Check(state.Expiry == request.LicenseExpiresAt && state.Number == request.LicenseNumber?.Trim(), name + ": exact requested licence preserved");
                Check(state.Active == request.IsActive && (state.Active || state.Availability == "OFFLINE"), name + ": deactivation sets OFFLINE");
            }
            else Check(state.Expiry == oldExpiry && !state.Saved, name + ": failure preserves existing data");
            Console.WriteLine("PASS " + name);
        }

        var instant = DateTimeOffset.Parse("2026-10-20T06:59:00+07:00");
        var today = new DateOnly(2026, 10, 20);
        Check(VietnamDate.FromInstant(instant) == today, "controlled Vietnam day");
        foreach (var day in new[] { today.AddDays(-1), today, today.AddDays(1) })
        {
            Check(VietnamDate.IsLicenseExpired(day, instant) == (day < today), "yesterday/today/tomorrow eligibility");
            await Case("deactivate unchanged licence " + day, new State(day, instant), Request(day, false), 200);
            await Case("reactivate unchanged licence " + day, new State(day, instant) { Active = false }, Request(day, true), day < today ? 422 : 200);
            await Case("new expiry while inactive " + day, new State(null, instant) { Active = false }, Request(day, false), day < today ? 422 : 200);
            await Case("new expiry while active " + day, new State(null, instant), Request(day, true), day < today ? 422 : 200);
        }

        var expired = today.AddDays(-1);
        foreach (var active in new[] { false, true })
            await Case("edit other data, preserve expired history active=" + active, new State(expired, instant) { Active = active }, Request(expired, active), 200);

        foreach (var work in new[] { "assignment", "trip", "return" })
        {
            await Case("deactivation blocked by " + work, new State(expired, instant) { Work = work }, Request(expired, false), 409);
            await Case("today licence still blocked by " + work, new State(today, instant) { Work = work }, Request(today, false), 409);
        }
        foreach (var active in new[] { false, true })
        {
            var changed = Request(expired, active); changed.LicenseNumber = "NEW-123";
            await Case("change number cannot keep expired date active=" + active, new State(expired, instant) { Active = active }, changed, 422);
            var caseChanged = Request(expired, active); caseChanged.LicenseNumber = "ab-123";
            await Case("case-sensitive licence change active=" + active, new State(expired, instant) { Active = active }, caseChanged, 422);
            await Case("change expiry cannot enter past active=" + active, new State(today, instant) { Active = active }, Request(expired, active), 422);
        }

        var trimmed = Request(expired, false); trimmed.LicenseNumber = " AB-123 ";
        await Case("normalised unchanged number", new State(expired, instant) { Number = " AB-123 " }, trimmed, 200);
        await Case("locked current licence differs from form snapshot", new State(expired, instant) { Number = "CHANGED-ELSEWHERE" }, Request(expired, false), 422);
        await Case("locked current shipper is inactive, request activates", new State(expired, instant) { Active = false }, Request(expired, true), 422);
        foreach (var error in new[] { 54901, 54902, 54903 })
            await Case("auth/scope retained " + error, new State(expired, instant) { Error = error }, Request(expired, false), error == 54901 ? 401 : error == 54902 ? 403 : 404);

        var optional = Request(null, true); optional.LicenseNumber = null;
        await Case("optional licence reactivation", new State(null, instant) { Active = false, Number = null }, optional, 200);
        var missingNumber = Request(expired, false); missingNumber.LicenseNumber = null;
        await Case("date still requires licence number", new State(expired, instant), missingNumber, 400);
        foreach (var (time, expected) in new[] { ("2026-10-19T16:59:59Z", 200), ("2026-10-19T17:00:00Z", 422) })
            await Case("reactivation at Vietnamese midnight " + time, new State(expired, DateTimeOffset.Parse(time)) { Active = false }, Request(expired, true), expected);

        // Receiving/starting work must continue to check active shipper and the
        // Vietnam date. These source assertions complement the mocked endpoint;
        // they do not claim to execute the operational SQL.
        foreach (var name in new[] { "MyTasksController", "MyHandoversController", "TripActionsController", "OrderReturnStartController", "DispatchAssignmentsController" })
        {
            var source = await File.ReadAllTextAsync(Path.Combine(root, "backend/LastMile/LastMile.Api/Controllers/" + name + ".cs"));
            Check(source.Contains("VietnamDate.SqlDate(") && source.Contains("NgayHetHanBangLai") && source.Contains("DangHoatDong = 1"), name + ": eligibility gates retained");
        }
        Console.WriteLine($"Shipper update: {scenarios} mocked controller cases, {checks} checks passed. No database accessed; SQL Server execution is not covered.");
    }

    private static UpdateShipperRequest Request(DateOnly? expiry, bool active) => new()
    {
        ExpectedVersion = "AAAAAAAAAAE=", IdentityNumber = "012345678901", LicenseNumber = "AB-123", LicenseExpiresAt = expiry, IsActive = active, Areas = []
    };

    private sealed class State(DateOnly? expiry, DateTimeOffset now)
    {
        public DateOnly? Expiry = expiry;
        public DateTimeOffset Now = now;
        public string? Number = "AB-123", Work;
        public string Availability = "AVAILABLE";
        public bool Active = true, Saved;
        public int Executions, ConnectionDisposed, CommandDisposed, Error;
    }

    private sealed class Controller : ShipperUpdateController
    {
        private readonly State state;
        public Controller(State state) : base(new ConfigurationBuilder().Build())
        {
            this.state = state;
            ControllerContext = new() { HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "7")], "Mock")) } };
        }
        protected override DbConnection CreateConnection() => new Connection(state);
    }

    private sealed class Connection(State state) : DbConnection
    {
        private ConnectionState status;
        [AllowNull] public override string ConnectionString { get; set; } = "";
        public override string Database => "MockOnly";
        public override string DataSource => "NoDatabase";
        public override string ServerVersion => "Mock";
        public override ConnectionState State => status;
        public override void Open() => status = ConnectionState.Open;
        public override void Close() => status = ConnectionState.Closed;
        public override void ChangeDatabase(string databaseName) => throw new NotSupportedException();
        protected override DbTransaction BeginDbTransaction(IsolationLevel isolationLevel) => throw new NotSupportedException();
        protected override DbCommand CreateDbCommand() => new Command(state, this);
        public override ValueTask DisposeAsync() { state.ConnectionDisposed++; Close(); return ValueTask.CompletedTask; }
    }

    private sealed class Command(State state, Connection connection) : DbCommand
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
        public override object ExecuteScalar()
        {
            state.Executions++;
            var sql = Regex.Replace(CommandText, @"\s+", " ");
            foreach (var required in new[] { "BEGIN TRAN;", "@WasActive = nv.DangHoatDong", "@OldLicenseNumber = NULLIF(LTRIM(RTRIM(nv.SoBangLai)), '')", "@OldLicenseExpiresAt = nv.NgayHetHanBangLai",
                "FROM dbo.NhanVienGiaoHang nv WITH (UPDLOCK, HOLDLOCK)", "@ActorRole = 'ADMIN' OR tk.MaBuuCuc = @ActorBranch", "'TAIKHOAN_QUANLY'",
                "FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)", "ThoiGianKetThuc IS NULL", "FROM dbo.ChuyenGiaoHang WITH (UPDLOCK, HOLDLOCK)", "'ASSIGNED', 'ACCEPTED', 'IN_PROGRESS'",
                "tt.KyHieuTrangThai = 'RETURNING'", "latest.MaNhanVienGiaoHang = @ShipperId", "WHEN @IsActive = 0 THEN 'OFFLINE'", "INSERT INTO dbo.NhatKyHoatDong", "COMMIT;", "ROLLBACK;" })
                if (!sql.Contains(required)) throw new InvalidOperationException("Missing SQL guard: " + required);
            var predicate = "IF @LicenseExpiresAt IS NOT NULL AND @LicenseExpiresAt < " + VietnamDate.SqlDate("SYSUTCDATETIME()");
            if (!sql.Contains(predicate) || !sql.Contains("(@WasActive = 0 AND @IsActive = 1) OR @OldLicenseExpiresAt IS NULL OR @OldLicenseExpiresAt <> @LicenseExpiresAt OR ISNULL(@OldLicenseNumber, '') COLLATE Latin1_General_100_BIN2 <> ISNULL(@LicenseNumber, '') COLLATE Latin1_General_100_BIN2"))
                throw new InvalidOperationException("Missing historical/reactivation/changed-licence predicate");
            if (!(sql.IndexOf("BEGIN TRAN;", StringComparison.Ordinal) < sql.IndexOf("@WasActive = nv.DangHoatDong", StringComparison.Ordinal)
                && sql.IndexOf("@OldLicenseExpiresAt = nv.NgayHetHanBangLai", StringComparison.Ordinal) < sql.IndexOf(predicate, StringComparison.Ordinal)
                && sql.IndexOf(predicate, StringComparison.Ordinal) < sql.IndexOf("UPDATE dbo.NhanVienGiaoHang", StringComparison.Ordinal)))
                throw new InvalidOperationException("Licence comparison must use locked current row inside transaction before writes");

            if (state.Error != 0) throw SqlError(state.Error);
            if (state.Work is not null) throw SqlError(54905);
            var value = parameters.Parameters["@LicenseExpiresAt"].Value;
            var expiry = value is DateTime date ? DateOnly.FromDateTime(date) : (DateOnly?)null;
            var number = parameters.Parameters["@LicenseNumber"].Value as string;
            var active = (bool)parameters.Parameters["@IsActive"].Value;
            var historyUnchanged = expiry == state.Expiry && number == state.Number?.Trim();
            if (VietnamDate.IsLicenseExpired(expiry, state.Now) && (!historyUnchanged || !state.Active && active))
                throw SqlError(54904);
            state.Expiry = expiry; state.Number = number; state.Active = active; state.Saved = true;
            if (!active) state.Availability = "OFFLINE";
            return JsonSerializer.Serialize(new { id = 3, licenseNumber = number, licenseExpiresAt = expiry, isActive = active, availability = state.Availability });
        }
        public override ValueTask DisposeAsync() { state.CommandDisposed++; parameters.Dispose(); return ValueTask.CompletedTask; }
    }

    private static SqlException SqlError(int number)
    {
        var constructor = typeof(SqlError).GetConstructors(BindingFlags.NonPublic | BindingFlags.Instance).First(c => c.GetParameters().Length == 8);
        var error = constructor.Invoke([number, (byte)1, (byte)16, "MockOnly", "Mock business rejection", "MockProcedure", 1, null]);
        var errors = (SqlErrorCollection)Activator.CreateInstance(typeof(SqlErrorCollection), nonPublic: true)!;
        typeof(SqlErrorCollection).GetMethod("Add", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(errors, [error]);
        return (SqlException)typeof(SqlException).GetMethod("CreateException", BindingFlags.NonPublic | BindingFlags.Static, null, [typeof(SqlErrorCollection), typeof(string)], null)!.Invoke(null, [errors, "Mock"])!;
    }
}
