using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Data.Common;
using System.Security.Claims;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class DeliveryFailureRequest
{
    [Range(1, int.MaxValue)]
    public int ReasonId { get; set; }

    [Required]
    [StringLength(1000)]
    public string Notes { get; set; } = "";

    public IFormFile? Evidence { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1")]
public class OrderDeliveryFailureController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly IWebHostEnvironment _environment;
    private readonly ILogger<OrderDeliveryFailureController> _logger;

    public OrderDeliveryFailureController(
        IConfiguration configuration,
        IWebHostEnvironment environment,
        ILogger<OrderDeliveryFailureController> logger)
    {
        _configuration = configuration;
        _environment = environment;
        _logger = logger;
    }

    // Keep the provider at the boundary so transaction/file failure paths can be
    // exercised with a mock connection, without touching an operational database.
    protected virtual DbConnection CreateConnection() => new SqlConnection(
        _configuration.GetConnectionString("DefaultConnection"));

    private enum CommitOutcome { NotCommitted, Committed, Unknown }

    // Kiểm tra tài khoản và quyền theo database hiện tại.
    private const string AuthSql = """
        DECLARE
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Role VARCHAR(50),
            @RoleId INT,
            @AccountBranchId INT,
            @ShipperId BIGINT;

        SELECT
            @Role = vt.KyHieuVaiTro,
            @RoleId = tk.MaVaiTro,
            @AccountBranchId = tk.MaBuuCuc
        FROM dbo.TaiKhoan tk
        INNER JOIN dbo.VaiTro vt
            ON vt.MaVaiTro = tk.MaVaiTro
        WHERE tk.MaTaiKhoan = @AccountId
          AND tk.TrangThaiTaiKhoan = 'ACTIVE'
          AND vt.DangHoatDong = 1
          AND (
              tk.KhoaDenLuc IS NULL
              OR tk.KhoaDenLuc <= @Now
          );

        IF @Role IS NULL
            THROW 51901,
                N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                1;

        IF @Role <> 'SHIPPER'
           OR NOT EXISTS (
               SELECT 1
               FROM dbo.VaiTroQuyen vtq
               INNER JOIN dbo.Quyen q
                   ON q.MaQuyen = vtq.MaQuyen
               WHERE vtq.MaVaiTro = @RoleId
                 AND q.KyHieuQuyen = 'NHIEMVU_CAPNHAT'
           )
            THROW 51902,
                N'API này dành cho shipper ghi nhận kết quả giao hàng.',
                1;

        SELECT @ShipperId = MaNhanVienGiaoHang
        FROM dbo.NhanVienGiaoHang
        WHERE MaTaiKhoan = @AccountId
          AND DangHoatDong = 1;

        IF @ShipperId IS NULL
            THROW 51902,
                N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                1;

        """;

    [HttpGet("delivery-failure-reasons")]
    public async Task<IActionResult> GetReasons()
    {
        if (!TryGetAccountId(out var accountId))
            return Unauthorized();

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        var sql = "SET NOCOUNT ON;\n" + AuthSql + """
            SELECT (
                SELECT
                    MaLyDoGiaoThatBai AS id,
                    KyHieuLyDo AS code,
                    TenLyDo AS name,
                    BatBuocMinhChung AS requiresEvidence
                FROM dbo.LyDoGiaoThatBai
                WHERE DangHoatDong = 1
                ORDER BY MaLyDoGiaoThatBai
                FOR JSON PATH
            );
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is 51901 or 51902)
        {
            return SqlError(ex);
        }
    }

    [HttpPost("orders/{id:long}/delivery-failure")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(6 * 1024 * 1024)]
    public async Task<IActionResult> DeliveryFailure(
        long id,
        [FromForm] DeliveryFailureRequest request,
        CancellationToken cancellationToken = default)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã đơn hàng không hợp lệ."
            });
        }

        if (!TryGetAccountId(out var accountId))
            return Unauthorized();

        var notes = request.Notes.Trim();

        if (string.IsNullOrWhiteSpace(notes))
        {
            return BadRequest(new
            {
                message = "Phải nhập ghi chú tình huống giao thất bại."
            });
        }

        string? localFilePath = null;
        string? evidencePath = null;
        var outcome = CommitOutcome.NotCommitted;
        var commitAttempted = false;
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
            command.CommandText = "SET NOCOUNT ON;\n" + AuthSql + """
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.DonHang d
                    WHERE d.MaDonHang = @OrderId
                      AND d.MaBuuCuc = @AccountBranchId
                      AND EXISTS (
                          SELECT 1 FROM dbo.PhanCongGiaoHang pc
                          WHERE pc.MaDonHang = d.MaDonHang
                            AND pc.MaNhanVienGiaoHang = @ShipperId
                      )
                )
                    THROW 51903, N'Không tìm thấy đơn hàng của bạn.', 1;
                SELECT 1;
                """;
            command.Parameters.Add(new SqlParameter(
                "@AccountId", SqlDbType.BigInt) { Value = accountId });
            command.Parameters.Add(new SqlParameter(
                "@OrderId", SqlDbType.BigInt) { Value = id });
            await command.ExecuteScalarAsync(cancellationToken);
            await DisposeSafelyAsync(command, "preflight command");
            command = null;

            var image = request.Evidence is null ? null
                : await DeliveryEvidenceImage.ReadAsync(request.Evidence, cancellationToken);

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

            var sql = """
                SET NOCOUNT ON;
                SET XACT_ABORT ON;

                """ + AuthSql + """
                    DECLARE
                        @OrderStatus VARCHAR(40),
                        @AssignmentId BIGINT,
                        @AttemptId BIGINT,
                        @OldJson NVARCHAR(MAX),
                        @Result NVARCHAR(MAX);

                    SELECT @OrderStatus = tt.KyHieuTrangThai
                    FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.TrangThaiDonHang tt
                        ON tt.MaTrangThaiDonHang =
                           d.MaTrangThaiHienTai
                    WHERE d.MaDonHang = @OrderId
                      AND d.MaBuuCuc = @AccountBranchId
                      AND EXISTS (
                          SELECT 1
                          FROM dbo.PhanCongGiaoHang pc
                          WHERE pc.MaDonHang = d.MaDonHang
                            AND pc.MaNhanVienGiaoHang = @ShipperId
                      );

                    IF @OrderStatus IS NULL
                        THROW 51903,
                            N'Không tìm thấy đơn hàng của bạn.',
                            1;

                    IF @OrderStatus <> 'IN_DELIVERY'
                        THROW 51904,
                            N'Chỉ đơn IN_DELIVERY mới được ghi nhận giao thất bại.',
                            1;

                    SELECT @AssignmentId = MaPhanCongGiaoHang
                    FROM dbo.PhanCongGiaoHang
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND MaNhanVienGiaoHang = @ShipperId
                      AND ThoiGianKetThuc IS NULL
                      AND TrangThaiPhanCong = 'IN_PROGRESS';

                    IF @AssignmentId IS NULL
                        THROW 51904,
                            N'Bạn không có phân công IN_PROGRESS hiện hành của đơn.',
                            1;

                    SET @OldJson = (
                        SELECT
                            @OrderId AS orderId,
                            @AssignmentId AS assignmentId,
                            @OrderStatus AS orderStatus
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    );

                    EXEC dbo.sp_XacNhanGiaoHangThatBai
                        @MaDonHang = @OrderId,
                        @MaNhanVienGiaoHang = @ShipperId,
                        @MaTaiKhoan = @AccountId,
                        @MaLyDoGiaoThatBai = @ReasonId,
                        @GhiChu = @Notes,
                        @ThoiGianGiaoLaiDuKien = NULL,
                        @DuongDanTepMinhChung = @EvidencePath,
                        @ViDo = NULL,
                        @KinhDo = NULL;

                    UPDATE dbo.YeuCauGiaoLaiHoacHoan
                    SET TrangThaiYeuCau = 'COMPLETED',
                        ThoiGianHoanTat = SYSUTCDATETIME()
                    WHERE MaDonHang = @OrderId
                      AND LoaiYeuCau = 'RETRY'
                      AND TrangThaiYeuCau = 'IN_PROGRESS';


                    SELECT TOP (1) @AttemptId = MaLanGiaoHang
                    FROM dbo.LanGiaoHang
                    WHERE MaDonHang = @OrderId
                      AND MaPhanCongGiaoHang = @AssignmentId
                      AND KetQua = 'FAILED'
                    ORDER BY SoLanThu DESC;

                    SET @Result = (
                        SELECT
                            d.MaDonHang AS orderId,
                            d.KyHieuDonHang AS orderCode,
                            d.MaVanDon AS trackingNumber,
                            @AssignmentId AS assignmentId,
                            lg.MaLanGiaoHang AS deliveryAttemptId,
                            lg.SoLanThu AS attemptNumber,
                            tt.KyHieuTrangThai AS orderStatus,
                            pc.TrangThaiPhanCong AS assignmentStatus,
                            ld.MaLyDoGiaoThatBai AS reasonId,
                            ld.TenLyDo AS reasonName,
                            lg.GhiChu AS notes,
                            CAST(
                                CASE WHEN @EvidencePath IS NULL
                                     THEN 0 ELSE 1 END
                                AS BIT
                            ) AS hasEvidence,
                            lg.ThoiGianThuGiao AS failedAt,
                            d.PhienBan AS version,
                            N'Đã ghi nhận giao thất bại. Chờ xử lý giao lại hoặc hoàn hàng.'
                                AS message
                        FROM dbo.DonHang d
                        INNER JOIN dbo.TrangThaiDonHang tt
                            ON tt.MaTrangThaiDonHang =
                               d.MaTrangThaiHienTai
                        INNER JOIN dbo.LanGiaoHang lg
                            ON lg.MaLanGiaoHang = @AttemptId
                        INNER JOIN dbo.LyDoGiaoThatBai ld
                            ON ld.MaLyDoGiaoThatBai =
                               lg.MaLyDoGiaoThatBai
                        INNER JOIN dbo.PhanCongGiaoHang pc
                            ON pc.MaPhanCongGiaoHang = @AssignmentId
                        WHERE d.MaDonHang = @OrderId
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    );

                    INSERT INTO dbo.NhatKyHoatDong (
                        MaTaiKhoan,
                        LoaiThaoTac,
                        TenDoiTuong,
                        MaDoiTuong,
                        DuLieuCuJson,
                        DuLieuMoiJson
                    )
                    VALUES (
                        @AccountId,
                        'DELIVERY_FAILURE',
                        'DonHang',
                        CONVERT(VARCHAR(100), @OrderId),
                        @OldJson,
                        @Result
                    );

                    SELECT @Result AS Result;
                """;

            // sp_XacNhanGiaoHangThatBai has a balanced BEGIN TRAN/COMMIT pair:
            // its inner COMMIT only decrements @@TRANCOUNT (2 -> 1). Its CATCH
            // can roll back the entire transaction, including this outer one.
            command = connection.CreateCommand();
            command.CommandText = sql;
            command.Transaction = transaction;

            command.Parameters.Add(new SqlParameter(
                "@AccountId", SqlDbType.BigInt) { Value = accountId });

            command.Parameters.Add(new SqlParameter(
                "@OrderId", SqlDbType.BigInt) { Value = id });

            command.Parameters.Add(new SqlParameter(
                "@ReasonId", SqlDbType.Int) { Value = request.ReasonId });

            command.Parameters.Add(new SqlParameter(
                "@Notes", SqlDbType.NVarChar, 1000) { Value = notes });

            command.Parameters.Add(new SqlParameter(
                "@EvidencePath", SqlDbType.NVarChar, 1000)
                { Value = (object?)evidencePath ?? DBNull.Value });

            outcome = CommitOutcome.Unknown;
            reader = await command.ExecuteReaderAsync(cancellationToken);
            // Drain through command completion, including errors after the result
            // row. No durable commit is sent until the full result has been read.
            var json = await SqlResult.ReadSingleAsync(reader, ["Result"],
                row => row.Text("Result"), cancellationToken);
            await reader.DisposeAsync();
            reader = null;

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
                    "Delivery failure outcome unknown for order {OrderId}; commit attempted {CommitAttempted}; error type {ErrorType}",
                    id, commitAttempted, error.GetType().Name);
                return StatusCode(500, new
                {
                    code = "DELIVERY_FAILURE_RESULT_UNKNOWN",
                    resultUnknown = true,
                    message = "Chưa xác định được kết quả ghi nhận giao thất bại. Ảnh minh chứng được giữ lại nếu đã lưu. Hãy tải lại đơn hàng và kiểm tra trước khi thực hiện lại."
                });
            }

            if (error is SqlException sqlError &&
                ((sqlError.Number is >= 51901 and <= 51904) ||
                 (sqlError.Number is >= 51140 and <= 51146) || sqlError.Number == 1205))
                return SqlError(sqlError);

            if (error is EvidenceImageException imageError)
                return StatusCode(imageError.StatusCode, new { message = imageError.Message });

            if (error is OperationCanceledException) throw;

            _logger.LogError("Delivery failure not committed for order {OrderId}; error type {ErrorType}",
                id, error.GetType().Name);
            return StatusCode(500, new
            {
                code = "DELIVERY_FAILURE_NOT_COMMITTED",
                resultUnknown = false,
                message = "Không thể ghi nhận giao thất bại. Giao dịch chưa được lưu."
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
            if (outcome == CommitOutcome.NotCommitted && localFilePath is not null)
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
                        "Không thể dọn ảnh giao thất bại: {Path}",
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
            _logger.LogWarning("Cannot roll back delivery failure transaction; error type {ErrorType}", error.GetType().Name);
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
            _logger.LogWarning("Cannot confirm delivery failure rollback; error type {ErrorType}", error.GetType().Name);
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
            _logger.LogWarning("Cannot dispose delivery failure {Resource}; error type {ErrorType}", name, error.GetType().Name);
        }
    }

    private bool TryGetAccountId(out long accountId)
    {
        return long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out accountId);
    }

    private IActionResult SqlError(SqlException ex)
    {
        var statusCode = ex.Number switch
        {
            51901 => StatusCodes.Status401Unauthorized,
            51902 or 51140 => StatusCodes.Status403Forbidden,
            51903 or 51141 => StatusCodes.Status404NotFound,
            51143 or 51144 or 51145 =>
                StatusCodes.Status422UnprocessableEntity,
            _ => StatusCodes.Status409Conflict
        };

        return StatusCode(statusCode, new
        {
            message = ex.Number == 1205
                ? "Có thao tác đồng thời. Hãy tải lại đơn và thử lại."
                : ex.Message
        });
    }
}
