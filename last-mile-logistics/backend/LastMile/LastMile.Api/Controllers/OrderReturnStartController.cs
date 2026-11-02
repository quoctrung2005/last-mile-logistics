using LastMile.Api.Services;
using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class StartOrderReturnRequest
{
    [Range(1, long.MaxValue)]
    public long ReturnRequestId { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/orders")]
public class OrderReturnStartController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public OrderReturnStartController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{id:long}/return-start")]
    public async Task<IActionResult> StartReturn(
        long id,
        [FromBody] StartOrderReturnRequest request)
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

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        var sql = $$"""
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Now DATETIME2(0) = SYSUTCDATETIME(),
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @AccountBranchId INT,
                    @ShipperId BIGINT,
                    @OrderStatus VARCHAR(40),
                    @AssignmentId BIGINT,
                    @VehicleId BIGINT,
                    @ReturnBranchId INT,
                    @RequestStatus VARCHAR(20),
                    @ReturnReason NVARCHAR(500),
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
                    THROW 52301,
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
                    THROW 52302,
                        N'API này dành cho shipper bắt đầu hoàn hàng.',
                        1;

                SELECT @ShipperId = MaNhanVienGiaoHang
                FROM dbo.NhanVienGiaoHang
                WHERE MaTaiKhoan = @AccountId
                  AND DangHoatDong = 1;

                IF @ShipperId IS NULL
                    THROW 52302,
                        N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                        1;

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
                    THROW 52303,
                        N'Không tìm thấy đơn hàng của bạn.',
                        1;

                IF @OrderStatus NOT IN ('FAILED', 'RETRY_WAITING')
                    THROW 52304,
                        N'Chỉ đơn FAILED hoặc RETRY_WAITING mới được bắt đầu hoàn.',
                        1;

                SELECT
                    @AssignmentId = MaPhanCongGiaoHang,
                    @VehicleId = MaPhuongTien
                FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaDonHang = @OrderId
                  AND MaNhanVienGiaoHang = @ShipperId
                  AND ThoiGianKetThuc IS NULL
                  AND TrangThaiPhanCong = 'IN_PROGRESS';

                IF @AssignmentId IS NULL
                    THROW 52304,
                        N'Bạn không có phân công IN_PROGRESS hiện hành của đơn.',
                        1;

                SELECT
                    @ReturnBranchId = MaBuuCucHoan,
                    @RequestStatus = TrangThaiYeuCau,
                    @ReturnReason = LyDo
                FROM dbo.YeuCauGiaoLaiHoacHoan
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE MaYeuCauGiaoLaiHoacHoan = @ReturnRequestId
                  AND MaDonHang = @OrderId
                  AND LoaiYeuCau = 'RETURN';

                IF @RequestStatus IS NULL
                    THROW 52303,
                        N'Không tìm thấy yêu cầu hoàn của đơn.',
                        1;

                IF @RequestStatus <> 'APPROVED'
                    THROW 52304,
                        N'Yêu cầu hoàn phải ở trạng thái APPROVED.',
                        1;

                -- Hiện hỗ trợ hoàn về bưu cục gốc.
                IF @ReturnBranchId IS NULL
                   OR @ReturnBranchId <> @AccountBranchId
                    THROW 52304,
                        N'Bưu cục nhận hoàn không phù hợp với luồng hoàn hiện tại.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.BuuCuc
                    WHERE MaBuuCuc = @ReturnBranchId
                      AND DangHoatDong = 1
                )
                    THROW 52304,
                        N'Bưu cục nhận hoàn đã ngừng hoạt động.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.NhanVienGiaoHang
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaNhanVienGiaoHang = @ShipperId
                      AND MaTaiKhoan = @AccountId
                      AND DangHoatDong = 1
                      AND TrangThaiSanSang IN (
                          'AVAILABLE', 'DELIVERING'
                      )
                      AND (
                          NgayHetHanBangLai IS NULL
                          OR NgayHetHanBangLai >= {{VietnamDate.SqlDate("@Now")}}
                      )
                )
                    THROW 52304,
                        N'Shipper hiện không đủ điều kiện vận chuyển hàng hoàn.',
                        1;

                IF @VehicleId IS NULL
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.PhuongTien WITH (UPDLOCK, HOLDLOCK)
                       WHERE MaPhuongTien = @VehicleId
                         AND DangHoatDong = 1
                         AND TrangThaiPhuongTien IN (
                             'AVAILABLE', 'IN_USE'
                         )
                   )
                    THROW 52304,
                        N'Phương tiện không còn phù hợp.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongPhuongTien
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaNhanVienGiaoHang = @ShipperId
                      AND MaPhuongTien = @VehicleId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 52304,
                        N'Phương tiện không còn được phân cho bạn.',
                        1;

                SET @OldJson = (
                    SELECT
                        @OrderId AS orderId,
                        @OrderStatus AS orderStatus,
                        @ReturnRequestId AS returnRequestId,
                        @RequestStatus AS requestStatus,
                        @AssignmentId AS assignmentId,
                        'IN_PROGRESS' AS assignmentStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                UPDATE dbo.YeuCauGiaoLaiHoacHoan
                SET TrangThaiYeuCau = 'IN_PROGRESS'
                WHERE MaYeuCauGiaoLaiHoacHoan = @ReturnRequestId;

                -- Procedure chuyển RETURNING đồng thời kết thúc
                -- phân công giao hiện hành.
                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'RETURNING',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = @ReturnReason,
                    @NguonCapNhat = 'API';

                UPDATE dbo.NhanVienGiaoHang
                SET TrangThaiSanSang = 'DELIVERING'
                WHERE MaNhanVienGiaoHang = @ShipperId;

                UPDATE dbo.PhuongTien
                SET TrangThaiPhuongTien = 'IN_USE'
                WHERE MaPhuongTien = @VehicleId;

                {{DeferredReturnSql.Reconcile}}

                SET @Result = (
                    SELECT
                        d.MaDonHang AS orderId,
                        d.KyHieuDonHang AS orderCode,
                        d.MaVanDon AS trackingNumber,
                        @ReturnRequestId AS returnRequestId,
                        @ReturnBranchId AS returnBranchId,
                        b.TenBuuCuc AS returnBranchName,
                        @ShipperId AS shipperId,
                        @VehicleId AS vehicleId,
                        pc.MaPhanCongGiaoHang AS assignmentId,
                        pc.TrangThaiPhanCong AS assignmentStatus,
                        pc.ThoiGianKetThuc AS assignmentEndedAt,
                        tt.KyHieuTrangThai AS orderStatus,
                        'IN_PROGRESS' AS requestStatus,
                        d.ThoiGianCapNhat AS startedAt,
                        d.PhienBan AS version,
                        N'Đã ghi nhận kiện chờ trả kho cuối ca. Bạn có thể nhận chuyến mới khi còn đủ tải.'
                            AS message
                    FROM dbo.DonHang d
                    INNER JOIN dbo.TrangThaiDonHang tt
                        ON tt.MaTrangThaiDonHang =
                           d.MaTrangThaiHienTai
                    INNER JOIN dbo.BuuCuc b
                        ON b.MaBuuCuc = @ReturnBranchId
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
                    'START_RETURN',
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
            "@ReturnRequestId", SqlDbType.BigInt).Value =
                request.ReturnRequestId;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 52301 and <= 52304)
        {
            var statusCode = ex.Number switch
            {
                52301 => StatusCodes.Status401Unauthorized,
                52302 => StatusCodes.Status403Forbidden,
                52303 => StatusCodes.Status404NotFound,
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
