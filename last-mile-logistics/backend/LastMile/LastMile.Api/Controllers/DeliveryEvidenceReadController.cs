using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/orders/{orderId:long}/evidence")]
public class DeliveryEvidenceReadController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public DeliveryEvidenceReadController(
        IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> Get(
        [FromRoute]
        [Range(typeof(long), "1", "9223372036854775807")]
        long orderId,

        [FromQuery]
        [Range(typeof(long), "1", "9223372036854775807")]
        long? evidenceId = null,

        [FromQuery]
        [RegularExpression(
            "^(PHOTO|SIGNATURE|OTP|RECEIVER_CONFIRMATION)$")]
        string? type = null,

        [FromQuery]
        [Range(1, int.MaxValue)]
        int page = 1,

        [FromQuery]
        [Range(1, 100)]
        int pageSize = 10,

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
                @TrackingNumber VARCHAR(50),
                @Result NVARCHAR(MAX);

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
                THROW 56801,
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
                  AND q.KyHieuQuyen = @RequiredPermission
            )
                THROW 56802,
                    N'Bạn không có quyền xem bằng chứng giao hàng.', 1;

            -- Chỉ tìm đơn nằm trong phạm vi được phép xem.
            SELECT @TrackingNumber = d.MaVanDon
            FROM dbo.DonHang d
            WHERE d.MaDonHang = @OrderId
              AND (
                  @ActorRole = 'ADMIN'

                  OR (
                      @ActorRole <> 'ADMIN'
                      AND @ActorRole <> 'SHIPPER'
                      AND d.MaBuuCuc = @ActorBranchId
                  )

                  OR (
                      @ActorRole = 'SHIPPER'
                      AND EXISTS (
                          SELECT 1
                          FROM dbo.PhanCongGiaoHang pc
                          JOIN dbo.NhanVienGiaoHang nv
                              ON nv.MaNhanVienGiaoHang =
                                 pc.MaNhanVienGiaoHang
                          WHERE pc.MaDonHang = d.MaDonHang
                            AND nv.MaTaiKhoan = @ActorId
                      )
                  )
              );

            IF @TrackingNumber IS NULL
                THROW 56803,
                    N'Không tìm thấy đơn hàng trong phạm vi được phép xem.', 1;

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
                tk.HoTen AS uploadedByName,

                CONVERT(BIT, CASE
                    WHEN NULLIF(
                        LTRIM(RTRIM(bc.DuongDanTep)), N''
                    ) IS NOT NULL
                    THEN 1
                    ELSE 0
                END) AS hasFile

            INTO #Evidence

            FROM dbo.BangChungGiaoHang bc
            JOIN dbo.LanGiaoHang lg
                ON lg.MaLanGiaoHang = bc.MaLanGiaoHang
               AND lg.MaDonHang = bc.MaDonHang
            JOIN dbo.PhanCongGiaoHang pc
                ON pc.MaPhanCongGiaoHang =
                   lg.MaPhanCongGiaoHang
               AND pc.MaDonHang = lg.MaDonHang
            JOIN dbo.NhanVienGiaoHang nv
                ON nv.MaNhanVienGiaoHang =
                   pc.MaNhanVienGiaoHang
            JOIN dbo.TaiKhoan tk
                ON tk.MaTaiKhoan = bc.MaTaiKhoanTaiLen

            WHERE bc.MaDonHang = @OrderId
              AND (
                  @ActorRole <> 'SHIPPER'
                  OR nv.MaTaiKhoan = @ActorId
              )
              AND (
                  (
                      @EvidenceId IS NOT NULL
                      AND bc.MaBangChung = @EvidenceId
                  )
                  OR (
                      @EvidenceId IS NULL
                      AND (
                          @Type IS NULL
                          OR bc.LoaiBangChung = @Type
                      )
                  )
              );

            IF @EvidenceId IS NOT NULL
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM #Evidence)
                    THROW 56803,
                        N'Không tìm thấy bằng chứng trong phạm vi được phép xem.', 1;

                SELECT @Result = (
                    SELECT *
                    FROM #Evidence
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );
            END
            ELSE
            BEGIN
                DECLARE @TotalItems BIGINT;

                SELECT @TotalItems = COUNT_BIG(*)
                FROM #Evidence;

                SELECT @Result = (
                    SELECT
                        @OrderId AS orderId,
                        @TrackingNumber AS trackingNumber,
                        @Page AS page,
                        @PageSize AS pageSize,
                        @TotalItems AS totalItems,

                        JSON_QUERY(COALESCE((
                            SELECT *
                            FROM #Evidence
                            ORDER BY recordedAt DESC, id DESC
                            OFFSET @Offset ROWS
                            FETCH NEXT @PageSize ROWS ONLY
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        ), N'[]')) AS items

                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );
            END;

            SELECT @Result;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@ActorId", SqlDbType.BigInt).Value = actorId;

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt).Value = orderId;

        command.Parameters.Add(
            "@EvidenceId", SqlDbType.BigInt).Value =
            (object?)evidenceId ?? DBNull.Value;

        command.Parameters.Add(
            "@Type", SqlDbType.VarChar, 30).Value =
            (object?)type ?? DBNull.Value;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value = pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.BigInt).Value =
            ((long)page - 1) * pageSize;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 56801)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56802)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56803)
        {
            return NotFound(new { message = ex.Message });
        }
    }
}
