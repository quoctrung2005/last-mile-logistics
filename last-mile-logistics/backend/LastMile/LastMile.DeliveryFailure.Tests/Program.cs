using System.Collections;
using System.Data;
using System.Data.Common;
using System.Diagnostics.CodeAnalysis;
using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using LastMile.Api.Controllers;
using ImageMagick;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Logging;

var artifactRoot = Path.GetFullPath(args[0]);
var fixtures = Path.GetFullPath(args[1]);
Directory.CreateDirectory(artifactRoot);
using var validImage = new MagickImage(MagickColors.CornflowerBlue, 64, 48);
var validPng = validImage.ToByteArray(MagickFormat.Png);
var checks = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException(name);
    checks++;
    Console.WriteLine("PASS " + name);
}

async Task Scenario(string name, Action<MockDatabase>? configure,
    Func<MockDatabase, IActionResult, string, TestLogger, Task> verify, bool noFile = false,
    byte[]? imageBytes = null)
{
    var folder = Path.Combine(artifactRoot, "mock-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(folder);
    var db = new MockDatabase { Root = folder };
    var logger = new TestLogger();
    configure?.Invoke(db);
    try
    {
        var controller = new TestController(db, folder, logger);
        var png = imageBytes ?? validPng;
        var upload = new TrackingFile(png, () => db.Preflights == 1);
        var result = await controller.DeliveryFailure(17, new DeliveryFailureRequest
        {
            ReasonId = 1, Notes = "Mock delivery failure",
            Evidence = noFile ? null : upload
        });
        var saved = Directory.GetFiles(folder, "*", SearchOption.AllDirectories);
        await verify(db, result, saved.SingleOrDefault() ?? db.EvidenceFile(folder), logger);
        Check(db.Preflights <= 1 && upload.OpenCalls <= 1 && upload.CopyCalls == 0,
            name + ": preflight before decode; save validated bytes without reopening upload");
        if (db.PreflightError != 0)
            Check(upload.OpenCalls == 0, name + ": rejected scope/permission never reads image");
        Check(db.Executions <= 1 && db.Commits <= 1 && controller.FactoryCalls == 1,
            name + ": no automatic write/commit retry");
        Check(db.ConnectionDisposals == 1 && (db.Begins == 0 || db.TransactionDisposals == 1),
            name + ": connection/transaction disposed");
        Check(db.Commands.All(command => command.WasDisposed), name + ": all commands disposed");
        Check(db.RollbackTokens.All(token => !token.CanBeCanceled), name + ": cleanup rollback ignores caller cancellation");
    }
    finally
    {
        db.FileLock?.Dispose();
        RemoveScenarioFolder(folder);
    }
}

void RemoveScenarioFolder(string folder)
{
    // Only the random child directory created by a scenario can be removed.
    if (Path.GetDirectoryName(Path.GetFullPath(folder)) != artifactRoot ||
        !Path.GetFileName(folder).StartsWith("mock-", StringComparison.Ordinal))
        throw new InvalidOperationException("Unsafe artifact cleanup path");
    Directory.Delete(folder, recursive: true);
}

static JsonElement Body(IActionResult result) => result switch
{
    ContentResult content => JsonSerializer.Deserialize<JsonElement>(content.Content!),
    ObjectResult value => JsonSerializer.SerializeToElement(value.Value),
    _ => throw new InvalidOperationException("Unexpected result: " + result.GetType().Name)
};
static int Status(IActionResult result) => result is ContentResult content ? content.StatusCode ?? 200 : ((ObjectResult)result).StatusCode ?? 200;

await Scenario("success", null, (db, result, photo, _) =>
{
    Check(Status(result) == 200 && Body(result).GetProperty("deliveryAttemptId").GetInt64() == 31, "success: existing JSON contract");
    Check(db.RecordCommitted && File.Exists(photo), "success: committed record and actual image both exist");
    Check(db.ReaderDisposedBeforeCommit, "success: result fully consumed and reader disposed before commit");
    Check(db.Rollbacks == 0, "success: no rollback after commit");
    return Task.CompletedTask;
});

foreach (var phase in new[] { "execute", "result-tail", "empty-result" })
    await Scenario(phase, db => db.FailAt = phase, (db, result, photo, _) =>
    {
        Check(Status(result) == 500 && !Body(result).GetProperty("resultUnknown").GetBoolean(), phase + ": definite failure after acknowledged rollback");
        Check(!db.RecordCommitted && !db.PendingRecord && !File.Exists(photo), phase + ": no database record and image removed");
        Check(db.Commits == 0 && db.Rollbacks == 1, phase + ": no commit before a complete valid result");
        return Task.CompletedTask;
    });

await Scenario("procedure already rolled back", db => db.FailAt = "server-rollback", (db, result, photo, _) =>
{
    Check(!Body(result).GetProperty("resultUnknown").GetBoolean() && !File.Exists(photo), "server rollback: confirmed absent transaction permits image cleanup");
    Check(db.Probes == 1 && db.Commits == 0, "server rollback: verify XACT_STATE/@@TRANCOUNT without replaying writes");
    return Task.CompletedTask;
});

foreach (var phase in new[] { "commit-before", "commit-after", "commit-cancel" })
    await Scenario(phase, db => db.FailAt = phase, (db, result, photo, _) =>
    {
        Check(Status(result) == 500 && Body(result).GetProperty("resultUnknown").GetBoolean(), phase + ": explicit unknown outcome");
        Check(Body(result).GetProperty("message").GetString()!.Contains("kiểm tra trước khi thực hiện lại"), phase + ": check-before-repeat message");
        Check(File.Exists(photo), phase + ": preserve image regardless of commit acknowledgement");
        Check(db.RecordCommitted == (phase != "commit-before"), phase + ": mock durable state distinguishes lost acknowledgement from failed commit");
        Check(db.Probes == 0, phase + ": empty transaction after commit cannot prove rollback");
        return Task.CompletedTask;
    });

await Scenario("unconfirmed rollback", db => { db.FailAt = "execute"; db.RollbackFails = true; }, (db, result, photo, _) =>
{
    Check(Body(result).GetProperty("resultUnknown").GetBoolean() && File.Exists(photo), "rollback connection loss: preserve photo even before commitAttempted");
    Check(db.Commits == 0, "rollback connection loss: no commit or replay");
    return Task.CompletedTask;
});

await Scenario("unconfirmed server state", db => { db.FailAt = "server-rollback"; db.ProbeValue = 0; }, (db, result, photo, _) =>
{
    Check(Body(result).GetProperty("resultUnknown").GetBoolean() && File.Exists(photo), "server state not confirmed: keep evidence");
    Check(db.Probes == 1 && db.Commits == 0, "unconfirmed server state: only a read probe, no commit retry");
    return Task.CompletedTask;
});

await Scenario("open failed", db => db.FailAt = "open", (db, result, photo, _) =>
{
    Check(!Body(result).GetProperty("resultUnknown").GetBoolean() && !File.Exists(photo), "open failed: database never received evidence path, remove photo");
    Check(db.Executions == 0 && db.Begins == 0, "open failed: no database write started");
    return Task.CompletedTask;
});

await Scenario("cleanup error", db => { db.FailAt = "execute"; db.LockFile = true; }, (db, result, photo, logger) =>
{
    Check(Status(result) == 500 && Body(result).GetProperty("code").GetString() == "DELIVERY_FAILURE_NOT_COMMITTED", "file cleanup error does not mask original database failure");
    Check(File.Exists(photo) && logger.Messages.Any(message => message.Contains("Không thể dọn ảnh")), "locked file: cleanup failure logged and original result retained");
    return Task.CompletedTask;
});

await Scenario("dispose error after success", db => db.DisposeFails = true, (db, result, photo, logger) =>
{
    Check(Status(result) == 200 && db.RecordCommitted && File.Exists(photo), "dispose errors cannot turn acknowledged commit into image deletion/failure");
    Check(logger.Messages.Count(message => message.Contains("Cannot dispose")) >= 2, "dispose errors are logged");
    return Task.CompletedTask;
});

await Scenario("dispose error after failure", db => { db.FailAt = "execute"; db.DisposeFails = true; }, (db, result, photo, logger) =>
{
    Check(Body(result).GetProperty("code").GetString() == "DELIVERY_FAILURE_NOT_COMMITTED" && !File.Exists(photo), "dispose errors preserve original known failure and safe file cleanup");
    Check(logger.Messages.Count(message => message.Contains("Cannot dispose")) >= 2, "failure cleanup errors are logged");
    return Task.CompletedTask;
});

await Scenario("without evidence", null, (db, result, photo, _) =>
{
    Check(Status(result) == 200 && db.RecordCommitted && !File.Exists(photo), "optional evidence: successful write without a file remains supported");
    return Task.CompletedTask;
}, noFile: true);

foreach (var name in new[] { "valid.png", "valid.jpg", "max-size.png" })
{
    var bytes = await File.ReadAllBytesAsync(Path.Combine(fixtures, name));
    await Scenario(name, null, async (db, result, photo, _) =>
    {
        Check(Status(result) == 200 && db.RecordCommitted, name + ": decoded image accepted");
        Check(Path.GetExtension(photo) == (name.EndsWith(".jpg") ? ".jpg" : ".png"), name + ": extension from decoder despite misleading filename/type");
        Check((await File.ReadAllBytesAsync(photo)).SequenceEqual(bytes), name + ": saved shared processor bytes");
    }, imageBytes: bytes);
}

foreach (var name in new[] { "signature.png", "signature.jpg", "fake-header.png", "fake-header.jpg", "truncated.png", "truncated.jpg",
    "missing-end.png", "missing-end.jpg", "bad-idat.png", "bad-entropy.jpg", "oversize.png",
    "wide.png", "pixels.png", "animated.png", "unsupported.gif", "text.jpg" })
{
    await Scenario(name, null, (db, result, _, _) =>
    {
        Check(Status(result) is 400 or 415, name + ": invalid image rejected with controlled error");
        Check(db.Executions == 0 && db.Begins == 0 && db.Commits == 0, name + ": rejected before write/transaction");
        Check(!Directory.Exists(Path.Combine(db.Root, "App_Data")), name + ": rejected before saving any file");
        return Task.CompletedTask;
    }, imageBytes: await File.ReadAllBytesAsync(Path.Combine(fixtures, name)));
}

foreach (var error in new[] { 51901, 51902, 51903 })
    await Scenario("preflight " + error, db => db.PreflightError = error, (db, result, _, _) =>
    {
        Check(Status(result) == (error == 51901 ? 401 : error == 51902 ? 403 : 404), "preflight: existing permission/scope mapping " + error);
        Check(db.Begins == 0 && db.Executions == 0 && !Directory.Exists(Path.Combine(db.Root, "App_Data")), "preflight: reject before decode/file/write " + error);
        return Task.CompletedTask;
    });

await Scenario("required evidence missing", db => db.RequiresEvidence = true, (db, result, photo, _) =>
{
    Check(Status(result) == 422 && !db.RecordCommitted && !File.Exists(photo), "required evidence: existing procedure validation remains authoritative");
    Check(db.Commits == 0 && db.Rollbacks == 1, "required evidence: rollback without commit/retry");
    return Task.CompletedTask;
}, noFile: true);

await Scenario("required evidence present", db => db.RequiresEvidence = true, (db, result, photo, _) =>
{
    Check(Status(result) == 200 && db.RecordCommitted && File.Exists(photo), "required evidence: valid photo accepted");
    return Task.CompletedTask;
});

await Scenario("scope changed after decode", db => db.WriteError = 51903, (db, result, photo, _) =>
{
    Check(Status(result) == 404 && !db.RecordCommitted && !File.Exists(photo), "scope changed: transactional recheck rejects and cleans validated photo");
    Check(db.Rollbacks == 1 && db.Commits == 0, "scope changed: rollback, no commit/retry");
    return Task.CompletedTask;
});

// Cancellation must not be passed to rollback; it also must not be marked as an
// attempted commit when the caller has cancelled before CommitAsync is invoked.
var cancelledFolder = Path.Combine(artifactRoot, "mock-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(cancelledFolder);
using (var cancellation = new CancellationTokenSource())
{
    var db = new MockDatabase { Root = cancelledFolder, OnResultComplete = cancellation.Cancel };
    try
    {
        var controller = new TestController(db, cancelledFolder, new TestLogger());
        using var bytes = new MemoryStream(validPng);
        try
        {
            await controller.DeliveryFailure(17, new() { ReasonId = 1, Notes = "Cancel before commit", Evidence = new FormFile(bytes, 0, bytes.Length, "Evidence", "test.png") }, cancellation.Token);
            throw new InvalidOperationException("Expected pre-commit cancellation");
        }
        catch (OperationCanceledException)
        {
            Check(db.Commits == 0 && db.Rollbacks == 1 && !db.RecordCommitted, "pre-commit cancellation: rollback, no commit/retry");
            Check(!File.Exists(db.EvidenceFile(cancelledFolder)), "pre-commit cancellation: remove image after rollback acknowledgement");
            Check(db.RollbackTokens.All(token => !token.CanBeCanceled), "pre-commit cancellation: rollback uses CancellationToken.None");
            Check(db.ConnectionDisposals == 1 && db.TransactionDisposals == 1 && db.Commands.All(command => command.WasDisposed), "pre-commit cancellation: resources disposed without masking cancellation");
        }
    }
    finally { RemoveScenarioFolder(cancelledFolder); }
}

Console.WriteLine($"{checks} checks passed. Mock DbConnection only; no SQL Server/database accessed.");

sealed class TrackingFile(byte[] bytes, Func<bool> preflightCompleted) : IFormFile
{
    public int OpenCalls, CopyCalls;
    public string ContentType => "application/octet-stream";
    public string ContentDisposition => "";
    public IHeaderDictionary Headers { get; set; } = new HeaderDictionary();
    public long Length => bytes.Length;
    public string Name => "Evidence";
    public string FileName => "untrusted.exe";
    public Stream OpenReadStream()
    {
        if (!preflightCompleted()) throw new InvalidOperationException("Image read before authorization/scope preflight");
        OpenCalls++;
        return new MemoryStream(bytes);
    }
    public void CopyTo(Stream target) { CopyCalls++; throw new InvalidOperationException("Must save shared processor output"); }
    public Task CopyToAsync(Stream target, CancellationToken cancellationToken = default)
    { CopyTo(target); return Task.CompletedTask; }
}

static class MockSqlError
{
    // Construct provider errors at the mocked command boundary; never connect.
    public static SqlException Create(int number)
    {
        var errorConstructor = typeof(SqlError).GetConstructors(BindingFlags.NonPublic | BindingFlags.Instance)
            .First(constructor => constructor.GetParameters().Length == 8);
        var error = (SqlError)errorConstructor.Invoke([number, (byte)1, (byte)16, "MockOnly", "Mock business rejection", "MockProcedure", 1, null]);
        var errors = (SqlErrorCollection)Activator.CreateInstance(typeof(SqlErrorCollection), nonPublic: true)!;
        typeof(SqlErrorCollection).GetMethod("Add", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(errors, [error]);
        return (SqlException)typeof(SqlException).GetMethod("CreateException", BindingFlags.NonPublic | BindingFlags.Static,
            null, [typeof(SqlErrorCollection), typeof(string)], null)!.Invoke(null, [errors, "Mock"])!;
    }
}

sealed class TestController : OrderDeliveryFailureController
{
    private readonly MockDatabase database;
    public TestController(MockDatabase db, string folder, TestLogger logger) : base(
        new ConfigurationBuilder().Build(), new TestEnvironment { ContentRootPath = folder }, logger)
    {
        database = db;
        ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "7")], "Mock")) } };
    }
    public int FactoryCalls { get; private set; }
    protected override DbConnection CreateConnection() { FactoryCalls++; return new MockConnection(database); }
}

