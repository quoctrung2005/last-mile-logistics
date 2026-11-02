using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
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
        [FromForm] DeliveryFailureRequest request)
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

        string? extension = null;

        if (request.Evidence is not null)
        {
            if (request.Evidence.Length < 8
                || request.Evidence.Length > 5 * 1024 * 1024)
            {
                return BadRequest(new
                {
                    message = "Ảnh phải có dữ liệu và không vượt quá 5 MB."
                });
            }

            // Kiểm tra chữ ký đầu tệp; không dùng tên tệp
            // người dùng cung cấp để quyết định định dạng.
            var header = new byte[8];

            await using (var stream = request.Evidence.OpenReadStream())
            {
                await stream.ReadExactlyAsync(header);
            }

            if (header[0] == 0xFF
                && header[1] == 0xD8
                && header[2] == 0xFF)
            {
                extension = ".jpg";
            }
            else if (
                header[0] == 0x89
                && header[1] == 0x50
                && header[2] == 0x4E
                && header[3] == 0x47
                && header[4] == 0x0D
                && header[5] == 0x0A
                && header[6] == 0x1A
                && header[7] == 0x0A)
            {
                extension = ".png";
            }
            else
            {
                return BadRequest(new
                {
                    message = "Chỉ nhận tệp ảnh JPEG hoặc PNG."
                });
            }
        }

        string? localFilePath = null;
        string? evidencePath = null;
        var completed = false;

        try
        {
            // Lưu ảnh riêng, ngoài wwwroot.
            if (request.Evidence is not null)
            {
                var folder = Path.Combine(
                    _environment.ContentRootPath,
                    "App_Data",
                    "DeliveryEvidence",
                    accountId.ToString());

                Directory.CreateDirectory(folder);

                var filename =
                    Guid.NewGuid().ToString("N") + extension;

                localFilePath = Path.Combine(folder, filename);

                evidencePath =
                    $"App_Data/DeliveryEvidence/{accountId}/{filename}";

                await using var output = new FileStream(
                    localFilePath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None);

                await request.Evidence.CopyToAsync(output);
            }

            await using var connection = new SqlConnection(
                _configuration.GetConnectionString("DefaultConnection"));

            await connection.OpenAsync();

            var sql = """
                SET NOCOUNT ON;
                SET XACT_ABORT ON;

                BEGIN TRY
                    BEGIN TRAN;

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

                    COMMIT;

                    SELECT @Result;
                END TRY
                BEGIN CATCH
                    IF XACT_STATE() <> 0
                        ROLLBACK;

                    THROW;
                END CATCH;
                """;

            await using var command = new SqlCommand(sql, connection);

            command.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value = accountId;

            command.Parameters.Add(
                "@OrderId", SqlDbType.BigInt).Value = id;

            command.Parameters.Add(
                "@ReasonId", SqlDbType.Int).Value = request.ReasonId;

            command.Parameters.Add(
                "@Notes", SqlDbType.NVarChar, 1000).Value = notes;

            command.Parameters.Add(
                "@EvidencePath", SqlDbType.NVarChar, 1000).Value =
                    (object?)evidencePath ?? DBNull.Value;

            var json = (string?)await command.ExecuteScalarAsync();

            completed = true;

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            (ex.Number is >= 51901 and <= 51904)
            || (ex.Number is >= 51140 and <= 51146)
            || ex.Number == 1205)
        {
            return SqlError(ex);
        }
        finally
        {
            // Nếu ghi database thất bại, dọn ảnh vừa lưu.
            if (!completed && localFilePath is not null)
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