using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using System.ComponentModel.DataAnnotations;
namespace LastMile.Api.Controllers;

public class ReadyForDispatchRequest
{
    [Required(ErrorMessage = "Phải gửi phiên bản dữ liệu của đơn.")]
    [StringLength(16)]
    public string ExpectedVersion { get; set; } = "";
}
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
     [FromBody] ReadyForDispatchRequest request,
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
        if (string.IsNullOrWhiteSpace(request.ExpectedVersion))
        {
            return BadRequest(new
            {
                message = "Phải gửi phiên bản dữ liệu của đơn."
            });
        }

        byte[] expectedVersion;

        try
        {
            expectedVersion = Convert.FromBase64String(
                request.ExpectedVersion);
        }
        catch (FormatException)
        {
            return BadRequest(new
            {
                message = "ExpectedVersion phải là Base64 hợp lệ."
            });
        }

        if (expectedVersion.Length != 8)
        {
            return BadRequest(new
            {
                message = "ExpectedVersion phải giải mã thành đúng 8 byte."
            });
        }
        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
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
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
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
                    @Status VARCHAR(40),
                    @CurrentVersion BINARY(8),
                    @OldReadyAt DATETIME2(0),
                    @RequestedDeliveryAt DATETIME2(0),
                    @ExpectedDeliveryAt DATETIME2(0);

                SELECT
                    @OrderBranchId = d.MaBuuCuc,
                    @CurrentWarehouseId = d.MaKhoHienTai,
                    @Status = tt.KyHieuTrangThai,
                    @CurrentVersion = d.PhienBan,
                    @OldReadyAt = d.ThoiGianSanSang,
                    @RequestedDeliveryAt = d.ThoiGianYeuCauGiao,
                    @ExpectedDeliveryAt = d.ThoiGianDuKienGiao
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt WITH (HOLDLOCK)
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId;

                IF @Status IS NULL
                    THROW 52903, N'Không tìm thấy đơn hàng.', 1;

                IF @Role <> 'ADMIN'
                   AND @OrderBranchId <> @AccountBranchId
                    THROW 52902,
                        N'Bạn chỉ được xử lý đơn thuộc bưu cục của mình.',
                        1;
                IF @CurrentVersion IS NULL
               OR @CurrentVersion <> @ExpectedVersion
                THROW 52906,
                    N'Đơn đã thay đổi. Hãy tải lại tồn kho và kiểm tra lịch giao trước khi chuyển sang chờ phân công.',
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

                -- Lấy giờ sau khi đã chờ và khóa các dữ liệu cần kiểm tra.
                DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

                -- Giữ mốc sẵn sàng đã được ghi nhận trước đó.
                -- Nếu chưa có, ghi nhận thời điểm thực hiện thao tác.
                DECLARE @ReadyAt DATETIME2(0) =
                    COALESCE(@OldReadyAt, @Now);

                IF @ReadyAt > @Now
                    THROW 52905,
                        N'Thời gian sẵn sàng đang nằm trong tương lai. Hãy kiểm tra lại dữ liệu thời gian của đơn.',
                        1;

                IF @RequestedDeliveryAt IS NOT NULL
                   AND @ExpectedDeliveryAt IS NOT NULL
                   AND @ExpectedDeliveryAt < @RequestedDeliveryAt
                    THROW 52905,
                        N'Hạn giao đang trước thời gian yêu cầu giao. Cần điều chỉnh kế hoạch giao trước khi chuyển trạng thái.',
                        1;

                -- Kiểm tra trước các điều kiện của CK_DonHang_DeliveryTime.
                IF @RequestedDeliveryAt IS NOT NULL
                   AND @RequestedDeliveryAt < @ReadyAt
                    THROW 52905,
                        N'Thời gian yêu cầu giao đang trước thời gian sẵn sàng của hàng. Cần điều chỉnh kế hoạch giao trước khi chuyển sang chờ phân công.',
                        1;

                IF @ExpectedDeliveryAt IS NOT NULL
                   AND @ExpectedDeliveryAt < @ReadyAt
                    THROW 52905,
                        N'Hạn giao đang trước thời gian sẵn sàng của hàng. Cần điều chỉnh kế hoạch giao trước khi chuyển sang chờ phân công.',
                        1;

                DECLARE
                    @DeadlineOverdue BIT = 0,
                    @RequestedTimePassed BIT = 0,
                    @MissingExpectedDeliveryAt BIT = 0,
                    @Warning NVARCHAR(1000);

                IF @ExpectedDeliveryAt IS NULL
                    SET @MissingExpectedDeliveryAt = 1;
                ELSE IF @ExpectedDeliveryAt <= @Now
                    SET @DeadlineOverdue = 1;

                IF @RequestedDeliveryAt IS NOT NULL
                   AND @RequestedDeliveryAt <= @Now
                    SET @RequestedTimePassed = 1;

                SET @Warning = NULLIF(
                    CONCAT(
                        CASE
                            WHEN @MissingExpectedDeliveryAt = 1
                            THEN N'Đơn chưa có hạn giao; cần bổ sung kế hoạch giao. '
                            ELSE N''
                        END,
                        CASE
                            WHEN @DeadlineOverdue = 1
                            THEN N'Đơn đã đến hoặc quá hạn giao; cần xử lý ưu tiên. '
                            ELSE N''
                        END,
                        CASE
                            WHEN @RequestedTimePassed = 1
                            THEN N'Thời gian khách yêu cầu giao đã đến hoặc đã qua. '
                            ELSE N''
                        END
                    ),
                    N''
                );

                UPDATE dbo.DonHang
                SET ThoiGianSanSang = @ReadyAt,
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
                        SELECT
                            @Status AS status,
                            CASE
                                WHEN @OldReadyAt IS NULL THEN NULL
                                ELSE CONVERT(
                                    VARCHAR(33), @OldReadyAt, 126
                                ) + 'Z'
                            END AS readyAt
                        FOR JSON PATH, INCLUDE_NULL_VALUES,
                            WITHOUT_ARRAY_WRAPPER
                    ),
                    (
                        SELECT
                            'WAITING_ASSIGNMENT' AS status,
                            @CurrentWarehouseId AS warehouseId,
                            @LocationId AS locationId,
                            CONVERT(
                                VARCHAR(33), @ReadyAt, 126
                            ) + 'Z' AS readyAt,
                            CASE
                                WHEN @RequestedDeliveryAt IS NULL THEN NULL
                                ELSE CONVERT(
                                    VARCHAR(33),
                                    @RequestedDeliveryAt,
                                    126
                                ) + 'Z'
                            END AS requestedDeliveryAt,
                            CASE
                                WHEN @ExpectedDeliveryAt IS NULL THEN NULL
                                ELSE CONVERT(
                                    VARCHAR(33),
                                    @ExpectedDeliveryAt,
                                    126
                                ) + 'Z'
                            END AS expectedDeliveryAt,
                            @DeadlineOverdue AS deadlineOverdue,
                            @RequestedTimePassed AS requestedTimePassed,
                            @MissingExpectedDeliveryAt
                                AS missingExpectedDeliveryAt,
                            @Warning AS warning
                        FOR JSON PATH, INCLUDE_NULL_VALUES,
                            WITHOUT_ARRAY_WRAPPER
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

                        CONVERT(
                            VARCHAR(33),
                            d.ThoiGianSanSang,
                            126
                        ) + 'Z' AS readyAt,

                        CASE
                            WHEN d.ThoiGianYeuCauGiao IS NULL THEN NULL
                            ELSE CONVERT(
                                VARCHAR(33),
                                d.ThoiGianYeuCauGiao,
                                126
                            ) + 'Z'
                        END AS requestedDeliveryAt,

                        CASE
                            WHEN d.ThoiGianDuKienGiao IS NULL THEN NULL
                            ELSE CONVERT(
                                VARCHAR(33),
                                d.ThoiGianDuKienGiao,
                                126
                            ) + 'Z'
                        END AS expectedDeliveryAt,

                        @DeadlineOverdue AS deadlineOverdue,
                        @RequestedTimePassed AS requestedTimePassed,
                        @MissingExpectedDeliveryAt
                            AS missingExpectedDeliveryAt,
                        @Warning AS warning,

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
             command.Parameters.Add(
                "@ExpectedVersion", SqlDbType.Binary, 8
            ).Value = expectedVersion;
            var json = await command.ExecuteScalarAsync(
                cancellationToken) as string;

            if (string.IsNullOrWhiteSpace(json))
            {
                _logger.LogError(
                    "Không nhận được kết quả chuyển đơn {OrderId} sang chờ phân công.",
                    id);

                return StatusCode(500, new
                {
                    message = "Không đọc được kết quả xử lý. Hãy tải lại chi tiết để kiểm tra trạng thái đơn."
                });
            }

            return Content(json, "application/json");
        }
        catch (SqlException ex) when (ex.Number == 52901)
        {
            return Unauthorized(new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (ex.Number == 52902)
        {
            return StatusCode(
                StatusCodes.Status403Forbidden,
                new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52903)
        {
            return NotFound(new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex)
                            when (ex.Number is 52904 or 52905 or 52906
                    or 51001 or 51102)
        {
            return Conflict(new
            {
                message = ex.Message
            });
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
                message = "Dữ liệu đơn chưa đáp ứng ràng buộc chuyển trạng thái. Hãy tải lại đơn và kiểm tra dữ liệu kho, phân công và thời gian giao."
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

            return StatusCode(500, new
            {
                message = "Không chuyển được đơn sang chờ phân công. Hãy kiểm tra log backend."
            });
        }
    }
}