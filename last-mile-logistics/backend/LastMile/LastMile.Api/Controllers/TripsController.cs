using LastMile.Api.Services;
using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class CreateTripRequest
{
    [Range(1, int.MaxValue)]
    public int BranchId { get; set; }

    [Range(1, int.MaxValue)]
    public int WarehouseId { get; set; }

    public DateTimeOffset? PlannedStartAt { get; set; }

    [Required]
    [MinLength(1)]
    [MaxLength(100)]
    public List<long> OrderIds { get; set; } = [];
}

[ApiController]
[Authorize]
[Route("api/v1/trips")]
public class TripsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public TripsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreateTripRequest request)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        if (request.OrderIds.Any(x => x <= 0))
        {
            return BadRequest(new
            {
                message = "Mã đơn hàng phải lớn hơn 0."
            });
        }

        if (request.OrderIds.Distinct().Count()
            != request.OrderIds.Count)
        {
            return BadRequest(new
            {
                message = "Danh sách đơn không được trùng mã."
            });
        }

        DateTime? plannedStartAt = null;

        if (request.PlannedStartAt.HasValue)
        {
            var utc = request.PlannedStartAt.Value.UtcDateTime;

            plannedStartAt = new DateTime(
                utc.Ticks - utc.Ticks % TimeSpan.TicksPerSecond,
                DateTimeKind.Utc);

            if (plannedStartAt <= DateTime.UtcNow)
            {
                return BadRequest(new
                {
                    message =
                        "Thời gian bắt đầu dự kiến phải nằm trong tương lai."
                });
            }
        }

        var orderIdsJson = JsonSerializer.Serialize(request.OrderIds);

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
                    @TripId BIGINT,
                    @TripCode VARCHAR(40),
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
                    THROW 53701,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DIEUPHOI_GOMDON'
                )
                    THROW 53702,
                        N'Bạn không có quyền tạo chuyến giao.',
                        1;

                IF @Role <> 'ADMIN'
                   AND (
                       @AccountBranchId IS NULL
                       OR @AccountBranchId <> @BranchId
                   )
                    THROW 53702,
                        N'Bạn chỉ được tạo chuyến trong bưu cục của mình.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.Kho k
                    INNER JOIN dbo.BuuCuc b
                        ON b.MaBuuCuc = k.MaBuuCuc
                    WHERE k.MaKho = @WarehouseId
                      AND k.MaBuuCuc = @BranchId
                      AND k.DangHoatDong = 1
                      AND b.DangHoatDong = 1
                )
                    THROW 53704,
                        N'Kho không hoạt động hoặc không thuộc bưu cục đã chọn.',
                        1;

                CREATE TABLE #RequestedOrders (
                    orderId BIGINT NOT NULL PRIMARY KEY,
                    sequence INT NOT NULL
                );

                INSERT INTO #RequestedOrders (orderId, sequence)
                SELECT
                    CONVERT(BIGINT, [value]),
                    CONVERT(INT, [key]) + 1
                FROM OPENJSON(@OrderIdsJson);

                -- Khóa đơn để tránh gom/phân công đồng thời.
                SELECT
                    d.MaDonHang AS orderId,
                    d.MaKhoHienTai AS warehouseId,
                    d.TongKhoiLuongKg AS weightKg,
                    tt.KyHieuTrangThai AS orderStatus
                INTO #LockedOrders
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN #RequestedOrders x
                    ON x.orderId = d.MaDonHang
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang =
                       d.MaTrangThaiHienTai
                WHERE d.MaBuuCuc = @BranchId;

                IF (
                    SELECT COUNT(*) FROM #LockedOrders
                ) <> (
                    SELECT COUNT(*) FROM #RequestedOrders
                )
                    THROW 53704,
                        N'Có đơn không tồn tại hoặc không thuộc bưu cục đã chọn.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM #LockedOrders
                    WHERE orderStatus <> 'WAITING_ASSIGNMENT'
                       OR warehouseId IS NULL
                       OR warehouseId <> @WarehouseId
                       OR weightKg <= 0
                )
                    THROW 53704,
                        N'Tất cả đơn phải WAITING_ASSIGNMENT, có khối lượng hợp lệ và ở cùng kho.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM #RequestedOrders x
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM dbo.TonKhoDonHang t
                            WITH (UPDLOCK, HOLDLOCK)
                        INNER JOIN dbo.ViTriLuuKho v
                            ON v.MaViTriLuuKho = t.MaViTriLuuKho
                           AND v.MaKho = t.MaKho
                        WHERE t.MaDonHang = x.orderId
                          AND t.MaKho = @WarehouseId
                          AND t.TrangThaiTonKho = 'STORED'
                          AND v.DangHoatDong = 1
                    )
                )
                    THROW 53704,
                        N'Có đơn không còn tồn kho STORED tại vị trí đang hoạt động.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongGiaoHang pc
                        WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN #RequestedOrders x
                        ON x.orderId = pc.MaDonHang
                    WHERE pc.ThoiGianKetThuc IS NULL
                )
                    THROW 53704,
                        N'Có đơn đã được phân công.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.ChiTietChuyenGiao ct
                    INNER JOIN dbo.ChuyenGiaoHang cg
                        ON cg.MaChuyenGiao = ct.MaChuyenGiao
                    INNER JOIN #RequestedOrders x
                        ON x.orderId = ct.MaDonHang
                    WHERE cg.TrangThaiChuyen NOT IN (
                        'COMPLETED', 'CANCELLED'
                    )
                )
                    THROW 53704,
                        N'Có đơn đã thuộc chuyến chưa kết thúc.',
                        1;

                SET @Now = SYSUTCDATETIME();

                IF @PlannedStartAt IS NOT NULL
                   AND @PlannedStartAt <= @Now
                    THROW 53704,
                        N'Thời gian bắt đầu dự kiến đã nằm trong quá khứ.',
                        1;

                SET @TripCode =
                    'CG-' + REPLACE(
                        CONVERT(VARCHAR(36), NEWID()), '-', ''
                    );

                INSERT INTO dbo.ChuyenGiaoHang (
                    KyHieuChuyenGiao,
                    MaBuuCuc,
                    MaKho,
                    TrangThaiChuyen,
                    ThoiGianBatDauDuKien,
                    MaTaiKhoanTao,
                    ThoiGianTao
                )
                VALUES (
                    @TripCode,
                    @BranchId,
                    @WarehouseId,
                    'PLANNED',
                    @PlannedStartAt,
                    @AccountId,
                    @Now
                );

                SET @TripId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.ChiTietChuyenGiao (
                    MaChuyenGiao,
                    MaDonHang,
                    ThuTuDuKien
                )
                SELECT @TripId, orderId, sequence
                FROM #RequestedOrders;

                SET @Result = (
                    SELECT
                        @TripId AS id,
                        @TripCode AS tripCode,
                        @BranchId AS branchId,
                        @WarehouseId AS warehouseId,
                        'PLANNED' AS status,
                        @PlannedStartAt AS plannedStartAt,
                        @Now AS createdAt,
                        (
                            SELECT COUNT(*)
                            FROM #RequestedOrders
                        ) AS orderCount,
                        (
                            SELECT SUM(weightKg)
                            FROM #LockedOrders
                        ) AS totalWeightKg,
                        JSON_QUERY((
                            SELECT orderId, sequence
                            FROM #RequestedOrders
                            ORDER BY sequence
                            FOR JSON PATH
                        )) AS orders,
                        N'Đã tạo chuyến, chờ chọn shipper và phương tiện.'
                            AS message
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan,
                    LoaiThaoTac,
                    TenDoiTuong,
                    MaDoiTuong,
                    DuLieuMoiJson
                )
                VALUES (
                    @AccountId,
                    'CREATE_TRIP',
                    'ChuyenGiaoHang',
                    CONVERT(VARCHAR(100), @TripId),
                    @Result
                );

                DROP TABLE #LockedOrders;
                DROP TABLE #RequestedOrders;

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
            "@BranchId", SqlDbType.Int).Value = request.BranchId;

        command.Parameters.Add(
            "@WarehouseId", SqlDbType.Int).Value = request.WarehouseId;

        command.Parameters.Add(
            "@OrderIdsJson", SqlDbType.NVarChar, -1).Value = orderIdsJson;

        var plannedParameter = command.Parameters.Add(
            "@PlannedStartAt", SqlDbType.DateTime2);
        plannedParameter.Scale = 0;
        plannedParameter.Value =
            (object?)plannedStartAt ?? DBNull.Value;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return new ContentResult
            {
                StatusCode = StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = json
            };
        }
        catch (SqlException ex) when (
            ex.Number is 53701 or 53702 or 53704
            or 51050 or 51051)
        {
            var statusCode = ex.Number switch
            {
                53701 => StatusCodes.Status401Unauthorized,
                53702 => StatusCodes.Status403Forbidden,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Có thao tác đồng thời. Hãy tải lại danh sách đơn và thử lại."
            });
        }
    }
    [HttpGet]
    public async Task<IActionResult> GetTrips(
    [FromQuery, Range(1, long.MaxValue)] long? id = null,
    [FromQuery, StringLength(100)] string? keyword = null,
    [FromQuery, StringLength(20)] string? status = null,
    [FromQuery, Range(1, int.MaxValue)] int? branchId = null,
    [FromQuery, Range(1, int.MaxValue)] int? warehouseId = null,
    [FromQuery, Range(1, long.MaxValue)] long? shipperId = null,
    [FromQuery, Range(1, long.MaxValue)] long? vehicleId = null,
    [FromQuery] DateOnly? fromDate = null,
    [FromQuery] DateOnly? toDate = null,
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
            "PLANNED",
        "ASSIGNED",
        "ACCEPTED",
        "IN_PROGRESS",
        "COMPLETED",
        "CANCELLED"
        ];

        if (fromDate > toDate || toDate == DateOnly.MaxValue)
            return BadRequest(new { message = "Khoảng ngày chuyến giao không hợp lệ." });

        if (status is not null && !allowedStatuses.Contains(status))
        {
            return BadRequest(new
            {
                message = "Trạng thái chuyến không hợp lệ.",
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
            @AccountBranchId INT,
            @OwnShipperId BIGINT;

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
            THROW 53801,
                N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                1;

        IF @Role = 'SHIPPER'
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vtq
                INNER JOIN dbo.Quyen q
                    ON q.MaQuyen = vtq.MaQuyen
                WHERE vtq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen = 'NHIEMVU_XEM'
            )
                THROW 53802,
                    N'Bạn không có quyền xem chuyến giao.',
                    1;

            SELECT @OwnShipperId = MaNhanVienGiaoHang
            FROM dbo.NhanVienGiaoHang
            WHERE MaTaiKhoan = @AccountId
              AND DangHoatDong = 1;

            IF @OwnShipperId IS NULL
                THROW 53802,
                    N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                    1;

            IF @Id IS NULL
               AND @ShipperId IS NOT NULL
               AND @ShipperId <> @OwnShipperId
                THROW 53802,
                    N'Bạn chỉ được xem chuyến của mình.',
                    1;
        END
        ELSE
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vtq
                INNER JOIN dbo.Quyen q
                    ON q.MaQuyen = vtq.MaQuyen
                WHERE vtq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen = 'DIEUPHOI_GIAMSAT'
            )
                THROW 53802,
                    N'Bạn không có quyền xem chuyến giao.',
                    1;

            IF @Role <> 'ADMIN'
               AND @AccountBranchId IS NULL
                THROW 53802,
                    N'Tài khoản chưa được gán bưu cục.',
                    1;

            IF @Id IS NULL
               AND @Role <> 'ADMIN'
               AND @BranchId IS NOT NULL
               AND @BranchId <> @AccountBranchId
                THROW 53802,
                    N'Bạn chỉ được xem chuyến thuộc bưu cục của mình.',
                    1;
        END;

        SELECT
            cg.MaChuyenGiao AS id,
            cg.KyHieuChuyenGiao AS tripCode,
            cg.MaBuuCuc AS branchId,
            b.TenBuuCuc AS branchName,
            cg.MaKho AS warehouseId,
            k.TenKho AS warehouseName,
            cg.MaNhanVienGiaoHang AS shipperId,
            shipper.HoTen AS shipperName,
            cg.MaPhuongTien AS vehicleId,
            pt.BienSo AS licensePlate,
            cg.TrangThaiChuyen AS status,
            cg.PhuongPhapToiUu AS optimizationMethod,
            cg.TongQuangDuongKm AS totalDistanceKm,
            cg.ThoiGianDuKienPhut AS estimatedDurationMinutes,
            cg.ThoiGianBatDauDuKien AS plannedStartAt,
            cg.ThoiGianBatDauThucTe AS startedAt,
            cg.ThoiGianKetThucThucTe AS endedAt,
            cg.MaTaiKhoanTao AS createdBy,
            creator.HoTen AS createdByName,
            cg.ThoiGianTao AS createdAt,
            (
                SELECT COUNT_BIG(*)
                FROM dbo.ChiTietChuyenGiao ct
                WHERE ct.MaChuyenGiao = cg.MaChuyenGiao
            ) AS orderCount,
            COALESCE((
                SELECT SUM(d.TongKhoiLuongKg)
                FROM dbo.ChiTietChuyenGiao ct
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = ct.MaDonHang
                WHERE ct.MaChuyenGiao = cg.MaChuyenGiao
            ), 0) AS totalWeightKg
        INTO #Trips
        FROM dbo.ChuyenGiaoHang cg
        INNER JOIN dbo.BuuCuc b
            ON b.MaBuuCuc = cg.MaBuuCuc
        INNER JOIN dbo.Kho k
            ON k.MaKho = cg.MaKho
        INNER JOIN dbo.TaiKhoan creator
            ON creator.MaTaiKhoan = cg.MaTaiKhoanTao
        LEFT JOIN dbo.NhanVienGiaoHang nv
            ON nv.MaNhanVienGiaoHang = cg.MaNhanVienGiaoHang
        LEFT JOIN dbo.TaiKhoan shipper
            ON shipper.MaTaiKhoan = nv.MaTaiKhoan
        LEFT JOIN dbo.PhuongTien pt
            ON pt.MaPhuongTien = cg.MaPhuongTien
        WHERE (
            (
                @Role = 'SHIPPER'
                AND cg.MaNhanVienGiaoHang = @OwnShipperId
            )
            OR (
                @Role <> 'SHIPPER'
                AND (
                    @Role = 'ADMIN'
                    OR cg.MaBuuCuc = @AccountBranchId
                )
            )
        )
          AND (
              @Id IS NULL
              OR cg.MaChuyenGiao = @Id
          )
          AND (
              @Id IS NOT NULL
              OR (
                  (
                      @BranchId IS NULL
                      OR cg.MaBuuCuc = @BranchId
                  )
                  AND (
                      @WarehouseId IS NULL
                      OR cg.MaKho = @WarehouseId
                  )
                  AND (
                      @ShipperId IS NULL
                      OR cg.MaNhanVienGiaoHang = @ShipperId
                  )
                  AND (@VehicleId IS NULL OR cg.MaPhuongTien = @VehicleId)
                  AND (@FromDate IS NULL OR COALESCE(cg.ThoiGianBatDauDuKien,cg.ThoiGianTao)>=DATEADD(HOUR,-7,CAST(@FromDate AS DATETIME2)))
                  AND (@ToDate IS NULL OR COALESCE(cg.ThoiGianBatDauDuKien,cg.ThoiGianTao)<DATEADD(HOUR,-7,DATEADD(DAY,1,CAST(@ToDate AS DATETIME2))))
                  AND (
                      @Status IS NULL
                      OR cg.TrangThaiChuyen = @Status
                  )
                  AND (
                      @Keyword IS NULL
                      OR CHARINDEX(@Keyword, cg.KyHieuChuyenGiao) > 0
                      OR CHARINDEX(@Keyword, shipper.HoTen) > 0
                      OR CHARINDEX(@Keyword, pt.BienSo) > 0
                  )
              )
          );

        IF @Id IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM #Trips)
                THROW 53803,
                    N'Không tìm thấy chuyến giao.',
                    1;

            SELECT (
                SELECT
                    t.*,
                    JSON_QUERY((
                        SELECT
                            d.MaDonHang AS orderId,
                            d.KyHieuDonHang AS orderCode,
                            d.MaVanDon AS trackingNumber,
                            tt.KyHieuTrangThai AS orderStatus,
                            ct.ThuTuDuKien AS sequence,
                            ct.ThoiGianDenDuKien AS plannedArrivalAt,
                            ct.ThoiGianDenThucTe AS arrivedAt,
                            d.TongKhoiLuongKg AS weightKg,
                            d.TienCOD AS codAmount,
                            gn.TenNguoiLienHe AS receiverName,
                            gn.SoDienThoaiLienHe AS receiverPhone,
                            gn.DiaChi AS deliveryAddress,
                            gn.MaKhuVuc AS deliveryAreaId,
                            gn.ViDo AS latitude,
                            gn.KinhDo AS longitude,
                            assignment.MaPhanCongGiaoHang
                                AS assignmentId,
                            assignment.TrangThaiPhanCong
                                AS assignmentStatus
                        FROM dbo.ChiTietChuyenGiao ct
                        INNER JOIN dbo.DonHang d
                            ON d.MaDonHang = ct.MaDonHang
                        INNER JOIN dbo.TrangThaiDonHang tt
                            ON tt.MaTrangThaiDonHang =
                               d.MaTrangThaiHienTai
                        LEFT JOIN dbo.DiemGiaoNhan gn
                            ON gn.MaDonHang = d.MaDonHang
                           AND gn.LoaiDiem = 'DELIVERY'
                        OUTER APPLY (
                            SELECT TOP (1)
                                pc.MaPhanCongGiaoHang,
                                pc.TrangThaiPhanCong
                            FROM dbo.PhanCongGiaoHang pc
                            WHERE pc.MaChuyenGiao = ct.MaChuyenGiao
                              AND pc.MaDonHang = ct.MaDonHang
                            ORDER BY pc.MaPhanCongGiaoHang DESC
                        ) assignment
                        WHERE ct.MaChuyenGiao = t.id
                        ORDER BY ct.ThuTuDuKien
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    )) AS orders,
                    JSON_QUERY((
                        SELECT
                            dd.MaDiemDung AS id,
                            dd.ThuTuDiemDung AS sequence,
                            dd.LoaiDiem AS type,
                            dd.MaDonHang AS orderId,
                            dd.MaDiemGiaoNhan AS deliveryPointId,
                            gn.TenNguoiLienHe AS contactName,
                            gn.SoDienThoaiLienHe AS phone,
                            gn.DiaChi AS address,
                            dd.ViDo AS latitude,
                            dd.KinhDo AS longitude,
                            dd.ThoiGianDenDuKien AS plannedArrivalAt,
                            dd.ThoiGianDenThucTe AS arrivedAt,
                            dd.KhoangCachTuDiemTruocKm
                                AS distanceFromPreviousKm,
                            dd.ThoiGianTuDiemTruocPhut
                                AS minutesFromPrevious
                        FROM dbo.DiemDungTuyen dd
                        LEFT JOIN dbo.DiemGiaoNhan gn
                            ON gn.MaDiemGiaoNhan =
                               dd.MaDiemGiaoNhan
                           AND gn.MaDonHang = dd.MaDonHang
                        WHERE dd.MaChuyenGiao = t.id
                        ORDER BY dd.ThuTuDiemDung
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    )) AS stops
                FROM #Trips t
                FOR JSON PATH,
                    INCLUDE_NULL_VALUES,
                    WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE
        BEGIN
            SELECT (
                SELECT
                    @Page AS page,
                    @PageSize AS pageSize,
                    (
                        SELECT COUNT_BIG(*) FROM #Trips
                    ) AS totalItems,
                    JSON_QUERY(COALESCE((
                        SELECT *
                        FROM #Trips
                        ORDER BY createdAt DESC, id DESC
                        OFFSET @Offset ROWS
                        FETCH NEXT @PageSize ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END;

        DROP TABLE #Trips;
        """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Id", SqlDbType.BigInt).Value =
                (object?)id ?? DBNull.Value;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;

        command.Parameters.Add(
            "@Status", SqlDbType.VarChar, 20).Value =
                (object?)status ?? DBNull.Value;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
                (object?)branchId ?? DBNull.Value;

        command.Parameters.Add(
            "@WarehouseId", SqlDbType.Int).Value =
                (object?)warehouseId ?? DBNull.Value;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value =
                (object?)shipperId ?? DBNull.Value;

        command.Parameters.Add("@VehicleId", SqlDbType.BigInt).Value = (object?)vehicleId ?? DBNull.Value;
        command.Parameters.Add("@FromDate", SqlDbType.Date).Value = fromDate.HasValue ? fromDate.Value.ToDateTime(TimeOnly.MinValue) : DBNull.Value;
        command.Parameters.Add("@ToDate", SqlDbType.Date).Value = toDate.HasValue ? toDate.Value.ToDateTime(TimeOnly.MinValue) : DBNull.Value;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value = pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.Int).Value =
                (page - 1) * pageSize;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 53801 and <= 53803)
        {
            var statusCode = ex.Number switch
            {
                53801 => StatusCodes.Status401Unauthorized,
                53802 => StatusCodes.Status403Forbidden,
                _ => StatusCodes.Status404NotFound
            };

            return StatusCode(statusCode, new { message = ex.Message });
        }
    }
    public class UpdateTripRequest
    {
        [Required]
        [MinLength(1)]
        [MaxLength(100)]
        public List<long> OrderIds { get; set; } = [];

        [Range(1, long.MaxValue)]
        public long? ShipperId { get; set; }

        [Range(1, long.MaxValue)]
        public long? VehicleId { get; set; }

        public DateTimeOffset? PlannedStartAt { get; set; }
    }
    [HttpPut("{id:long}")]
    public async Task<IActionResult> Update(
    long id,
    [FromBody] UpdateTripRequest request)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã chuyến không hợp lệ." });

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        if (request.OrderIds.Any(x => x <= 0)
            || request.OrderIds.Distinct().Count()
               != request.OrderIds.Count)
        {
            return BadRequest(new
            {
                message = "Mã đơn phải lớn hơn 0 và không được trùng."
            });
        }

        if (request.ShipperId.HasValue != request.VehicleId.HasValue)
        {
            return BadRequest(new
            {
                message = "Phải chọn cả shipper và phương tiện hoặc bỏ cả hai."
            });
        }

        DateTime? plannedStartAt = null;

        if (request.PlannedStartAt.HasValue)
        {
            var utc = request.PlannedStartAt.Value.UtcDateTime;

            plannedStartAt = new DateTime(
                utc.Ticks - utc.Ticks % TimeSpan.TicksPerSecond,
                DateTimeKind.Utc);

            if (plannedStartAt <= DateTime.UtcNow)
            {
                return BadRequest(new
                {
                    message = "Thời gian bắt đầu dự kiến phải nằm trong tương lai."
                });
            }
        }

        var orderIdsJson = JsonSerializer.Serialize(request.OrderIds);

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
                @BranchId INT,
                @WarehouseId INT,
                @TripStatus VARCHAR(20),
                @ShipperBranchId INT,
                @MaxWeight DECIMAL(10,2),
                @MaxVolume DECIMAL(10,3),
                @TotalWeight DECIMAL(28,3),
                @TotalVolume DECIMAL(28,6),
                @MissingDimensions INT,
                @OrderId BIGINT,
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
                THROW 53901,
                    N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vtq
                INNER JOIN dbo.Quyen q ON q.MaQuyen = vtq.MaQuyen
                WHERE vtq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen = 'DIEUPHOI_GOMDON'
            )
                THROW 53902,
                    N'Bạn không có quyền cập nhật chuyến.',
                    1;

            IF @ShipperId IS NOT NULL
               AND NOT EXISTS (
                   SELECT 1
                   FROM dbo.VaiTroQuyen vtq
                   INNER JOIN dbo.Quyen q ON q.MaQuyen = vtq.MaQuyen
                   WHERE vtq.MaVaiTro = @RoleId
                     AND q.KyHieuQuyen = 'DIEUPHOI_PHANCONG'
               )
                THROW 53902,
                    N'Bạn không có quyền phân công chuyến.',
                    1;

            IF @Role <> 'ADMIN' AND @AccountBranchId IS NULL
                THROW 53902,
                    N'Tài khoản chưa được gán bưu cục.',
                    1;

            SELECT
                @BranchId = MaBuuCuc,
                @WarehouseId = MaKho,
                @TripStatus = TrangThaiChuyen
            FROM dbo.ChuyenGiaoHang WITH (UPDLOCK, HOLDLOCK)
            WHERE MaChuyenGiao = @TripId
              AND (
                  @Role = 'ADMIN'
                  OR MaBuuCuc = @AccountBranchId
              );

            IF @BranchId IS NULL
                THROW 53903, N'Không tìm thấy chuyến giao.', 1;

            IF @TripStatus <> 'PLANNED'
                THROW 53904,
                    N'Chỉ chuyến PLANNED mới được sửa bằng API lập kế hoạch.',
                    1;

            IF EXISTS (
                SELECT 1
                FROM dbo.PhanCongGiaoHang
                WHERE MaChuyenGiao = @TripId
            )
                THROW 53904,
                    N'Chuyến đã có lịch sử phân công, không thể thay danh sách bằng API lập kế hoạch.',
                    1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.Kho k
                INNER JOIN dbo.BuuCuc b ON b.MaBuuCuc = k.MaBuuCuc
                WHERE k.MaKho = @WarehouseId
                  AND k.MaBuuCuc = @BranchId
                  AND k.DangHoatDong = 1
                  AND b.DangHoatDong = 1
            )
                THROW 53904, N'Kho hoặc bưu cục đã ngừng hoạt động.', 1;

            CREATE TABLE #Requested (
                orderId BIGINT NOT NULL PRIMARY KEY,
                sequence INT NOT NULL,
                processed BIT NOT NULL DEFAULT 0
            );

            INSERT INTO #Requested (orderId, sequence)
            SELECT
                CONVERT(BIGINT, [value]),
                CONVERT(INT, [key]) + 1
            FROM OPENJSON(@OrderIdsJson);

            -- Khóa cả đơn cũ và đơn mới của chuyến.
            SELECT
                d.MaDonHang AS orderId,
                d.MaBuuCuc AS branchId,
                d.MaKhoHienTai AS warehouseId,
                d.TongKhoiLuongKg AS weightKg,
                tt.KyHieuTrangThai AS orderStatus
            INTO #LockedOrders
            FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            WHERE EXISTS (
                SELECT 1 FROM #Requested x
                WHERE x.orderId = d.MaDonHang
            )
               OR EXISTS (
                SELECT 1 FROM dbo.ChiTietChuyenGiao ct
                WHERE ct.MaChuyenGiao = @TripId
                  AND ct.MaDonHang = d.MaDonHang
            );

            IF EXISTS (
                SELECT 1
                FROM #Requested x
                LEFT JOIN #LockedOrders d ON d.orderId = x.orderId
                WHERE d.orderId IS NULL
                   OR d.branchId <> @BranchId
                   OR d.warehouseId IS NULL
                   OR d.warehouseId <> @WarehouseId
                   OR d.orderStatus <> 'WAITING_ASSIGNMENT'
                   OR d.weightKg <= 0
            )
                THROW 53904,
                    N'Có đơn không hợp lệ. Đơn phải WAITING_ASSIGNMENT và nằm tại kho của chuyến.',
                    1;

            IF EXISTS (
                SELECT 1
                FROM #Requested x
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM dbo.TonKhoDonHang t WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.ViTriLuuKho v
                        ON v.MaViTriLuuKho = t.MaViTriLuuKho
                       AND v.MaKho = t.MaKho
                    WHERE t.MaDonHang = x.orderId
                      AND t.MaKho = @WarehouseId
                      AND t.TrangThaiTonKho = 'STORED'
                      AND v.DangHoatDong = 1
                )
            )
                THROW 53904, N'Có đơn không còn tồn kho phù hợp.', 1;

            IF EXISTS (
                SELECT 1
                FROM dbo.PhanCongGiaoHang pc WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN #Requested x ON x.orderId = pc.MaDonHang
                WHERE pc.ThoiGianKetThuc IS NULL
            )
                THROW 53904, N'Có đơn đã được phân công riêng.', 1;

            IF EXISTS (
                SELECT 1
                FROM dbo.ChiTietChuyenGiao ct
                INNER JOIN dbo.ChuyenGiaoHang cg
                    ON cg.MaChuyenGiao = ct.MaChuyenGiao
                INNER JOIN #Requested x ON x.orderId = ct.MaDonHang
                WHERE ct.MaChuyenGiao <> @TripId
                  AND cg.TrangThaiChuyen NOT IN ('COMPLETED', 'CANCELLED')
            )
                THROW 53904, N'Có đơn thuộc chuyến khác chưa kết thúc.', 1;

            SELECT
                gn.MaDonHang AS orderId,
                gn.MaDiemGiaoNhan AS pointId,
                gn.MaKhuVuc AS areaId,
                gn.ViDo AS latitude,
                gn.KinhDo AS longitude
            INTO #DeliveryPoints
            FROM dbo.DiemGiaoNhan gn
            INNER JOIN #Requested x ON x.orderId = gn.MaDonHang
            WHERE gn.LoaiDiem = 'DELIVERY';

            IF (
                SELECT COUNT(*) FROM #DeliveryPoints
            ) <> (
                SELECT COUNT(*) FROM #Requested
            )
               OR EXISTS (
                   SELECT 1 FROM #DeliveryPoints
                   WHERE latitude IS NULL OR longitude IS NULL
               )
                THROW 53905,
                    N'Mỗi đơn phải có điểm giao và đủ tọa độ để lập tuyến.',
                    1;

            SET @OldJson = (
                SELECT
                    cg.MaChuyenGiao AS id,
                    cg.TrangThaiChuyen AS status,
                    cg.ThoiGianBatDauDuKien AS plannedStartAt,
                    JSON_QUERY((
                        SELECT MaDonHang AS orderId, ThuTuDuKien AS sequence
                        FROM dbo.ChiTietChuyenGiao
                        WHERE MaChuyenGiao = @TripId
                        ORDER BY ThuTuDuKien
                        FOR JSON PATH
                    )) AS orders
                FROM dbo.ChuyenGiaoHang cg
                WHERE cg.MaChuyenGiao = @TripId
                FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
            );

            IF @ShipperId IS NOT NULL
            BEGIN
                SELECT @ShipperBranchId = tk.MaBuuCuc
                FROM dbo.NhanVienGiaoHang nv WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan = nv.MaTaiKhoan
                INNER JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                WHERE nv.MaNhanVienGiaoHang = @ShipperId
                  AND nv.DangHoatDong = 1
                  AND nv.TrangThaiSanSang IN ('AVAILABLE', 'DELIVERING')
                  AND (
                      nv.NgayHetHanBangLai IS NULL
                      OR nv.NgayHetHanBangLai >= {{VietnamDate.SqlDate("@Now")}}
                  )
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= @Now)
                  AND vt.KyHieuVaiTro = 'SHIPPER'
                  AND vt.DangHoatDong = 1;

                IF @ShipperBranchId IS NULL OR @ShipperBranchId <> @BranchId
                    THROW 53904, N'Shipper không phù hợp với chuyến.', 1;

                IF EXISTS (
                    SELECT 1
                    FROM #DeliveryPoints p
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM dbo.KhuVucNhanVienGiaoHang kv
                        INNER JOIN dbo.KhuVuc area
                            ON area.MaKhuVuc = kv.MaKhuVuc
                           AND area.DangHoatDong = 1
                        WHERE kv.MaNhanVienGiaoHang = @ShipperId
                          AND kv.MaKhuVuc = p.areaId
                    )
                )
                    THROW 53904,
                        N'Shipper phải phụ trách khu vực giao của tất cả đơn.',
                        1;

                SELECT
                    @MaxWeight = KhoiLuongDenKg,
                    @MaxVolume = TheTichToiDaM3
                FROM dbo.PhuongTien WITH (UPDLOCK, HOLDLOCK)
                WHERE MaPhuongTien = @VehicleId
                  AND DangHoatDong = 1
                  AND TrangThaiPhuongTien IN ('AVAILABLE', 'IN_USE');

                IF @MaxWeight IS NULL
                    THROW 53904, N'Phương tiện không phù hợp.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongPhuongTien WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaNhanVienGiaoHang = @ShipperId
                      AND MaPhuongTien = @VehicleId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 53904,
                        N'Xe chưa được phân cho shipper đã chọn.',
                        1;

                SELECT MaDonHang AS orderId
                INTO #VehicleOrders
                FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaPhuongTien = @VehicleId
                  AND ThoiGianKetThuc IS NULL;

                INSERT INTO #VehicleOrders (orderId)
                SELECT held.MaDonHang FROM ({{DeferredReturnSql.HeldOrders(true)}}) held
                WHERE held.MaPhuongTien=@VehicleId
                  AND NOT EXISTS (SELECT 1 FROM #VehicleOrders x WHERE x.orderId=held.MaDonHang);

                INSERT INTO #VehicleOrders (orderId)
                SELECT orderId FROM #Requested;

                SELECT @TotalWeight = SUM(d.TongKhoiLuongKg)
                FROM #VehicleOrders x
                INNER JOIN dbo.DonHang d ON d.MaDonHang = x.orderId;

                IF @TotalWeight > @MaxWeight
                    THROW 53904, N'Tổng đơn đang phân công vượt tải trọng xe.', 1;

                IF @MaxVolume IS NOT NULL
                BEGIN
                    SELECT
                        @MissingDimensions = COALESCE(MAX(
                            CASE WHEN ct.ChieuDaiCm IS NULL
                                   OR ct.ChieuRongCm IS NULL
                                   OR ct.ChieuCaoCm IS NULL
                                 THEN 1 ELSE 0 END
                        ), 0),
                        @TotalVolume = COALESCE(SUM(
                            CAST(ct.SoLuong AS DECIMAL(18,6))
                            * ct.ChieuDaiCm * ct.ChieuRongCm
                            * ct.ChieuCaoCm / 1000000.0
                        ), 0)
                    FROM #VehicleOrders x
                    INNER JOIN dbo.ChiTietDonHang ct ON ct.MaDonHang = x.orderId;

                    IF @MissingDimensions = 1
                        THROW 53905, N'Cần đủ kích thước hàng để kiểm tra xe.', 1;

                    IF @TotalVolume > @MaxVolume
                        THROW 53904, N'Tổng thể tích hàng vượt sức chứa xe.', 1;
                END;

                DROP TABLE #VehicleOrders;
            END;

            SET @Now = SYSUTCDATETIME();

            IF @PlannedStartAt IS NOT NULL AND @PlannedStartAt <= @Now
                THROW 53904, N'Thời gian bắt đầu dự kiến đã qua.', 1;

            -- Chuyến PLANNED chưa có phân công nên có thể
            -- thay toàn bộ danh sách và tuyến.
            DELETE FROM dbo.DiemDungTuyen WHERE MaChuyenGiao = @TripId;
            IF OBJECT_ID('dbo.TripRouteGeometry','U') IS NOT NULL
                EXEC sp_executesql N'DELETE dbo.TripRouteGeometry WHERE TripId=@t',N'@t BIGINT',@t=@TripId;
            DELETE FROM dbo.ChiTietChuyenGiao WHERE MaChuyenGiao = @TripId;

            INSERT INTO dbo.ChiTietChuyenGiao (
                MaChuyenGiao, MaDonHang, ThuTuDuKien
            )
            SELECT @TripId, orderId, sequence FROM #Requested;

            INSERT INTO dbo.DiemDungTuyen (
                MaChuyenGiao, MaDonHang, MaDiemGiaoNhan,
                ThuTuDiemDung, LoaiDiem, ViDo, KinhDo
            )
            SELECT
                @TripId, x.orderId, p.pointId,
                x.sequence, 'DELIVERY', p.latitude, p.longitude
            FROM #Requested x
            INNER JOIN #DeliveryPoints p ON p.orderId = x.orderId;

            UPDATE dbo.ChuyenGiaoHang
            SET MaNhanVienGiaoHang = @ShipperId,
                MaPhuongTien = @VehicleId,
                TrangThaiChuyen =
                    CASE WHEN @ShipperId IS NULL
                         THEN 'PLANNED' ELSE 'ASSIGNED' END,
                PhuongPhapToiUu = 'MANUAL',
                TongQuangDuongKm = NULL,
                ThoiGianDuKienPhut = NULL,
                ThoiGianBatDauDuKien = @PlannedStartAt
            WHERE MaChuyenGiao = @TripId;

            IF @ShipperId IS NOT NULL
            BEGIN
                INSERT INTO dbo.PhanCongGiaoHang (
                    MaDonHang, MaChuyenGiao,
                    MaNhanVienGiaoHang, MaPhuongTien,
                    MaTaiKhoanPhanCong, ThoiGianPhanCong,
                    TrangThaiPhanCong, BoQuaQuyTacKhuVuc
                )
                SELECT
                    orderId, @TripId, @ShipperId, @VehicleId,
                    @AccountId, @Now, 'PENDING', 0
                FROM #Requested;

                WHILE EXISTS (SELECT 1 FROM #Requested WHERE processed = 0)
                BEGIN
                    SELECT TOP (1) @OrderId = orderId
                    FROM #Requested WHERE processed = 0 ORDER BY orderId;

                    EXEC dbo.sp_ChuyenTrangThaiDonHang
                        @MaDonHang = @OrderId,
                        @KyHieuTrangThaiMoi = 'ASSIGNED',
                        @MaTaiKhoan = @AccountId,
                        @LyDo = N'Phân công theo chuyến giao.',
                        @NguonCapNhat = 'API';

                    UPDATE #Requested SET processed = 1 WHERE orderId = @OrderId;
                END;
            END;

            SET @Result = (
                SELECT
                    cg.MaChuyenGiao AS id,
                    cg.KyHieuChuyenGiao AS tripCode,
                    cg.TrangThaiChuyen AS status,
                    cg.MaNhanVienGiaoHang AS shipperId,
                    cg.MaPhuongTien AS vehicleId,
                    cg.PhuongPhapToiUu AS optimizationMethod,
                    cg.ThoiGianBatDauDuKien AS plannedStartAt,
                    JSON_QUERY((
                        SELECT
                            x.orderId, x.sequence,
                            pc.MaPhanCongGiaoHang AS assignmentId,
                            pc.TrangThaiPhanCong AS assignmentStatus
                        FROM #Requested x
                        LEFT JOIN dbo.PhanCongGiaoHang pc
                            ON pc.MaChuyenGiao = @TripId
                           AND pc.MaDonHang = x.orderId
                           AND pc.ThoiGianKetThuc IS NULL
                        ORDER BY x.sequence
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    )) AS orders,
                    N'Đã cập nhật chuyến giao.' AS message
                FROM dbo.ChuyenGiaoHang cg
                WHERE cg.MaChuyenGiao = @TripId
                FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO dbo.NhatKyHoatDong (
                MaTaiKhoan, LoaiThaoTac, TenDoiTuong,
                MaDoiTuong, DuLieuCuJson, DuLieuMoiJson
            )
            VALUES (
                @AccountId, 'UPDATE_TRIP', 'ChuyenGiaoHang',
                CONVERT(VARCHAR(100), @TripId), @OldJson, @Result
            );

            DROP TABLE #DeliveryPoints;
            DROP TABLE #LockedOrders;
            DROP TABLE #Requested;

            COMMIT;

            SELECT @Result;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK;
            THROW;
        END CATCH;
        """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@TripId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@OrderIdsJson", SqlDbType.NVarChar, -1).Value = orderIdsJson;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value =
                (object?)request.ShipperId ?? DBNull.Value;

        command.Parameters.Add(
            "@VehicleId", SqlDbType.BigInt).Value =
                (object?)request.VehicleId ?? DBNull.Value;

        var plannedParameter = command.Parameters.Add(
            "@PlannedStartAt", SqlDbType.DateTime2);
        plannedParameter.Scale = 0;
        plannedParameter.Value = (object?)plannedStartAt ?? DBNull.Value;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();
            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            (ex.Number is >= 53901 and <= 53905)
            || (ex.Number is >= 51030 and <= 51035)
            || ex.Number is 51043 or 51044 or 51050 or 51051)
        {
            var statusCode = ex.Number switch
            {
                53901 => StatusCodes.Status401Unauthorized,
                53902 => StatusCodes.Status403Forbidden,
                53903 => StatusCodes.Status404NotFound,
                53905 => StatusCodes.Status422UnprocessableEntity,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number is 1205 or 2601 or 2627)
        {
            return Conflict(new
            {
                message = "Dữ liệu chuyến đang thay đổi. Hãy tải lại và thử lại."
            });
        }
    }
}
