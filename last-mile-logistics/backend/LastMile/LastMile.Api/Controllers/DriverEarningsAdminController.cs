using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using LastMile.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public sealed class UpdateWageRatesRequest
{
    [Range(0, 100000000)]
    public decimal DeliverySuccessRate { get; set; }

    [Range(0, 100000000)]
    public decimal RetryBonusRate { get; set; }

    [Range(0, 100000000)]
    public decimal ReturnCompletedRate { get; set; }

    [Range(0, 100)]
    public decimal? CommissionRate { get; set; } = 80.00m;

    [Range(0, 100000000)]
    public decimal? MinWage { get; set; } = 15000m;

    [Range(0, 100000000)]
    public decimal? VanAllowance { get; set; } = 20000m;

    [Range(0, 100000000)]
    public decimal? TruckAllowance { get; set; } = 50000m;
}

public sealed class BatchPayEarningsRequest
{
    [Required, MinLength(1)]
    public List<long> EarningIds { get; set; } = [];
}

[ApiController]
[Authorize]
[Route("api/v1/admin/driver-earnings")]
public class DriverEarningsAdminController(IConfiguration configuration) : ControllerBase
{
    private SqlConnection CreateConnection() =>
        new(configuration.GetConnectionString("DefaultConnection"));

    [HttpGet("rates")]
    public async Task<IActionResult> GetRates(CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT TOP 1
                MaCauHinh AS configId,
                TenCauHinh AS configName,
                TienCongGiaoThanhCong AS deliverySuccessRate,
                PhuCapGiaoLai AS retryBonusRate,
                TienCongChuyenHoan AS returnCompletedRate,
                COALESCE(TiLeChietKhauPhanTram, 80.00) AS commissionRate,
                COALESCE(TienCongToiThieu, 15000) AS minWage,
                COALESCE(PhuCapXeVan, 20000) AS vanAllowance,
                COALESCE(PhuCapXeTai, 50000) AS truckAllowance,
                DangHoatDong AS isActive,
                ThoiGianTao AS createdAt
            FROM dbo.CauHinhTienCong
            WHERE DangHoatDong = 1
            ORDER BY MaCauHinh DESC;
            """;

        await using var connection = CreateConnection();
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
            return NotFound(new { message = "Chưa có cấu hình thù lao nào trong hệ thống." });

        return Ok(new
        {
            configId = reader.GetInt32(reader.GetOrdinal("configId")),
            configName = reader.GetString(reader.GetOrdinal("configName")),
            deliverySuccessRate = reader.GetDecimal(reader.GetOrdinal("deliverySuccessRate")),
            retryBonusRate = reader.GetDecimal(reader.GetOrdinal("retryBonusRate")),
            returnCompletedRate = reader.GetDecimal(reader.GetOrdinal("returnCompletedRate")),
            commissionRate = reader.GetDecimal(reader.GetOrdinal("commissionRate")),
            minWage = reader.GetDecimal(reader.GetOrdinal("minWage")),
            vanAllowance = reader.GetDecimal(reader.GetOrdinal("vanAllowance")),
            truckAllowance = reader.GetDecimal(reader.GetOrdinal("truckAllowance")),
            isActive = reader.GetBoolean(reader.GetOrdinal("isActive")),
            createdAt = reader.GetDateTime(reader.GetOrdinal("createdAt"))
        });
    }

    [HttpPut("rates")]
    public async Task<IActionResult> UpdateRates(
        [FromBody] UpdateWageRatesRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId))
            return Unauthorized();

        const string sql = """
            SET NOCOUNT ON;
            DECLARE @Role VARCHAR(50);
            SELECT @Role = vt.KyHieuVaiTro
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());

            IF @Role IS NULL OR @Role NOT IN ('ADMIN', 'DISPATCHER', 'COORDINATOR', 'BRANCH_MANAGER', 'ACCOUNTANT')
                THROW 55201, N'Bạn không có quyền cập nhật cấu hình thù lao tài xế.', 1;

            UPDATE dbo.CauHinhTienCong SET DangHoatDong = 0 WHERE DangHoatDong = 1;

            INSERT INTO dbo.CauHinhTienCong (
                TenCauHinh, TienCongGiaoThanhCong, PhuCapGiaoLai, TienCongChuyenHoan,
                TiLeChietKhauPhanTram, TienCongToiThieu, PhuCapXeVan, PhuCapXeTai, DangHoatDong
            )
            VALUES (
                N'Bảng thù lao cập nhật', @SuccessRate, @RetryRate, @ReturnRate,
                @CommissionRate, @MinWage, @VanAllowance, @TruckAllowance, 1
            );

