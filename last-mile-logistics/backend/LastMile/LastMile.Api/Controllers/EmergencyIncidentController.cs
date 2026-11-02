using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class EmergencyIncidentRequest
{
    public long? OrderId { get; set; }

    public long? TripId { get; set; }

    public long? AssignmentId { get; set; }

    [Required]
    [RegularExpression(
        "^(VEHICLE_BREAKDOWN|ACCIDENT|DAMAGED_PARCEL|OTHER)$",
        ErrorMessage = "Loại sự cố phải là VEHICLE_BREAKDOWN, ACCIDENT, DAMAGED_PARCEL hoặc OTHER.")]
    public string IncidentType { get; set; } = "OTHER";

    [RegularExpression(
        "^(CRITICAL|WARNING|INFO)$",
        ErrorMessage = "Mức độ phải là CRITICAL, WARNING hoặc INFO.")]
    public string Severity { get; set; } = "CRITICAL";

    [Required]
    [StringLength(1000, MinimumLength = 5,
        ErrorMessage = "Mô tả sự cố phải từ 5 đến 1000 ký tự.")]
    public string Description { get; set; } = "";

    public bool NeedsReassignment { get; set; } = true;

    [Range(-90.0, 90.0)]
    public double? Latitude { get; set; }

    [Range(-180.0, 180.0)]
    public double? Longitude { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/my")]
public class EmergencyIncidentController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public EmergencyIncidentController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("emergency-incident")]
    public async Task<IActionResult> ReportEmergency(
        [FromBody] EmergencyIncidentRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var actorId))
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
                    @ShipperId BIGINT,
                    @DriverName NVARCHAR(100),
                    @DriverPhone VARCHAR(20),
                    @BranchId INT,
                    @ResolvedOrderId BIGINT = @OrderId,
                    @ResolvedTripId BIGINT = @TripId,
                    @AlertId BIGINT,
                    @CategoryLabel NVARCHAR(50),
                    @FullContent NVARCHAR(1000);

                -- Kiểm tra tài khoản và shipper
                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @BranchId = tk.MaBuuCuc,
                    @ShipperId = nv.MaNhanVienGiaoHang,
                    @DriverName = nv.HoTen,
                    @DriverPhone = nv.SoDienThoai
                FROM dbo.TaiKhoan tk
                JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                LEFT JOIN dbo.NhanVienGiaoHang nv ON nv.MaTaiKhoan = tk.MaTaiKhoan
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= @Now
                  );

                IF @Role IS NULL
                    THROW 59101, N'Tài khoản không còn hiệu lực.', 1;

                IF @Role <> 'SHIPPER' OR @ShipperId IS NULL
                    THROW 59102, N'Chỉ tài xế mới có quyền gửi báo cáo sự cố trên đường.', 1;

                -- Nếu có assignmentId mà chưa có orderId / tripId, tra cứu
                IF @AssignmentId IS NOT NULL AND @ResolvedOrderId IS NULL
                BEGIN
                    SELECT
                        @ResolvedOrderId = pc.MaDonHang,
                        @ResolvedTripId = COALESCE(@ResolvedTripId, pc.MaChuyenGiao)
                    FROM dbo.PhanCongGiaoHang pc
                    WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                      AND pc.MaNhanVienGiaoHang = @ShipperId;
                END;

                -- Nhãn loại sự cố
                SET @CategoryLabel = CASE @IncidentType
                    WHEN 'VEHICLE_BREAKDOWN' THEN N'Hỏng xe'
                    WHEN 'ACCIDENT' THEN N'Tai nạn'
                    WHEN 'DAMAGED_PARCEL' THEN N'Hàng hóa hư hỏng'
                    ELSE N'Sự cố khác'
                END;

                -- Tạo nội dung cảnh báo chi tiết
                SET @FullContent = CONCAT(
                    N'[SỰ CỐ KHẨN CẤP - ', @CategoryLabel, N'] ',
                    N'Tài xế: ', COALESCE(@DriverName, N'Shipper'),
                    CASE WHEN @DriverPhone IS NOT NULL THEN CONCAT(N' (', @DriverPhone, N')') ELSE N'' END,
                    N' · ', @Description,
                    CASE WHEN @NeedsReassignment = 1 THEN N' · [YÊU CẦU: Thu hồi & chia lại đơn]' ELSE N'' END,
                    CASE WHEN @Latitude IS NOT NULL AND @Longitude IS NOT NULL
                         THEN CONCAT(N' · GPS: ', FORMAT(@Latitude, '0.00000'), N', ', FORMAT(@Longitude, '0.00000'))
                         ELSE N'' END
                );

                IF LEN(@FullContent) > 1000
                    SET @FullContent = LEFT(@FullContent, 1000);

                -- 1. Lưu cảnh báo giao hàng
                INSERT INTO dbo.CanhBaoGiaoHang (
                    MaDonHang,
                    MaChuyenGiao,
                    LoaiCanhBao,
                    MucDoCanhBao,
                    NoiDungCanhBao,
                    TrangThaiCanhBao,
                    ThoiGianPhatHien
                )
                VALUES (
                    @ResolvedOrderId,
                    @ResolvedTripId,
                    'OTHER',
                    @Severity,
                    @FullContent,
                    'OPEN',
                    @Now
                );

                SET @AlertId = SCOPE_IDENTITY();

                -- Mở đầu hội thoại chat xử lý sự cố
                INSERT INTO dbo.TinNhanSuCo (
                    MaCanhBao,
                    MaDonHang,
                    MaChuyenGiao,
                    MaTaiKhoanGui,
                    VaiTroNguoiGui,
                    TenNguoiGui,
                    NoiDung,
                    ThoiGianGui,
                    DaDoc
                )
                VALUES (
                    @AlertId,
                    @ResolvedOrderId,
                    @ResolvedTripId,
                    @ActorId,
                    'SHIPPER',
                    COALESCE(@DriverName, N'Tài xế'),
                    @FullContent,
                    @Now,
                    0
                );

                -- 2. Gửi thông báo đến các tài khoản điều phối / quản lý
                INSERT INTO dbo.ThongBao (
                    MaTaiKhoan,
                    LoaiThongBao,
                    TieuDe,
                    NoiDung,
                    LoaiDoiTuongThamChieu,
                    MaDoiTuongThamChieu,
                    DaDoc,
                    ThoiGianTao
                )
                SELECT
                    tk.MaTaiKhoan,
                    'EMERGENCY_INCIDENT',
                    CONCAT(N'SỰ CỐ KHẨN CẤP: ', @CategoryLabel, N' - ', COALESCE(@DriverName, N'Tài xế')),
                    @FullContent,
                    CASE WHEN @ResolvedOrderId IS NOT NULL THEN 'ORDER' ELSE 'TRIP' END,
                    COALESCE(@ResolvedOrderId, @ResolvedTripId, @AlertId),
                    0,
                    @Now
                FROM dbo.TaiKhoan tk
                JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND vt.KyHieuVaiTro IN ('DISPATCHER', 'ADMIN', 'COORDINATOR', 'BRANCH_MANAGER')
                  AND (@BranchId IS NULL OR tk.MaBuuCuc IS NULL OR tk.MaBuuCuc = @BranchId);

                -- 3. Tạo thông báo xác nhận gửi vào hòm thư của Shipper
                INSERT INTO dbo.ThongBao (
                    MaTaiKhoan,
                    LoaiThongBao,
                    TieuDe,
                    NoiDung,
                    LoaiDoiTuongThamChieu,
                    MaDoiTuongThamChieu,
                    DaDoc,
                    ThoiGianTao
                )
                VALUES (
                    @ActorId,
                    'EMERGENCY_INCIDENT',
                    CONCAT(N'Đã tiếp nhận báo sự cố: ', @CategoryLabel),
                    CONCAT(N'Báo cáo sự cố khẩn cấp trên đường của bạn đã được ghi nhận và gửi đến bộ phận điều phối. ',
                           CASE WHEN @NeedsReassignment = 1 THEN N'Điều phối viên sẽ can thiệp thu hồi hoặc chia lại đơn cho tài xế khác sớm nhất.' ELSE N'Điều phối viên đang kiểm tra và hỗ trợ.' END),
                    CASE WHEN @ResolvedOrderId IS NOT NULL THEN 'ORDER' ELSE 'TRIP' END,
                    COALESCE(@ResolvedOrderId, @ResolvedTripId, @AlertId),
                    0,
                    @Now
                );

                COMMIT;

                SELECT (
                    SELECT
                        @AlertId AS alertId,
                        @AlertId AS incidentId,
                        @ResolvedOrderId AS orderId,
                        @ResolvedTripId AS tripId,
                        @CategoryLabel AS category,
                        N'Đã gửi báo cáo sự cố khẩn cấp tới điều phối viên thành công.' AS message,
                        1 AS success
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK;
                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@ActorId", SqlDbType.BigInt).Value = actorId;
        command.Parameters.Add("@OrderId", SqlDbType.BigInt).Value = (object?)request.OrderId ?? DBNull.Value;
        command.Parameters.Add("@TripId", SqlDbType.BigInt).Value = (object?)request.TripId ?? DBNull.Value;
        command.Parameters.Add("@AssignmentId", SqlDbType.BigInt).Value = (object?)request.AssignmentId ?? DBNull.Value;
        command.Parameters.Add("@IncidentType", SqlDbType.VarChar, 30).Value = request.IncidentType;
        command.Parameters.Add("@Severity", SqlDbType.VarChar, 10).Value = request.Severity;
        command.Parameters.Add("@Description", SqlDbType.NVarChar, 1000).Value = request.Description.Trim();
        command.Parameters.Add("@NeedsReassignment", SqlDbType.Bit).Value = request.NeedsReassignment;
        command.Parameters.Add("@Latitude", SqlDbType.Float).Value = (object?)request.Latitude ?? DBNull.Value;
        command.Parameters.Add("@Longitude", SqlDbType.Float).Value = (object?)request.Longitude ?? DBNull.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);
            var result = await command.ExecuteScalarAsync(cancellationToken);
            return Content(result?.ToString() ?? "{}", "application/json");
        }
        catch (SqlException ex) when (ex.Number is >= 59101 and <= 59102)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}