sealed class MockDatabase
{
    public required string Root;
    public string? FailAt;
    public bool RollbackFails, DisposeFails, LockFile, PendingRecord, RecordCommitted, ReaderDisposedBeforeCommit, RequiresEvidence;
    public int Begins, Executions, Commits, Rollbacks, Probes, ConnectionDisposals, TransactionDisposals, Preflights, PreflightError, WriteError;
    public int ProbeValue = 1;
    public Action? OnResultComplete;
    public string? RelativeEvidencePath;
    public FileStream? FileLock;
    public List<MockCommand> Commands = [];
    public List<CancellationToken> RollbackTokens = [];
    public string EvidenceFile(string root) => Path.Combine(root, RelativeEvidencePath ?? "not-created.png");
}

sealed class MockConnection(MockDatabase db) : DbConnection
{
    private ConnectionState state;
    [AllowNull] public override string ConnectionString { get; set; } = "";
    public override string Database => "MockOnly";
    public override string DataSource => "NoSqlServer";
    public override string ServerVersion => "Mock";
    public override ConnectionState State => state;
    public MockTransaction? Transaction;
    public override void Open() { if (db.FailAt == "open") throw new IOException("Mock open failure"); state = ConnectionState.Open; }
    public override Task OpenAsync(CancellationToken token) { token.ThrowIfCancellationRequested(); Open(); return Task.CompletedTask; }
    public override void Close() => state = ConnectionState.Closed;
    public override void ChangeDatabase(string name) => throw new NotSupportedException();
    protected override DbTransaction BeginDbTransaction(IsolationLevel level) { db.Begins++; return Transaction = new MockTransaction(db, this); }
    protected override DbCommand CreateDbCommand() { var command = new MockCommand(db, this); db.Commands.Add(command); return command; }
    public override ValueTask DisposeAsync() { db.ConnectionDisposals++; Close(); if (db.DisposeFails) throw new IOException("Mock connection dispose failure"); return ValueTask.CompletedTask; }
}