            SELECT SCOPE_IDENTITY() AS NewConfigId;
            """;

        try
        {
            await using var connection = CreateConnection();
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(sql, connection);
            command.Parameters.Add(new SqlParameter("@AccountId", SqlDbType.BigInt) { Value = accountId });
            command.Parameters.Add(new SqlParameter("@SuccessRate", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = request.DeliverySuccessRate });
            command.Parameters.Add(new SqlParameter("@RetryRate", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = request.RetryBonusRate });
            command.Parameters.Add(new SqlParameter("@ReturnRate", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = request.ReturnCompletedRate });
            command.Parameters.Add(new SqlParameter("@CommissionRate", SqlDbType.Decimal) { Precision = 5, Scale = 2, Value = request.CommissionRate ?? 80.00m });
            command.Parameters.Add(new SqlParameter("@MinWage", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = request.MinWage ?? 15000m });
            command.Parameters.Add(new SqlParameter("@VanAllowance", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = request.VanAllowance ?? 20000m });
            command.Parameters.Add(new SqlParameter("@TruckAllowance", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = request.TruckAllowance ?? 50000m });

            var newId = Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
            return Ok(new
            {
                message = "Đã cập nhật cấu hình thù lao tài xế thành công.",
                configId = newId,
                rates = request
            });
        }
        catch (SqlException ex) when (ex.Number == 55201)
        {
            return StatusCode(403, new { message = ex.Message });
        }
    }

    [HttpGet]
    public async Task<IActionResult> GetAllEarnings(
        [FromQuery, Range(1, long.MaxValue)] long? shipperId = null,
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

        var sql = """
            SET NOCOUNT ON;
            DECLARE @Role VARCHAR(50);
            SELECT @Role = vt.KyHieuVaiTro
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());

            IF @Role IS NULL OR @Role NOT IN ('ADMIN', 'DISPATCHER', 'COORDINATOR', 'ACCOUNTANT', 'BRANCH_MANAGER')
                THROW 55201, N'Bạn không có quyền tra cứu thù lao tài xế.', 1;

            SELECT COUNT_BIG(*) AS TotalCount
            FROM dbo.ThuNhapTaiXe tn
            WHERE (@ShipperId IS NULL OR tn.MaNhanVienGiaoHang = @ShipperId)
              AND (@Type IS NULL OR tn.LoaiThuNhap = @Type)
              AND (@Status IS NULL OR tn.TrangThai = @Status)
              AND (@From IS NULL OR tn.ThoiGianGhiNhan >= @From)
              AND (@To IS NULL OR tn.ThoiGianGhiNhan < @To);

            SELECT 
                tn.MaThuNhap AS earningId,
                tn.MaNhanVienGiaoHang AS shipperId,
                shipperTk.HoTen AS shipperName,
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
                COALESCE(tn.TiLeChietKhau, 80.00) AS commissionRate,
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
            INNER JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang = tn.MaNhanVienGiaoHang
            INNER JOIN dbo.TaiKhoan shipperTk ON shipperTk.MaTaiKhoan = nv.MaTaiKhoan
            WHERE (@ShipperId IS NULL OR tn.MaNhanVienGiaoHang = @ShipperId)
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
            command.Parameters.Add(new SqlParameter("@ShipperId", SqlDbType.BigInt) { Value = (object?)shipperId ?? DBNull.Value });
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
                    shipperId = reader.GetInt64(reader.GetOrdinal("shipperId")),
                    shipperName = reader.GetString(reader.GetOrdinal("shipperName")),
                    orderId = reader.GetInt64(reader.GetOrdinal("orderId")),
                    orderCode = reader.GetString(reader.GetOrdinal("orderCode")),
                    trackingNumber = reader.GetString(reader.GetOrdinal("trackingNumber")),
                    assignmentId = reader.IsDBNull(reader.GetOrdinal("assignmentId")) ? (long?)null : reader.GetInt64(reader.GetOrdinal("assignmentId")),
                    earningType = reader.GetString(reader.GetOrdinal("earningType")),
                    earningTypeLabel = reader.GetString(reader.GetOrdinal("earningTypeLabel")),
                    amount = reader.GetDecimal(reader.GetOrdinal("amount")),
                    shippingFee = reader.IsDBNull(reader.GetOrdinal("shippingFee")) ? 0m : reader.GetDecimal(reader.GetOrdinal("shippingFee")),
                    commissionRate = reader.IsDBNull(reader.GetOrdinal("commissionRate")) ? 80.00m : reader.GetDecimal(reader.GetOrdinal("commissionRate")),
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
        catch (SqlException ex) when (ex.Number == 55201)
        {
            return StatusCode(403, new { message = ex.Message });
        }
    }

    [HttpPost("{id:long}/pay")]
    public async Task<IActionResult> MarkAsPaid(long id, CancellationToken cancellationToken)
    {
        if (id <= 0) return BadRequest(new { message = "Mã thu nhập không hợp lệ." });
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId))
            return Unauthorized();

        const string sql = """
            SET NOCOUNT ON;
            DECLARE @Role VARCHAR(50);
            SELECT @Role = vt.KyHieuVaiTro
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());

            IF @Role IS NULL OR @Role NOT IN ('ADMIN', 'DISPATCHER', 'COORDINATOR', 'ACCOUNTANT', 'BRANCH_MANAGER')
                THROW 55201, N'Bạn không có quyền thực hiện thanh toán thù lao.', 1;

            UPDATE dbo.ThuNhapTaiXe
            SET TrangThai = 'PAID',
                ThoiGianThanhToan = SYSUTCDATETIME()
            WHERE MaThuNhap = @EarningId AND TrangThai IN ('PENDING', 'APPROVED');

            IF @@ROWCOUNT = 0
                THROW 55202, N'Khoản thu nhập không tồn tại hoặc đã được thanh toán từ trước.', 1;
            """;

        try
        {
            await using var connection = CreateConnection();
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand(sql, connection);
            command.Parameters.Add(new SqlParameter("@AccountId", SqlDbType.BigInt) { Value = accountId });
            command.Parameters.Add(new SqlParameter("@EarningId", SqlDbType.BigInt) { Value = id });

            await command.ExecuteNonQueryAsync(cancellationToken);
            return Ok(new { message = "Đã đánh dấu thanh toán thành công.", earningId = id, status = "PAID" });
        }
        catch (SqlException ex) when (ex.Number is 55201 or 55202)
        {
            return StatusCode(ex.Number == 55201 ? 403 : 400, new { message = ex.Message });
        }
    }

    [HttpPost("batch-pay")]
    public async Task<IActionResult> BatchPay(
        [FromBody] BatchPayEarningsRequest request,
        CancellationToken cancellationToken)
    {
        if (request.EarningIds.Count == 0)
            return BadRequest(new { message = "Danh sách mã thu nhập không được rỗng." });

        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var accountId))
            return Unauthorized();

        const string sql = """
            SET NOCOUNT ON;
            DECLARE @Role VARCHAR(50);
            SELECT @Role = vt.KyHieuVaiTro
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME());

            IF @Role IS NULL OR @Role NOT IN ('ADMIN', 'DISPATCHER', 'COORDINATOR', 'ACCOUNTANT', 'BRANCH_MANAGER')
                THROW 55201, N'Bạn không có quyền thực hiện thanh toán thù lao.', 1;
            """;

        try
        {
            await using var connection = CreateConnection();
            await connection.OpenAsync(cancellationToken);

            await using var authCmd = new SqlCommand(sql, connection);
            authCmd.Parameters.Add(new SqlParameter("@AccountId", SqlDbType.BigInt) { Value = accountId });
            await authCmd.ExecuteNonQueryAsync(cancellationToken);

            var idList = string.Join(",", request.EarningIds.Where(x => x > 0).Distinct());
            if (string.IsNullOrEmpty(idList))
                return BadRequest(new { message = "Không có mã thu nhập hợp lệ." });

            var updateSql = $"""
                UPDATE dbo.ThuNhapTaiXe
                SET TrangThai = 'PAID',
                    ThoiGianThanhToan = SYSUTCDATETIME()
                WHERE MaThuNhap IN ({idList}) AND TrangThai IN ('PENDING', 'APPROVED');
                SELECT @@ROWCOUNT;
                """;

            await using var updateCmd = new SqlCommand(updateSql, connection);
            var updatedRows = Convert.ToInt32(await updateCmd.ExecuteScalarAsync(cancellationToken));

            return Ok(new
            {
                message = $"Đã đánh dấu thanh toán thành công cho {updatedRows} khoản thù lao.",
                updatedCount = updatedRows
            });
        }
        catch (SqlException ex) when (ex.Number == 55201)
        {
            return StatusCode(403, new { message = ex.Message });
        }
    }
}
