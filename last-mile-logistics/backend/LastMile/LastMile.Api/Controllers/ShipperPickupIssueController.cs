using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Data.Common;
using System.Security.Claims;
using System.Text.Json;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class PickupIssueRequest
{
    [Required, StringLength(500, MinimumLength = 3)] public string Reason { get; set; } = "";
    [RegularExpression("^(MISSING|WRONG_LABEL|DAMAGED|WAREHOUSE_UNAVAILABLE|OTHER)$")] public string Kind { get; set; } = "OTHER";
    public Guid? RequestId { get; set; }
    [Range(1, int.MaxValue)] public int? ExpectedRevision { get; set; }
    [RegularExpression("^(REQUEST_INFO|RESOLVE)$")] public string? Action { get; set; }
}
public sealed class PickupIssueForm : PickupIssueRequest { public IFormFile? Evidence { get; set; } }
[ApiController, Authorize, Route("api/v1")]
public class ShipperPickupIssueController(IConfiguration configuration, ShipperNotifications notifications, IWebHostEnvironment environment, ILogger<ShipperPickupIssueController> logger) : ControllerBase
{
    readonly IWebHostEnvironment _environment = environment;
    readonly ILogger<ShipperPickupIssueController> _logger = logger;
    protected virtual DbConnection CreateConnection() => new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
    protected virtual Task NotifyPickup(long orderId) => notifications.OrderTasksUpdated(orderId);
    private enum CommitOutcome { NotCommitted, Committed, Unknown }
    [HttpPost("my/tasks/{id:long}/pickup-issue"), Consumes("application/json")]
    public Task<IActionResult> Report(long id, [FromBody] PickupIssueRequest request, CancellationToken ct = default) => Submit(id, null, 0, "REPORT", request, null, ct);
    [HttpPost("my/tasks/{id:long}/pickup-issue"), Consumes("multipart/form-data"), RequestSizeLimit(6 * 1024 * 1024)]
    public Task<IActionResult> ReportWithEvidence(long id, [FromForm] PickupIssueForm request, CancellationToken ct = default) => Submit(id, null, 0, "REPORT", request, request.Evidence, ct);
    [HttpPost("my/tasks/{id:long}/pickup-issues/{issueId:long}/supplement"), Consumes("application/json")]
    public Task<IActionResult> Supplement(long id, long issueId, [FromBody] PickupIssueRequest request, CancellationToken ct = default) => Submit(id, null, issueId, "SUPPLEMENT", request, null, ct);
    [HttpPost("my/tasks/{id:long}/pickup-issues/{issueId:long}/supplement"), Consumes("multipart/form-data"), RequestSizeLimit(6 * 1024 * 1024)]
    public Task<IActionResult> SupplementWithEvidence(long id, long issueId, [FromForm] PickupIssueForm request, CancellationToken ct = default) => Submit(id, null, issueId, "SUPPLEMENT", request, request.Evidence, ct);
    [HttpPost("orders/{orderId:long}/pickup-issues/{issueId:long}/response")]
    public Task<IActionResult> Respond(long orderId, long issueId, [FromBody] PickupIssueRequest request, CancellationToken ct = default) => Submit(null, orderId, issueId, request.Action ?? "", request, null, ct);
    private async Task<IActionResult> Submit(long? assignmentId, long? orderId, long issueId, string mode, PickupIssueRequest request, IFormFile? evidence, CancellationToken cancellationToken)
    {
        if ((assignmentId is <= 0) || (orderId is <= 0) || issueId < 0 || (mode != "REPORT" && issueId <= 0) ||
            mode is not ("REPORT" or "SUPPLEMENT" or "REQUEST_INFO" or "RESOLVE") ||
            string.IsNullOrWhiteSpace(request.Reason) || request.Reason.Trim().Length < 3 || request.Reason.Length > 500 ||
            request.Kind is not ("MISSING" or "WRONG_LABEL" or "DAMAGED" or "WAREHOUSE_UNAVAILABLE" or "OTHER"))
            return BadRequest(new { message = "Mô tả sự cố/hướng xử lý phải từ 3 đến 500 ký tự; loại thao tác không hợp lệ." });
        if (mode != "REPORT" && (request.ExpectedRevision is null or < 1 || request.RequestId is null || request.RequestId == Guid.Empty))
            return BadRequest(new { message = "Thiếu phiên bản hồ sơ hoặc mã yêu cầu. Hãy tải lại." });
        if (request.RequestId == Guid.Empty) return BadRequest(new { message = "Mã yêu cầu không hợp lệ." });
        if (mode == "REPORT" && request.Kind is ("DAMAGED" or "WRONG_LABEL") && evidence is null)
            return BadRequest(new { message = "Sự cố hàng hỏng hoặc sai nhãn phải có ảnh minh chứng." });
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId)) return Unauthorized();
        var requestId = request.RequestId ?? Guid.NewGuid();
        void AddParameters(DbCommand command, string? path = null)
        {
            command.Parameters.Add(new SqlParameter("@AccountId", SqlDbType.BigInt) { Value = accountId });
            command.Parameters.Add(new SqlParameter("@AssignmentId", SqlDbType.BigInt) { Value = (object?)assignmentId ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@OrderId", SqlDbType.BigInt) { Value = (object?)orderId ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@IssueId", SqlDbType.BigInt) { Value = issueId });
            command.Parameters.Add(new SqlParameter("@Mode", SqlDbType.VarChar, 20) { Value = mode });
            command.Parameters.Add(new SqlParameter("@RequestId", SqlDbType.UniqueIdentifier) { Value = requestId });
            command.Parameters.Add(new SqlParameter("@Kind", SqlDbType.VarChar, 30) { Value = request.Kind });
            command.Parameters.Add(new SqlParameter("@Reason", SqlDbType.NVarChar, 500) { Value = request.Reason.Trim() });
            command.Parameters.Add(new SqlParameter("@ExpectedRevision", SqlDbType.Int) { Value = (object?)request.ExpectedRevision ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@EvidencePath", SqlDbType.NVarChar, 1000) { Value = (object?)path ?? DBNull.Value });
        }
        string? localFilePath = null;
        string? evidencePath = null;
        var outcome = CommitOutcome.NotCommitted;
        var commitAttempted = false;
        bool unusedUpload = false;
        DbConnection? connection = null;
        DbTransaction? transaction = null;
        DbCommand? command = null;
        DbDataReader? reader = null;

        try
        {
            connection = CreateConnection();
            await connection.OpenAsync(cancellationToken);

            // Read-only preflight: reject revoked permissions and out-of-scope
            // orders before opening/decoding the image. Recheck under locks below.
            command = connection.CreateCommand();
            command.CommandText = "SELECT CASE WHEN OBJECT_ID(N'dbo.ShipperPickupIssue',N'U') IS NOT NULL AND OBJECT_ID(N'dbo.ShipperPickupIssueEvent',N'U') IS NOT NULL THEN 1 ELSE 0 END;";
            if (!Equals(await command.ExecuteScalarAsync(cancellationToken), 1)) return StatusCode(503, new { message = "Chưa áp dụng migration 20261030_shipper_pickup_issues.sql." });
            command.CommandText = PickupIssueSql.Preflight;
            AddParameters(command);
            var existing = await command.ExecuteScalarAsync(cancellationToken);
            if (existing is string originalReceipt) return Content(originalReceipt, "application/json");
            await DisposeSafelyAsync(command, "preflight command");
            command = null;

            var image = evidence is null ? null
                : await DeliveryEvidenceImage.ReadAsync(evidence, cancellationToken);

            // Lưu ảnh riêng, ngoài wwwroot.
            if (image is not null)
            {
                var folder = Path.Combine(
                    _environment.ContentRootPath,
                    "App_Data",
                    "PickupIssueEvidence",
                    accountId.ToString());

                Directory.CreateDirectory(folder);

                var filename =
                    Guid.NewGuid().ToString("N") + image.Extension;

                localFilePath = Path.Combine(folder, filename);

                evidencePath =
                    $"App_Data/PickupIssueEvidence/{accountId}/{filename}";

                await using var output = new FileStream(
                    localFilePath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None);

                // Save only the bytes/extension returned by the shared processor;
                // never reopen the upload or trust its filename/Content-Type.
                await output.WriteAsync(image.Bytes, cancellationToken);
            }

            transaction = await connection.BeginTransactionAsync(cancellationToken);

            command = connection.CreateCommand();
            command.CommandText = PickupIssueSql.Write;
            command.Transaction = transaction;
            AddParameters(command, evidencePath);
            outcome = CommitOutcome.Unknown;
            reader = await command.ExecuteReaderAsync(cancellationToken);
            // Drain through command completion, including errors after the result
            // row. No durable commit is sent until the full result has been read.
            var json = await SqlResult.ReadSingleAsync(reader, ["Result"],
                row => row.Text("Result"), cancellationToken);
            await reader.DisposeAsync();
            reader = null;

            using var responseData = JsonDocument.Parse(json);
            unusedUpload = responseData.RootElement.GetProperty("alreadyRecorded").GetBoolean();
            cancellationToken.ThrowIfCancellationRequested();
            commitAttempted = true;
            await transaction.CommitAsync(cancellationToken);
            outcome = CommitOutcome.Committed;
            try { await NotifyPickup(responseData.RootElement.GetProperty("orderId").GetInt64()); }
            catch (Exception notificationError)
            {
                _logger.LogWarning(notificationError, "Could not notify after committed pickup {AssignmentId}", assignmentId);
            }

            return Content(json, "application/json");
        }
        catch (Exception error)
        {
            await DisposeSafelyAsync(reader, "reader");
            reader = null;
            if (transaction is not null)
            {
                var rolledBack = await TryRollbackAsync(transaction, connection!, !commitAttempted);
                // A rollback after a commit error is not evidence that commit failed.
                if (!commitAttempted && rolledBack) outcome = CommitOutcome.NotCommitted;
            }

            if (outcome == CommitOutcome.Unknown)
            {
                _logger.LogError(
                    "Pickup issue outcome unknown for order {OrderId}; commit attempted {CommitAttempted}; error type {ErrorType}",
                    assignmentId, commitAttempted, error.GetType().Name);
                return StatusCode(500, new
                {
                    code = "PICKUP_ISSUE_RESULT_UNKNOWN",
                    resultUnknown = true,
                    message = "Chưa xác định được kết quả ghi báo cáo sự cố nhận kiện. Ảnh minh chứng được giữ lại nếu đã lưu. Hãy tải lại đơn hàng và kiểm tra trước khi thực hiện lại."
                });
            }

            if (error is SqlException sqlError &&
                ((sqlError.Number is >= 55900 and <= 55905) || sqlError.Number is 547 or 1205 or 2601 or 2627))
                return SqlError(sqlError);

            if (error is EvidenceImageException imageError)
                return StatusCode(imageError.StatusCode, new { message = imageError.Message });

            if (error is OperationCanceledException) throw;

            _logger.LogError("Pickup issue not committed for order {OrderId}; error type {ErrorType}",
                assignmentId, error.GetType().Name);
            return StatusCode(500, new
            {
                code = "PICKUP_ISSUE_NOT_COMMITTED",
                resultUnknown = false,
                message = "Không thể ghi báo cáo sự cố nhận kiện. Giao dịch chưa được lưu."
            });
        }
        finally
        {
            await DisposeSafelyAsync(reader, "reader");
            await DisposeSafelyAsync(command, "command");
            await DisposeSafelyAsync(transaction, "transaction");
            await DisposeSafelyAsync(connection, "connection");
            // Keep the file for both confirmed commits and uncertain outcomes.
            // Connection disposal/cancellation alone is not proof of a rollback.
            if ((outcome == CommitOutcome.NotCommitted || outcome == CommitOutcome.Committed && unusedUpload) && localFilePath is not null)
            {
                try
                {
                    System.IO.File.Delete(localFilePath);
                }
                catch (Exception ex) when (
                    ex is IOException or UnauthorizedAccessException)
                {
                    _logger.LogWarning(
                        ex,
                        "Không thể dọn ảnh sự cố nhận kiện: {Path}",
                        localFilePath);
                }
            }
        }
    }

    private async Task<bool> TryRollbackAsync(DbTransaction transaction, DbConnection connection, bool canVerifyRollback)
    {
        try
        {
            await transaction.RollbackAsync(CancellationToken.None);
            return true;
        }
        catch (Exception error)
        {
            _logger.LogWarning("Cannot roll back pickup issue transaction; error type {ErrorType}", error.GetType().Name);
        }

        // XACT_ABORT / the procedure's CATCH may already have rolled back the
        // outer transaction, leaving SqlTransaction completed. Confirm the server
        // has no transaction left, only when no outer commit was ever attempted.
        if (!canVerifyRollback) return false;
        DbCommand? check = null;
        try
        {
            if (transaction.Connection is not null || connection.State != ConnectionState.Open) return false;
            check = connection.CreateCommand();
            check.CommandText = "SELECT CASE WHEN XACT_STATE() = 0 AND @@TRANCOUNT = 0 THEN 1 ELSE 0 END;";
            check.CommandTimeout = 5;
            return Equals(await check.ExecuteScalarAsync(CancellationToken.None), 1);
        }
        catch (Exception error)
        {
            _logger.LogWarning("Cannot confirm pickup issue rollback; error type {ErrorType}", error.GetType().Name);
        }
        finally { await DisposeSafelyAsync(check, "rollback check"); }
        return false;
    }

    private async Task DisposeSafelyAsync(IAsyncDisposable? resource, string name)
    {
        if (resource is null) return;
        try { await resource.DisposeAsync(); }
        catch (Exception error)
        {
            _logger.LogWarning("Cannot dispose pickup issue {Resource}; error type {ErrorType}", name, error.GetType().Name);
        }
    }


    private IActionResult SqlError(SqlException error) => StatusCode(error.Number switch { 55900 => 503, 55901 => 401, 55902 => 403, 55903 => 404, _ => 409 }, new { message = error.Number is 1205 or 2601 or 2627 ? "Có thao tác đồng thời. Hãy tải lại hồ sơ và kiểm tra kết quả trước khi gửi lại." : error.Message });
}
