using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using System.ComponentModel.DataAnnotations;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/my/tasks")]
public class MyTasksController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public MyTasksController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{id:long}/accept")]
    public async Task<IActionResult> Accept(long id)
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
                    @EndedAt DATETIME2(0),
                    @VehicleId BIGINT,
                    @OldJson NVARCHAR(MAX),
                    @NewJson NVARCHAR(MAX),
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
                    THROW 51401,
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
                    THROW 51402,
                        N'API này dành cho shipper nhận nhiệm vụ của mình.',
                        1;

                SELECT @ShipperId = MaNhanVienGiaoHang
                FROM dbo.NhanVienGiaoHang
                WHERE MaTaiKhoan = @AccountId
                  AND DangHoatDong = 1;

                IF @ShipperId IS NULL
                    THROW 51402,
                        N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                        1;

                -- Chỉ tìm nhiệm vụ được phân cho người đăng nhập.
                SELECT @OrderId = MaDonHang
                FROM dbo.PhanCongGiaoHang
                WHERE MaPhanCongGiaoHang = @AssignmentId
                  AND MaNhanVienGiaoHang = @ShipperId;

                IF @OrderId IS NULL
                    THROW 51403,
                        N'Không tìm thấy nhiệm vụ của bạn.',
                        1;

                -- Khóa theo thứ tự: đơn, phân công, shipper, xe.
                SELECT @OrderStatus = tt.KyHieuTrangThai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang =
                       d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND d.MaBuuCuc = @AccountBranchId;

                IF @OrderStatus IS NULL
                    THROW 51403,
                        N'Không tìm thấy nhiệm vụ trong bưu cục của bạn.',
                        1;

                SELECT
                    @AssignmentStatus = pc.TrangThaiPhanCong,
                    @EndedAt = pc.ThoiGianKetThuc,
                    @VehicleId = pc.MaPhuongTien
                FROM dbo.PhanCongGiaoHang pc
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                  AND pc.MaDonHang = @OrderId
                  AND pc.MaNhanVienGiaoHang = @ShipperId;

                IF @AssignmentStatus IS NULL
                    THROW 51403,
                        N'Không tìm thấy nhiệm vụ của bạn.',
                        1;

                IF @EndedAt IS NOT NULL
                    THROW 51404,
                        N'Phân công đã kết thúc hoặc đã bị hủy.',
                        1;

                IF @AssignmentStatus <> 'PENDING'
                    THROW 51404,
                        N'Chỉ nhiệm vụ PENDING mới được nhận.',
                        1;

                IF @OrderStatus <> 'ASSIGNED'
                    THROW 51404,
                        N'Đơn không còn ở trạng thái ASSIGNED.',
                        1;

                SELECT
                    @Availability = nv.TrangThaiSanSang,
                    @LicenseExpiry = nv.NgayHetHanBangLai
                FROM dbo.NhanVienGiaoHang nv
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE nv.MaNhanVienGiaoHang = @ShipperId
                  AND nv.MaTaiKhoan = @AccountId
                  AND nv.DangHoatDong = 1;

                IF @Availability IS NULL
                   OR @Availability NOT IN (
                       'AVAILABLE', 'DELIVERING'
                   )
                    THROW 51404,
                        N'Bạn cần ở trạng thái sẵn sàng hoặc đang giao để nhận nhiệm vụ.',
                        1;

                IF @LicenseExpiry IS NOT NULL
                   AND @LicenseExpiry <
                       CAST(SYSUTCDATETIME() AS DATE)
                    THROW 51404,
                        N'Bằng lái đã hết hạn.',
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
                    THROW 51404,
                        N'Phương tiện của nhiệm vụ không còn phù hợp.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongPhuongTien
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaNhanVienGiaoHang = @ShipperId
                      AND MaPhuongTien = @VehicleId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 51404,
                        N'Phương tiện hiện không còn được phân cho bạn.',
                        1;

                SET @OldJson = (
                    SELECT
                        @AssignmentId AS assignmentId,
                        @OrderId AS orderId,
                        @ShipperId AS shipperId,
                        @AssignmentStatus AS assignmentStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                SET @Now = SYSUTCDATETIME();

                UPDATE dbo.PhanCongGiaoHang
                SET TrangThaiPhanCong = 'ACCEPTED',
                    ThoiGianChapNhan = @Now
                WHERE MaPhanCongGiaoHang = @AssignmentId;

                UPDATE dbo.DonHang
                SET MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = @Now
                WHERE MaDonHang = @OrderId;

                SET @NewJson = (
                    SELECT
                        @AssignmentId AS assignmentId,
                        @OrderId AS orderId,
                        @ShipperId AS shipperId,
                        'ACCEPTED' AS assignmentStatus,
                        @Now AS acceptedAt
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
                    'ACCEPT_ASSIGNMENT',
                    'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    @OldJson,
                    @NewJson
                );

                SET @Result = (
                    SELECT
                        pc.MaPhanCongGiaoHang AS id,
                        d.MaDonHang AS orderId,
                        d.KyHieuDonHang AS orderCode,
                        d.MaVanDon AS trackingNumber,
                        pc.MaNhanVienGiaoHang AS shipperId,
                        pc.MaPhuongTien AS vehicleId,
                        pc.TrangThaiPhanCong AS assignmentStatus,
                        @OrderStatus AS orderStatus,
                        pc.ThoiGianChapNhan AS acceptedAt,
                        d.PhienBan AS version,
                        N'Đã nhận nhiệm vụ. Chờ bàn giao hàng.'
                            AS message
                    FROM dbo.PhanCongGiaoHang pc
                    INNER JOIN dbo.DonHang d
                        ON d.MaDonHang = pc.MaDonHang
                    WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
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
            ex.Number is >= 51401 and <= 51404)
        {
            var statusCode = ex.Number switch
            {
                51401 => StatusCodes.Status401Unauthorized,
                51402 => StatusCodes.Status403Forbidden,
                51403 => StatusCodes.Status404NotFound,
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
    [HttpPost("{id:long}/start-retry")]
    public async Task<IActionResult> StartRetry(long id)
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
                @OrderId BIGINT,
                @OrderStatus VARCHAR(40),
                @AssignmentStatus VARCHAR(20),
                @EndedAt DATETIME2(0),
                @VehicleId BIGINT,
                @RequestId BIGINT,
                @RetryAt DATETIME2(0),
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
                THROW 52101,
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
                THROW 52102,
                    N'API này dành cho shipper bắt đầu giao lại.',
                    1;

            SELECT @ShipperId = MaNhanVienGiaoHang
            FROM dbo.NhanVienGiaoHang
            WHERE MaTaiKhoan = @AccountId
              AND DangHoatDong = 1;

            IF @ShipperId IS NULL
                THROW 52102,
                    N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                    1;

            SELECT @OrderId = MaDonHang
            FROM dbo.PhanCongGiaoHang
            WHERE MaPhanCongGiaoHang = @AssignmentId
              AND MaNhanVienGiaoHang = @ShipperId;

            IF @OrderId IS NULL
                THROW 52103,
                    N'Không tìm thấy nhiệm vụ của bạn.',
                    1;

            SELECT @OrderStatus = tt.KyHieuTrangThai
            FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            WHERE d.MaDonHang = @OrderId
              AND d.MaBuuCuc = @AccountBranchId;

            IF @OrderStatus IS NULL
                THROW 52103,
                    N'Không tìm thấy nhiệm vụ trong bưu cục của bạn.',
                    1;

            IF @OrderStatus <> 'RETRY_WAITING'
                THROW 52104,
                    N'Chỉ đơn RETRY_WAITING mới được bắt đầu giao lại.',
                    1;

            SELECT
                @AssignmentStatus = TrangThaiPhanCong,
                @EndedAt = ThoiGianKetThuc,
                @VehicleId = MaPhuongTien
            FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
            WHERE MaPhanCongGiaoHang = @AssignmentId
              AND MaDonHang = @OrderId
              AND MaNhanVienGiaoHang = @ShipperId;

            IF @AssignmentStatus IS NULL
               OR @AssignmentStatus <> 'IN_PROGRESS'
               OR @EndedAt IS NOT NULL
                THROW 52104,
                    N'Phân công không còn IN_PROGRESS hoặc đã kết thúc.',
                    1;

            SELECT TOP (1)
                @RequestId = MaYeuCauGiaoLaiHoacHoan
            FROM dbo.YeuCauGiaoLaiHoacHoan
                WITH (UPDLOCK, HOLDLOCK)
            WHERE MaDonHang = @OrderId
              AND LoaiYeuCau = 'RETRY'
              AND TrangThaiYeuCau = 'APPROVED'
            ORDER BY MaYeuCauGiaoLaiHoacHoan DESC;

            IF @RequestId IS NULL
                THROW 52104,
                    N'Không có yêu cầu giao lại đã được duyệt.',
                    1;

            SELECT TOP (1)
                @RetryAt = ThoiGianGiaoLaiDuKien
            FROM dbo.LanGiaoHang WITH (UPDLOCK, HOLDLOCK)
            WHERE MaDonHang = @OrderId
              AND MaPhanCongGiaoHang = @AssignmentId
              AND KetQua = 'FAILED'
            ORDER BY SoLanThu DESC;

            IF @RetryAt IS NULL
                THROW 52104,
                    N'Chưa có lịch giao lại hợp lệ.',
                    1;

            SET @Now = SYSUTCDATETIME();

            IF @Now < @RetryAt
                THROW 52104,
                    N'Chưa đến thời gian giao lại đã hẹn.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.NhanVienGiaoHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaNhanVienGiaoHang = @ShipperId
                  AND MaTaiKhoan = @AccountId
                  AND DangHoatDong = 1
                  AND TrangThaiSanSang IN (
                      'AVAILABLE', 'DELIVERING'
                  )
                  AND (
                      NgayHetHanBangLai IS NULL
                      OR NgayHetHanBangLai >= CAST(@Now AS DATE)
                  )
            )
                THROW 52104,
                    N'Shipper hiện không đủ điều kiện giao lại.',
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
                THROW 52104,
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
                THROW 52104,
                    N'Phương tiện không còn được phân cho bạn.',
                    1;

            SET @OldJson = (
                SELECT
                    @OrderId AS orderId,
                    @RequestId AS retryRequestId,
                    'RETRY_WAITING' AS orderStatus,
                    'APPROVED' AS requestStatus,
                    @RetryAt AS retryAt
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            UPDATE dbo.YeuCauGiaoLaiHoacHoan
            SET TrangThaiYeuCau = 'IN_PROGRESS'
            WHERE MaYeuCauGiaoLaiHoacHoan = @RequestId;

            EXEC dbo.sp_ChuyenTrangThaiDonHang
                @MaDonHang = @OrderId,
                @KyHieuTrangThaiMoi = 'IN_DELIVERY',
                @MaTaiKhoan = @AccountId,
                @LyDo = N'Shipper bắt đầu lần giao lại theo lịch.',
                @NguonCapNhat = 'API';

            UPDATE dbo.NhanVienGiaoHang
            SET TrangThaiSanSang = 'DELIVERING'
            WHERE MaNhanVienGiaoHang = @ShipperId;

            UPDATE dbo.PhuongTien
            SET TrangThaiPhuongTien = 'IN_USE'
            WHERE MaPhuongTien = @VehicleId;

            SET @Result = (
                SELECT
                    d.MaDonHang AS orderId,
                    d.KyHieuDonHang AS orderCode,
                    d.MaVanDon AS trackingNumber,
                    @AssignmentId AS assignmentId,
                    @RequestId AS retryRequestId,
                    @ShipperId AS shipperId,
                    @VehicleId AS vehicleId,
                    tt.KyHieuTrangThai AS orderStatus,
                    'IN_PROGRESS' AS requestStatus,
                    @RetryAt AS retryAt,
                    d.ThoiGianCapNhat AS startedAt,
                    d.PhienBan AS version,
                    N'Đã bắt đầu lần giao lại.' AS message
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
                'START_RETRY',
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
            ex.Number is >= 52101 and <= 52104)
        {
            var statusCode = ex.Number switch
            {
                52101 => StatusCodes.Status401Unauthorized,
                52102 => StatusCodes.Status403Forbidden,
                52103 => StatusCodes.Status404NotFound,
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
    [HttpGet]
    public async Task<IActionResult> GetTasks(
    [FromQuery, StringLength(100)] string? keyword = null,
    [FromQuery, StringLength(20)] string? assignmentStatus = null,
    [FromQuery] bool activeOnly = true,
    [FromQuery, Range(1, 100000)] int page = 1,
    [FromQuery, Range(1, 100)] int pageSize = 10)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        keyword = string.IsNullOrWhiteSpace(keyword)
            ? null
            : keyword.Trim();

        assignmentStatus = string.IsNullOrWhiteSpace(assignmentStatus)
            ? null
            : assignmentStatus.Trim().ToUpperInvariant();

        string[] allowedStatuses =
        [
            "PENDING",
        "ACCEPTED",
        "IN_PROGRESS",
        "COMPLETED",
        "ATTEMPT_FAILED",
        "REJECTED",
        "CANCELLED",
        "REASSIGNED"
        ];

        if (assignmentStatus is not null
            && !allowedStatuses.Contains(assignmentStatus))
        {
            return BadRequest(new
            {
                message = "Trạng thái phân công không hợp lệ.",
                allowedStatuses
            });
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
            @ShipperId BIGINT;

        SELECT
            @Role = vt.KyHieuVaiTro,
            @RoleId = tk.MaVaiTro
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
            THROW 52601,
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
            THROW 52602,
                N'API này dành cho shipper xem nhiệm vụ của mình.',
                1;

        SELECT @ShipperId = MaNhanVienGiaoHang
        FROM dbo.NhanVienGiaoHang
        WHERE MaTaiKhoan = @AccountId
          AND DangHoatDong = 1;

        IF @ShipperId IS NULL
            THROW 52602,
                N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                1;

        SELECT
            pc.MaPhanCongGiaoHang AS id,
            d.MaDonHang AS orderId,
            d.KyHieuDonHang AS orderCode,
            d.MaVanDon AS trackingNumber,
            d.MaBuuCuc AS branchId,
            b.TenBuuCuc AS branchName,
            tt.KyHieuTrangThai AS orderStatus,
            tt.TenTrangThai AS orderStatusName,
            pc.TrangThaiPhanCong AS assignmentStatus,
            pc.MaChuyenGiao AS tripId,
            pc.MaPhuongTien AS vehicleId,
            pt.BienSo AS licensePlate,
            pc.ThoiGianPhanCong AS assignedAt,
            pc.ThoiGianChapNhan AS acceptedAt,
            pc.ThoiGianKetThuc AS endedAt,
            CAST(
                CASE WHEN pc.ThoiGianKetThuc IS NULL
                     THEN 1 ELSE 0 END
                AS BIT
            ) AS isAssignmentActive,
            duty.isCurrentTask,
            d.MucDoUuTien AS priority,
            d.TongKhoiLuongKg AS weightKg,
            d.TienCOD AS codAmount,
            d.ThoiGianDuKienGiao AS expectedDeliveryAt,
            d.GhiChuDacBiet AS notes,
            gn.TenNguoiLienHe AS receiverName,
            gn.SoDienThoaiLienHe AS receiverPhone,
            gn.DiaChi AS deliveryAddress,
            gn.ViDo AS latitude,
            gn.KinhDo AS longitude,
            retry.ThoiGianGiaoLaiDuKien AS retryAt,
            ret.MaYeuCauGiaoLaiHoacHoan AS returnRequestId,
            ret.MaBuuCucHoan AS returnBranchId,
            ret.TrangThaiYeuCau AS returnRequestStatus
        INTO #MyTasks
        FROM dbo.PhanCongGiaoHang pc
        INNER JOIN dbo.DonHang d
            ON d.MaDonHang = pc.MaDonHang
        INNER JOIN dbo.BuuCuc b
            ON b.MaBuuCuc = d.MaBuuCuc
        INNER JOIN dbo.TrangThaiDonHang tt
            ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
        LEFT JOIN dbo.PhuongTien pt
            ON pt.MaPhuongTien = pc.MaPhuongTien
        LEFT JOIN dbo.DiemGiaoNhan gn
            ON gn.MaDonHang = d.MaDonHang
           AND gn.LoaiDiem = 'DELIVERY'
        OUTER APPLY (
            SELECT TOP (1)
                lg.ThoiGianGiaoLaiDuKien
            FROM dbo.LanGiaoHang lg
            WHERE lg.MaDonHang = d.MaDonHang
              AND lg.MaPhanCongGiaoHang =
                  pc.MaPhanCongGiaoHang
              AND lg.KetQua = 'FAILED'
            ORDER BY lg.SoLanThu DESC
        ) retry
        OUTER APPLY (
            SELECT TOP (1)
                yc.MaYeuCauGiaoLaiHoacHoan,
                yc.MaBuuCucHoan,
                yc.TrangThaiYeuCau
            FROM dbo.YeuCauGiaoLaiHoacHoan yc
            WHERE yc.MaDonHang = d.MaDonHang
              AND yc.LoaiYeuCau = 'RETURN'
              AND yc.TrangThaiYeuCau IN (
                  'PENDING', 'APPROVED', 'IN_PROGRESS'
              )
            ORDER BY yc.MaYeuCauGiaoLaiHoacHoan DESC
        ) ret
        CROSS APPLY (
            SELECT CAST(
                CASE
                    WHEN pc.ThoiGianKetThuc IS NULL THEN 1
                    WHEN tt.KyHieuTrangThai = 'RETURNING'
                     AND ret.TrangThaiYeuCau = 'IN_PROGRESS'
                     AND pc.TrangThaiPhanCong = 'ATTEMPT_FAILED'
                     AND NOT EXISTS (
                         SELECT 1
                         FROM dbo.PhanCongGiaoHang newer
                         WHERE newer.MaDonHang = pc.MaDonHang
                           AND newer.MaPhanCongGiaoHang >
                               pc.MaPhanCongGiaoHang
                     )
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS isCurrentTask
        ) duty
        WHERE pc.MaNhanVienGiaoHang = @ShipperId
          AND (
              @ActiveOnly = 0
              OR duty.isCurrentTask = 1
          )
          AND (
              @AssignmentStatus IS NULL
              OR pc.TrangThaiPhanCong = @AssignmentStatus
          )
          AND (
              @Keyword IS NULL
              OR CHARINDEX(@Keyword, d.KyHieuDonHang) > 0
              OR CHARINDEX(@Keyword, d.MaVanDon) > 0
              OR CHARINDEX(@Keyword, gn.TenNguoiLienHe) > 0
              OR CHARINDEX(@Keyword, gn.SoDienThoaiLienHe) > 0
          );

        SELECT (
            SELECT
                @ShipperId AS shipperId,
                @Page AS page,
                @PageSize AS pageSize,
                (
                    SELECT COUNT_BIG(*)
                    FROM #MyTasks
                ) AS totalItems,
                JSON_QUERY((
                    SELECT *
                    FROM #MyTasks
                    ORDER BY
                        isCurrentTask DESC,
                        assignedAt DESC,
                        id DESC
                    OFFSET @Offset ROWS
                    FETCH NEXT @PageSize ROWS ONLY
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                )) AS items
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        DROP TABLE #MyTasks;
        """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;

        command.Parameters.Add(
            "@AssignmentStatus", SqlDbType.VarChar, 20).Value =
                (object?)assignmentStatus ?? DBNull.Value;

        command.Parameters.Add(
            "@ActiveOnly", SqlDbType.Bit).Value = activeOnly;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value = pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.Int).Value = (page - 1) * pageSize;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is 52601 or 52602)
        {
            return StatusCode(
                ex.Number == 52601
                    ? StatusCodes.Status401Unauthorized
                    : StatusCodes.Status403Forbidden,
                new { message = ex.Message });
        }
    }
    [HttpGet("{id:long}")]
    public async Task<IActionResult> GetTask(long id)
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

        DECLARE
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Role VARCHAR(50),
            @RoleId INT,
            @ShipperId BIGINT,
            @OrderId BIGINT;

        SELECT
            @Role = vt.KyHieuVaiTro,
            @RoleId = tk.MaVaiTro
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
            THROW 52701,
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
            THROW 52702,
                N'API này dành cho shipper xem nhiệm vụ của mình.',
                1;

        SELECT @ShipperId = MaNhanVienGiaoHang
        FROM dbo.NhanVienGiaoHang
        WHERE MaTaiKhoan = @AccountId
          AND DangHoatDong = 1;

        IF @ShipperId IS NULL
            THROW 52702,
                N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                1;

        SELECT @OrderId = MaDonHang
        FROM dbo.PhanCongGiaoHang
        WHERE MaPhanCongGiaoHang = @AssignmentId
          AND MaNhanVienGiaoHang = @ShipperId;

        IF @OrderId IS NULL
            THROW 52703,
                N'Không tìm thấy nhiệm vụ của bạn.',
                1;

        SELECT (
            SELECT
                pc.MaPhanCongGiaoHang AS id,
                d.MaDonHang AS orderId,
                d.PhienBan AS version,
                d.KyHieuDonHang AS orderCode,
                d.MaVanDon AS trackingNumber,
                d.MaBuuCuc AS branchId,
                b.TenBuuCuc AS branchName,
                pc.MaNhanVienGiaoHang AS shipperId,
                pc.MaPhuongTien AS vehicleId,
                pt.BienSo AS licensePlate,
                pc.MaChuyenGiao AS tripId,
                pc.TrangThaiPhanCong AS assignmentStatus,
                tt.KyHieuTrangThai AS orderStatus,
                tt.TenTrangThai AS orderStatusName,
                pc.ThoiGianPhanCong AS assignedAt,
                pc.ThoiGianChapNhan AS acceptedAt,
                pc.ThoiGianKetThuc AS endedAt,
                CAST(
                    CASE WHEN pc.ThoiGianKetThuc IS NULL
                         THEN 1 ELSE 0 END
                    AS BIT
                ) AS isAssignmentActive,
                CAST(
                    CASE
                        WHEN pc.ThoiGianKetThuc IS NULL THEN 1
                        WHEN tt.KyHieuTrangThai = 'RETURNING'
                         AND pc.TrangThaiPhanCong = 'ATTEMPT_FAILED'
                         AND EXISTS (
                             SELECT 1
                             FROM dbo.YeuCauGiaoLaiHoacHoan yc
                             WHERE yc.MaDonHang = d.MaDonHang
                               AND yc.LoaiYeuCau = 'RETURN'
                               AND yc.TrangThaiYeuCau = 'IN_PROGRESS'
                         )
                         AND NOT EXISTS (
                             SELECT 1
                             FROM dbo.PhanCongGiaoHang newer
                             WHERE newer.MaDonHang = d.MaDonHang
                               AND newer.MaPhanCongGiaoHang >
                                   pc.MaPhanCongGiaoHang
                         )
                        THEN 1
                        ELSE 0
                    END
                    AS BIT
                ) AS isCurrentTask,
                d.MucDoUuTien AS priority,
                d.TongKhoiLuongKg AS weightKg,
                d.TienCOD AS codAmount,
                d.PhiVanChuyen AS shippingFee,
                d.ThoiGianDuKienGiao AS expectedDeliveryAt,
                d.GhiChuDacBiet AS notes,

                JSON_QUERY((
                    SELECT
                        gn.MaDiemGiaoNhan AS id,
                        gn.LoaiDiem AS type,
                        gn.TenNguoiLienHe AS contactName,
                        gn.SoDienThoaiLienHe AS phone,
                        gn.DiaChi AS address,
                        gn.MaKhuVuc AS areaId,
                        gn.ViDo AS latitude,
                        gn.KinhDo AS longitude,
                        gn.GhiChu AS notes
                    FROM dbo.DiemGiaoNhan gn
                    WHERE gn.MaDonHang = d.MaDonHang
                    ORDER BY
                        CASE WHEN gn.LoaiDiem = 'PICKUP'
                             THEN 0 ELSE 1 END
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                )) AS deliveryPoints,

                JSON_QUERY((
                    SELECT
                        ct.MaChiTietDonHang AS id,
                        ct.TenHang AS name,
                        ct.LoaiHang AS type,
                        ct.SoLuong AS quantity,
                        ct.KhoiLuongDonViKg AS unitWeightKg,
                        ct.ChieuDaiCm AS lengthCm,
                        ct.ChieuRongCm AS widthCm,
                        ct.ChieuCaoCm AS heightCm,
                        ct.GiaTriHang AS value,
                        ct.HangDeVo AS fragile,
                        ct.GhiChu AS notes
                    FROM dbo.ChiTietDonHang ct
                    WHERE ct.MaDonHang = d.MaDonHang
                    ORDER BY ct.MaChiTietDonHang
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                )) AS items,

                JSON_QUERY((
                    SELECT
                        lg.MaLanGiaoHang AS id,
                        lg.SoLanThu AS attemptNumber,
                        lg.KetQua AS result,
                        lg.ThoiGianThuGiao AS attemptedAt,
                        lg.MaLyDoGiaoThatBai AS reasonId,
                        ld.TenLyDo AS reasonName,
                        lg.GhiChu AS notes,
                        lg.ThoiGianGiaoLaiDuKien AS retryAt,
                        JSON_QUERY((
                            SELECT
                                bc.MaBangChung AS id,
                                bc.LoaiBangChung AS type,
                                bc.TenNguoiNhan AS receiverName,
                                bc.ThoiGianGhiNhan AS recordedAt,
                                bc.ViDo AS latitude,
                                bc.KinhDo AS longitude
                            FROM dbo.BangChungGiaoHang bc
                            WHERE bc.MaLanGiaoHang =
                                  lg.MaLanGiaoHang
                              AND bc.MaDonHang = d.MaDonHang
                            ORDER BY bc.MaBangChung
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        )) AS evidence
                    FROM dbo.LanGiaoHang lg
                    LEFT JOIN dbo.LyDoGiaoThatBai ld
                        ON ld.MaLyDoGiaoThatBai =
                           lg.MaLyDoGiaoThatBai
                    WHERE lg.MaDonHang = d.MaDonHang
                      AND lg.MaPhanCongGiaoHang =
                          pc.MaPhanCongGiaoHang
                    ORDER BY lg.SoLanThu DESC
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                )) AS deliveryAttempts,

                JSON_QUERY((
                    SELECT
                        yc.MaYeuCauGiaoLaiHoacHoan AS id,
                        yc.LoaiYeuCau AS type,
                        yc.TrangThaiYeuCau AS status,
                        yc.MaBuuCucHoan AS returnBranchId,
                        rb.TenBuuCuc AS returnBranchName,
                        yc.LyDo AS reason,
                        yc.ThoiGianYeuCau AS requestedAt,
                        yc.ThoiGianHoanTat AS completedAt
                    FROM dbo.YeuCauGiaoLaiHoacHoan yc
                    LEFT JOIN dbo.BuuCuc rb
                        ON rb.MaBuuCuc = yc.MaBuuCucHoan
                    WHERE yc.MaDonHang = d.MaDonHang
                      AND yc.ThoiGianYeuCau >=
                          pc.ThoiGianPhanCong
                      AND (
                          pc.ThoiGianKetThuc IS NULL
                          OR yc.ThoiGianYeuCau <=
                             pc.ThoiGianKetThuc
                      )
                    ORDER BY yc.MaYeuCauGiaoLaiHoacHoan DESC
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                )) AS requests

            FROM dbo.PhanCongGiaoHang pc
            INNER JOIN dbo.DonHang d
                ON d.MaDonHang = pc.MaDonHang
            INNER JOIN dbo.BuuCuc b
                ON b.MaBuuCuc = d.MaBuuCuc
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang =
                   d.MaTrangThaiHienTai
            LEFT JOIN dbo.PhuongTien pt
                ON pt.MaPhuongTien = pc.MaPhuongTien
            WHERE pc.MaPhanCongGiaoHang = @AssignmentId
              AND pc.MaNhanVienGiaoHang = @ShipperId
            FOR JSON PATH,
                INCLUDE_NULL_VALUES,
                WITHOUT_ARRAY_WRAPPER
        );
        """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@AssignmentId", SqlDbType.BigInt).Value = id;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            if (string.IsNullOrWhiteSpace(json))
            {
                return NotFound(new
                {
                    message = "Không tìm thấy nhiệm vụ của bạn."
                });
            }

            return Content(json, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 52701 and <= 52703)
        {
            var statusCode = ex.Number switch
            {
                52701 => StatusCodes.Status401Unauthorized,
                52702 => StatusCodes.Status403Forbidden,
                _ => StatusCodes.Status404NotFound
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
    }
    public class RejectMyTaskRequest
    {
        [Required]
        [StringLength(500)]
        public string Reason { get; set; } = "";
    }
    [HttpPost("{id:long}/reject")]
    public async Task<IActionResult> Reject(
    long id,
    [FromBody] RejectMyTaskRequest request)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã nhiệm vụ không hợp lệ."
            });
        }

        var reason = request.Reason.Trim();

        if (string.IsNullOrWhiteSpace(reason))
        {
            return BadRequest(new
            {
                message = "Phải nhập lý do từ chối nhiệm vụ."
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
                @OrderId BIGINT,
                @OrderStatus VARCHAR(40),
                @AssignmentStatus VARCHAR(20),
                @AcceptedAt DATETIME2(0),
                @EndedAt DATETIME2(0),
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
                THROW 52801,
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
                THROW 52802,
                    N'API này dành cho shipper từ chối nhiệm vụ của mình.',
                    1;

            SELECT @ShipperId = MaNhanVienGiaoHang
            FROM dbo.NhanVienGiaoHang
            WHERE MaTaiKhoan = @AccountId
              AND DangHoatDong = 1;

            IF @ShipperId IS NULL
                THROW 52802,
                    N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                    1;

            SELECT @OrderId = MaDonHang
            FROM dbo.PhanCongGiaoHang
            WHERE MaPhanCongGiaoHang = @AssignmentId
              AND MaNhanVienGiaoHang = @ShipperId;

            IF @OrderId IS NULL
                THROW 52803,
                    N'Không tìm thấy nhiệm vụ của bạn.',
                    1;

            -- Khóa đơn trước phân công, giống các API trước.
            SELECT @OrderStatus = tt.KyHieuTrangThai
            FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang =
                   d.MaTrangThaiHienTai
            WHERE d.MaDonHang = @OrderId
              AND d.MaBuuCuc = @AccountBranchId;

            IF @OrderStatus IS NULL
                THROW 52803,
                    N'Không tìm thấy nhiệm vụ trong bưu cục của bạn.',
                    1;

            SELECT
                @AssignmentStatus = TrangThaiPhanCong,
                @AcceptedAt = ThoiGianChapNhan,
                @EndedAt = ThoiGianKetThuc,
                @TripId = MaChuyenGiao
            FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
            WHERE MaPhanCongGiaoHang = @AssignmentId
              AND MaDonHang = @OrderId
              AND MaNhanVienGiaoHang = @ShipperId;

            IF @AssignmentStatus IS NULL
                THROW 52803,
                    N'Không tìm thấy nhiệm vụ của bạn.',
                    1;

            IF @EndedAt IS NOT NULL
                THROW 52804,
                    N'Phân công đã kết thúc, không thể từ chối lại.',
                    1;

            IF @AssignmentStatus <> 'PENDING'
               OR @AcceptedAt IS NOT NULL
                THROW 52804,
                    N'Chỉ nhiệm vụ PENDING chưa nhận mới được từ chối.',
                    1;

            IF @OrderStatus <> 'ASSIGNED'
                THROW 52804,
                    N'Đơn không còn ở trạng thái ASSIGNED.',
                    1;

            IF @TripId IS NOT NULL
                THROW 52804,
                    N'Nhiệm vụ thuộc chuyến giao. Cần xử lý từ chối qua API chuyến.',
                    1;

            IF EXISTS (
                SELECT 1
                FROM dbo.TonKhoDonHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaDonHang = @OrderId
                  AND TrangThaiTonKho = 'HANDED_OVER'
            )
                THROW 52804,
                    N'Hàng đã được bàn giao, không thể từ chối nhiệm vụ.',
                    1;

            SET @OldJson = (
                SELECT
                    @AssignmentId AS assignmentId,
                    @OrderId AS orderId,
                    @ShipperId AS shipperId,
                    @AssignmentStatus AS assignmentStatus,
                    @OrderStatus AS orderStatus
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            SET @Now = SYSUTCDATETIME();

            -- Kết thúc phân công trước khi trả đơn về hàng đợi,
            -- để procedure không đổi phân công này thành REASSIGNED.
            UPDATE dbo.PhanCongGiaoHang
            SET TrangThaiPhanCong = 'REJECTED',
                ThoiGianKetThuc = @Now
            WHERE MaPhanCongGiaoHang = @AssignmentId;

            EXEC dbo.sp_ChuyenTrangThaiDonHang
                @MaDonHang = @OrderId,
                @KyHieuTrangThaiMoi = 'WAITING_ASSIGNMENT',
                @MaTaiKhoan = @AccountId,
                @LyDo = @Reason,
                @NguonCapNhat = 'API';

            SET @Result = (
                SELECT
                    pc.MaPhanCongGiaoHang AS id,
                    d.MaDonHang AS orderId,
                    d.KyHieuDonHang AS orderCode,
                    d.MaVanDon AS trackingNumber,
                    pc.MaNhanVienGiaoHang AS shipperId,
                    pc.TrangThaiPhanCong AS assignmentStatus,
                    tt.KyHieuTrangThai AS orderStatus,
                    pc.ThoiGianKetThuc AS rejectedAt,
                    @Reason AS reason,
                    d.PhienBan AS version,
                    N'Đã từ chối nhiệm vụ. Đơn được đưa về chờ phân công.'
                        AS message
                FROM dbo.PhanCongGiaoHang pc
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = pc.MaDonHang
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang =
                       d.MaTrangThaiHienTai
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
                'REJECT_ASSIGNMENT',
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

        command.Parameters.Add(
            "@Reason", SqlDbType.NVarChar, 500).Value = reason;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 52801 and <= 52804)
        {
            var statusCode = ex.Number switch
            {
                52801 => StatusCodes.Status401Unauthorized,
                52802 => StatusCodes.Status403Forbidden,
                52803 => StatusCodes.Status404NotFound,
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
