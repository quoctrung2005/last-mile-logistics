using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CompleteOrderRequest
{
    [StringLength(500)]
    public string? Notes { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/orders")]
public class OrderCompleteController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public OrderCompleteController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{id:long}/complete")]
    public async Task<IActionResult> Complete(
        long id,
        [FromBody] CompleteOrderRequest request)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã đơn hàng không hợp lệ."
            });
        }

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        var notes = string.IsNullOrWhiteSpace(request.Notes)
            ? null
            : request.Notes.Trim();

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Now DATETIME2(0) = SYSUTCDATETIME(),
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @AccountBranchId INT,
                    @OrderStatus VARCHAR(40),
                    @OrderWarehouseId INT,
                    @CodAmount DECIMAL(18,2),
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

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
                    THROW 52501,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DONHANG_CAPNHAT'
                )
                    THROW 52502,
                        N'Bạn không có quyền kết thúc đơn hàng.',
                        1;

                IF @Role <> 'ADMIN'
                   AND @AccountBranchId IS NULL
                    THROW 52502,
                        N'Tài khoản chưa được gán bưu cục.',
                        1;

                SELECT
                    @OrderStatus = tt.KyHieuTrangThai,
                    @OrderWarehouseId = d.MaKhoHienTai,
                    @CodAmount = d.TienCOD
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang =
                       d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (
                      @Role = 'ADMIN'
                      OR d.MaBuuCuc = @AccountBranchId
                  );

                IF @OrderStatus IS NULL
                    THROW 52503,
                        N'Không tìm thấy đơn hàng.',
                        1;

                IF @OrderStatus NOT IN ('DELIVERED', 'RETURNED')
                    THROW 52504,
                        N'Chỉ đơn DELIVERED hoặc RETURNED mới được kết thúc.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongGiaoHang
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 52504,
                        N'Đơn vẫn còn phân công chưa kết thúc.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.YeuCauGiaoLaiHoacHoan
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND TrangThaiYeuCau IN (
                          'PENDING', 'APPROVED', 'IN_PROGRESS'
                      )
                )
                    THROW 52504,
                        N'Đơn còn yêu cầu giao lại hoặc hoàn chưa kết thúc.',
                        1;

                IF @OrderStatus = 'DELIVERED'
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.LanGiaoHang lg
                        INNER JOIN dbo.BangChungGiaoHang bc
                            ON bc.MaLanGiaoHang = lg.MaLanGiaoHang
                           AND bc.MaDonHang = lg.MaDonHang
                        WHERE lg.MaDonHang = @OrderId
                          AND lg.KetQua = 'SUCCESS'
                    )
                        THROW 52504,
                            N'Đơn chưa có lần giao thành công và bằng chứng tương ứng.',
                            1;

                    IF @CodAmount > 0
                       AND NOT EXISTS (
                           SELECT 1
                           FROM dbo.ThuTienCOD c
                           INNER JOIN dbo.LanGiaoHang lg
                               ON lg.MaLanGiaoHang = c.MaLanGiaoHang
                              AND lg.MaDonHang = c.MaDonHang
                           INNER JOIN dbo.PhanCongGiaoHang pc
                               ON pc.MaPhanCongGiaoHang =
                                  lg.MaPhanCongGiaoHang
                              AND pc.MaDonHang = lg.MaDonHang
                           WHERE c.MaDonHang = @OrderId
                             AND lg.KetQua = 'SUCCESS'
                             AND c.MaNhanVienGiaoHang =
                                 pc.MaNhanVienGiaoHang
                             AND c.TrangThaiThuTien = 'COLLECTED'
                             AND c.SoTienPhaiThu = @CodAmount
                             AND c.SoTienThucThu = @CodAmount
                       )
                        THROW 52504,
                            N'Đơn COD chưa được ghi nhận thu đủ tiền.',
                            1;
                END;

                IF @OrderStatus = 'RETURNED'
                BEGIN
                    IF @OrderWarehouseId IS NULL
                       OR NOT EXISTS (
                           SELECT 1
                           FROM dbo.TonKhoDonHang
                               WITH (UPDLOCK, HOLDLOCK)
                           WHERE MaDonHang = @OrderId
                             AND MaKho = @OrderWarehouseId
                             AND TrangThaiTonKho = 'RETURNED'
                             AND MaViTriLuuKho IS NOT NULL
                       )
                        THROW 52504,
                            N'Hàng hoàn chưa có tồn kho RETURNED tại kho hiện tại.',
                            1;

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.YeuCauGiaoLaiHoacHoan
                        WHERE MaDonHang = @OrderId
                          AND LoaiYeuCau = 'RETURN'
                          AND TrangThaiYeuCau = 'COMPLETED'
                    )
                        THROW 52504,
                            N'Yêu cầu hoàn hàng chưa được hoàn tất.',
                            1;
                END;

                SET @OldJson = (
                    SELECT
                        @OrderId AS orderId,
                        @OrderStatus AS orderStatus,
                        @CodAmount AS codAmount
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'COMPLETED',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = @Notes,
                    @NguonCapNhat = 'API';

                SET @Result = (
                    SELECT
                        d.MaDonHang AS orderId,
                        d.KyHieuDonHang AS orderCode,
                        d.MaVanDon AS trackingNumber,
                        @OrderStatus AS previousStatus,
                        tt.KyHieuTrangThai AS orderStatus,
                        d.ThoiGianCapNhat AS completedAt,
                        d.PhienBan AS version,
                        N'Đã kết thúc đơn hàng.' AS message
                    FROM dbo.DonHang d
                    INNER JOIN dbo.TrangThaiDonHang tt
                        ON tt.MaTrangThaiDonHang =
                           d.MaTrangThaiHienTai
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
                    'COMPLETE_ORDER',
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
            "@Notes", SqlDbType.NVarChar, 500).Value =
                (object?)notes ?? DBNull.Value;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 52501 and <= 52504)
        {
            var statusCode = ex.Number switch
            {
                52501 => StatusCodes.Status401Unauthorized,
                52502 => StatusCodes.Status403Forbidden,
                52503 => StatusCodes.Status404NotFound,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Có thao tác đồng thời. Hãy tải lại đơn và thử lại."
            });
        }
    }
}