sealed class MockTransaction(MockDatabase db, MockConnection connection) : DbTransaction
{
    public bool Completed;
    protected override DbConnection? DbConnection => Completed ? null : connection;
    public override IsolationLevel IsolationLevel => IsolationLevel.ReadCommitted;
    public override void Commit() => CommitAsync().GetAwaiter().GetResult();
    public override Task CommitAsync(CancellationToken token = default)
    {
        db.Commits++;
        db.ReaderDisposedBeforeCommit = db.Commands.All(command => command.Reader?.IsClosed != false);
        if (db.FailAt == "commit-before") throw new IOException("Mock connection loss before commit");
        db.RecordCommitted = db.PendingRecord; db.PendingRecord = false; Completed = true;
        if (db.FailAt == "commit-after") throw new IOException("Mock committed, acknowledgement lost");
        if (db.FailAt == "commit-cancel") throw new OperationCanceledException("Mock commit cancelled after server commit");
        return Task.CompletedTask;
    }
    public override void Rollback() => RollbackAsync().GetAwaiter().GetResult();
    public override Task RollbackAsync(CancellationToken token = default)
    {
        db.Rollbacks++; db.RollbackTokens.Add(token);
        if (db.RollbackFails || Completed) throw new IOException("Mock rollback not acknowledged/already completed");
        db.PendingRecord = false; Completed = true; return Task.CompletedTask;
    }
    public override ValueTask DisposeAsync() { db.TransactionDisposals++; if (db.DisposeFails) throw new IOException("Mock transaction dispose failure"); return ValueTask.CompletedTask; }
}

