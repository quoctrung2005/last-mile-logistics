using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/orders")]
public class OrderReadyForDispatchController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<OrderReadyForDispatchController> _logger;

    public OrderReadyForDispatchController(
        IConfiguration configuration,
        ILogger<OrderReadyForDispatchController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPost("{id:long}/ready-for-dispatch")]
    public async Task<IActionResult> ReadyForDispatch(
        long id,
        CancellationToken cancellationToken)
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

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Now DATETIME2(0) = SYSUTCDATETIME(),
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @AccountBranchId INT;

                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @RoleId = tk.MaVaiTro,
                    @AccountBranchId = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @AccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= @Now
                  );

                IF @Role IS NULL
                    THROW 52901,
                        N'Tài khoản đã bị khóa hoặc ngừng hoạt động.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                    INNER JOIN dbo.Quyen q WITH (HOLDLOCK)
                        ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'KHO_NHAP'
                )
                    THROW 52902,
                        N'Bạn không có quyền chuyển đơn sang chờ phân công.',
                        1;

                IF @Role <> 'ADMIN'
                   AND @AccountBranchId IS NULL
                    THROW 52902,
                        N'Tài khoản chưa được gán bưu cục.',
                        1;

                DECLARE
                    @OrderBranchId INT,
                    @CurrentWarehouseId INT,
                    @Status VARCHAR(40);

                SELECT
                    @OrderBranchId = d.MaBuuCuc,
                    @CurrentWarehouseId = d.MaKhoHienTai,
                    @Status = tt.KyHieuTrangThai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId;

                IF @Status IS NULL
                    THROW 52903, N'Không tìm thấy đơn hàng.', 1;

                IF @Role <> 'ADMIN'
                   AND @OrderBranchId <> @AccountBranchId
                    THROW 52902,
                        N'Bạn chỉ được xử lý đơn thuộc bưu cục của mình.',
                        1;

                IF @Status <> 'IN_WAREHOUSE'
                    THROW 52904,
                        N'Chỉ đơn IN_WAREHOUSE mới được chuyển sang chờ phân công.',
                        1;

                DECLARE
                    @InventoryWarehouseId INT,
                    @LocationId BIGINT,
                    @InventoryStatus VARCHAR(30);

                SELECT
                    @InventoryWarehouseId = t.MaKho,
                    @LocationId = t.MaViTriLuuKho,
                    @InventoryStatus = t.TrangThaiTonKho
                FROM dbo.TonKhoDonHang t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.MaDonHang = @OrderId;

                IF @CurrentWarehouseId IS NULL
                   OR @InventoryWarehouseId IS NULL
                   OR @CurrentWarehouseId <> @InventoryWarehouseId
                   OR @InventoryStatus IS NULL
                   OR @InventoryStatus <> 'STORED'
                   OR @LocationId IS NULL
                    THROW 52904,
                        N'Đơn không có tồn kho đang lưu hợp lệ. Hãy tải lại tồn kho.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.Kho k WITH (HOLDLOCK)
                    INNER JOIN dbo.BuuCuc bc WITH (HOLDLOCK)
                        ON bc.MaBuuCuc = k.MaBuuCuc
                    INNER JOIN dbo.ViTriLuuKho v WITH (HOLDLOCK)
                        ON v.MaKho = k.MaKho
                    WHERE k.MaKho = @CurrentWarehouseId
                      AND k.MaBuuCuc = @OrderBranchId
                      AND k.DangHoatDong = 1
                      AND bc.DangHoatDong = 1
                      AND v.MaViTriLuuKho = @LocationId
                      AND v.DangHoatDong = 1
                )
                    THROW 52904,
                        N'Kho hoặc vị trí không còn hoạt động hoặc không khớp bưu cục.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 52904,
                        N'Đơn đã có phân công đang hoạt động.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.ChiTietChuyenGiao ct WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.ChuyenGiaoHang cg WITH (HOLDLOCK)
                        ON cg.MaChuyenGiao = ct.MaChuyenGiao
                    WHERE ct.MaDonHang = @OrderId
                      AND cg.TrangThaiChuyen NOT IN (
                          'COMPLETED', 'CANCELLED'
                      )
                )
                    THROW 52904,
                        N'Đơn đang thuộc một chuyến giao chưa kết thúc.',
                        1;

                UPDATE dbo.DonHang
                SET ThoiGianSanSang = COALESCE(
                        ThoiGianSanSang, @Now
                    ),
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = @Now
                WHERE MaDonHang = @OrderId;

                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'WAITING_ASSIGNMENT',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = N'Hàng đã nhập kho, sẵn sàng phân công.',
                    @NguonCapNhat = 'API';

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
                    'ORDER_READY_FOR_DISPATCH',
                    'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    (
                        SELECT @Status AS status
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    ),
                    (
                        SELECT
                            'WAITING_ASSIGNMENT' AS status,
                            @CurrentWarehouseId AS warehouseId,
                            @LocationId AS locationId
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )
                );

                DECLARE @Result NVARCHAR(MAX);

                SELECT @Result = (
                    SELECT
                        d.MaDonHang AS orderId,
                        d.KyHieuDonHang AS orderCode,
                        d.MaVanDon AS trackingNumber,
                        d.PhienBan AS version,
                        tt.KyHieuTrangThai AS status,
                        tt.TenTrangThai AS statusName,
                        d.MaKhoHienTai AS warehouseId,
                        @LocationId AS locationId,
                        @InventoryStatus AS inventoryStatus,
                        d.ThoiGianSanSang AS readyAt,
                        N'Đơn đã chuyển sang chờ phân công.' AS message
                    FROM dbo.DonHang d
                    INNER JOIN dbo.TrangThaiDonHang tt
                        ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                    WHERE d.MaDonHang = @OrderId
                    FOR JSON PATH, INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
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

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        try
        {
            await connection.OpenAsync(cancellationToken);

            await using var command = new SqlCommand(sql, connection);

            command.Parameters.Add(
                "@AccountId", SqlDbType.BigInt
            ).Value = accountId;

            command.Parameters.Add(
                "@OrderId", SqlDbType.BigInt
            ).Value = id;

            var json = await command.ExecuteScalarAsync(
                cancellationToken) as string;

            if (string.IsNullOrWhiteSpace(json))
            {
                throw new InvalidOperationException(
                    "Không nhận được kết quả chuyển trạng thái.");
            }

            return Content(json, "application/json");
        }
        catch (SqlException ex) when (ex.Number == 52901)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52902)
        {
            return StatusCode(
                StatusCodes.Status403Forbidden,
                new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52903)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (
            ex.Number is 52904 or 51001 or 51102)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được cập nhật đồng thời. Hãy tải lại và thử lại."
            });
        }
        catch (SqlException ex) when (ex.Number == 547)
        {
            _logger.LogWarning(
                ex,
                "Đơn {OrderId} không đáp ứng ràng buộc chuyển trạng thái.",
                id);

            return Conflict(new
            {
                message = "Dữ liệu đơn chưa đáp ứng ràng buộc. Hãy kiểm tra thời gian sẵn sàng và thời gian dự kiến giao."
            });
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Không chuyển được đơn {OrderId} sang chờ phân công.",
                id);

            return StatusCode(
                StatusCodes.Status500InternalServerError,
                new
                {
                    message = "Không chuyển được đơn sang chờ phân công. Hãy kiểm tra log backend."
                });
        }
    }
}