using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class UploadDeliveryEvidenceRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long DeliveryAttemptId { get; set; }

    [Required]
    [RegularExpression("^(PHOTO|SIGNATURE)$")]
    public string Type { get; set; } = "PHOTO";

    [Required]
    public IFormFile? File { get; set; }

    [StringLength(150)]
    public string? ReceiverName { get; set; }

    [Range(
        typeof(decimal), "-90", "90",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? Latitude { get; set; }

    [Range(
        typeof(decimal), "-180", "180",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? Longitude { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/orders/{orderId:long}/evidence")]
public class DeliveryEvidenceUploadController : ControllerBase
{
    private const long MaxFileSize = 5 * 1024 * 1024;

    private readonly IConfiguration _configuration;
    private readonly IWebHostEnvironment _environment;
    private readonly ILogger<DeliveryEvidenceUploadController> _logger;

    public DeliveryEvidenceUploadController(
        IConfiguration configuration,
        IWebHostEnvironment environment,
        ILogger<DeliveryEvidenceUploadController> logger)
    {
        _configuration = configuration;
        _environment = environment;
        _logger = logger;
    }

    [HttpPost]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(6 * 1024 * 1024)]
    [RequestFormLimits(MultipartBodyLengthLimit = 6 * 1024 * 1024)]
    public async Task<IActionResult> Upload(
        [FromRoute]
        [Range(typeof(long), "1", "9223372036854775807")]
        long orderId,

        [FromForm]
        UploadDeliveryEvidenceRequest request,

        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        var file = request.File!;

        if (file.Length <= 0 || file.Length > MaxFileSize)
        {
            return BadRequest(new
            {
                message = "Ảnh phải có dung lượng lớn hơn 0 và tối đa 5 MB."
            });
        }

        if (request.Latitude.HasValue != request.Longitude.HasValue)
        {
            return BadRequest(new
            {
                message = "Phải nhập đồng thời latitude và longitude."
            });
        }

        if ((request.Latitude.HasValue
             && decimal.Round(request.Latitude.Value, 6)
                != request.Latitude.Value)
            || (request.Longitude.HasValue
                && decimal.Round(request.Longitude.Value, 6)
                   != request.Longitude.Value))
        {
            return BadRequest(new
            {
                message = "Tọa độ tối đa 6 chữ số thập phân."
            });
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync(cancellationToken);

        await using var transaction =
            (SqlTransaction)await connection.BeginTransactionAsync(
                cancellationToken);

        string? savedPath = null;
        var commitAttempted = false;
        var committed = false;

        try
        {
            // Kiểm tra và khóa các bản ghi trước khi lưu file.
            const string validateSql = """
                SET NOCOUNT ON;

                DECLARE
                    @ActorRole VARCHAR(50),
                    @ActorRoleId INT;

                SELECT
                    @ActorRole = vt.KyHieuVaiTro,
                    @ActorRoleId = tk.MaVaiTro
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @ActorRole IS NULL
                    THROW 57001,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF @ActorRole <> 'SHIPPER'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                       JOIN dbo.Quyen q WITH (HOLDLOCK)
                           ON q.MaQuyen = vq.MaQuyen
                       WHERE vq.MaVaiTro = @ActorRoleId
                         AND q.KyHieuQuyen = 'BANGCHUNG_TAO'
                   )
                    THROW 57002,
                        N'API này dành cho shipper có quyền gửi bằng chứng.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.LanGiaoHang lg WITH (UPDLOCK, HOLDLOCK)
                    JOIN dbo.PhanCongGiaoHang pc WITH (HOLDLOCK)
                        ON pc.MaPhanCongGiaoHang =
                           lg.MaPhanCongGiaoHang
                       AND pc.MaDonHang = lg.MaDonHang
                    JOIN dbo.NhanVienGiaoHang nv WITH (HOLDLOCK)
                        ON nv.MaNhanVienGiaoHang =
                           pc.MaNhanVienGiaoHang
                    WHERE lg.MaLanGiaoHang = @DeliveryAttemptId
                      AND lg.MaDonHang = @OrderId
                      AND nv.MaTaiKhoan = @ActorId
                )
                    THROW 57003,
                        N'Không tìm thấy lần giao thuộc nhiệm vụ của bạn.', 1;

                SELECT 1;
                """;

            await using (var validateCommand = new SqlCommand(
                validateSql, connection, transaction))
            {
                validateCommand.Parameters.Add(
                    "@ActorId", SqlDbType.BigInt).Value = actorId;

                validateCommand.Parameters.Add(
                    "@OrderId", SqlDbType.BigInt).Value = orderId;

                validateCommand.Parameters.Add(
                    "@DeliveryAttemptId", SqlDbType.BigInt).Value =
                    request.DeliveryAttemptId;

                await validateCommand.ExecuteScalarAsync(
                    cancellationToken);
            }

            // Đọc vào bộ nhớ, tối đa 5 MB, để kiểm tra nội dung file.
            using var buffer = new MemoryStream();

            await file.CopyToAsync(buffer, cancellationToken);

            if (buffer.Length <= 0 || buffer.Length > MaxFileSize)
            {
                return BadRequest(new
                {
                    message = "Ảnh phải có dung lượng tối đa 5 MB."
                });
            }

            var bytes = buffer.ToArray();
            var extension = GetImageExtension(bytes);

            if (extension is null)
            {
                return StatusCode(415, new
                {
                    message = "Chỉ chấp nhận ảnh JPEG hoặc PNG."
                });
            }

            var fileName = $"{Guid.NewGuid():N}{extension}";

            var relativePath = Path.Combine(
                "App_Data",
                "DeliveryEvidence",
                actorId.ToString(),
                fileName);

            savedPath = Path.Combine(
                _environment.ContentRootPath,
                relativePath);

            Directory.CreateDirectory(
                Path.GetDirectoryName(savedPath)!);

            await System.IO.File.WriteAllBytesAsync(
                savedPath,
                bytes,
                cancellationToken);

            const string insertSql = """
                SET NOCOUNT ON;

                DECLARE
                    @EvidenceId BIGINT,
                    @Result NVARCHAR(MAX);

                INSERT INTO dbo.BangChungGiaoHang (
                    MaDonHang,
                    MaLanGiaoHang,
                    LoaiBangChung,
                    DuongDanTep,
                    TenNguoiNhan,
                    ViDo,
                    KinhDo,
                    MaTaiKhoanTaiLen
                )
                VALUES (
                    @OrderId,
                    @DeliveryAttemptId,
                    @Type,
                    @FilePath,
                    @ReceiverName,
                    @Latitude,
                    @Longitude,
                    @ActorId
                );

                SET @EvidenceId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                SELECT @Result = (
                    SELECT
                        bc.MaBangChung AS id,
                        bc.MaDonHang AS orderId,
                        bc.MaLanGiaoHang AS deliveryAttemptId,
                        lg.SoLanThu AS attemptNumber,
                        lg.KetQua AS attemptResult,
                        bc.LoaiBangChung AS type,
                        bc.TenNguoiNhan AS receiverName,
                        bc.ThoiGianGhiNhan AS recordedAt,
                        bc.ViDo AS latitude,
                        bc.KinhDo AS longitude,
                        bc.MaTaiKhoanTaiLen AS uploadedBy,
                        CONVERT(BIT, 1) AS hasFile,
                        N'Tải bằng chứng thành công.' AS message
                    FROM dbo.BangChungGiaoHang bc
                    JOIN dbo.LanGiaoHang lg
                        ON lg.MaLanGiaoHang = bc.MaLanGiaoHang
                       AND lg.MaDonHang = bc.MaDonHang
                    WHERE bc.MaBangChung = @EvidenceId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
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
                    @ActorId,
                    'UPLOAD_DELIVERY_EVIDENCE',
                    'BangChungGiaoHang',
                    CONVERT(VARCHAR(100), @EvidenceId),
                    NULL,
                    @Result
                );

                SELECT @Result;
                """;

            await using var insertCommand = new SqlCommand(
                insertSql, connection, transaction);

            insertCommand.Parameters.Add(
                "@ActorId", SqlDbType.BigInt).Value = actorId;

            insertCommand.Parameters.Add(
                "@OrderId", SqlDbType.BigInt).Value = orderId;

            insertCommand.Parameters.Add(
                "@DeliveryAttemptId", SqlDbType.BigInt).Value =
                request.DeliveryAttemptId;

            insertCommand.Parameters.Add(
                "@Type", SqlDbType.VarChar, 30).Value = request.Type;

            insertCommand.Parameters.Add(
                "@FilePath", SqlDbType.NVarChar, 1000).Value =
                relativePath.Replace('\\', '/');

            insertCommand.Parameters.Add(
                "@ReceiverName", SqlDbType.NVarChar, 150).Value =
                string.IsNullOrWhiteSpace(request.ReceiverName)
                    ? DBNull.Value
                    : request.ReceiverName.Trim();

            var latitudeParameter = insertCommand.Parameters.Add(
                "@Latitude", SqlDbType.Decimal);

            latitudeParameter.Precision = 9;
            latitudeParameter.Scale = 6;
            latitudeParameter.Value =
                (object?)request.Latitude ?? DBNull.Value;

            var longitudeParameter = insertCommand.Parameters.Add(
                "@Longitude", SqlDbType.Decimal);

            longitudeParameter.Precision = 10;
            longitudeParameter.Scale = 6;
            longitudeParameter.Value =
                (object?)request.Longitude ?? DBNull.Value;

            var result = await insertCommand.ExecuteScalarAsync(
                cancellationToken);

            commitAttempted = true;

            await transaction.CommitAsync(cancellationToken);

            committed = true;

            return new ContentResult
            {
                StatusCode = StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = result?.ToString() ?? "{}"
            };
        }
        catch (SqlException ex) when (ex.Number == 57001)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57002)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57003)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 547)
        {
            return Conflict(new
            {
                message = "Lần giao hoặc dữ liệu liên quan không còn hợp lệ."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Nhiệm vụ đang được cập nhật đồng thời. Hãy thử lại."
            });
        }
        catch (Exception ex) when (
            ex is IOException or UnauthorizedAccessException)
        {
            _logger.LogError(ex, "Không thể lưu ảnh bằng chứng.");

            return StatusCode(500, new
            {
                message = "Không thể lưu ảnh bằng chứng."
            });
        }
        finally
        {
            if (!committed)
            {
                try
                {
                    await transaction.RollbackAsync(
                        CancellationToken.None);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(
                        ex, "Không thể rollback giao dịch tải bằng chứng.");
                }

                // Nếu lỗi xảy ra trong lúc commit, kết quả commit
                // có thể chưa xác định. Giữ file để tránh xóa ảnh
                // đã được database ghi nhận.
                if (!commitAttempted && savedPath is not null)
                {
                    try
                    {
                        System.IO.File.Delete(savedPath);
                    }
                    catch (Exception ex) when (
                        ex is IOException
                        or UnauthorizedAccessException)
                    {
                        _logger.LogWarning(
                            ex, "Không thể xóa file bằng chứng chưa lưu.");
                    }
                }
            }
        }
    }

    private static string? GetImageExtension(byte[] bytes)
    {
        if (bytes.Length >= 8
            && bytes[0] == 0x89
            && bytes[1] == 0x50
            && bytes[2] == 0x4E
            && bytes[3] == 0x47
            && bytes[4] == 0x0D
            && bytes[5] == 0x0A
            && bytes[6] == 0x1A
            && bytes[7] == 0x0A)
        {
            return ".png";
        }

        if (bytes.Length >= 3
            && bytes[0] == 0xFF
            && bytes[1] == 0xD8
            && bytes[2] == 0xFF)
        {
            return ".jpg";
        }

        return null;
    }
}