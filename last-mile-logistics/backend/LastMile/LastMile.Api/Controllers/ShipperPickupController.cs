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

public class ShipperPickupRequest
{
    [Required, StringLength(50)] public string TrackingNumber { get; set; } = "";
    [StringLength(500)] public string? Notes { get; set; }
    [RegularExpression("^(NORMAL|PREEXISTING_DAMAGE)$")] public string? ParcelCondition { get; set; }
    [ModelBinder(BinderType = typeof(InvariantDecimalModelBinder)), Range(typeof(decimal), "-90", "90", ParseLimitsInInvariantCulture = true, ConvertValueInInvariantCulture = true)] public decimal? Latitude { get; set; }
    [ModelBinder(BinderType = typeof(InvariantDecimalModelBinder)), Range(typeof(decimal), "-180", "180", ParseLimitsInInvariantCulture = true, ConvertValueInInvariantCulture = true)] public decimal? Longitude { get; set; }
    [ModelBinder(BinderType = typeof(InvariantDecimalModelBinder)), Range(typeof(decimal), "0", "100", ParseLimitsInInvariantCulture = true, ConvertValueInInvariantCulture = true)] public decimal? AccuracyMeters { get; set; }
}
public sealed class ShipperPickupForm : ShipperPickupRequest { public IFormFile? Evidence { get; set; } }
[ApiController, Authorize, Route("api/v1/my/tasks")]
public class ShipperPickupController(IConfiguration configuration, ShipperNotifications notifications, IWebHostEnvironment environment, ILogger<ShipperPickupController> logger) : ControllerBase
{
    readonly ShipperNotifications _notifications = notifications;
    readonly IWebHostEnvironment _environment = environment;
    readonly ILogger<ShipperPickupController> _logger = logger;
    protected virtual DbConnection CreateConnection() => new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
    protected virtual Task NotifyPickup(long assignmentId) => _notifications.TaskUpdated(assignmentId);
    private enum CommitOutcome { NotCommitted, Committed, Unknown }
    [HttpPost("{id:long}/pickup"), Consumes("application/json")]
    public Task<IActionResult> Pickup(long id, [FromBody] ShipperPickupRequest request, CancellationToken ct = default) => Submit(id, request, null, ct);
    [HttpPost("{id:long}/pickup"), Consumes("multipart/form-data"), RequestSizeLimit(6 * 1024 * 1024)]
    public Task<IActionResult> PickupWithEvidence(long id, [FromForm] ShipperPickupForm request, CancellationToken ct = default) => Submit(id, request, request.Evidence, ct);
    private async Task<IActionResult> Submit(long id, ShipperPickupRequest request, IFormFile? evidence, CancellationToken cancellationToken)
    {
        if (id <= 0 || string.IsNullOrWhiteSpace(request.TrackingNumber) || request.TrackingNumber.Trim().Length > 50 || request.Notes?.Length > 500)
            return BadRequest(new { message = "Mã kiện hoặc ghi chú nhận không hợp lệ." });
        if (request.ParcelCondition is not (null or "NORMAL" or "PREEXISTING_DAMAGE")) return BadRequest(new { message = "Tình trạng kiện không hợp lệ." });
        if (request.ParcelCondition == "PREEXISTING_DAMAGE" && (string.IsNullOrWhiteSpace(request.Notes) || evidence is null))
            return BadRequest(new { message = "Kiện hư hại sẵn phải có mô tả và ảnh trước khi nhận." });
        if (request.Latitude.HasValue != request.Longitude.HasValue || request.Latitude is < -90 or > 90 || request.Longitude is < -180 or > 180 || request.AccuracyMeters is < 0 or > 100 ||
            request.AccuracyMeters.HasValue && !request.Latitude.HasValue || request.Latitude.HasValue && decimal.Round(request.Latitude.Value, 6) != request.Latitude ||
            request.Longitude.HasValue && decimal.Round(request.Longitude.Value, 6) != request.Longitude || request.AccuracyMeters.HasValue && decimal.Round(request.AccuracyMeters.Value, 2) != request.AccuracyMeters)
            return BadRequest(new { message = "GPS nhận kiện không hợp lệ. Vị trí tối đa 6 số thập phân, độ chính xác tối đa 100 m." });
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId)) return Unauthorized();
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
            command.CommandText = ShipperPickupSql.Preflight;
            AddScopeParameters(command, accountId, id, request.TrackingNumber.Trim());
            await command.ExecuteScalarAsync(cancellationToken);
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
                    "PickupEvidence",
                    accountId.ToString());

                Directory.CreateDirectory(folder);

                var filename =
                    Guid.NewGuid().ToString("N") + image.Extension;

                localFilePath = Path.Combine(folder, filename);

                evidencePath =
                    $"App_Data/PickupEvidence/{accountId}/{filename}";

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
            command.CommandText = ShipperPickupSql.Write;
            command.Transaction = transaction;
            AddScopeParameters(command, accountId, id, request.TrackingNumber.Trim());
            command.Parameters.Add(new SqlParameter("@Notes", SqlDbType.NVarChar, 500) { Value = (object?)request.Notes?.Trim() ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@ParcelCondition", SqlDbType.VarChar, 30) { Value = (object?)request.ParcelCondition ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@Latitude", SqlDbType.Decimal) { Precision = 9, Scale = 6, Value = (object?)request.Latitude ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@Longitude", SqlDbType.Decimal) { Precision = 10, Scale = 6, Value = (object?)request.Longitude ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@AccuracyMeters", SqlDbType.Decimal) { Precision = 9, Scale = 2, Value = (object?)request.AccuracyMeters ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@EvidencePath", SqlDbType.NVarChar, 1000) { Value = (object?)evidencePath ?? DBNull.Value });
            outcome = CommitOutcome.Unknown;
            reader = await command.ExecuteReaderAsync(cancellationToken);
            // Drain through command completion, including errors after the result
            // row. No durable commit is sent until the full result has been read.
            var json = await SqlResult.ReadSingleAsync(reader, ["Result"],
                row => row.Text("Result"), cancellationToken);
            await reader.DisposeAsync();
            reader = null;

            using var responseData = JsonDocument.Parse(json);
            unusedUpload = responseData.RootElement.GetProperty("alreadyReceived").GetBoolean();
            cancellationToken.ThrowIfCancellationRequested();
            commitAttempted = true;
            await transaction.CommitAsync(cancellationToken);
            outcome = CommitOutcome.Committed;
            try { await NotifyPickup(id); }
            catch (Exception notificationError)
            {
                _logger.LogWarning(notificationError, "Could not notify after committed pickup {AssignmentId}", id);
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
                    "Pickup receipt outcome unknown for order {OrderId}; commit attempted {CommitAttempted}; error type {ErrorType}",
                    id, commitAttempted, error.GetType().Name);
                return StatusCode(500, new
                {
                    code = "PICKUP_RECEIPT_RESULT_UNKNOWN",
                    resultUnknown = true,
                    message = "Chưa xác định được kết quả ghi nhận nhận kiện. Ảnh minh chứng được giữ lại nếu đã lưu. Hãy tải lại đơn hàng và kiểm tra trước khi thực hiện lại."
                });
            }

            if (error is SqlException sqlError &&
                ((sqlError.Number is >= 51501 and <= 51504) ||
                 sqlError.Number is 55800 or 51100 or 51101 or 51102 or 547 or 1205 or 2601 or 2627))
                return SqlError(sqlError);

            if (error is EvidenceImageException imageError)
                return StatusCode(imageError.StatusCode, new { message = imageError.Message });

            if (error is OperationCanceledException) throw;

            _logger.LogError("Pickup receipt not committed for order {OrderId}; error type {ErrorType}",
                id, error.GetType().Name);
            return StatusCode(500, new
            {
                code = "PICKUP_RECEIPT_NOT_COMMITTED",
                resultUnknown = false,
                message = "Không thể ghi nhận nhận kiện. Giao dịch chưa được lưu."
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
                        "Không thể dọn ảnh nhận kiện: {Path}",
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
            _logger.LogWarning("Cannot roll back pickup receipt transaction; error type {ErrorType}", error.GetType().Name);
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
            _logger.LogWarning("Cannot confirm pickup receipt rollback; error type {ErrorType}", error.GetType().Name);
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
            _logger.LogWarning("Cannot dispose pickup receipt {Resource}; error type {ErrorType}", name, error.GetType().Name);
        }
    }


    private static void AddScopeParameters(DbCommand command, long account, long assignment, string code)
    {
        command.Parameters.Add(new SqlParameter("@AccountId", SqlDbType.BigInt) { Value = account });
        command.Parameters.Add(new SqlParameter("@AssignmentId", SqlDbType.BigInt) { Value = assignment });
        command.Parameters.Add(new SqlParameter("@ConfirmedCode", SqlDbType.VarChar, 50) { Value = code });
    }
    private IActionResult SqlError(SqlException error) => StatusCode(error.Number switch { 51501 => 401, 51502 => 403, 51503 => 404, 55800 => 503, _ => 409 }, new { message = error.Number == 1205 ? "Có thao tác đồng thời. Hãy kiểm tra lại biên nhận trước khi gửi lại." : error.Message });
}
