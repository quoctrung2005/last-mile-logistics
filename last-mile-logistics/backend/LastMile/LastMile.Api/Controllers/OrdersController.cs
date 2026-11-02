using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/v1/orders")]
public partial class OrdersController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public OrdersController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    private SqlConnection CreateConnection()
    {
        return new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
    }

    private async Task<(bool IsAdmin, int? BranchId)?> GetScope(
        SqlConnection connection,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return null;
        }

        const string sql = """
            SELECT
                vt.KyHieuVaiTro,
                tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
            INNER JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
              )
              AND EXISTS (
                  SELECT 1
                  FROM dbo.VaiTroQuyen vq
                  INNER JOIN dbo.Quyen q
                      ON q.MaQuyen = vq.MaQuyen
                  WHERE vq.MaVaiTro = tk.MaVaiTro
                    AND q.KyHieuQuyen = 'DONHANG_XEM'
              );
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt
        ).Value = accountId;

        await using var reader =
            await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
            return null;

        var isAdmin =
            reader["KyHieuVaiTro"].ToString() == "ADMIN";

        int? branchId = reader["MaBuuCuc"] == DBNull.Value
            ? null
            : Convert.ToInt32(reader["MaBuuCuc"]);

        if (!isAdmin && branchId is null)
            return null;

        return (isAdmin, branchId);
    }

    private static void AddScopeParameters(
        SqlCommand command,
        bool isAdmin,
        int? branchId)
    {
        command.Parameters.Add(
            "@IsAdmin", SqlDbType.Bit
        ).Value = isAdmin;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int
        ).Value = (object?)branchId ?? DBNull.Value;
    }

    [HttpGet]
    public async Task<IActionResult> GetOrders(
        [FromQuery] string? keyword = null,
        [FromQuery] string? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] int? warehouseId = null,
        [FromQuery] bool inboundOnly = false,
        [FromQuery] int? branchId = null,
        [FromQuery] long? shipperId = null,
        [FromQuery] string? statusGroup = null,
        [FromQuery] DateOnly? fromDate = null,
        [FromQuery] DateOnly? toDate = null,
        [FromQuery] string? operationalGroup = null,
        CancellationToken cancellationToken = default)
    {
        if (operationalGroup is not null
            && !OperationalOrderQuery.Groups.Contains(operationalGroup))
        {
            return BadRequest(new
            {
                message = "Nhóm công việc tổng quan không hợp lệ."
            });
        }

        if (page < 1 || page > 100000
            || pageSize < 1 || pageSize > 100)
        {
            return BadRequest(new
            {
                message = "page từ 1–100000; pageSize từ 1–100."
            });
        }

        keyword = string.IsNullOrWhiteSpace(keyword)
            ? null
            : keyword.Trim();

        status = string.IsNullOrWhiteSpace(status)
            ? null
            : status.Trim().ToUpperInvariant();

        statusGroup = string.IsNullOrWhiteSpace(statusGroup)
            ? null
            : statusGroup.Trim().ToUpperInvariant();

        if (keyword?.Length > 100 || status?.Length > 40)
        {
            return BadRequest(new
            {
                message = "Từ khóa tối đa 100 ký tự; trạng thái tối đa 40."
            });
        }

        if (warehouseId is <= 0)
        {
            return BadRequest(new
            {
                message = "warehouseId phải lớn hơn 0."
            });
        }

        if (inboundOnly && warehouseId is null)
        {
            return BadRequest(new
            {
                message = "Hãy chọn kho để xem đơn có thể nhập kho."
            });
        }

        if (inboundOnly
            && status is not null
            && status is not ("CONFIRMED" or "WAITING_INBOUND"))
        {
            return BadRequest(new
            {
                message = "Nhập kho chỉ áp dụng trạng thái CONFIRMED hoặc WAITING_INBOUND."
            });
        }

        if (branchId is <= 0
            || shipperId is <= 0
            || (statusGroup is not null
                && statusGroup is not ("PROGRESS" or "ATTENTION" or "DONE"))
            || (fromDate.HasValue
                && toDate.HasValue
                && fromDate > toDate)
            || fromDate < new DateOnly(1, 1, 2)
            || toDate < new DateOnly(1, 1, 2)
            || toDate > new DateOnly(9999, 12, 30))
        {
            return BadRequest(new
            {
                message = "Bộ lọc theo dõi không hợp lệ."
            });
        }

        await using var connection = CreateConnection();
        await connection.OpenAsync(cancellationToken);

        var scope = await GetScope(connection, cancellationToken);

        if (scope is null)
            return Forbid();

        if (!scope.Value.IsAdmin
            && branchId.HasValue
            && branchId != scope.Value.BranchId)
        {
            return Forbid();
        }

        int? warehouseBranchId = null;

        if (warehouseId.HasValue)
        {
            const string warehouseSql = """
                SELECT k.MaBuuCuc
                FROM dbo.Kho k
                INNER JOIN dbo.BuuCuc bc
                    ON bc.MaBuuCuc = k.MaBuuCuc
                WHERE k.MaKho = @WarehouseId
                  AND k.DangHoatDong = 1
                  AND bc.DangHoatDong = 1
                  AND (
                      @IsAdmin = 1
                      OR k.MaBuuCuc = @BranchId
                  );
                """;

            await using var warehouseCommand =
                new SqlCommand(warehouseSql, connection);

            AddScopeParameters(
                warehouseCommand,
                scope.Value.IsAdmin,
                scope.Value.BranchId);

            warehouseCommand.Parameters.Add(
                "@WarehouseId", SqlDbType.Int
            ).Value = warehouseId.Value;

            var branch = await warehouseCommand.ExecuteScalarAsync(
                cancellationToken);

            if (branch is null || branch == DBNull.Value)
            {
                return NotFound(new
                {
                    message = "Không tìm thấy kho hoạt động trong phạm vi tài khoản."
                });
            }

            warehouseBranchId = Convert.ToInt32(branch);
        }

        var sql = $$"""
            SET NOCOUNT ON;

            SELECT
                d.MaDonHang AS id,
                d.PhienBan AS version,
                d.KyHieuDonHang AS orderCode,
                d.MaVanDon AS trackingNumber,
                d.MaBuuCuc AS branchId,
                bc.TenBuuCuc AS branchName,
                ng.HoTen AS senderName,
                nn.HoTen AS receiverName,
                tt.KyHieuTrangThai AS status,
                tt.TenTrangThai AS statusName,
                d.TongKhoiLuongKg AS weightKg,
                d.TienCOD AS codAmount,
                d.PhiVanChuyen AS shippingFee,
                d.ThoiGianYeuCauGiao AS requestedDeliveryAt,
                d.ThoiGianDuKienGiao AS expectedDeliveryAt,
                d.ThoiGianTao AS createdAt,
                COALESCE(
                    d.ThoiGianCapNhat,
                    d.ThoiGianTao
                ) AS updatedAt,
                delivery.DiaChi AS deliveryAddress,
                currentAssignment.MaNhanVienGiaoHang AS shipperId,
                currentShipper.HoTen AS shipperName
            INTO #FilteredOrders
            FROM dbo.DonHang d
            INNER JOIN dbo.TrangThaiDonHang tt
                ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
            INNER JOIN dbo.BuuCuc bc
                ON bc.MaBuuCuc = d.MaBuuCuc
            INNER JOIN dbo.KhachHang ng
                ON ng.MaKhachHang = d.MaNguoiGui
            INNER JOIN dbo.KhachHang nn
                ON nn.MaKhachHang = d.MaNguoiNhan
            OUTER APPLY (
                SELECT TOP (1)
                    p.DiaChi
                FROM dbo.DiemGiaoNhan p
                WHERE p.MaDonHang = d.MaDonHang
                  AND p.LoaiDiem = 'DELIVERY'
                ORDER BY p.MaDiemGiaoNhan
            ) delivery
            OUTER APPLY (
                SELECT TOP (1)
                    pc.MaNhanVienGiaoHang
                FROM dbo.PhanCongGiaoHang pc
                WHERE pc.MaDonHang = d.MaDonHang
                  AND pc.ThoiGianKetThuc IS NULL
                  AND pc.TrangThaiPhanCong IN (
                      'PENDING',
                      'ACCEPTED',
                      'IN_PROGRESS'
                  )
                ORDER BY pc.MaPhanCongGiaoHang DESC
            ) currentAssignment
            LEFT JOIN dbo.NhanVienGiaoHang currentEmployee
                ON currentEmployee.MaNhanVienGiaoHang
                    = currentAssignment.MaNhanVienGiaoHang
            LEFT JOIN dbo.TaiKhoan currentShipper
                ON currentShipper.MaTaiKhoan
                    = currentEmployee.MaTaiKhoan
            WHERE (@IsAdmin = 1 OR d.MaBuuCuc = @BranchId)
              AND {{OperationalOrderQuery.FilterSql}}
              AND (
                  @FilterBranchId IS NULL
                  OR d.MaBuuCuc = @FilterBranchId
              )
              AND (
                  @ShipperId IS NULL
                  OR currentAssignment.MaNhanVienGiaoHang = @ShipperId
              )
              AND (
                  @FromDate IS NULL
                  OR COALESCE(
                      d.ThoiGianCapNhat,
                      d.ThoiGianTao
                  ) >= @FromDate
              )
              AND (
                  @ToDate IS NULL
                  OR COALESCE(
                      d.ThoiGianCapNhat,
                      d.ThoiGianTao
                  ) < @ToDate
              )
              AND (
                  @StatusGroup IS NULL
                  OR (
                      @StatusGroup = 'PROGRESS'
                      AND tt.KyHieuTrangThai IN (
                          'ASSIGNED',
                          'HANDED_OVER',
                          'EN_ROUTE_PICKUP',
                          'PICKED_UP',
                          'IN_DELIVERY'
                      )
                  )
                  OR (
                      @StatusGroup = 'ATTENTION'
                      AND tt.KyHieuTrangThai IN (
                          'FAILED',
                          'RETRY_WAITING',
                          'RETURNING'
                      )
                  )
                  OR (
                      @StatusGroup = 'DONE'
                      AND tt.KyHieuTrangThai IN (
                          'DELIVERED',
                          'COMPLETED',
                          'RETURNED',
                          'CANCELLED'
                      )
                  )
              )
              AND (
                  @WarehouseBranchId IS NULL
                  OR d.MaBuuCuc = @WarehouseBranchId
              )
              AND (
                  @InboundOnly = 0
                  OR (
                      tt.KyHieuTrangThai IN (
                          'CONFIRMED',
                          'WAITING_INBOUND'
                      )
                      AND d.MaKhoHienTai IS NULL
                      AND NOT EXISTS (
                          SELECT 1
                          FROM dbo.TonKhoDonHang stock
                          WHERE stock.MaDonHang = d.MaDonHang
                      )
                  )
              )
              AND (
                  @Status IS NULL
                  OR tt.KyHieuTrangThai = @Status
              )
              AND (
                  @Keyword IS NULL
                  OR CHARINDEX(@Keyword, d.MaVanDon) > 0
                  OR CHARINDEX(@Keyword, d.KyHieuDonHang) > 0
              );

            SELECT (
                SELECT
                    @Page AS page,
                    @PageSize AS pageSize,
                    (
                        SELECT COUNT_BIG(*)
                        FROM #FilteredOrders
                    ) AS totalItems,
                    JSON_QUERY(COALESCE((
                        SELECT
                            f.id,
                            f.version,
                            f.orderCode,
                            f.trackingNumber,
                            f.branchId,
                            f.branchName,
                            f.senderName,
                            f.receiverName,
                            f.status,
                            f.statusName,
                            f.weightKg,
                            f.codAmount,
                            f.shippingFee,

                            CASE
                                WHEN f.requestedDeliveryAt IS NULL
                                THEN NULL
                                ELSE CONVERT(
                                    VARCHAR(33),
                                    f.requestedDeliveryAt,
                                    126
                                ) + 'Z'
                            END AS requestedDeliveryAt,

                            CASE
                                WHEN f.expectedDeliveryAt IS NULL
                                THEN NULL
                                ELSE CONVERT(
                                    VARCHAR(33),
                                    f.expectedDeliveryAt,
                                    126
                                ) + 'Z'
                            END AS expectedDeliveryAt,

                            CASE
                                WHEN f.createdAt IS NULL
                                THEN NULL
                                ELSE CONVERT(
                                    VARCHAR(33),
                                    f.createdAt,
                                    126
                                ) + 'Z'
                            END AS createdAt,

                            CASE
                                WHEN f.updatedAt IS NULL
                                THEN NULL
                                ELSE CONVERT(
                                    VARCHAR(33),
                                    f.updatedAt,
                                    126
                                ) + 'Z'
                            END AS updatedAt,

                            f.deliveryAddress,
                            f.shipperId,
                            f.shipperName
                        FROM #FilteredOrders f
                        ORDER BY
                            CASE
                                WHEN @StatusGroup IS NOT NULL
                                THEN f.updatedAt
                                ELSE f.createdAt
                            END DESC,
                            f.id DESC
                        OFFSET @Offset ROWS
                        FETCH NEXT @PageSize ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            DROP TABLE #FilteredOrders;
            """;

        await using var command = new SqlCommand(sql, connection);

        AddScopeParameters(
            command,
            scope.Value.IsAdmin,
            scope.Value.BranchId);

        command.Parameters.Add(
            "@FilterBranchId", SqlDbType.Int
        ).Value = (object?)branchId ?? DBNull.Value;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt
        ).Value = (object?)shipperId ?? DBNull.Value;

        command.Parameters.Add(
            "@StatusGroup", SqlDbType.VarChar, 20
        ).Value = (object?)statusGroup ?? DBNull.Value;

        // Bộ lọc ngày được hiểu theo giờ Việt Nam (UTC+7).
        // Database lưu UTC nên chuyển mốc lọc về UTC.
        command.Parameters.Add(
            "@FromDate", SqlDbType.DateTime2
        ).Value = fromDate.HasValue
            ? fromDate.Value
                .ToDateTime(TimeOnly.MinValue)
                .AddHours(-7)
            : DBNull.Value;

        command.Parameters.Add(
            "@ToDate", SqlDbType.DateTime2
        ).Value = toDate.HasValue
            ? toDate.Value
                .AddDays(1)
                .ToDateTime(TimeOnly.MinValue)
                .AddHours(-7)
            : DBNull.Value;

        command.Parameters.Add(
            "@WarehouseBranchId", SqlDbType.Int
        ).Value = (object?)warehouseBranchId ?? DBNull.Value;

        command.Parameters.Add(
            "@InboundOnly", SqlDbType.Bit
        ).Value = inboundOnly;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100
        ).Value = (object?)keyword ?? DBNull.Value;

        command.Parameters.Add(
            "@OperationalGroup", SqlDbType.VarChar, 30
        ).Value = (object?)operationalGroup ?? DBNull.Value;

        command.Parameters.Add(
            "@Status", SqlDbType.VarChar, 40
        ).Value = (object?)status ?? DBNull.Value;

        command.Parameters.Add(
            "@Page", SqlDbType.Int
        ).Value = page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int
        ).Value = pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.Int
        ).Value = (page - 1) * pageSize;

        var json = await command.ExecuteScalarAsync(
            cancellationToken) as string;

        if (string.IsNullOrWhiteSpace(json))
        {
            return StatusCode(500, new
            {
                message = "Không đọc được danh sách đơn hàng."
            });
        }

        return Content(json, "application/json");
    }

    [HttpGet("{id:long}")]
    public async Task<IActionResult> GetOrder(
        long id,
        CancellationToken cancellationToken,
        [FromQuery] bool tracking = false)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã đơn phải lớn hơn 0."
            });
        }

        await using var connection = CreateConnection();
        await connection.OpenAsync(cancellationToken);

        var scope = await GetScope(connection, cancellationToken);

        if (scope is null)
            return Forbid();

        const string sql = """
            SET NOCOUNT ON;

            SELECT (
                SELECT
                    d.MaDonHang AS id,
                    d.PhienBan AS version,
                    d.KyHieuDonHang AS orderCode,
                    d.MaVanDon AS trackingNumber,

                    d.MaBuuCuc AS branchId,
                    bc.TenBuuCuc AS branchName,

                    d.MaNguoiGui AS senderId,
                    ng.HoTen AS senderName,

                    d.MaNguoiNhan AS receiverId,
                    nn.HoTen AS receiverName,

                    d.MaLoaiDichVu AS serviceId,
                    dv.TenDichVu AS serviceName,

                    pickupAddress.addressId AS pickupAddressId,
                    deliveryAddress.addressId AS deliveryAddressId,

                    CAST(
                        CASE
                            WHEN pickupAddress.addressId IS NULL
                              OR deliveryAddress.addressId IS NULL
                            THEN 1
                            ELSE 0
                        END AS BIT
                    ) AS requiresAddressSelection,

                    tt.KyHieuTrangThai AS status,
                    tt.TenTrangThai AS statusName,
                    d.MaKhoHienTai AS warehouseId,
                    d.MucDoUuTien AS priority,
                    d.TongKhoiLuongKg AS weightKg,
                    d.GiaTriKhaiBao AS declaredValue,
                    d.TienCOD AS codAmount,
                    d.PhiVanChuyen AS shippingFee,
                    d.GhiChuDacBiet AS notes,

                    CASE
                        WHEN d.ThoiGianYeuCauGiao IS NULL
                        THEN NULL
                        ELSE CONVERT(
                            VARCHAR(33),
                            d.ThoiGianYeuCauGiao,
                            126
                        ) + 'Z'
                    END AS requestedDeliveryAt,

                    CASE
                        WHEN d.ThoiGianDuKienGiao IS NULL
                        THEN NULL
                        ELSE CONVERT(
                            VARCHAR(33),
                            d.ThoiGianDuKienGiao,
                            126
                        ) + 'Z'
                    END AS expectedDeliveryAt,

                    CASE
                        WHEN d.ThoiGianTao IS NULL
                        THEN NULL
                        ELSE CONVERT(
                            VARCHAR(33),
                            d.ThoiGianTao,
                            126
                        ) + 'Z'
                    END AS createdAt,

                    CASE
                        WHEN d.ThoiGianCapNhat IS NULL
                        THEN NULL
                        ELSE CONVERT(
                            VARCHAR(33),
                            d.ThoiGianCapNhat,
                            126
                        ) + 'Z'
                    END AS updatedAt,

                    JSON_QUERY(COALESCE((
                        SELECT
                            p.MaDiemGiaoNhan AS id,
                            p.LoaiDiem AS type,
                            p.TenNguoiLienHe AS contactName,
                            p.SoDienThoaiLienHe AS phone,
                            p.DiaChi AS address,
                            p.MaKhuVuc AS areaId,
                            p.ViDo AS latitude,
                            p.KinhDo AS longitude,
                            p.GhiChu AS notes
                        FROM dbo.DiemGiaoNhan p
                        WHERE p.MaDonHang = d.MaDonHang
                        ORDER BY
                            CASE
                                WHEN p.LoaiDiem = 'PICKUP' THEN 0
                                ELSE 1
                            END,
                            p.MaDiemGiaoNhan
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS deliveryPoints,

                    JSON_QUERY(COALESCE((
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
                    ), N'[]')) AS items,

                    JSON_QUERY(COALESCE((
                        SELECT
                            kp.MaKhoanPhi AS id,
                            kp.LoaiKhoanPhi AS type,
                            kp.SoTien AS amount,
                            kp.MoTa AS description
                        FROM dbo.KhoanPhiDonHang kp
                        WHERE kp.MaDonHang = d.MaDonHang
                        ORDER BY kp.MaKhoanPhi
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS fees,

                    JSON_QUERY(COALESCE((
                        SELECT
                            ls.MaLichSuTrangThai AS id,
                            cu.KyHieuTrangThai AS previousStatus,
                            moi.KyHieuTrangThai AS newStatus,
                            ls.MaTaiKhoanThayDoi AS changedBy,
                            actor.HoTen AS changedByName,

                            CASE
                                WHEN ls.ThoiGianThayDoi IS NULL
                                THEN NULL
                                ELSE CONVERT(
                                    VARCHAR(33),
                                    ls.ThoiGianThayDoi,
                                    126
                                ) + 'Z'
                            END AS changedAt,

                            ls.LyDo AS reason,
                            ls.NguonCapNhat AS source
                        FROM dbo.LichSuTrangThaiDonHang ls
                        LEFT JOIN dbo.TrangThaiDonHang cu
                            ON cu.MaTrangThaiDonHang = ls.MaTrangThaiCu
                        INNER JOIN dbo.TrangThaiDonHang moi
                            ON moi.MaTrangThaiDonHang = ls.MaTrangThaiMoi
                        LEFT JOIN dbo.TaiKhoan actor
                            ON actor.MaTaiKhoan = ls.MaTaiKhoanThayDoi
                        WHERE ls.MaDonHang = d.MaDonHang
                        ORDER BY
                            ls.ThoiGianThayDoi DESC,
                            ls.MaLichSuTrangThai DESC
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')) AS statusHistory

                FROM dbo.DonHang d
                INNER JOIN dbo.BuuCuc bc
                    ON bc.MaBuuCuc = d.MaBuuCuc
                INNER JOIN dbo.KhachHang ng
                    ON ng.MaKhachHang = d.MaNguoiGui
                INNER JOIN dbo.KhachHang nn
                    ON nn.MaKhachHang = d.MaNguoiNhan
                INNER JOIN dbo.LoaiDichVu dv
                    ON dv.MaLoaiDichVu = d.MaLoaiDichVu
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai

                OUTER APPLY (
                    SELECT
                        CASE
                            WHEN COUNT_BIG(*) = 1
                            THEN MIN(dc.MaDiaChiKhachHang)
                            ELSE NULL
                        END AS addressId
                    FROM dbo.DiaChiKhachHang dc
                    WHERE dc.MaKhachHang = d.MaNguoiGui
                      AND dc.DangHoatDong = 1
                      AND EXISTS (
                          SELECT 1
                          FROM dbo.DiemGiaoNhan p
                          WHERE p.MaDonHang = d.MaDonHang
                            AND p.LoaiDiem = 'PICKUP'
                            AND NOT EXISTS (
                                SELECT
                                    dc.TenNguoiLienHe,
                                    dc.SoDienThoaiLienHe,
                                    dc.DiaChi,
                                    dc.MaKhuVuc,
                                    dc.ViDo,
                                    dc.KinhDo
                                EXCEPT
                                SELECT
                                    p.TenNguoiLienHe,
                                    p.SoDienThoaiLienHe,
                                    p.DiaChi,
                                    p.MaKhuVuc,
                                    p.ViDo,
                                    p.KinhDo
                            )
                      )
                ) pickupAddress

                OUTER APPLY (
                    SELECT
                        CASE
                            WHEN COUNT_BIG(*) = 1
                            THEN MIN(dc.MaDiaChiKhachHang)
                            ELSE NULL
                        END AS addressId
                    FROM dbo.DiaChiKhachHang dc
                    WHERE dc.MaKhachHang = d.MaNguoiNhan
                      AND dc.DangHoatDong = 1
                      AND EXISTS (
                          SELECT 1
                          FROM dbo.DiemGiaoNhan p
                          WHERE p.MaDonHang = d.MaDonHang
                            AND p.LoaiDiem = 'DELIVERY'
                            AND NOT EXISTS (
                                SELECT
                                    dc.TenNguoiLienHe,
                                    dc.SoDienThoaiLienHe,
                                    dc.DiaChi,
                                    dc.MaKhuVuc,
                                    dc.ViDo,
                                    dc.KinhDo
                                EXCEPT
                                SELECT
                                    p.TenNguoiLienHe,
                                    p.SoDienThoaiLienHe,
                                    p.DiaChi,
                                    p.MaKhuVuc,
                                    p.ViDo,
                                    p.KinhDo
                            )
                      )
                ) deliveryAddress

                WHERE d.MaDonHang = @Id
                  AND (
                      @IsAdmin = 1
                      OR d.MaBuuCuc = @BranchId
                  )

                FOR JSON PATH, INCLUDE_NULL_VALUES,
                    WITHOUT_ARRAY_WRAPPER
            );
            """;

        await using var command = new SqlCommand(sql, connection);

        AddScopeParameters(
            command,
            scope.Value.IsAdmin,
            scope.Value.BranchId);

        command.Parameters.Add(
            "@Id", SqlDbType.BigInt
        ).Value = id;

        var json = await command.ExecuteScalarAsync(
            cancellationToken) as string;

        if (string.IsNullOrWhiteSpace(json))
        {
            return NotFound(new
            {
                message = "Không tìm thấy đơn hàng trong phạm vi được xem."
            });
        }

        if (tracking)
        {
            if (!await CanMonitor(connection, cancellationToken))
                return Forbid();

            var payload =
                System.Text.Json.Nodes.JsonNode.Parse(json)!;

            payload["tracking"] = await ReadTracking(
                connection,
                id,
                scope.Value,
                cancellationToken);

            return Content(
                payload.ToJsonString(),
                "application/json");
        }

        return Content(json, "application/json");
    }
}