sealed class MockCommand(MockDatabase db, MockConnection connection) : DbCommand
{
    private readonly SqlCommand parameters = new();
    public DbDataReader? Reader;
    public bool WasDisposed;
    [AllowNull] public override string CommandText { get; set; } = "";
    public override int CommandTimeout { get; set; }
    public override CommandType CommandType { get; set; }
    public override bool DesignTimeVisible { get; set; }
    public override UpdateRowSource UpdatedRowSource { get; set; }
    protected override DbConnection? DbConnection { get; set; } = connection;
    protected override DbTransaction? DbTransaction { get; set; }
    protected override DbParameterCollection DbParameterCollection => parameters.Parameters;
    public override void Cancel() { }
    public override int ExecuteNonQuery() => throw new NotSupportedException();
    public override object ExecuteScalar()
    {
        if (CommandText.Contains("XACT_STATE() = 0 AND @@TRANCOUNT = 0"))
        { db.Probes++; return db.ProbeValue; }
        foreach (var required in new[] { "NHIEMVU_CAPNHAT", "tk.TrangThaiTaiKhoan = 'ACTIVE'", "vt.DangHoatDong = 1",
            "d.MaBuuCuc = @AccountBranchId", "pc.MaNhanVienGiaoHang = @ShipperId", "THROW 51903" })
            if (!CommandText.Contains(required)) throw new InvalidOperationException("Missing preflight scope/auth: " + required);
        if (DbTransaction is not null || Directory.Exists(Path.Combine(db.Root, "App_Data")))
            throw new InvalidOperationException("Preflight must precede file save/transaction");
        db.Preflights++;
        if (db.PreflightError != 0) throw MockSqlError.Create(db.PreflightError);
        return 1;
    }
    public override void Prepare() { }
    protected override DbParameter CreateDbParameter() => new SqlParameter();
    protected override DbDataReader ExecuteDbDataReader(CommandBehavior behavior)
    {
        db.Executions++;
        if (DbTransaction is null || CommandText.Contains("COMMIT;", StringComparison.OrdinalIgnoreCase) ||
            CommandText.Contains("BEGIN TRAN", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Controller must own the outer transaction");
        foreach (var retained in new[] { "NHIEMVU_CAPNHAT", "@OrderStatus <> 'IN_DELIVERY'", "TrangThaiPhanCong = 'IN_PROGRESS'", "sp_XacNhanGiaoHangThatBai", "UPDATE dbo.YeuCauGiaoLaiHoacHoan", "INSERT INTO dbo.NhatKyHoatDong" })
            if (!CommandText.Contains(retained)) throw new InvalidOperationException("Lost business SQL: " + retained);
        db.RelativeEvidencePath = parameters.Parameters["@EvidencePath"].Value as string;
        if (db.RelativeEvidencePath is not null && !File.Exists(db.EvidenceFile(db.Root)))
            throw new InvalidOperationException("Evidence must exist before database insert");
        if (db.WriteError != 0) throw MockSqlError.Create(db.WriteError);
        if (db.RequiresEvidence && db.RelativeEvidencePath is null) throw MockSqlError.Create(51144);
        db.PendingRecord = true;
        if (db.LockFile && db.RelativeEvidencePath is not null)
        {
            db.FileLock = new FileStream(db.EvidenceFile(db.Root), FileMode.Open, FileAccess.Read, FileShare.None);
        }
        if (db.FailAt == "server-rollback") { db.PendingRecord = false; connection.Transaction!.Completed = true; throw new IOException("Mock procedure rolled back entire transaction"); }
        if (db.FailAt == "execute") throw new IOException("Mock execute failure");
        var table = new DataTable(); table.Columns.Add("Result", typeof(string));
        if (db.FailAt != "empty-result") table.Rows.Add("{\"orderId\":17,\"deliveryAttemptId\":31,\"message\":\"Đã ghi nhận giao thất bại.\"}");
        return Reader = new ResultReader(table.CreateDataReader(), db.FailAt == "result-tail", db.OnResultComplete);
    }
    public override ValueTask DisposeAsync() { WasDisposed = true; parameters.Dispose(); return ValueTask.CompletedTask; }
}

sealed class ResultReader(DbDataReader inner, bool failTail, Action? onComplete) : DbDataReader
{
    public override int FieldCount => inner.FieldCount;
    public override bool HasRows => inner.HasRows;
    public override bool IsClosed => inner.IsClosed;
    public override int RecordsAffected => inner.RecordsAffected;
    public override int Depth => inner.Depth;
    public override object this[int i] => inner[i];
    public override object this[string name] => inner[name];
    public override bool Read() => inner.Read();
    public override bool NextResult()
    {
        if (failTail) throw new IOException("Mock result tail lost");
        var next = inner.NextResult();
        if (!next) onComplete?.Invoke();
        return next;
    }
    public override string GetName(int i) => inner.GetName(i);
    public override int GetOrdinal(string name) => inner.GetOrdinal(name);
    public override object GetValue(int i) => inner.GetValue(i);
    public override int GetValues(object[] values) => inner.GetValues(values);
    public override Type GetFieldType(int i) => inner.GetFieldType(i);
    public override string GetDataTypeName(int i) => inner.GetDataTypeName(i);
    public override bool IsDBNull(int i) => inner.IsDBNull(i);
    public override bool GetBoolean(int i) => inner.GetBoolean(i);
    public override byte GetByte(int i) => inner.GetByte(i);
    public override long GetBytes(int i, long offset, byte[]? buffer, int start, int length) => inner.GetBytes(i, offset, buffer, start, length);
    public override char GetChar(int i) => inner.GetChar(i);
    public override long GetChars(int i, long offset, char[]? buffer, int start, int length) => inner.GetChars(i, offset, buffer, start, length);
    public override Guid GetGuid(int i) => inner.GetGuid(i);
    public override short GetInt16(int i) => inner.GetInt16(i);
    public override int GetInt32(int i) => inner.GetInt32(i);
    public override long GetInt64(int i) => inner.GetInt64(i);
    public override float GetFloat(int i) => inner.GetFloat(i);
    public override double GetDouble(int i) => inner.GetDouble(i);
    public override string GetString(int i) => inner.GetString(i);
    public override decimal GetDecimal(int i) => inner.GetDecimal(i);
    public override DateTime GetDateTime(int i) => inner.GetDateTime(i);
    public override IEnumerator GetEnumerator() => ((IEnumerable)inner).GetEnumerator();
    public override ValueTask DisposeAsync() => inner.DisposeAsync();
}

sealed class TestLogger : ILogger<OrderDeliveryFailureController>
{
    public List<string> Messages = [];
    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
    public bool IsEnabled(LogLevel level) => true;
    public void Log<TState>(LogLevel level, EventId id, TState state, Exception? error, Func<TState, Exception?, string> formatter) => Messages.Add(formatter(state, error));
}

sealed class TestEnvironment : IWebHostEnvironment
{
    public string ApplicationName { get; set; } = "MockDeliveryFailure";
    public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
    public string WebRootPath { get; set; } = "";
    public string EnvironmentName { get; set; } = "Testing";
    public string ContentRootPath { get; set; } = "";
    public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
}
