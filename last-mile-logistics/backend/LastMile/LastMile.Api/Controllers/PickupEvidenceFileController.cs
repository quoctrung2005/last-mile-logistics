using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/orders/{orderId:long}/pickup-receipts")]
public class PickupEvidenceFileController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly IWebHostEnvironment _environment;

    public PickupEvidenceFileController(
        IConfiguration configuration,
        IWebHostEnvironment environment)
    {
        _configuration = configuration;
        _environment = environment;
    }

    [HttpGet("{assignmentId:long}/image")]
    public async Task<IActionResult> GetFile(
        [FromRoute]
        [Range(typeof(long), "1", "9223372036854775807")]
        long orderId,

        [FromRoute]
        [Range(typeof(long), "1", "9223372036854775807")]
        long assignmentId,

        [FromQuery]
        bool download = false,

        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
        {
            return Unauthorized();
        }

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @ActorRole VARCHAR(50),
                @ActorRoleId INT,
                @ActorBranchId INT,
                @RequiredPermission VARCHAR(100),
                @FilePath NVARCHAR(1000);

            SELECT
                @ActorRole = vt.KyHieuVaiTro,
                @ActorRoleId = tk.MaVaiTro,
                @ActorBranchId = tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @ActorId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
              );

            IF @ActorRole IS NULL
                THROW 56901,
                    N'Tài khoản không còn hợp lệ.', 1;

            SET @RequiredPermission = CASE
                WHEN @ActorRole = 'SHIPPER'
                    THEN 'NHIEMVU_XEM'
                ELSE 'DONHANG_XEM'
            END;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vq
                JOIN dbo.Quyen q
                    ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @ActorRoleId
                  AND (q.KyHieuQuyen = @RequiredPermission OR (@ActorRole<>'SHIPPER' AND q.KyHieuQuyen='KHO_XEM'))
            )
                THROW 56902,
                    N'Bạn không có quyền xem ảnh nhận kiện.', 1;

            SELECT @FilePath=r.EvidencePath
            FROM dbo.ShipperPickupReceipt r
            JOIN dbo.DonHang d ON d.MaDonHang=r.OrderId
            JOIN dbo.PhanCongGiaoHang pc ON pc.MaPhanCongGiaoHang=r.AssignmentId AND pc.MaDonHang=r.OrderId
            JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang=pc.MaNhanVienGiaoHang
            WHERE r.AssignmentId=@AssignmentId AND r.OrderId=@OrderId
              AND (@ActorRole='ADMIN' OR (@ActorRole<>'SHIPPER' AND d.MaBuuCuc=@ActorBranchId)
                OR (@ActorRole='SHIPPER' AND nv.MaTaiKhoan=@ActorId AND nv.DangHoatDong=1
                  AND d.MaBuuCuc=@ActorBranchId AND EXISTS(SELECT 1 FROM dbo.BuuCuc WHERE MaBuuCuc=@ActorBranchId AND DangHoatDong=1)));

            IF NULLIF(LTRIM(RTRIM(@FilePath)), N'') IS NULL
                THROW 56903,
                    N'Không tìm thấy file bằng chứng trong phạm vi được phép xem.', 1;

            SELECT @FilePath;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = actorId;

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt).Value = orderId;

        command.Parameters.Add(
            "@AssignmentId", SqlDbType.BigInt).Value = assignmentId;

        string storedPath;

        try
        {
            await connection.OpenAsync(cancellationToken);

            await using (var schema = new SqlCommand("SELECT OBJECT_ID(N'dbo.ShipperPickupReceipt',N'U');", connection))
                if (await schema.ExecuteScalarAsync(cancellationToken) is DBNull) return NotFound(new { message = "Chưa có ảnh nhận kiện." });
            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            storedPath = result?.ToString() ?? "";
        }
        catch (SqlException ex) when (ex.Number == 56901)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56902)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56903)
        {
            return NotFound(new { message = ex.Message });
        }

        string fullPath;

        try
        {
            var contentRoot = Path.GetFullPath(
                _environment.ContentRootPath);

            var evidenceRoot = Path.GetFullPath(
                Path.Combine(
                    contentRoot,
                    "App_Data",
                    "PickupEvidence"));

            // Hỗ trợ:
            // App_Data/PickupEvidence/.../file.jpg
            // hoặc đường dẫn tuyệt đối nằm trong evidenceRoot.
            fullPath = Path.GetFullPath(
                Path.IsPathRooted(storedPath)
                    ? storedPath
                    : Path.Combine(contentRoot, storedPath));

            var rootPrefix = evidenceRoot
                + Path.DirectorySeparatorChar;

            var comparison = OperatingSystem.IsWindows()
                ? StringComparison.OrdinalIgnoreCase
                : StringComparison.Ordinal;

            if (!fullPath.StartsWith(rootPrefix, comparison))
            {
                return NotFound(new
                {
                    message = "File bằng chứng không nằm trong thư mục lưu ảnh."
                });
            }

            if (!System.IO.File.Exists(fullPath))
            {
                return NotFound(new
                {
                    message = "File bằng chứng không còn tồn tại."
                });
            }

            // Không đọc file qua symbolic link hoặc junction.
            if (ContainsLink(fullPath))
            {
                return NotFound(new
                {
                    message = "Đường dẫn file bằng chứng không hợp lệ."
                });
            }
        }
        catch (Exception ex) when (
            ex is ArgumentException
            or NotSupportedException
            or IOException
            or UnauthorizedAccessException)
        {
            return NotFound(new
            {
                message = "Không thể truy cập file bằng chứng."
            });
        }

        FileStream? stream = null;

        try
        {
            stream = new FileStream(
                fullPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 81920,
                options: FileOptions.Asynchronous);

            var header = new byte[8];
            var bytesRead = 0;

            while (bytesRead < header.Length)
            {
                var read = await stream.ReadAsync(
                    header.AsMemory(bytesRead),
                    cancellationToken);

                if (read == 0)
                    break;

                bytesRead += read;
            }

            string contentType;
            string extension;

            if (IsPng(header, bytesRead))
            {
                contentType = "image/png";
                extension = ".png";
            }
            else if (IsJpeg(header, bytesRead))
            {
                contentType = "image/jpeg";
                extension = ".jpg";
            }
            else
            {
                return StatusCode(415, new
                {
                    message = "File bằng chứng phải là ảnh JPEG hoặc PNG."
                });
            }

            stream.Position = 0;

            Response.Headers["Cache-Control"] = "private, no-store";
            Response.Headers["X-Content-Type-Options"] = "nosniff";

            var fileName = download
                ? $"evidence-{assignmentId}{extension}"
                : null;

            var fileResult = File(
                stream,
                contentType,
                fileName,
                enableRangeProcessing: true);

            // ASP.NET Core sẽ đóng stream sau khi gửi file.
            stream = null;

            return fileResult;
        }
        catch (Exception ex) when (
            ex is IOException
            or UnauthorizedAccessException)
        {
            return NotFound(new
            {
                message = "Không thể đọc file bằng chứng."
            });
        }
        finally
        {
            if (stream is not null)
                await stream.DisposeAsync();
        }
    }

    private static bool ContainsLink(string fullPath)
    {
        if ((System.IO.File.GetAttributes(fullPath)
             & FileAttributes.ReparsePoint) != 0)
        {
            return true;
        }

        var directory = new FileInfo(fullPath).Directory;

        while (directory is not null)
        {
            if ((directory.Attributes
                 & FileAttributes.ReparsePoint) != 0)
            {
                return true;
            }

            directory = directory.Parent;
        }

        return false;
    }

    private static bool IsPng(byte[] header, int length)
    {
        return length >= 8
            && header[0] == 0x89
            && header[1] == 0x50
            && header[2] == 0x4E
            && header[3] == 0x47
            && header[4] == 0x0D
            && header[5] == 0x0A
            && header[6] == 0x1A
            && header[7] == 0x0A;
    }

    private static bool IsJpeg(byte[] header, int length)
    {
        return length >= 3
            && header[0] == 0xFF
            && header[1] == 0xD8
            && header[2] == 0xFF;
    }
}