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

public class DeliverySuccessRequest
{
    [Range(1,long.MaxValue)] public long? AssignmentId {get;set;}
    [Required,StringLength(150)] public string ReceiverName {get;set;}="";
    [Required,Range(typeof(decimal),"0","9999999999999999.99",ParseLimitsInInvariantCulture=true,ConvertValueInInvariantCulture=true)]
    [ModelBinder(BinderType=typeof(InvariantDecimalModelBinder))] public decimal? ActualCodAmount {get;set;}
    [ModelBinder(BinderType=typeof(InvariantDecimalModelBinder)),Range(typeof(decimal),"-90","90",ParseLimitsInInvariantCulture=true,ConvertValueInInvariantCulture=true)] public decimal? Latitude {get;set;}
    [ModelBinder(BinderType=typeof(InvariantDecimalModelBinder)),Range(typeof(decimal),"-180","180",ParseLimitsInInvariantCulture=true,ConvertValueInInvariantCulture=true)] public decimal? Longitude {get;set;}
    [StringLength(500)] public string? CodNotes {get;set;}
    [StringLength(500)] public string? DeliveryNotes {get;set;}
}
public sealed class DeliverySuccessForm : DeliverySuccessRequest
{
    public IFormFile? Evidence {get;set;}
}

[ApiController,Authorize,Route("api/v1/orders")]
public class OrderDeliverySuccessController(IConfiguration configuration,IWebHostEnvironment environment,
    ILogger<OrderDeliverySuccessController> logger) : ControllerBase
{
    readonly IWebHostEnvironment _environment=environment;
    readonly ILogger<OrderDeliverySuccessController> _logger=logger;
    protected virtual DbConnection CreateConnection()=>new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
    private enum CommitOutcome {NotCommitted,Committed,Unknown}

    [HttpPost("{id:long}/delivery-success"),Consumes("application/json")]
    public Task<IActionResult> DeliverySuccess(long id,[FromBody]DeliverySuccessRequest request,CancellationToken cancellationToken=default)
        => Submit(id,request,null,cancellationToken);

    [HttpPost("{id:long}/delivery-success"),Consumes("multipart/form-data"),RequestSizeLimit(6*1024*1024)]
    public Task<IActionResult> DeliverySuccessWithEvidence(long id,[FromForm]DeliverySuccessForm request,CancellationToken cancellationToken=default)
        => Submit(id,request,request.Evidence,cancellationToken);

    [HttpGet("/api/v1/my/tasks/{assignmentId:long}/delivery-receipt")]
    public async Task<IActionResult> Receipt(long assignmentId,CancellationToken ct)
    {
        if(assignmentId<=0) return BadRequest(new{message="Mã nhiệm vụ không hợp lệ."});
        if(!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out var account))return Unauthorized();
        await using var connection=CreateConnection();await connection.OpenAsync(ct);
        await using var command=connection.CreateCommand();
        command.CommandText="DECLARE @OrderId BIGINT=(SELECT MaDonHang FROM dbo.PhanCongGiaoHang WHERE MaPhanCongGiaoHang=@ExpectedAssignment);"+DeliverySuccessSql.Scope+"SELECT @ExistingReceipt;";
        command.Parameters.Add(new SqlParameter("@AccountId",SqlDbType.BigInt){Value=account});
        command.Parameters.Add(new SqlParameter("@ExpectedAssignment",SqlDbType.BigInt){Value=assignmentId});
        command.Parameters.Add(new SqlParameter("@Permission",SqlDbType.VarChar,100){Value="NHIEMVU_XEM"});
        try {var result=await command.ExecuteScalarAsync(ct);return result is string receipt?Content(receipt,"application/json"):Conflict(new{message="Chưa có biên nhận giao thành công cho nhiệm vụ này."});}
        catch(SqlException error) when(error.Number is >=51801 and <=51805){return SqlError(error);}
    }

    private async Task<IActionResult> Submit(long id,DeliverySuccessRequest request,IFormFile? evidence,CancellationToken cancellationToken)
    {
        if(id<=0 || request.AssignmentId is <=0 || string.IsNullOrWhiteSpace(request.ReceiverName) || request.ActualCodAmount is null)
            return BadRequest(new{message="Mã nhiệm vụ, người nhận thực tế và tiền thực thu phải hợp lệ."});
        if(request.Latitude.HasValue!=request.Longitude.HasValue || request.Latitude is < -90 or >90 || request.Longitude is < -180 or >180 ||
            request.Latitude.HasValue && decimal.Round(request.Latitude.Value,6)!=request.Latitude || request.Longitude.HasValue && decimal.Round(request.Longitude.Value,6)!=request.Longitude ||
            request.ActualCodAmount<0 || decimal.Round(request.ActualCodAmount.Value,2)!=request.ActualCodAmount)
            return BadRequest(new{message="Tiền COD hoặc tọa độ không hợp lệ. Tọa độ tối đa 6 số thập phân; COD tối đa 2 số."});
        if(evidence is not null && request.AssignmentId is null)return BadRequest(new{message="Ảnh bằng chứng phải gắn với mã nhiệm vụ."});
        if(!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out var accountId))return Unauthorized();
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
            command.CommandText = DeliverySuccessSql.Scope + "SELECT @ExistingReceipt;";
            AddScopeParameters(command, accountId, id, request.AssignmentId, "NHIEMVU_CAPNHAT");
            var existing = await command.ExecuteScalarAsync(cancellationToken);
            if (existing is string receipt) return Content(receipt, "application/json");
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
                    "DeliveryEvidence",
                    accountId.ToString());

                Directory.CreateDirectory(folder);

                var filename =
                    Guid.NewGuid().ToString("N") + image.Extension;

                localFilePath = Path.Combine(folder, filename);

                evidencePath =
                    $"App_Data/DeliveryEvidence/{accountId}/{filename}";

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
            command.CommandText = DeliverySuccessSql.Write;
            command.Transaction = transaction;
            AddScopeParameters(command, accountId, id, request.AssignmentId, "NHIEMVU_CAPNHAT");
            command.Parameters.Add(new SqlParameter("@ReceiverName",SqlDbType.NVarChar,150){Value=request.ReceiverName.Trim()});
            command.Parameters.Add(new SqlParameter("@ActualCodAmount",SqlDbType.Decimal){Precision=18,Scale=2,Value=request.ActualCodAmount!.Value});
            command.Parameters.Add(new SqlParameter("@Latitude",SqlDbType.Decimal){Precision=9,Scale=6,Value=(object?)request.Latitude??DBNull.Value});
            command.Parameters.Add(new SqlParameter("@Longitude",SqlDbType.Decimal){Precision=10,Scale=6,Value=(object?)request.Longitude??DBNull.Value});
            command.Parameters.Add(new SqlParameter("@CodNotes",SqlDbType.NVarChar,500){Value=(object?)request.CodNotes?.Trim()??DBNull.Value});
            command.Parameters.Add(new SqlParameter("@Notes",SqlDbType.NVarChar,500){Value=(object?)request.DeliveryNotes?.Trim()??DBNull.Value});
            command.Parameters.Add(new SqlParameter("@EvidencePath",SqlDbType.NVarChar,1000){Value=(object?)evidencePath??DBNull.Value});
            command.Parameters.Add(new SqlParameter("@EvidenceType",SqlDbType.VarChar,30){Value=image is null?"RECEIVER_CONFIRMATION":"PHOTO"});
            outcome = CommitOutcome.Unknown;
            reader = await command.ExecuteReaderAsync(cancellationToken);
            // Drain through command completion, including errors after the result
            // row. No durable commit is sent until the full result has been read.
            var json = await SqlResult.ReadSingleAsync(reader, ["Result"],
                row => row.Text("Result"), cancellationToken);
            await reader.DisposeAsync();
            reader = null;

            using var responseData=JsonDocument.Parse(json);
            unusedUpload=responseData.RootElement.GetProperty("alreadyDelivered").GetBoolean();
            cancellationToken.ThrowIfCancellationRequested();
            commitAttempted = true;
            await transaction.CommitAsync(cancellationToken);
            outcome = CommitOutcome.Committed;

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
                    "Delivery success outcome unknown for order {OrderId}; commit attempted {CommitAttempted}; error type {ErrorType}",
                    id, commitAttempted, error.GetType().Name);
                return StatusCode(500, new
                {
                    code = "DELIVERY_SUCCESS_RESULT_UNKNOWN",
                    resultUnknown = true,
                    message = "Chưa xác định được kết quả ghi nhận giao thành công. Ảnh minh chứng được giữ lại nếu đã lưu. Hãy tải lại đơn hàng và kiểm tra trước khi thực hiện lại."
                });
            }

            if (error is SqlException sqlError &&
                ((sqlError.Number is >= 51801 and <= 51805) ||
                 (sqlError.Number is >= 51120 and <= 51130) || sqlError.Number is 1205 or 2601 or 2627))
                return SqlError(sqlError);

            if (error is EvidenceImageException imageError)
                return StatusCode(imageError.StatusCode, new { message = imageError.Message });

            if (error is OperationCanceledException) throw;

            _logger.LogError("Delivery success not committed for order {OrderId}; error type {ErrorType}",
                id, error.GetType().Name);
            return StatusCode(500, new
            {
                code = "DELIVERY_SUCCESS_NOT_COMMITTED",
                resultUnknown = false,
                message = "Không thể ghi nhận giao thành công. Giao dịch chưa được lưu."
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
                        "Không thể dọn ảnh giao thành công: {Path}",
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
            _logger.LogWarning("Cannot roll back delivery success transaction; error type {ErrorType}", error.GetType().Name);
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
            _logger.LogWarning("Cannot confirm delivery success rollback; error type {ErrorType}", error.GetType().Name);
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
            _logger.LogWarning("Cannot dispose delivery success {Resource}; error type {ErrorType}", name, error.GetType().Name);
        }
    }


    private static void AddScopeParameters(DbCommand command,long account,long order,long? assignment,string permission)
    {
        command.Parameters.Add(new SqlParameter("@AccountId",SqlDbType.BigInt){Value=account});
        command.Parameters.Add(new SqlParameter("@OrderId",SqlDbType.BigInt){Value=order});
        command.Parameters.Add(new SqlParameter("@ExpectedAssignment",SqlDbType.BigInt){Value=(object?)assignment??DBNull.Value});
        command.Parameters.Add(new SqlParameter("@Permission",SqlDbType.VarChar,100){Value=permission});
    }
    private IActionResult SqlError(SqlException error)=>StatusCode(error.Number switch {
        51801=>401,51802 or 51120=>403,51803 or 51121=>404,
        51805 or 51124 or 51125 or 51126 or 51128 or 51129=>422,_=>409
    },new{message=error.Number==1205?"Có thao tác đồng thời. Hãy kiểm tra lại biên nhận trước khi gửi lại.":error.Message});
}
