using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class DeleteDeliveryEvidenceRequest
{
    [Required]
    [StringLength(500, MinimumLength = 3)]
    public string Reason { get; set; } = "";
}

[ApiController]
[Authorize]
[Route("api/v1/orders/{orderId:long}/evidence")]
public class DeliveryEvidenceDeleteController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly IWebHostEnvironment _environment;
    private readonly ILogger<DeliveryEvidenceDeleteController> _logger;

    public DeliveryEvidenceDeleteController(
        IConfiguration configuration,
        IWebHostEnvironment environment,
        ILogger<DeliveryEvidenceDeleteController> logger)
    {
        _configuration = configuration;
        _environment = environment;
        _logger = logger;
    }

    [HttpDelete("{evidenceId:long}")]
    public async Task<IActionResult> Delete(
        [FromRoute]
        [Range(typeof(long), "1", "9223372036854775807")]
        long orderId,

        [FromRoute]
        [Range(typeof(long), "1", "9223372036854775807")]
        long evidenceId,

        [FromBody]
        DeleteDeliveryEvidenceRequest request,

        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        var reason = request.Reason.Trim();

        if (reason.Length < 3)
        {
            return BadRequest(new
            {
                message = "Lý do xóa phải có ít nhất 3 ký tự."
            });
        }

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @ActorRole VARCHAR(50),
                    @ActorRoleId INT,
                    @AttemptId BIGINT,
                    @AttemptResult VARCHAR(20),
                    @RequiresPhoto BIT,
                    @OrderStatus VARCHAR(40),
                    @FilePath NVARCHAR(1000),
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX),
                    @RemainingCount BIGINT;

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
                    THROW 57301,
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
                    THROW 57302,
                        N'API này dành cho shipper quản lý bằng chứng của mình.', 1;

                SELECT @AttemptId = MaLanGiaoHang
                FROM dbo.BangChungGiaoHang
                WHERE MaBangChung = @EvidenceId
                  AND MaDonHang = @OrderId
                  AND MaTaiKhoanTaiLen = @ActorId;

                IF @AttemptId IS NULL
                    THROW 57303,
                        N'Không tìm thấy bằng chứng của bạn.', 1;

                -- Khóa lần giao trước, cùng thứ tự với API upload.
                SELECT
                    @AttemptResult = lg.KetQua,
                    @RequiresPhoto = ISNULL(ld.BatBuocMinhChung, 0)
                FROM dbo.LanGiaoHang lg WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.PhanCongGiaoHang pc WITH (HOLDLOCK)
                    ON pc.MaPhanCongGiaoHang =
                       lg.MaPhanCongGiaoHang
                   AND pc.MaDonHang = lg.MaDonHang
                JOIN dbo.NhanVienGiaoHang nv WITH (HOLDLOCK)
                    ON nv.MaNhanVienGiaoHang =
                       pc.MaNhanVienGiaoHang
                LEFT JOIN dbo.LyDoGiaoThatBai ld WITH (HOLDLOCK)
                    ON ld.MaLyDoGiaoThatBai =
                       lg.MaLyDoGiaoThatBai
                WHERE lg.MaLanGiaoHang = @AttemptId
                  AND lg.MaDonHang = @OrderId
                  AND nv.MaTaiKhoan = @ActorId;

                IF @AttemptResult IS NULL
                    THROW 57303,
                        N'Bằng chứng không thuộc lần giao của bạn.', 1;

                SELECT @OrderStatus = tt.KyHieuTrangThai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang =
                       d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId;

                IF @OrderStatus = 'COMPLETED'
                    THROW 57304,
                        N'Đơn đã hoàn tất, không được xóa bằng chứng.', 1;

                SELECT @OldJson = (
                    SELECT
                        MaBangChung AS id,
                        MaDonHang AS orderId,
                        MaLanGiaoHang AS deliveryAttemptId,
                        LoaiBangChung AS type,
                        DuongDanTep AS filePath,
                        TenNguoiNhan AS receiverName,
                        ThoiGianGhiNhan AS recordedAt,
                        ViDo AS latitude,
                        KinhDo AS longitude,
                        MaTaiKhoanTaiLen AS uploadedBy
                    FROM dbo.BangChungGiaoHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaBangChung = @EvidenceId
                      AND MaDonHang = @OrderId
                      AND MaLanGiaoHang = @AttemptId
                      AND MaTaiKhoanTaiLen = @ActorId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                IF NULLIF(@OldJson, N'') IS NULL
                    THROW 57303,
                        N'Không tìm thấy bằng chứng của bạn.', 1;

                IF JSON_VALUE(@OldJson, '$.type')
                   NOT IN ('PHOTO', 'SIGNATURE')
                    THROW 57304,
                        N'Không được xóa xác nhận OTP hoặc xác nhận người nhận.', 1;

                -- Chỉ cho xóa bằng chứng bổ sung được tạo
                -- bởi API upload, có nhật ký tương ứng.
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.NhatKyHoatDong WITH (HOLDLOCK)
                    WHERE MaTaiKhoan = @ActorId
                      AND LoaiThaoTac = 'UPLOAD_DELIVERY_EVIDENCE'
                      AND TenDoiTuong = 'BangChungGiaoHang'
                      AND MaDoiTuong =
                          CONVERT(VARCHAR(100), @EvidenceId)
                )
                    THROW 57304,
                        N'Bằng chứng xác nhận kết quả giao hàng không được xóa bằng API này.', 1;

                IF @AttemptResult = 'SUCCESS'
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.BangChungGiaoHang WITH (UPDLOCK, HOLDLOCK)
                       WHERE MaLanGiaoHang = @AttemptId
                         AND MaDonHang = @OrderId
                         AND MaBangChung <> @EvidenceId
                   )
                    THROW 57304,
                        N'Phải giữ lại bằng chứng của lần giao thành công.', 1;

                IF @AttemptResult = 'FAILED'
                   AND @RequiresPhoto = 1
                   AND NOT EXISTS (
                       SELECT 1
                       FROM dbo.BangChungGiaoHang WITH (UPDLOCK, HOLDLOCK)
                       WHERE MaLanGiaoHang = @AttemptId
                         AND MaDonHang = @OrderId
                         AND MaBangChung <> @EvidenceId
                         AND LoaiBangChung = 'PHOTO'
                         AND NULLIF(
                             LTRIM(RTRIM(DuongDanTep)), N''
                         ) IS NOT NULL
                   )
                    THROW 57304,
                        N'Lý do giao thất bại này bắt buộc phải giữ lại ảnh minh chứng.', 1;

                SET @FilePath = JSON_VALUE(@OldJson, '$.filePath');

                DELETE FROM dbo.BangChungGiaoHang
                WHERE MaBangChung = @EvidenceId
                  AND MaDonHang = @OrderId;

                SELECT @RemainingCount = COUNT_BIG(*)
                FROM dbo.BangChungGiaoHang
                WHERE MaLanGiaoHang = @AttemptId
                  AND MaDonHang = @OrderId;

                SELECT @Result = (
                    SELECT
                        @EvidenceId AS id,
                        @OrderId AS orderId,
                        @AttemptId AS deliveryAttemptId,
                        CONVERT(BIT, 1) AS deleted,
                        @RemainingCount AS remainingEvidenceCount,
                        @Reason AS reason,
                        N'Đã xóa bằng chứng tải nhầm.' AS message
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
                    @ActorId,
                    'DELETE_DELIVERY_EVIDENCE',
                    'BangChungGiaoHang',
                    CONVERT(VARCHAR(100), @EvidenceId),
                    @OldJson,
                    @Result
                );

                -- Nếu một bản ghi khác dùng chung file,
                -- giữ lại file đó.
                IF EXISTS (
                    SELECT 1
                    FROM dbo.BangChungGiaoHang WITH (HOLDLOCK)
                    WHERE DuongDanTep = @FilePath
                )
                    SET @FilePath = NULL;

                COMMIT;

                SELECT
                    @Result AS ResultJson,
                    @FilePath AS FilePath;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK;
                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = actorId;

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt).Value = orderId;

        command.Parameters.Add(
            "@EvidenceId", SqlDbType.BigInt).Value = evidenceId;

        command.Parameters.Add(
            "@Reason", SqlDbType.NVarChar, 500).Value = reason;

        string resultJson;
        string? filePath;

        try
        {
            await connection.OpenAsync(cancellationToken);

            await using var reader = await command.ExecuteReaderAsync(
                cancellationToken);

            if (!await reader.ReadAsync(cancellationToken))
            {
                return StatusCode(500, new
                {
                    message = "Không nhận được kết quả xóa bằng chứng."
                });
            }

            resultJson = reader.GetString(0);
            filePath = reader.IsDBNull(1)
                ? null
                : reader.GetString(1);
        }
        catch (SqlException ex) when (ex.Number == 57301)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57302)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57303)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 57304)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Bằng chứng đang được cập nhật đồng thời. Hãy thử lại."
            });
        }

        // Chỉ xóa file sau khi database đã commit.
        if (!string.IsNullOrWhiteSpace(filePath))
        {
            TryDeleteFile(filePath);
        }

        return Content(resultJson, "application/json");
    }

    private void TryDeleteFile(string storedPath)
    {
        try
        {
            var root = Path.GetFullPath(
                Path.Combine(
                    _environment.ContentRootPath,
                    "App_Data",
                    "DeliveryEvidence"));

            var fullPath = Path.GetFullPath(
                Path.IsPathRooted(storedPath)
                    ? storedPath
                    : Path.Combine(
                        _environment.ContentRootPath,
                        storedPath));

            var comparison = OperatingSystem.IsWindows()
                ? StringComparison.OrdinalIgnoreCase
                : StringComparison.Ordinal;

            if (!fullPath.StartsWith(
                    root + Path.DirectorySeparatorChar,
                    comparison))
            {
                _logger.LogWarning(
                    "Không xóa file bằng chứng nằm ngoài thư mục cho phép.");

                return;
            }

            if (!System.IO.File.Exists(fullPath))
                return;

            if ((System.IO.File.GetAttributes(fullPath)
                 & FileAttributes.ReparsePoint) != 0)
            {
                return;
            }

            var directory = new FileInfo(fullPath).Directory;

            while (directory is not null)
            {
                if ((directory.Attributes
                     & FileAttributes.ReparsePoint) != 0)
                {
                    return;
                }

                directory = directory.Parent;
            }

            System.IO.File.Delete(fullPath);
        }
        catch (Exception ex) when (
            ex is IOException
            or UnauthorizedAccessException
            or ArgumentException
            or NotSupportedException)
        {
            // Bản ghi đã xóa và nhật ký đã lưu.
            // Nếu file đang bị khóa, ghi log để dọn lại sau.
            _logger.LogWarning(
                ex, "Chưa thể dọn file của bằng chứng đã xóa.");
        }
    }
}