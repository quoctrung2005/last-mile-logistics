using LastMile.Api.Services;
using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CreateDispatchAssignmentRequest
{
    [Range(1, long.MaxValue)]
    public long OrderId { get; set; }

    [Range(1, long.MaxValue)]
    public long ShipperId { get; set; }

    [Range(1, long.MaxValue)]
    public long VehicleId { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }

    public DateTimeOffset? PickupDueAt { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/dispatch/assignments")]
public class DispatchAssignmentsController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ShipperNotifications _notifications;

    public DispatchAssignmentsController(IConfiguration configuration, ShipperNotifications notifications)
    {
        _configuration = configuration;
        _notifications = notifications;
    }

    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreateDispatchAssignmentRequest request)
    {
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
                    @OrderBranchId INT,
                    @OrderStatus VARCHAR(40),
                    @WarehouseId INT,
                    @DeliveryAreaId INT,
                    @OrderWeight DECIMAL(12,3),
                    @ShipperAccountId BIGINT,
                    @ShipperBranchId INT,
                    @Availability VARCHAR(20),
                    @ShipperActive BIT,
                    @LicenseExpiry DATE,
                    @VehicleActive BIT,
                    @VehicleStatus VARCHAR(20),
                    @MaxWeight DECIMAL(10,2),
                    @MaxVolume DECIMAL(10,3),
                    @TotalWeight DECIMAL(28,3),
                    @TotalVolume DECIMAL(28,6),
                    @MissingDimensions INT,
                    @AssignmentId BIGINT,
                    @OldJson NVARCHAR(MAX),
                    @NewJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                -- Kiểm tra tài khoản điều phối.
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
                    THROW 51201,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DIEUPHOI_PHANCONG'
                )
                    THROW 51202,
                        N'Bạn không có quyền phân công giao hàng.',
                        1;

                IF @Role <> 'ADMIN'
                   AND @AccountBranchId IS NULL
                    THROW 51202,
                        N'Tài khoản chưa được gán bưu cục.',
                        1;

                -- Khóa đơn để tránh hai yêu cầu cùng phân công.
                SELECT
                    @OrderBranchId = d.MaBuuCuc,
                    @OrderStatus = tt.KyHieuTrangThai,
                    @OrderWeight = d.TongKhoiLuongKg,
                    @WarehouseId = d.MaKhoHienTai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang =
                       d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (
                      @Role = 'ADMIN'
                      OR d.MaBuuCuc = @AccountBranchId
                  );

                IF @OrderBranchId IS NULL
                    THROW 51203,
                        N'Không tìm thấy đơn hàng.',
                        1;

                IF @OrderStatus <> 'WAITING_ASSIGNMENT'
                    THROW 51204,
                        N'Chỉ đơn WAITING_ASSIGNMENT mới được phân công.',
                        1;

                IF @OrderWeight <= 0
                    THROW 51204,
                        N'Khối lượng đơn phải lớn hơn 0.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.BuuCuc
                    WHERE MaBuuCuc = @OrderBranchId
                      AND DangHoatDong = 1
                )
                    THROW 51204,
                        N'Bưu cục của đơn đã ngừng hoạt động.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongGiaoHang
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 51204,
                        N'Đơn đã có phân công đang hoạt động.',
                        1;

                -- API này phân công đơn riêng.
                -- Đơn đã thuộc chuyến cần xử lý bằng API chuyến.
                IF EXISTS (
                    SELECT 1
                    FROM dbo.ChiTietChuyenGiao ct
                    INNER JOIN dbo.ChuyenGiaoHang cg
                        ON cg.MaChuyenGiao = ct.MaChuyenGiao
                    WHERE ct.MaDonHang = @OrderId
                      AND cg.TrangThaiChuyen
                          NOT IN ('COMPLETED', 'CANCELLED')
                )
                    THROW 51204,
                        N'Đơn đang thuộc một chuyến chưa kết thúc. Hãy phân công qua chuyến giao.',
                        1;

                SELECT @DeliveryAreaId = gn.MaKhuVuc
                FROM dbo.DiemGiaoNhan gn
                INNER JOIN dbo.KhuVuc kv
                    ON kv.MaKhuVuc = gn.MaKhuVuc
                   AND kv.DangHoatDong = 1
                WHERE gn.MaDonHang = @OrderId
                  AND gn.LoaiDiem = 'DELIVERY';

                IF @DeliveryAreaId IS NULL
                    THROW 51205,
                        N'Điểm giao chưa có khu vực hợp lệ.',
                        1;

                -- Kiểm tra tồn kho đối với đơn đã nhập kho.
                IF @WarehouseId IS NOT NULL
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.TonKhoDonHang t
                            WITH (UPDLOCK, HOLDLOCK)
                        INNER JOIN dbo.Kho k
                            ON k.MaKho = t.MaKho
                        INNER JOIN dbo.ViTriLuuKho v
                            ON v.MaViTriLuuKho = t.MaViTriLuuKho
                           AND v.MaKho = t.MaKho
                        WHERE t.MaDonHang = @OrderId
                          AND t.MaKho = @WarehouseId
                          AND t.TrangThaiTonKho = 'STORED'
                          AND k.MaBuuCuc = @OrderBranchId
                          AND k.DangHoatDong = 1
                          AND v.DangHoatDong = 1
                    )
                        THROW 51204,
                            N'Tồn kho của đơn không còn phù hợp. Hãy tải lại tồn kho.',
                            1;
                END
                ELSE IF EXISTS (
                    SELECT 1
                    FROM dbo.TonKhoDonHang
                    WHERE MaDonHang = @OrderId
                )
                    THROW 51204,
                        N'Dữ liệu kho hiện tại và tồn kho không khớp.',
                        1;

                -- Khóa hồ sơ shipper.
                SELECT
                    @ShipperAccountId = nv.MaTaiKhoan,
                    @Availability = nv.TrangThaiSanSang,
                    @ShipperActive = nv.DangHoatDong,
                    @LicenseExpiry = nv.NgayHetHanBangLai
                FROM dbo.NhanVienGiaoHang nv
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE nv.MaNhanVienGiaoHang = @ShipperId;

                IF @ShipperAccountId IS NULL
                    THROW 51205,
                        N'Không tìm thấy shipper.',
                        1;

                SELECT @ShipperBranchId = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk
                INNER JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ShipperAccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.KyHieuVaiTro = 'SHIPPER'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @ShipperActive <> 1
                   OR @ShipperBranchId IS NULL
                   OR @ShipperBranchId <> @OrderBranchId
                   OR @Availability NOT IN (
                       'AVAILABLE', 'DELIVERING'
                   )
                    THROW 51204,
                        N'Shipper không sẵn sàng hoặc không thuộc bưu cục của đơn.',
                        1;

                IF @LicenseExpiry IS NOT NULL
                   AND @LicenseExpiry <
                       {{VietnamDate.SqlDate("SYSUTCDATETIME()")}}
                    THROW 51204,
                        N'Bằng lái của shipper đã hết hạn.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.KhuVucNhanVienGiaoHang
                    WHERE MaNhanVienGiaoHang = @ShipperId
                      AND MaKhuVuc = @DeliveryAreaId
                )
                    THROW 51204,
                        N'Shipper không phụ trách khu vực giao của đơn.',
                        1;

                -- Khóa xe: các lần phân công dùng cùng xe
                -- phải lần lượt kiểm tra sức chứa.
                SELECT
                    @VehicleActive = pt.DangHoatDong,
                    @VehicleStatus = pt.TrangThaiPhuongTien,
                    @MaxWeight = pt.KhoiLuongDenKg,
                    @MaxVolume = pt.TheTichToiDaM3
                FROM dbo.PhuongTien pt WITH (UPDLOCK, HOLDLOCK)
                WHERE pt.MaPhuongTien = @VehicleId;

                IF @VehicleActive IS NULL
                    THROW 51205,
                        N'Không tìm thấy phương tiện.',
                        1;

                IF @VehicleActive <> 1
                   OR @VehicleStatus NOT IN (
                       'AVAILABLE', 'IN_USE'
                   )
                    THROW 51204,
                        N'Phương tiện không sẵn sàng để phân công.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongPhuongTien
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaNhanVienGiaoHang = @ShipperId
                      AND MaPhuongTien = @VehicleId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 51204,
                        N'Phương tiện hiện không được phân cho shipper này.',
                        1;

                -- Tập đơn đang dùng xe, cộng thêm đơn mới.
                SELECT pc.MaDonHang
                INTO #VehicleOrders
                FROM dbo.PhanCongGiaoHang pc
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE pc.MaPhuongTien = @VehicleId
                  AND pc.ThoiGianKetThuc IS NULL;

                INSERT INTO #VehicleOrders (MaDonHang)
                SELECT held.MaDonHang FROM ({{DeferredReturnSql.HeldOrders(true)}}) held
                WHERE held.MaPhuongTien=@VehicleId
                  AND NOT EXISTS (SELECT 1 FROM #VehicleOrders x WHERE x.MaDonHang=held.MaDonHang);

                INSERT INTO #VehicleOrders (MaDonHang)
                VALUES (@OrderId);

                SELECT @TotalWeight = SUM(d.TongKhoiLuongKg)
                FROM #VehicleOrders x
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = x.MaDonHang;

                IF @TotalWeight > @MaxWeight
                    THROW 51204,
                        N'Tổng khối lượng các đơn vượt tải trọng phương tiện.',
                        1;

                IF @MaxVolume IS NOT NULL
                BEGIN
                    SELECT
                        @MissingDimensions = COALESCE(MAX(
                            CASE
                                WHEN ct.ChieuDaiCm IS NULL
                                  OR ct.ChieuRongCm IS NULL
                                  OR ct.ChieuCaoCm IS NULL
                                THEN 1
                                ELSE 0
                            END
                        ), 0),
                        @TotalVolume = COALESCE(SUM(
                            CAST(ct.SoLuong AS DECIMAL(18,6))
                            * ct.ChieuDaiCm
                            * ct.ChieuRongCm
                            * ct.ChieuCaoCm
                            / 1000000.0
                        ), 0)
                    FROM #VehicleOrders x
                    INNER JOIN dbo.ChiTietDonHang ct
                        ON ct.MaDonHang = x.MaDonHang;

                    IF @MissingDimensions = 1
                        THROW 51205,
                            N'Cần đủ chiều dài, rộng, cao của hàng để kiểm tra thể tích xe.',
                            1;

                    IF @TotalVolume > @MaxVolume
                        THROW 51204,
                            N'Tổng thể tích các đơn vượt sức chứa phương tiện.',
                            1;
                END;

                SET @OldJson = (
                    SELECT
                        @OrderId AS orderId,
                        @OrderStatus AS orderStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                SET @Now = SYSUTCDATETIME();

                INSERT INTO dbo.PhanCongGiaoHang (
                    MaDonHang,
                    MaChuyenGiao,
                    MaNhanVienGiaoHang,
                    MaPhuongTien,
                    MaTaiKhoanPhanCong,
                    ThoiGianPhanCong,
                    TrangThaiPhanCong,
                    BoQuaQuyTacKhuVuc
                )
                VALUES (
                    @OrderId,
                    NULL,
                    @ShipperId,
                    @VehicleId,
                    @AccountId,
                    @Now,
                    'PENDING',
                    0
                );

                SET @AssignmentId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                {{PickupDeadlineSql.SaveOnCreate}}

                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'ASSIGNED',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = @Notes,
                    @NguonCapNhat = 'API';

                SET @NewJson = (
                    SELECT
                        @AssignmentId AS assignmentId,
                        @OrderId AS orderId,
                        @ShipperId AS shipperId,
                        @VehicleId AS vehicleId,
                        'PENDING' AS assignmentStatus,
                        'ASSIGNED' AS orderStatus,
                        @Notes AS notes
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
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
                    'ASSIGN_ORDER',
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
                        nv.MaNhanVienGiaoHang AS shipperId,
                        tk.HoTen AS shipperName,
                        pt.MaPhuongTien AS vehicleId,
                        pt.BienSo AS licensePlate,
                        pc.TrangThaiPhanCong AS assignmentStatus,
                        tt.KyHieuTrangThai AS orderStatus,
                        pc.ThoiGianPhanCong AS assignedAt,
                        TRY_CONVERT(DATETIME2(0),JSON_VALUE((SELECT pc.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'$.HanDenLayHang'),126) AS pickupDueAt,
                        d.PhienBan AS version,
                        N'Phân công thành công, chờ shipper nhận nhiệm vụ.'
                            AS message
                    FROM dbo.PhanCongGiaoHang pc
                    INNER JOIN dbo.DonHang d
                        ON d.MaDonHang = pc.MaDonHang
                    INNER JOIN dbo.TrangThaiDonHang tt
                        ON tt.MaTrangThaiDonHang =
                           d.MaTrangThaiHienTai
                    INNER JOIN dbo.NhanVienGiaoHang nv
                        ON nv.MaNhanVienGiaoHang =
                           pc.MaNhanVienGiaoHang
                    INNER JOIN dbo.TaiKhoan tk
                        ON tk.MaTaiKhoan = nv.MaTaiKhoan
                    INNER JOIN dbo.PhuongTien pt
                        ON pt.MaPhuongTien = pc.MaPhuongTien
                    WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                DROP TABLE #VehicleOrders;

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
            "@OrderId", SqlDbType.BigInt).Value = request.OrderId;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value = request.ShipperId;

        command.Parameters.Add(
            "@VehicleId", SqlDbType.BigInt).Value = request.VehicleId;

        command.Parameters.Add(
            "@Notes", SqlDbType.NVarChar, 500).Value =
                (object?)notes ?? DBNull.Value;

        command.Parameters.Add("@PickupDueAt",SqlDbType.DateTime2).Value=(object?)request.PickupDueAt?.UtcDateTime??DBNull.Value;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            await _notifications.AssignmentCreated(json);

            return new ContentResult
            {
                StatusCode = StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = json
            };
        }
        catch(SqlException ex) when(ex.Number==55700){return StatusCode(503,new{message=ex.Message});}
        catch (SqlException ex) when (
            ex.Number is >= 51201 and <= 51205)
        {
            var statusCode = ex.Number switch
            {
                51201 => StatusCodes.Status401Unauthorized,
                51202 => StatusCodes.Status403Forbidden,
                51203 => StatusCodes.Status404NotFound,
                51205 => StatusCodes.Status422UnprocessableEntity,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message =
                    "Dữ liệu phân công đã thay đổi. Hãy tải lại đơn và danh sách shipper."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Có thao tác đồng thời với dữ liệu này. Hãy tải lại và thử phân công lại."
            });
        }
    }

    [HttpGet]
    public async Task<IActionResult> GetAssignments(
        [FromQuery, StringLength(100)] string? keyword = null,
        [FromQuery, Range(1, long.MaxValue)] long? orderId = null,
        [FromQuery, Range(1, long.MaxValue)] long? shipperId = null,
        [FromQuery, Range(1, long.MaxValue)] long? vehicleId = null,
        [FromQuery, Range(1, int.MaxValue)] int? branchId = null,
        [FromQuery, StringLength(20)] string? status = null,
        [FromQuery] bool activeOnly = false,
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

        status = string.IsNullOrWhiteSpace(status)
            ? null
            : status.Trim().ToUpperInvariant();

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

        if (status is not null && !allowedStatuses.Contains(status))
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
            @AccountBranchId INT;

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
            THROW 51201,
                N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.VaiTroQuyen vtq
            INNER JOIN dbo.Quyen q
                ON q.MaQuyen = vtq.MaQuyen
            WHERE vtq.MaVaiTro = @RoleId
              AND q.KyHieuQuyen = 'DIEUPHOI_GIAMSAT'
        )
            THROW 51202,
                N'Bạn không có quyền xem danh sách phân công.',
                1;

        IF @Role <> 'ADMIN'
           AND @AccountBranchId IS NULL
            THROW 51202,
                N'Tài khoản chưa được gán bưu cục.',
                1;

        IF @Role <> 'ADMIN'
           AND @BranchId IS NOT NULL
           AND @BranchId <> @AccountBranchId
            THROW 51202,
                N'Bạn chỉ được xem phân công thuộc bưu cục của mình.',
                1;

        SELECT
            pc.MaPhanCongGiaoHang AS id,
            d.MaDonHang AS orderId,
            d.KyHieuDonHang AS orderCode,
            d.MaVanDon AS trackingNumber,
            d.MaBuuCuc AS branchId,
            b.TenBuuCuc AS branchName,
            tt.KyHieuTrangThai AS orderStatus,
            nv.MaNhanVienGiaoHang AS shipperId,
            nv.MaNhanVien AS employeeCode,
            shipper.HoTen AS shipperName,
            shipper.SoDienThoai AS shipperPhone,
            pc.MaPhuongTien AS vehicleId,
            pt.BienSo AS licensePlate,
            pc.MaChuyenGiao AS tripId,
            pc.TrangThaiPhanCong AS assignmentStatus,
            pc.MaTaiKhoanPhanCong AS assignedBy,
            dispatcher.HoTen AS assignedByName,
            pc.ThoiGianPhanCong AS assignedAt,
                        TRY_CONVERT(DATETIME2(0),JSON_VALUE((SELECT pc.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'$.HanDenLayHang'),126) AS pickupDueAt,
            pc.ThoiGianChapNhan AS acceptedAt,
            pc.ThoiGianKetThuc AS endedAt,
            CAST(
                CASE
                    WHEN pc.ThoiGianKetThuc IS NULL THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS isActive,
            pc.BoQuaQuyTacKhuVuc AS areaOverride,
            pc.LyDoBoQua AS overrideReason
        INTO #Assignments
        FROM dbo.PhanCongGiaoHang pc
        INNER JOIN dbo.DonHang d
            ON d.MaDonHang = pc.MaDonHang
        INNER JOIN dbo.BuuCuc b
            ON b.MaBuuCuc = d.MaBuuCuc
        INNER JOIN dbo.TrangThaiDonHang tt
            ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
        INNER JOIN dbo.NhanVienGiaoHang nv
            ON nv.MaNhanVienGiaoHang = pc.MaNhanVienGiaoHang
        INNER JOIN dbo.TaiKhoan shipper
            ON shipper.MaTaiKhoan = nv.MaTaiKhoan
        INNER JOIN dbo.TaiKhoan dispatcher
            ON dispatcher.MaTaiKhoan = pc.MaTaiKhoanPhanCong
        LEFT JOIN dbo.PhuongTien pt
            ON pt.MaPhuongTien = pc.MaPhuongTien
        WHERE (
            @Role = 'ADMIN'
            OR d.MaBuuCuc = @AccountBranchId
        )
          AND (
              @BranchId IS NULL
              OR d.MaBuuCuc = @BranchId
          )
          AND (
              @OrderId IS NULL
              OR pc.MaDonHang = @OrderId
          )
          AND (
              @ShipperId IS NULL
              OR pc.MaNhanVienGiaoHang = @ShipperId
          )
          AND (@VehicleId IS NULL OR pc.MaPhuongTien = @VehicleId)
          AND (
              @Status IS NULL
              OR pc.TrangThaiPhanCong = @Status
          )
          AND (
              @ActiveOnly = 0
              OR pc.ThoiGianKetThuc IS NULL
          )
          AND (
              @Keyword IS NULL
              OR CHARINDEX(@Keyword, d.KyHieuDonHang) > 0
              OR CHARINDEX(@Keyword, d.MaVanDon) > 0
              OR CHARINDEX(@Keyword, nv.MaNhanVien) > 0
              OR CHARINDEX(@Keyword, shipper.HoTen) > 0
              OR CHARINDEX(@Keyword, shipper.SoDienThoai) > 0
              OR CHARINDEX(@Keyword, pt.BienSo) > 0
          );

        SELECT (
            SELECT
                @Page AS page,
                @PageSize AS pageSize,
                (
                    SELECT COUNT_BIG(*)
                    FROM #Assignments
                ) AS totalItems,
                JSON_QUERY(COALESCE((
                    SELECT *
                    FROM #Assignments
                    ORDER BY assignedAt DESC, id DESC
                    OFFSET @Offset ROWS
                    FETCH NEXT @PageSize ROWS ONLY
                    FOR JSON PATH, INCLUDE_NULL_VALUES
                ), N'[]')) AS items
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        DROP TABLE #Assignments;
        """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;

        command.Parameters.Add(
            "@OrderId", SqlDbType.BigInt).Value =
                (object?)orderId ?? DBNull.Value;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value =
                (object?)shipperId ?? DBNull.Value;

        command.Parameters.Add("@VehicleId", SqlDbType.BigInt).Value = (object?)vehicleId ?? DBNull.Value;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
                (object?)branchId ?? DBNull.Value;

        command.Parameters.Add(
            "@Status", SqlDbType.VarChar, 20).Value =
                (object?)status ?? DBNull.Value;

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
            ex.Number is 51201 or 51202)
        {
            return StatusCode(
                ex.Number == 51201
                    ? StatusCodes.Status401Unauthorized
                    : StatusCodes.Status403Forbidden,
                new { message = ex.Message });
        }

    }
    public class CancelDispatchAssignmentRequest
    {
        [Required]
        [StringLength(500)]
        public string Reason { get; set; } = "";
    }
    [HttpPost("{id:long}/cancel")]
    public async Task<IActionResult> CancelAssignment(
    long id,
    [FromBody] CancelDispatchAssignmentRequest request)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã phân công không hợp lệ."
            });
        }

        var reason = request.Reason.Trim();

        if (string.IsNullOrWhiteSpace(reason))
        {
            return BadRequest(new
            {
                message = "Phải nhập lý do hủy phân công."
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
                @OrderId BIGINT,
                @OrderBranchId INT,
                @OrderStatus VARCHAR(40),
                @AssignmentStatus VARCHAR(20),
                @EndedAt DATETIME2(0),
                @TripId BIGINT,
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
                THROW 51201,
                    N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vtq
                INNER JOIN dbo.Quyen q
                    ON q.MaQuyen = vtq.MaQuyen
                WHERE vtq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen = 'DIEUPHOI_PHANCONG'
            )
                THROW 51202,
                    N'Bạn không có quyền hủy phân công.',
                    1;

            IF @Role <> 'ADMIN'
               AND @AccountBranchId IS NULL
                THROW 51202,
                    N'Tài khoản chưa được gán bưu cục.',
                    1;

            -- Xác định đơn, sau đó khóa đơn trước phân công.
            SELECT @OrderId = MaDonHang
            FROM dbo.PhanCongGiaoHang
            WHERE MaPhanCongGiaoHang = @AssignmentId;

            IF @OrderId IS NULL
                THROW 51203,
                    N'Không tìm thấy phân công.',
                    1;

            SELECT
                @OrderBranchId = d.MaBuuCuc,
                @OrderStatus = tt.KyHieuTrangThai
            FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang =
                   d.MaTrangThaiHienTai
            WHERE d.MaDonHang = @OrderId
              AND (
                  @Role = 'ADMIN'
                  OR d.MaBuuCuc = @AccountBranchId
              );

            IF @OrderBranchId IS NULL
                THROW 51203,
                    N'Không tìm thấy phân công.',
                    1;

            SELECT
                @AssignmentStatus = pc.TrangThaiPhanCong,
                @EndedAt = pc.ThoiGianKetThuc,
                @TripId = pc.MaChuyenGiao
            FROM dbo.PhanCongGiaoHang pc
                WITH (UPDLOCK, HOLDLOCK)
            WHERE pc.MaPhanCongGiaoHang = @AssignmentId
              AND pc.MaDonHang = @OrderId;

            IF @AssignmentStatus IS NULL
                THROW 51203,
                    N'Không tìm thấy phân công.',
                    1;

            IF @EndedAt IS NOT NULL
                THROW 51204,
                    N'Phân công đã kết thúc, không thể hủy lại.',
                    1;

            IF @OrderStatus <> 'ASSIGNED'
                THROW 51204,
                    N'Chỉ được hủy phân công khi đơn còn ở trạng thái ASSIGNED, trước khi bàn giao.',
                    1;

            IF @AssignmentStatus NOT IN ('PENDING', 'ACCEPTED')
                THROW 51204,
                    N'Phân công đã bắt đầu xử lý, không thể hủy bằng API này.',
                    1;

            IF @TripId IS NOT NULL
                THROW 51204,
                    N'Phân công thuộc chuyến giao. Cần xử lý qua API quản lý chuyến.',
                    1;

            IF EXISTS (
                SELECT 1
                FROM dbo.TonKhoDonHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaDonHang = @OrderId
                  AND TrangThaiTonKho = 'HANDED_OVER'
            )
                THROW 51204,
                    N'Hàng đã được bàn giao, không thể hủy phân công.',
                    1;

            SET @OldJson = (
                SELECT
                    pc.MaPhanCongGiaoHang AS assignmentId,
                    pc.MaDonHang AS orderId,
                    pc.MaNhanVienGiaoHang AS shipperId,
                    pc.MaPhuongTien AS vehicleId,
                    pc.TrangThaiPhanCong AS assignmentStatus,
                    @OrderStatus AS orderStatus
                FROM dbo.PhanCongGiaoHang pc
                WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                FOR JSON PATH,
                    INCLUDE_NULL_VALUES,
                    WITHOUT_ARRAY_WRAPPER
            );

            SET @Now = SYSUTCDATETIME();

            -- Kết thúc phân công cũ và giữ lại lịch sử.
            UPDATE dbo.PhanCongGiaoHang
            SET TrangThaiPhanCong = 'CANCELLED',
                ThoiGianKetThuc = @Now
            WHERE MaPhanCongGiaoHang = @AssignmentId;

            -- Trả đơn về hàng đợi điều phối.
            EXEC dbo.sp_ChuyenTrangThaiDonHang
                @MaDonHang = @OrderId,
                @KyHieuTrangThaiMoi = 'WAITING_ASSIGNMENT',
                @MaTaiKhoan = @AccountId,
                @LyDo = @Reason,
                @NguonCapNhat = 'API';

            SET @NewJson = (
                SELECT
                    @AssignmentId AS assignmentId,
                    @OrderId AS orderId,
                    'CANCELLED' AS assignmentStatus,
                    'WAITING_ASSIGNMENT' AS orderStatus,
                    @Now AS endedAt,
                    @Reason AS reason
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
                'CANCEL_ASSIGNMENT',
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
                    pc.TrangThaiPhanCong AS assignmentStatus,
                    tt.KyHieuTrangThai AS orderStatus,
                    pc.ThoiGianKetThuc AS endedAt,
                    d.PhienBan AS version,
                    @Reason AS reason,
                    N'Đã hủy phân công. Đơn được đưa về chờ phân công.'
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
            ex.Number is >= 51201 and <= 51204)
        {
            var statusCode = ex.Number switch
            {
                51201 => StatusCodes.Status401Unauthorized,
                51202 => StatusCodes.Status403Forbidden,
                51203 => StatusCodes.Status404NotFound,
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
                    "Có thao tác đồng thời. Hãy tải lại phân công và thử lại."
            });
        }
    }
    public class ReassignDispatchRequest
    {
        [Range(1, long.MaxValue)]
        public long ShipperId { get; set; }

        [Range(1, long.MaxValue)]
        public long VehicleId { get; set; }

        [Required]
        [StringLength(500)]
        public string Reason { get; set; } = "";
    }
    [HttpPost("{id:long}/reassign")]
    public async Task<IActionResult> Reassign(
    long id,
    [FromBody] ReassignDispatchRequest request)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã phân công không hợp lệ." });

        var reason = request.Reason.Trim();

        if (string.IsNullOrWhiteSpace(reason))
            return BadRequest(new { message = "Phải nhập lý do đổi phân công." });

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
                @OrderId BIGINT,
                @OrderBranchId INT,
                @OrderStatus VARCHAR(40),
                @WarehouseId INT,
                @OrderWeight DECIMAL(12,3),
                @DeliveryAreaId INT,
                @OldShipperId BIGINT,
                @OldVehicleId BIGINT,
                @OldAssignmentStatus VARCHAR(20),
                @OldEndedAt DATETIME2(0),
                @TripId BIGINT,
                @NewShipperBranchId INT,
                @MaxWeight DECIMAL(10,2),
                @MaxVolume DECIMAL(10,3),
                @TotalWeight DECIMAL(28,3),
                @TotalVolume DECIMAL(28,6),
                @MissingDimensions INT,
                @NewAssignmentId BIGINT,
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
                THROW 53601,
                    N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vtq
                INNER JOIN dbo.Quyen q
                    ON q.MaQuyen = vtq.MaQuyen
                WHERE vtq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen = 'DIEUPHOI_PHANCONG'
            )
                THROW 53602,
                    N'Bạn không có quyền đổi phân công.',
                    1;

            IF @Role <> 'ADMIN' AND @AccountBranchId IS NULL
                THROW 53602,
                    N'Tài khoản chưa được gán bưu cục.',
                    1;

            SELECT @OrderId = MaDonHang
            FROM dbo.PhanCongGiaoHang
            WHERE MaPhanCongGiaoHang = @OldAssignmentId;

            IF @OrderId IS NULL
                THROW 53603, N'Không tìm thấy phân công.', 1;

            SELECT
                @OrderBranchId = d.MaBuuCuc,
                @OrderStatus = tt.KyHieuTrangThai,
                @WarehouseId = d.MaKhoHienTai,
                @OrderWeight = d.TongKhoiLuongKg
            FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            WHERE d.MaDonHang = @OrderId
              AND (
                  @Role = 'ADMIN'
                  OR d.MaBuuCuc = @AccountBranchId
              );

            IF @OrderBranchId IS NULL
                THROW 53603, N'Không tìm thấy phân công.', 1;

            SELECT
                @OldShipperId = MaNhanVienGiaoHang,
                @OldVehicleId = MaPhuongTien,
                @OldAssignmentStatus = TrangThaiPhanCong,
                @OldEndedAt = ThoiGianKetThuc,
                @TripId = MaChuyenGiao
            FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
            WHERE MaPhanCongGiaoHang = @OldAssignmentId
              AND MaDonHang = @OrderId;

            IF @OldAssignmentStatus IS NULL
                THROW 53603, N'Không tìm thấy phân công.', 1;

            IF @OrderStatus <> 'ASSIGNED'
               OR @OldEndedAt IS NOT NULL
               OR @OldAssignmentStatus NOT IN ('PENDING', 'ACCEPTED')
                THROW 53604,
                    N'Chỉ đổi phân công PENDING hoặc ACCEPTED của đơn ASSIGNED.',
                    1;

            IF @TripId IS NOT NULL
                THROW 53604,
                    N'Phân công thuộc chuyến giao. Cần đổi qua API quản lý chuyến.',
                    1;

            IF EXISTS (
                SELECT 1
                FROM dbo.ChiTietChuyenGiao ct
                INNER JOIN dbo.ChuyenGiaoHang cg
                    ON cg.MaChuyenGiao = ct.MaChuyenGiao
                WHERE ct.MaDonHang = @OrderId
                  AND cg.TrangThaiChuyen NOT IN (
                      'COMPLETED', 'CANCELLED'
                  )
            )
                THROW 53604,
                    N'Đơn đang thuộc chuyến chưa kết thúc.',
                    1;

            IF @OldShipperId = @NewShipperId
               AND @OldVehicleId = @NewVehicleId
                THROW 53604,
                    N'Shipper và phương tiện mới giống phân công hiện tại.',
                    1;

            IF @OrderWeight <= 0
                THROW 53604, N'Khối lượng đơn không hợp lệ.', 1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.BuuCuc
                WHERE MaBuuCuc = @OrderBranchId
                  AND DangHoatDong = 1
            )
                THROW 53604, N'Bưu cục đã ngừng hoạt động.', 1;

            IF @WarehouseId IS NOT NULL
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.TonKhoDonHang t WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.Kho k ON k.MaKho = t.MaKho
                    INNER JOIN dbo.ViTriLuuKho v
                        ON v.MaViTriLuuKho = t.MaViTriLuuKho
                       AND v.MaKho = t.MaKho
                    WHERE t.MaDonHang = @OrderId
                      AND t.MaKho = @WarehouseId
                      AND t.TrangThaiTonKho IN ('STORED', 'ALLOCATED')
                      AND k.MaBuuCuc = @OrderBranchId
                      AND k.DangHoatDong = 1
                      AND v.DangHoatDong = 1
                )
                    THROW 53604,
                        N'Tồn kho không còn phù hợp để đổi phân công.',
                        1;
            END
            ELSE IF EXISTS (
                SELECT 1
                FROM dbo.TonKhoDonHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaDonHang = @OrderId
            )
                THROW 53604,
                    N'Đơn đã được xuất kho hoặc dữ liệu kho không khớp.',
                    1;

            SELECT @DeliveryAreaId = gn.MaKhuVuc
            FROM dbo.DiemGiaoNhan gn
            INNER JOIN dbo.KhuVuc kv
                ON kv.MaKhuVuc = gn.MaKhuVuc
               AND kv.DangHoatDong = 1
            WHERE gn.MaDonHang = @OrderId
              AND gn.LoaiDiem = 'DELIVERY';

            IF @DeliveryAreaId IS NULL
                THROW 53605,
                    N'Điểm giao chưa có khu vực hợp lệ.',
                    1;

            SELECT @NewShipperBranchId = tk.MaBuuCuc
            FROM dbo.NhanVienGiaoHang nv WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.TaiKhoan tk
                ON tk.MaTaiKhoan = nv.MaTaiKhoan
            INNER JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE nv.MaNhanVienGiaoHang = @NewShipperId
              AND nv.DangHoatDong = 1
              AND nv.TrangThaiSanSang IN ('AVAILABLE', 'DELIVERING')
              AND (
                  nv.NgayHetHanBangLai IS NULL
                  OR nv.NgayHetHanBangLai >= {{VietnamDate.SqlDate("@Now")}}
              )
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= @Now
              )
              AND vt.KyHieuVaiTro = 'SHIPPER'
              AND vt.DangHoatDong = 1;

            IF @NewShipperBranchId IS NULL
               OR @NewShipperBranchId <> @OrderBranchId
                THROW 53604,
                    N'Shipper mới không đủ điều kiện hoặc khác bưu cục.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.KhuVucNhanVienGiaoHang
                WHERE MaNhanVienGiaoHang = @NewShipperId
                  AND MaKhuVuc = @DeliveryAreaId
            )
                THROW 53604,
                    N'Shipper mới không phụ trách khu vực giao.',
                    1;

            SELECT
                @MaxWeight = KhoiLuongDenKg,
                @MaxVolume = TheTichToiDaM3
            FROM dbo.PhuongTien WITH (UPDLOCK, HOLDLOCK)
            WHERE MaPhuongTien = @NewVehicleId
              AND DangHoatDong = 1
              AND TrangThaiPhuongTien IN ('AVAILABLE', 'IN_USE');

            IF @MaxWeight IS NULL
                THROW 53604, N'Phương tiện mới không phù hợp.', 1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.PhanCongPhuongTien WITH (UPDLOCK, HOLDLOCK)
                WHERE MaNhanVienGiaoHang = @NewShipperId
                  AND MaPhuongTien = @NewVehicleId
                  AND ThoiGianKetThuc IS NULL
            )
                THROW 53604,
                    N'Phương tiện mới chưa được phân cho shipper này.',
                    1;

            SET @OldJson = (
                SELECT
                    @OldAssignmentId AS assignmentId,
                    @OrderId AS orderId,
                    @OldShipperId AS shipperId,
                    @OldVehicleId AS vehicleId,
                    @OldAssignmentStatus AS assignmentStatus
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            -- Procedure kết thúc phân công cũ thành REASSIGNED
            -- và trả đơn về WAITING_ASSIGNMENT.
            EXEC dbo.sp_ChuyenTrangThaiDonHang
                @MaDonHang = @OrderId,
                @KyHieuTrangThaiMoi = 'WAITING_ASSIGNMENT',
                @MaTaiKhoan = @AccountId,
                @LyDo = @Reason,
                @NguonCapNhat = 'API';

            -- Sau khi giải phóng phân công cũ, tính tải của xe mới.
            SELECT MaDonHang AS orderId
            INTO #VehicleOrders
            FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
            WHERE MaPhuongTien = @NewVehicleId
              AND ThoiGianKetThuc IS NULL;

            INSERT INTO #VehicleOrders (orderId)
            SELECT held.MaDonHang FROM ({{DeferredReturnSql.HeldOrders(true)}}) held
            WHERE held.MaPhuongTien=@NewVehicleId
              AND NOT EXISTS (SELECT 1 FROM #VehicleOrders x WHERE x.orderId=held.MaDonHang);

            INSERT INTO #VehicleOrders (orderId)
            VALUES (@OrderId);

            SELECT @TotalWeight = SUM(d.TongKhoiLuongKg)
            FROM #VehicleOrders x
            INNER JOIN dbo.DonHang d ON d.MaDonHang = x.orderId;

            IF @TotalWeight > @MaxWeight
                THROW 53604,
                    N'Tổng khối lượng vượt tải trọng phương tiện mới.',
                    1;

            IF @MaxVolume IS NOT NULL
            BEGIN
                SELECT
                    @MissingDimensions = COALESCE(MAX(
                        CASE
                            WHEN ct.ChieuDaiCm IS NULL
                              OR ct.ChieuRongCm IS NULL
                              OR ct.ChieuCaoCm IS NULL
                            THEN 1 ELSE 0
                        END
                    ), 0),
                    @TotalVolume = COALESCE(SUM(
                        CAST(ct.SoLuong AS DECIMAL(18,6))
                        * ct.ChieuDaiCm
                        * ct.ChieuRongCm
                        * ct.ChieuCaoCm / 1000000.0
                    ), 0)
                FROM #VehicleOrders x
                INNER JOIN dbo.ChiTietDonHang ct
                    ON ct.MaDonHang = x.orderId;

                IF @MissingDimensions = 1
                    THROW 53605,
                        N'Cần đủ kích thước hàng để kiểm tra thể tích xe mới.',
                        1;

                IF @TotalVolume > @MaxVolume
                    THROW 53604,
                        N'Tổng thể tích vượt sức chứa phương tiện mới.',
                        1;
            END;

            INSERT INTO dbo.PhanCongGiaoHang (
                MaDonHang,
                MaChuyenGiao,
                MaNhanVienGiaoHang,
                MaPhuongTien,
                MaTaiKhoanPhanCong,
                ThoiGianPhanCong,
                TrangThaiPhanCong,
                BoQuaQuyTacKhuVuc
            )
            VALUES (
                @OrderId,
                NULL,
                @NewShipperId,
                @NewVehicleId,
                @AccountId,
                SYSUTCDATETIME(),
                'PENDING',
                0
            );

            SET @NewAssignmentId =
                CONVERT(BIGINT, SCOPE_IDENTITY());

            EXEC dbo.sp_ChuyenTrangThaiDonHang
                @MaDonHang = @OrderId,
                @KyHieuTrangThaiMoi = 'ASSIGNED',
                @MaTaiKhoan = @AccountId,
                @LyDo = @Reason,
                @NguonCapNhat = 'API';

            SET @Result = (
                SELECT
                    @OldAssignmentId AS previousAssignmentId,
                    pc.MaPhanCongGiaoHang AS id,
                    d.MaDonHang AS orderId,
                    d.KyHieuDonHang AS orderCode,
                    d.MaVanDon AS trackingNumber,
                    pc.MaNhanVienGiaoHang AS shipperId,
                    tk.HoTen AS shipperName,
                    pc.MaPhuongTien AS vehicleId,
                    pt.BienSo AS licensePlate,
                    pc.TrangThaiPhanCong AS assignmentStatus,
                    tt.KyHieuTrangThai AS orderStatus,
                    pc.ThoiGianPhanCong AS assignedAt,
                        TRY_CONVERT(DATETIME2(0),JSON_VALUE((SELECT pc.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'$.HanDenLayHang'),126) AS pickupDueAt,
                    @Reason AS reason,
                    d.PhienBan AS version,
                    N'Đã đổi phân công, chờ shipper nhận nhiệm vụ mới.'
                        AS message
                FROM dbo.PhanCongGiaoHang pc
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = pc.MaDonHang
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                INNER JOIN dbo.NhanVienGiaoHang nv
                    ON nv.MaNhanVienGiaoHang = pc.MaNhanVienGiaoHang
                INNER JOIN dbo.TaiKhoan tk
                    ON tk.MaTaiKhoan = nv.MaTaiKhoan
                INNER JOIN dbo.PhuongTien pt
                    ON pt.MaPhuongTien = pc.MaPhuongTien
                WHERE pc.MaPhanCongGiaoHang = @NewAssignmentId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO dbo.NhatKyHoatDong (
                MaTaiKhoan, LoaiThaoTac, TenDoiTuong,
                MaDoiTuong, DuLieuCuJson, DuLieuMoiJson
            )
            VALUES (
                @AccountId, 'REASSIGN_ORDER', 'DonHang',
                CONVERT(VARCHAR(100), @OrderId),
                @OldJson, @Result
            );

            DROP TABLE #VehicleOrders;

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
            "@OldAssignmentId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@NewShipperId", SqlDbType.BigInt).Value = request.ShipperId;

        command.Parameters.Add(
            "@NewVehicleId", SqlDbType.BigInt).Value = request.VehicleId;

        command.Parameters.Add(
            "@Reason", SqlDbType.NVarChar, 500).Value = reason;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            await _notifications.AssignmentCreated(json);

            return new ContentResult
            {
                StatusCode = StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = json
            };
        }
        catch (SqlException ex) when (
            ex.Number is >= 53601 and <= 53605)
        {
            var statusCode = ex.Number switch
            {
                53601 => StatusCodes.Status401Unauthorized,
                53602 => StatusCodes.Status403Forbidden,
                53603 => StatusCodes.Status404NotFound,
                53605 => StatusCodes.Status422UnprocessableEntity,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new { message = ex.Message });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627 or 1205)
        {
            return Conflict(new
            {
                message =
                    "Dữ liệu phân công đang được thay đổi. Hãy tải lại và thử lại."
            });
        }
    }
}
