using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/my/handovers")]
public class MyHandoversController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public MyHandoversController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> GetPending()
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @Now DATETIME2(0) = SYSUTCDATETIME(),
                @Role VARCHAR(50),
                @RoleId INT,
                @AccountBranchId INT,
                @ShipperId BIGINT,
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
                THROW 51611,
                    N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                    1;

            IF @Role <> 'SHIPPER'
               OR NOT EXISTS (
                   SELECT 1
                   FROM dbo.VaiTroQuyen vtq
                   INNER JOIN dbo.Quyen q
                       ON q.MaQuyen = vtq.MaQuyen
                   WHERE vtq.MaVaiTro = @RoleId
                     AND q.KyHieuQuyen = 'NHIEMVU_XEM'
               )
                THROW 51612,
                    N'API này dành cho shipper xem phiếu bàn giao của mình.',
                    1;

            SELECT @ShipperId = MaNhanVienGiaoHang
            FROM dbo.NhanVienGiaoHang
            WHERE MaTaiKhoan = @AccountId
              AND DangHoatDong = 1;

            IF @ShipperId IS NULL
                THROW 51612,
                    N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                    1;

            SET @Result = (
                SELECT
                    bg.MaBanGiao AS handoverId,
                    bg.KyHieuBanGiao AS handoverCode,
                    bg.MaKho AS warehouseId,
                    k.TenKho AS warehouseName,
                    k.MaBuuCuc AS branchId,
                    b.TenBuuCuc AS branchName,
                    bg.ThoiGianBanGiao AS handedOverAt,
                    COUNT_BIG(ct.MaDonHang) AS orderCount,
                    JSON_QUERY((
                        SELECT
                            d.MaDonHang AS orderId,
                            d.KyHieuDonHang AS orderCode,
                            d.MaVanDon AS trackingNumber
                        FROM dbo.ChiTietBanGiaoHang item
                        INNER JOIN dbo.DonHang d
                            ON d.MaDonHang = item.MaDonHang
                        WHERE item.MaBanGiao = bg.MaBanGiao
                        ORDER BY d.MaDonHang
                        FOR JSON PATH
                    )) AS items
                FROM dbo.BanGiaoHang bg
                INNER JOIN dbo.Kho k
                    ON k.MaKho = bg.MaKho
                INNER JOIN dbo.BuuCuc b
                    ON b.MaBuuCuc = k.MaBuuCuc
                INNER JOIN dbo.ChiTietBanGiaoHang ct
                    ON ct.MaBanGiao = bg.MaBanGiao
                WHERE bg.MaNhanVienGiaoHang = @ShipperId
                  AND bg.TrangThaiBanGiao = 'PENDING'
                  AND k.MaBuuCuc = @AccountBranchId
                GROUP BY
                    bg.MaBanGiao,
                    bg.KyHieuBanGiao,
                    bg.MaKho,
                    k.TenKho,
                    k.MaBuuCuc,
                    b.TenBuuCuc,
                    bg.ThoiGianBanGiao
                ORDER BY bg.ThoiGianBanGiao, bg.MaBanGiao
                FOR JSON PATH
            );

            SELECT COALESCE(@Result, N'[]');
            """;

        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = accountId;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();
            return Content(json ?? "[]", "application/json");
        }
        catch (SqlException ex) when (ex.Number is 51611 or 51612)
        {
            return StatusCode(
                ex.Number == 51611
                    ? StatusCodes.Status401Unauthorized
                    : StatusCodes.Status403Forbidden,
                new { message = ex.Message });
        }
    }

    [HttpPost("{id:long}/confirm")]
    public async Task<IActionResult> Confirm(long id)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã phiếu bàn giao không hợp lệ."
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
                    @ShipperId BIGINT,
                    @Availability VARCHAR(20),
                    @LicenseExpiry DATE,
                    @WarehouseId INT,
                    @HandoverCode VARCHAR(40),
                    @HandoverStatus VARCHAR(20),
                    @HandedOverAt DATETIME2(0),
                    @OrderId BIGINT,
                    @Reason NVARCHAR(500),
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
                    THROW 51601,
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
                    THROW 51602,
                        N'API này dành cho shipper xác nhận nhận hàng.',
                        1;

                SELECT @ShipperId = MaNhanVienGiaoHang
                FROM dbo.NhanVienGiaoHang
                WHERE MaTaiKhoan = @AccountId
                  AND DangHoatDong = 1;

                IF @ShipperId IS NULL
                    THROW 51602,
                        N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                        1;

                -- Chỉ xác nhận phiếu được lập cho chính shipper.
                SELECT
                    @WarehouseId = bg.MaKho,
                    @HandoverCode = bg.KyHieuBanGiao,
                    @HandoverStatus = bg.TrangThaiBanGiao,
                    @HandedOverAt = bg.ThoiGianBanGiao
                FROM dbo.BanGiaoHang bg WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.Kho k
                    ON k.MaKho = bg.MaKho
                WHERE bg.MaBanGiao = @HandoverId
                  AND bg.MaNhanVienGiaoHang = @ShipperId
                  AND k.MaBuuCuc = @AccountBranchId;

                IF @WarehouseId IS NULL
                    THROW 51603,
                        N'Không tìm thấy phiếu bàn giao của bạn.',
                        1;

                IF @HandoverStatus <> 'PENDING'
                    THROW 51604,
                        N'Chỉ phiếu bàn giao PENDING mới được xác nhận.',
                        1;

                IF @HandedOverAt IS NULL
                    THROW 51604,
                        N'Kho chưa ghi nhận thời gian bàn giao.',
                        1;

                -- Thu thập và khóa các đơn trong phiếu.
                SELECT
                    d.MaDonHang AS orderId,
                    d.KyHieuDonHang AS orderCode,
                    d.MaVanDon AS trackingNumber,
                    d.MaBuuCuc AS branchId,
                    tt.KyHieuTrangThai AS orderStatus,
                    pc.MaPhanCongGiaoHang AS assignmentId,
                    pc.MaPhuongTien AS vehicleId,
                    pc.TrangThaiPhanCong AS assignmentStatus,
                    CAST(0 AS BIT) AS processed
                INTO #HandoverTasks
                FROM dbo.ChiTietBanGiaoHang ct
                INNER JOIN dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                    ON d.MaDonHang = ct.MaDonHang
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang =
                       d.MaTrangThaiHienTai
                LEFT JOIN dbo.PhanCongGiaoHang pc
                    WITH (UPDLOCK, HOLDLOCK)
                    ON pc.MaDonHang = d.MaDonHang
                   AND pc.MaNhanVienGiaoHang = @ShipperId
                   AND pc.ThoiGianKetThuc IS NULL
                WHERE ct.MaBanGiao = @HandoverId;

                IF NOT EXISTS (SELECT 1 FROM #HandoverTasks)
                    THROW 51604,
                        N'Phiếu bàn giao không có đơn hàng.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM #HandoverTasks
                    WHERE orderStatus <> 'HANDED_OVER'
                       OR branchId <> @AccountBranchId
                       OR assignmentId IS NULL
                       OR assignmentStatus <> 'ACCEPTED'
                       OR vehicleId IS NULL
                )
                    THROW 51604,
                        N'Có đơn không còn HANDED_OVER hoặc phân công không còn phù hợp.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM #HandoverTasks x
                    LEFT JOIN dbo.TonKhoDonHang t
                        WITH (UPDLOCK, HOLDLOCK)
                        ON t.MaDonHang = x.orderId
                    WHERE t.MaDonHang IS NULL
                       OR t.MaKho <> @WarehouseId
                       OR t.TrangThaiTonKho <> 'HANDED_OVER'
                )
                    THROW 51604,
                        N'Dữ liệu xuất kho của phiếu không còn phù hợp.',
                        1;

                SELECT
                    @Availability = TrangThaiSanSang,
                    @LicenseExpiry = NgayHetHanBangLai
                FROM dbo.NhanVienGiaoHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaNhanVienGiaoHang = @ShipperId
                  AND MaTaiKhoan = @AccountId
                  AND DangHoatDong = 1;

                IF @Availability IS NULL
                   OR @Availability NOT IN (
                       'AVAILABLE', 'DELIVERING'
                   )
                    THROW 51604,
                        N'Shipper hiện không sẵn sàng nhận hàng.',
                        1;

                IF @LicenseExpiry IS NOT NULL
                   AND @LicenseExpiry <
                       CAST(SYSUTCDATETIME() AS DATE)
                    THROW 51604,
                        N'Bằng lái của shipper đã hết hạn.',
                        1;

                -- Khóa các phương tiện liên quan.
                SELECT
                    pt.MaPhuongTien AS vehicleId,
                    pt.DangHoatDong AS active,
                    pt.TrangThaiPhuongTien AS vehicleStatus
                INTO #HandoverVehicles
                FROM dbo.PhuongTien pt WITH (UPDLOCK, HOLDLOCK)
                WHERE EXISTS (
                    SELECT 1
                    FROM #HandoverTasks x
                    WHERE x.vehicleId = pt.MaPhuongTien
                );

                IF EXISTS (
                    SELECT 1
                    FROM #HandoverTasks x
                    LEFT JOIN #HandoverVehicles v
                        ON v.vehicleId = x.vehicleId
                    WHERE v.vehicleId IS NULL
                       OR v.active <> 1
                       OR v.vehicleStatus NOT IN (
                           'AVAILABLE', 'IN_USE'
                       )
                       OR NOT EXISTS (
                           SELECT 1
                           FROM dbo.PhanCongPhuongTien
                               WITH (UPDLOCK, HOLDLOCK)
                           WHERE MaNhanVienGiaoHang = @ShipperId
                             AND MaPhuongTien = x.vehicleId
                             AND ThoiGianKetThuc IS NULL
                       )
                )
                    THROW 51604,
                        N'Phương tiện không còn hoạt động hoặc không còn được phân cho bạn.',
                        1;

                SET @OldJson = (
                    SELECT
                        @HandoverId AS handoverId,
                        @HandoverStatus AS handoverStatus,
                        JSON_QUERY((
                            SELECT
                                orderId,
                                assignmentId,
                                orderStatus,
                                assignmentStatus
                            FROM #HandoverTasks
                            ORDER BY orderId
                            FOR JSON PATH
                        )) AS items
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                SET @Now = SYSUTCDATETIME();

                IF @Now < @HandedOverAt
                    THROW 51604,
                        N'Thời gian hệ thống đang trước thời gian bàn giao. Cần kiểm tra đồng hồ máy chủ.',
                        1;

                UPDATE pc
                SET TrangThaiPhanCong = 'IN_PROGRESS'
                FROM dbo.PhanCongGiaoHang pc
                INNER JOIN #HandoverTasks x
                    ON x.assignmentId = pc.MaPhanCongGiaoHang;

                -- Chuyển từng đơn qua procedure để ghi lịch sử.
                SET @Reason =
                    N'Shipper xác nhận nhận hàng theo phiếu '
                    + @HandoverCode;

                WHILE EXISTS (
                    SELECT 1
                    FROM #HandoverTasks
                    WHERE processed = 0
                )
                BEGIN
                    SELECT TOP (1) @OrderId = orderId
                    FROM #HandoverTasks
                    WHERE processed = 0
                    ORDER BY orderId;

                    EXEC dbo.sp_ChuyenTrangThaiDonHang
                        @MaDonHang = @OrderId,
                        @KyHieuTrangThaiMoi = 'PICKED_UP',
                        @MaTaiKhoan = @AccountId,
                        @LyDo = @Reason,
                        @NguonCapNhat = 'API';

                    UPDATE #HandoverTasks
                    SET processed = 1
                    WHERE orderId = @OrderId;
                END;

                UPDATE dbo.BanGiaoHang
                SET TrangThaiBanGiao = 'CONFIRMED',
                    ThoiGianNhanVienXacNhan = @Now
                WHERE MaBanGiao = @HandoverId;

                UPDATE dbo.NhanVienGiaoHang
                SET TrangThaiSanSang = 'DELIVERING'
                WHERE MaNhanVienGiaoHang = @ShipperId;

                UPDATE pt
                SET TrangThaiPhuongTien = 'IN_USE'
                FROM dbo.PhuongTien pt
                INNER JOIN #HandoverVehicles v
                    ON v.vehicleId = pt.MaPhuongTien;

                SET @Result = (
                    SELECT
                        @HandoverId AS handoverId,
                        @HandoverCode AS handoverCode,
                        @ShipperId AS shipperId,
                        'CONFIRMED' AS handoverStatus,
                        @Now AS confirmedAt,
                        (
                            SELECT COUNT_BIG(*)
                            FROM #HandoverTasks
                        ) AS orderCount,
                        JSON_QUERY((
                            SELECT
                                x.orderId,
                                x.orderCode,
                                x.trackingNumber,
                                x.assignmentId,
                                x.vehicleId,
                                'IN_PROGRESS' AS assignmentStatus,
                                'PICKED_UP' AS orderStatus,
                                d.PhienBan AS version
                            FROM #HandoverTasks x
                            INNER JOIN dbo.DonHang d
                                ON d.MaDonHang = x.orderId
                            ORDER BY x.orderId
                            FOR JSON PATH
                        )) AS items,
                        N'Đã xác nhận nhận hàng từ kho.'
                            AS message
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
                    'CONFIRM_HANDOVER',
                    'BanGiaoHang',
                    CONVERT(VARCHAR(100), @HandoverId),
                    @OldJson,
                    @Result
                );

                DROP TABLE #HandoverVehicles;
                DROP TABLE #HandoverTasks;

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
            "@HandoverId", SqlDbType.BigInt).Value = id;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 51601 and <= 51604)
        {
            var statusCode = ex.Number switch
            {
                51601 => StatusCodes.Status401Unauthorized,
                51602 => StatusCodes.Status403Forbidden,
                51603 => StatusCodes.Status404NotFound,
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
                    "Có thao tác đồng thời. Hãy tải lại phiếu bàn giao và thử lại."
            });
        }
    }
    [HttpPost("/api/v1/my/tasks/{id:long}/start-delivery")]
    public async Task<IActionResult> StartDelivery(long id)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã nhiệm vụ không hợp lệ."
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
                @ShipperId BIGINT,
                @Availability VARCHAR(20),
                @LicenseExpiry DATE,
                @OrderId BIGINT,
                @OrderStatus VARCHAR(40),
                @AssignmentStatus VARCHAR(20),
                @AssignedAt DATETIME2(0),
                @EndedAt DATETIME2(0),
                @VehicleId BIGINT,
                @TripId BIGINT,
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
                THROW 51701,
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
                THROW 51702,
                    N'API này dành cho shipper bắt đầu giao nhiệm vụ của mình.',
                    1;

            SELECT @ShipperId = MaNhanVienGiaoHang
            FROM dbo.NhanVienGiaoHang
            WHERE MaTaiKhoan = @AccountId
              AND DangHoatDong = 1;

            IF @ShipperId IS NULL
                THROW 51702,
                    N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                    1;

            SELECT @OrderId = MaDonHang
            FROM dbo.PhanCongGiaoHang
            WHERE MaPhanCongGiaoHang = @AssignmentId
              AND MaNhanVienGiaoHang = @ShipperId;

            IF @OrderId IS NULL
                THROW 51703,
                    N'Không tìm thấy nhiệm vụ của bạn.',
                    1;

            SELECT @OrderStatus = tt.KyHieuTrangThai
            FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            WHERE d.MaDonHang = @OrderId
              AND d.MaBuuCuc = @AccountBranchId;

            IF @OrderStatus IS NULL
                THROW 51703,
                    N'Không tìm thấy nhiệm vụ trong bưu cục của bạn.',
                    1;

            SELECT
                @AssignmentStatus = pc.TrangThaiPhanCong,
                @AssignedAt = pc.ThoiGianPhanCong,
                @EndedAt = pc.ThoiGianKetThuc,
                @VehicleId = pc.MaPhuongTien,
                @TripId = pc.MaChuyenGiao
            FROM dbo.PhanCongGiaoHang pc
                WITH (UPDLOCK, HOLDLOCK)
            WHERE pc.MaPhanCongGiaoHang = @AssignmentId
              AND pc.MaDonHang = @OrderId
              AND pc.MaNhanVienGiaoHang = @ShipperId;

            IF @AssignmentStatus IS NULL
                THROW 51703,
                    N'Không tìm thấy nhiệm vụ của bạn.',
                    1;

            IF @EndedAt IS NOT NULL
               OR @AssignmentStatus <> 'IN_PROGRESS'
                THROW 51704,
                    N'Phân công phải còn hoạt động và ở trạng thái IN_PROGRESS.',
                    1;

            IF @OrderStatus <> 'PICKED_UP'
                THROW 51704,
                    N'Chỉ đơn PICKED_UP mới được bắt đầu giao.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.ChiTietBanGiaoHang ct
                INNER JOIN dbo.BanGiaoHang bg
                    ON bg.MaBanGiao = ct.MaBanGiao
                WHERE ct.MaDonHang = @OrderId
                  AND bg.MaNhanVienGiaoHang = @ShipperId
                  AND bg.TrangThaiBanGiao = 'CONFIRMED'
                  AND bg.ThoiGianNhanVienXacNhan >= @AssignedAt
            )
                THROW 51704,
                    N'Bạn chưa xác nhận nhận hàng theo phiếu bàn giao của lần phân công này.',
                    1;

            SELECT
                @Availability = TrangThaiSanSang,
                @LicenseExpiry = NgayHetHanBangLai
            FROM dbo.NhanVienGiaoHang WITH (UPDLOCK, HOLDLOCK)
            WHERE MaNhanVienGiaoHang = @ShipperId
              AND MaTaiKhoan = @AccountId
              AND DangHoatDong = 1;

            IF @Availability IS NULL
               OR @Availability NOT IN ('AVAILABLE', 'DELIVERING')
                THROW 51704,
                    N'Shipper hiện không sẵn sàng giao hàng.',
                    1;

            IF @LicenseExpiry IS NOT NULL
               AND @LicenseExpiry < CAST(SYSUTCDATETIME() AS DATE)
                THROW 51704,
                    N'Bằng lái của shipper đã hết hạn.',
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
                THROW 51704,
                    N'Phương tiện không còn phù hợp để giao hàng.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.PhanCongPhuongTien
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE MaNhanVienGiaoHang = @ShipperId
                  AND MaPhuongTien = @VehicleId
                  AND ThoiGianKetThuc IS NULL
            )
                THROW 51704,
                    N'Phương tiện không còn được phân cho bạn.',
                    1;

            IF @TripId IS NOT NULL
               AND NOT EXISTS (
                   SELECT 1
                   FROM dbo.ChuyenGiaoHang
                   WHERE MaChuyenGiao = @TripId
                     AND MaNhanVienGiaoHang = @ShipperId
                     AND MaPhuongTien = @VehicleId
                     AND TrangThaiChuyen = 'IN_PROGRESS'
               )
                THROW 51704,
                    N'Chuyến giao phải được bắt đầu trước khi giao đơn.',
                    1;

            SET @OldJson = (
                SELECT
                    @AssignmentId AS assignmentId,
                    @OrderId AS orderId,
                    @OrderStatus AS orderStatus
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            EXEC dbo.sp_ChuyenTrangThaiDonHang
                @MaDonHang = @OrderId,
                @KyHieuTrangThaiMoi = 'IN_DELIVERY',
                @MaTaiKhoan = @AccountId,
                @LyDo = N'Shipper bắt đầu giao hàng.',
                @NguonCapNhat = 'API';

            UPDATE dbo.NhanVienGiaoHang
            SET TrangThaiSanSang = 'DELIVERING'
            WHERE MaNhanVienGiaoHang = @ShipperId;

            UPDATE dbo.PhuongTien
            SET TrangThaiPhuongTien = 'IN_USE'
            WHERE MaPhuongTien = @VehicleId;

            SET @Result = (
                SELECT
                    pc.MaPhanCongGiaoHang AS id,
                    d.MaDonHang AS orderId,
                    d.KyHieuDonHang AS orderCode,
                    d.MaVanDon AS trackingNumber,
                    pc.MaNhanVienGiaoHang AS shipperId,
                    pc.MaPhuongTien AS vehicleId,
                    pc.TrangThaiPhanCong AS assignmentStatus,
                    tt.KyHieuTrangThai AS orderStatus,
                    d.ThoiGianCapNhat AS startedAt,
                    d.PhienBan AS version,
                    N'Đã bắt đầu giao hàng.' AS message
                FROM dbo.PhanCongGiaoHang pc
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = pc.MaDonHang
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE pc.MaPhanCongGiaoHang = @AssignmentId
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
                'START_DELIVERY',
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
            "@AssignmentId", SqlDbType.BigInt).Value = id;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 51701 and <= 51704)
        {
            var statusCode = ex.Number switch
            {
                51701 => StatusCodes.Status401Unauthorized,
                51702 => StatusCodes.Status403Forbidden,
                51703 => StatusCodes.Status404NotFound,
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
                    "Có thao tác đồng thời. Hãy tải lại nhiệm vụ và thử lại."
            });
        }
    }
}
