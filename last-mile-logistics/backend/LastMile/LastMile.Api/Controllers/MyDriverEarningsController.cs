using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/my/earnings")]
public class MyDriverEarningsController(IConfiguration configuration) : ControllerBase
{
    private SqlConnection CreateConnection() =>
        new(configuration.GetConnectionString("DefaultConnection"));

    [HttpGet]
    public async Task<IActionResult> GetSummary(CancellationToken cancellationToken)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId))
            return Unauthorized();

        var sql = $$"""
            SET NOCOUNT ON;
            DECLARE @Role VARCHAR(50), @ShipperId BIGINT, @ShipperName NVARCHAR(150),
                    @TodayDate DATE = {{VietnamDate.SqlDate("SYSUTCDATETIME()")}};

            SELECT @Role = vt.KyHieuVaiTro, @ShipperName = tk.HoTen
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());

            IF @Role IS NULL
                THROW 55101, N'Tài khoản không còn hoạt động hoặc đang bị khóa.', 1;
            IF @Role <> 'SHIPPER'
                THROW 55102, N'API ví thu nhập chỉ dành cho tài xế giao hàng.', 1;

            SELECT @ShipperId = MaNhanVienGiaoHang
            FROM dbo.NhanVienGiaoHang
            WHERE MaTaiKhoan = @AccountId AND DangHoatDong = 1;

            IF @ShipperId IS NULL
                THROW 55102, N'Tài khoản chưa có hồ sơ tài xế đang hoạt động.', 1;

            -- 1. Bảng thù lao hiện hành
            DECLARE @DeliverySuccessWage DECIMAL(18,2) = 15000,
                    @RetryBonusWage DECIMAL(18,2) = 5000,
                    @ReturnWage DECIMAL(18,2) = 8000,
                    @CommissionRate DECIMAL(5,2) = 80.00,
                    @MinWage DECIMAL(18,2) = 15000,
                    @VanAllowance DECIMAL(18,2) = 20000,
                    @TruckAllowance DECIMAL(18,2) = 50000;

            SELECT TOP 1 
                @DeliverySuccessWage = TienCongGiaoThanhCong,
                @RetryBonusWage = PhuCapGiaoLai,
                @ReturnWage = TienCongChuyenHoan,
                @CommissionRate = COALESCE(TiLeChietKhauPhanTram, 80.00),
                @MinWage = COALESCE(TienCongToiThieu, 15000),
                @VanAllowance = COALESCE(PhuCapXeVan, 20000),
                @TruckAllowance = COALESCE(PhuCapXeTai, 50000)
            FROM dbo.CauHinhTienCong
            WHERE DangHoatDong = 1
            ORDER BY MaCauHinh DESC;

            -- 2. Thống kê số dư theo trạng thái & hôm nay
            SELECT
                @ShipperId AS shipperId,
                @ShipperName AS shipperName,
                COALESCE(SUM(CASE WHEN {{VietnamDate.SqlDate("tn.ThoiGianGhiNhan")}} = @TodayDate THEN tn.SoTien ELSE 0 END), 0) AS todayEarnings,
                COALESCE(SUM(CASE WHEN tn.TrangThai = 'PENDING' THEN tn.SoTien ELSE 0 END), 0) AS pendingEarnings,
                COALESCE(SUM(CASE WHEN tn.TrangThai = 'APPROVED' THEN tn.SoTien ELSE 0 END), 0) AS approvedEarnings,
                COALESCE(SUM(CASE WHEN tn.TrangThai = 'PAID' THEN tn.SoTien ELSE 0 END), 0) AS paidEarnings,
                COALESCE(SUM(tn.SoTien), 0) AS totalEarnings,
                COALESCE(SUM(CASE WHEN {{VietnamDate.SqlDate("tn.ThoiGianGhiNhan")}} = @TodayDate THEN 1 ELSE 0 END), 0) AS todayCount,
                COUNT(*) AS totalCount,
                COALESCE(SUM(CASE WHEN tn.LoaiThuNhap = 'DELIVERY_SUCCESS' THEN 1 ELSE 0 END), 0) AS successCount,
                COALESCE(SUM(CASE WHEN tn.LoaiThuNhap = 'RETRY_BONUS' THEN 1 ELSE 0 END), 0) AS retryCount,
                COALESCE(SUM(CASE WHEN tn.LoaiThuNhap = 'RETURN_COMPLETED' THEN 1 ELSE 0 END), 0) AS returnCount,
                @DeliverySuccessWage AS successRate,
                @RetryBonusWage AS retryRate,
                @ReturnWage AS returnRate,
                @CommissionRate AS commissionRate,
                @MinWage AS minWage,
                @VanAllowance AS vanAllowance,
                @TruckAllowance AS truckAllowance
            FROM dbo.ThuNhapTaiXe tn
            WHERE tn.MaNhanVienGiaoHang = @ShipperId;
            """;

        try
        {
            await using var connection = CreateConnection();
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(sql, connection);
            command.Parameters.Add(new SqlParameter("@AccountId", SqlDbType.BigInt) { Value = accountId });

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return NotFound(new { message = "Không tìm thấy thông tin tài xế." });
            }

            return Ok(new
            {
                shipperId = reader.GetInt64(reader.GetOrdinal("shipperId")),
                shipperName = reader.GetString(reader.GetOrdinal("shipperName")),
                today = reader.GetDecimal(reader.GetOrdinal("todayEarnings")),
                pending = reader.GetDecimal(reader.GetOrdinal("pendingEarnings")),
                approved = reader.GetDecimal(reader.GetOrdinal("approvedEarnings")),
                paid = reader.GetDecimal(reader.GetOrdinal("paidEarnings")),
                total = reader.GetDecimal(reader.GetOrdinal("totalEarnings")),
                rates = new
                {
                    deliverySuccess = reader.GetDecimal(reader.GetOrdinal("successRate")),
                    retryBonus = reader.GetDecimal(reader.GetOrdinal("retryRate")),
                    returnCompleted = reader.GetDecimal(reader.GetOrdinal("returnRate")),
                    commissionRate = reader.GetDecimal(reader.GetOrdinal("commissionRate")),
                    minWage = reader.GetDecimal(reader.GetOrdinal("minWage")),
                    vanAllowance = reader.GetDecimal(reader.GetOrdinal("vanAllowance")),
                    truckAllowance = reader.GetDecimal(reader.GetOrdinal("truckAllowance"))
                },
                stats = new
                {
                    todayCount = reader.GetInt32(reader.GetOrdinal("todayCount")),
                    totalCount = reader.GetInt32(reader.GetOrdinal("totalCount")),
                    successCount = reader.GetInt32(reader.GetOrdinal("successCount")),
                    retryCount = reader.GetInt32(reader.GetOrdinal("retryCount")),
                    returnCount = reader.GetInt32(reader.GetOrdinal("returnCount"))
                }
            });
        }
        catch (SqlException ex) when (ex.Number is >= 55101 and <= 55105)
        {
            return StatusCode(ex.Number == 55101 ? 401 : 403, new { message = ex.Message });
        }
    }

    [HttpGet("history")]
    public async Task<IActionResult> GetHistory(
        [FromQuery, Range(1, 100000)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 20,
        [FromQuery, StringLength(30)] string? type = null,
        [FromQuery, StringLength(20)] string? status = null,
        [FromQuery] DateTimeOffset? from = null,
        [FromQuery] DateTimeOffset? to = null,
        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId))
            return Unauthorized();

        type = string.IsNullOrWhiteSpace(type) ? null : type.Trim().ToUpperInvariant();
        if (type is not null && type is not ("DELIVERY_SUCCESS" or "RETRY_BONUS" or "RETURN_COMPLETED" or "BONUS"))
            return BadRequest(new { message = "Loại thu nhập không hợp lệ." });

        status = string.IsNullOrWhiteSpace(status) ? null : status.Trim().ToUpperInvariant();
        if (status is not null && status is not ("PENDING" or "APPROVED" or "PAID"))
            return BadRequest(new { message = "Trạng thái thu nhập không hợp lệ. Chỉ nhận PENDING, APPROVED hoặc PAID." });

        if (from.HasValue && to.HasValue && from.Value > to.Value)
            return BadRequest(new { message = "Khoảng thời gian không hợp lệ. 'from' phải nhỏ hơn hoặc bằng 'to'." });

        var sql = """
            SET NOCOUNT ON;
            DECLARE @Role VARCHAR(50), @ShipperId BIGINT;

            SELECT @Role = vt.KyHieuVaiTro
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());

            IF @Role IS NULL
                THROW 55101, N'Tài khoản không còn hoạt động hoặc đang bị khóa.', 1;
            IF @Role <> 'SHIPPER'
                THROW 55102, N'API ví thu nhập chỉ dành cho tài xế giao hàng.', 1;

            SELECT @ShipperId = MaNhanVienGiaoHang
            FROM dbo.NhanVienGiaoHang
            WHERE MaTaiKhoan = @AccountId AND DangHoatDong = 1;

            IF @ShipperId IS NULL
                THROW 55102, N'Tài khoản chưa có hồ sơ tài xế đang hoạt động.', 1;

            -- Đếm tổng bản ghi khớp điều kiện
            SELECT COUNT_BIG(*) AS TotalCount
            FROM dbo.ThuNhapTaiXe tn
            WHERE tn.MaNhanVienGiaoHang = @ShipperId
              AND (@Type IS NULL OR tn.LoaiThuNhap = @Type)
              AND (@Status IS NULL OR tn.TrangThai = @Status)
              AND (@From IS NULL OR tn.ThoiGianGhiNhan >= @From)
              AND (@To IS NULL OR tn.ThoiGianGhiNhan < @To);

            -- Truy vấn danh sách phân trang
            SELECT 
                tn.MaThuNhap AS earningId,
                tn.MaDonHang AS orderId,
                d.KyHieuDonHang AS orderCode,
                d.MaVanDon AS trackingNumber,
                tn.MaPhanCongGiaoHang AS assignmentId,
                tn.LoaiThuNhap AS earningType,
                CASE tn.LoaiThuNhap
                    WHEN 'DELIVERY_SUCCESS' THEN N'Giao hàng thành công'
                    WHEN 'RETRY_BONUS' THEN N'Phụ cấp giao lại thành công'
                    WHEN 'RETURN_COMPLETED' THEN N'Thù lao chuyển hoàn về kho'
                    WHEN 'BONUS' THEN N'Thưởng bổ sung'
                    ELSE tn.LoaiThuNhap
                END AS earningTypeLabel,
                tn.SoTien AS amount,
                COALESCE(tn.CuocDonHang, d.PhiVanChuyen, 0) AS shippingFee,
                tn.TiLeChietKhau AS commissionRate,
                tn.TrangThai AS status,
                CASE tn.TrangThai
                    WHEN 'PENDING' THEN N'Chờ đối soát'
                    WHEN 'APPROVED' THEN N'Đã duyệt'
                    WHEN 'PAID' THEN N'Đã thanh toán'
                    ELSE tn.TrangThai
                END AS statusLabel,
                tn.ThoiGianGhiNhan AS recordedAt,
                tn.ThoiGianDuyet AS approvedAt,
                tn.ThoiGianThanhToan AS paidAt,
                tn.GhiChu AS notes
            FROM dbo.ThuNhapTaiXe tn
            INNER JOIN dbo.DonHang d ON d.MaDonHang = tn.MaDonHang
            WHERE tn.MaNhanVienGiaoHang = @ShipperId
              AND (@Type IS NULL OR tn.LoaiThuNhap = @Type)
              AND (@Status IS NULL OR tn.TrangThai = @Status)
              AND (@From IS NULL OR tn.ThoiGianGhiNhan >= @From)
              AND (@To IS NULL OR tn.ThoiGianGhiNhan < @To)
            ORDER BY tn.ThoiGianGhiNhan DESC, tn.MaThuNhap DESC
            OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
            """;

        try
        {
            await using var connection = CreateConnection();
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(sql, connection);
            command.Parameters.Add(new SqlParameter("@AccountId", SqlDbType.BigInt) { Value = accountId });
            command.Parameters.Add(new SqlParameter("@Type", SqlDbType.VarChar, 30) { Value = (object?)type ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@Status", SqlDbType.VarChar, 20) { Value = (object?)status ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@From", SqlDbType.DateTime2) { Value = (object?)from?.UtcDateTime ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@To", SqlDbType.DateTime2) { Value = (object?)to?.UtcDateTime ?? DBNull.Value });
            command.Parameters.Add(new SqlParameter("@Offset", SqlDbType.Int) { Value = (page - 1) * pageSize });
            command.Parameters.Add(new SqlParameter("@PageSize", SqlDbType.Int) { Value = pageSize });

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);

            long totalCount = 0;
            if (await reader.ReadAsync(cancellationToken))
            {
                totalCount = reader.GetInt64(0);
            }

            await reader.NextResultAsync(cancellationToken);

            var items = new List<object>();
            while (await reader.ReadAsync(cancellationToken))
            {
                items.Add(new
                {
                    earningId = reader.GetInt64(reader.GetOrdinal("earningId")),
                    orderId = reader.GetInt64(reader.GetOrdinal("orderId")),
                    orderCode = reader.GetString(reader.GetOrdinal("orderCode")),
                    trackingNumber = reader.GetString(reader.GetOrdinal("trackingNumber")),
                    assignmentId = reader.IsDBNull(reader.GetOrdinal("assignmentId")) ? (long?)null : reader.GetInt64(reader.GetOrdinal("assignmentId")),
                    earningType = reader.GetString(reader.GetOrdinal("earningType")),
                    earningTypeLabel = reader.GetString(reader.GetOrdinal("earningTypeLabel")),
                    amount = reader.GetDecimal(reader.GetOrdinal("amount")),
                    shippingFee = reader.IsDBNull(reader.GetOrdinal("shippingFee")) ? 0m : reader.GetDecimal(reader.GetOrdinal("shippingFee")),
                    commissionRate = reader.IsDBNull(reader.GetOrdinal("commissionRate")) ? (decimal?)null : reader.GetDecimal(reader.GetOrdinal("commissionRate")),
                    status = reader.GetString(reader.GetOrdinal("status")),
                    statusLabel = reader.GetString(reader.GetOrdinal("statusLabel")),
                    recordedAt = reader.GetDateTime(reader.GetOrdinal("recordedAt")),
                    approvedAt = reader.IsDBNull(reader.GetOrdinal("approvedAt")) ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("approvedAt")),
                    paidAt = reader.IsDBNull(reader.GetOrdinal("paidAt")) ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("paidAt")),
                    notes = reader.IsDBNull(reader.GetOrdinal("notes")) ? null : reader.GetString(reader.GetOrdinal("notes"))
                });
            }

            var totalPages = (int)Math.Ceiling((double)totalCount / pageSize);

            return Ok(new
            {
                items,
                page,
                pageSize,
                totalCount,
                totalPages
            });
        }
        catch (SqlException ex) when (ex.Number is >= 55101 and <= 55105)
        {
            return StatusCode(ex.Number == 55101 ? 401 : 403, new { message = ex.Message });
        }
    }
}
