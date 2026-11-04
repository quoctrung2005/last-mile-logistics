using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class SendIncidentChatMessageRequest
{
    public long? IncidentId { get; set; }

    public long? OrderId { get; set; }

    public long? TripId { get; set; }

    [Required]
    [StringLength(2000, MinimumLength = 1,
        ErrorMessage = "Nội dung tin nhắn không được để trống và tối đa 2000 ký tự.")]
    public string Content { get; set; } = "";

    public string? ImageUrl { get; set; }
}

public class ResolveIncidentRequest
{
    [Required]
    public long IncidentId { get; set; }

    [StringLength(500)]
    public string? ResolutionNote { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/incidents")]
public class IncidentChatController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public IncidentChatController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("chat")]
    public async Task<IActionResult> GetIncidentChat(
        [FromQuery] long? incidentId = null,
        [FromQuery] long? orderId = null,
        [FromQuery] long? tripId = null,
        [FromQuery] long? afterId = null,
        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var actorId))
        {
            return Unauthorized();
        }

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @ResolvedIncidentId BIGINT = @IncidentId,
                @ResolvedOrderId BIGINT = @OrderId,
                @ResolvedTripId BIGINT = @TripId,
                @OrderCode NVARCHAR(50),
                @TripCode NVARCHAR(50),
                @Title NVARCHAR(200) = N'Chat xử lý sự cố',
                @Status VARCHAR(30) = 'OPEN',
                @Severity VARCHAR(20) = 'CRITICAL',
                @Category NVARCHAR(50) = N'Sự cố';

            -- 1. Tra cứu thông tin cảnh báo nếu có
            IF @ResolvedIncidentId IS NOT NULL
            BEGIN
                SELECT
                    @ResolvedOrderId = COALESCE(@ResolvedOrderId, cb.MaDonHang),
                    @ResolvedTripId = COALESCE(@ResolvedTripId, cb.MaChuyenGiao),
                    @Status = cb.TrangThaiCanhBao,
                    @Severity = cb.MucDoCanhBao,
                    @Category = CASE cb.LoaiCanhBao
                        WHEN 'VEHICLE_BREAKDOWN' THEN N'Hỏng xe'
                        WHEN 'ACCIDENT' THEN N'Tai nạn'
                        WHEN 'DAMAGED_PARCEL' THEN N'Hàng hỏng'
                        ELSE N'Sự cố'
                    END
                FROM dbo.CanhBaoGiaoHang cb
                WHERE cb.MaCanhBao = @ResolvedIncidentId;
            END
            ELSE IF @ResolvedOrderId IS NOT NULL
            BEGIN
                -- Tra cứu cảnh báo gần nhất của đơn hàng
                SELECT TOP 1
                    @ResolvedIncidentId = cb.MaCanhBao,
                    @ResolvedTripId = COALESCE(@ResolvedTripId, cb.MaChuyenGiao),
                    @Status = cb.TrangThaiCanhBao,
                    @Severity = cb.MucDoCanhBao
                FROM dbo.CanhBaoGiaoHang cb
                WHERE cb.MaDonHang = @ResolvedOrderId
                ORDER BY cb.ThoiGianPhatHien DESC;
            END
            ELSE IF @ResolvedTripId IS NOT NULL
            BEGIN
                -- Tra cứu cảnh báo gần nhất của chuyến
                SELECT TOP 1
                    @ResolvedIncidentId = cb.MaCanhBao,
                    @Status = cb.TrangThaiCanhBao,
                    @Severity = cb.MucDoCanhBao
                FROM dbo.CanhBaoGiaoHang cb
                WHERE cb.MaChuyenGiao = @ResolvedTripId
                ORDER BY cb.ThoiGianPhatHien DESC;
            END;

            -- 2. Lấy mã đơn và mã chuyến nếu có
            IF @ResolvedOrderId IS NOT NULL
            BEGIN
                SELECT @OrderCode = dh.KyHieuDonHang FROM dbo.DonHang dh WHERE dh.MaDonHang = @ResolvedOrderId;
            END;

            IF @ResolvedTripId IS NOT NULL
            BEGIN
                SELECT @TripCode = cg.KyHieuChuyenGiao FROM dbo.ChuyenGiaoHang cg WHERE cg.MaChuyenGiao = @ResolvedTripId;
            END;

            SET @Title = CASE
                WHEN @OrderCode IS NOT NULL THEN CONCAT(N'Sự cố đơn: ', @OrderCode)
                WHEN @TripCode IS NOT NULL THEN CONCAT(N'Sự cố chuyến: ', @TripCode)
                ELSE N'Kênh chat hỗ trợ sự cố'
            END;

            -- 3. Đánh dấu đã đọc cho các tin nhắn người khác gửi
            IF @ResolvedIncidentId IS NOT NULL OR @ResolvedOrderId IS NOT NULL OR @ResolvedTripId IS NOT NULL
            BEGIN
                UPDATE dbo.TinNhanSuCo
                SET DaDoc = 1
                WHERE MaTaiKhoanGui <> @ActorId
                  AND DaDoc = 0
                  AND (
                      (@ResolvedIncidentId IS NOT NULL AND MaCanhBao = @ResolvedIncidentId)
                      OR (@ResolvedOrderId IS NOT NULL AND MaDonHang = @ResolvedOrderId)
                      OR (@ResolvedTripId IS NOT NULL AND MaChuyenGiao = @ResolvedTripId)
                  );
            END;

            -- 4. Trả về kết quả JSON
            SELECT (
                SELECT
                    @ResolvedIncidentId AS incidentId,
                    @ResolvedOrderId AS orderId,
                    @OrderCode AS orderCode,
                    @ResolvedTripId AS tripId,
                    @TripCode AS tripCode,
                    @Title AS title,
                    @Category AS category,
                    @Severity AS severity,
                    @Status AS status,
                    (
                        SELECT
                            tn.MaTinNhan AS id,
                            tn.MaCanhBao AS incidentId,
                            tn.MaTaiKhoanGui AS senderAccountId,
                            tn.VaiTroNguoiGui AS senderRole,
                            tn.TenNguoiGui AS senderName,
                            CASE WHEN tn.MaTaiKhoanGui = @ActorId THEN 1 ELSE 0 END AS isMe,
                            tn.NoiDung AS content,
                            tn.HinhAnhMinhChung AS imageUrl,
                            tn.ThoiGianGui AS sentAt,
                            tn.DaDoc AS isRead
                        FROM dbo.TinNhanSuCo tn
                        WHERE (
                            (@ResolvedIncidentId IS NOT NULL AND tn.MaCanhBao = @ResolvedIncidentId)
                            OR (@ResolvedOrderId IS NOT NULL AND tn.MaDonHang = @ResolvedOrderId)
                            OR (@ResolvedTripId IS NOT NULL AND tn.MaChuyenGiao = @ResolvedTripId)
                        )
                        AND (@AfterId IS NULL OR tn.MaTinNhan > @AfterId)
                        ORDER BY tn.ThoiGianGui ASC, tn.MaTinNhan ASC
                        FOR JSON PATH
                    ) AS messages
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@ActorId", SqlDbType.BigInt).Value = actorId;
        command.Parameters.Add("@IncidentId", SqlDbType.BigInt).Value = (object?)incidentId ?? DBNull.Value;
        command.Parameters.Add("@OrderId", SqlDbType.BigInt).Value = (object?)orderId ?? DBNull.Value;
        command.Parameters.Add("@TripId", SqlDbType.BigInt).Value = (object?)tripId ?? DBNull.Value;
        command.Parameters.Add("@AfterId", SqlDbType.BigInt).Value = (object?)afterId ?? DBNull.Value;

        await connection.OpenAsync(cancellationToken);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Content(result?.ToString() ?? "{\"messages\":[]}", "application/json");
    }

    [HttpPost("chat")]
    public async Task<IActionResult> SendMessage(
        [FromBody] SendIncidentChatMessageRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var actorId))
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
                    @SenderName NVARCHAR(100),
                    @BranchId INT,
                    @ResolvedIncidentId BIGINT = @IncidentId,
                    @ResolvedOrderId BIGINT = @OrderId,
                    @ResolvedTripId BIGINT = @TripId,
                    @NewMessageId BIGINT,
                    @RecipientAccountId BIGINT;

                -- Xác định người gửi
                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @BranchId = tk.MaBuuCuc,
                    @SenderName = COALESCE(tk.HoTen, tk.TenDangNhap, N'Người dùng')
                FROM dbo.TaiKhoan tk
                JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1;

                IF @Role IS NULL
                    THROW 59201, N'Tài khoản không hợp lệ hoặc đã bị khóa.', 1;

                -- Chuẩn hóa vai trò người gửi trong chat
                DECLARE @ChatRole VARCHAR(30) = CASE
                    WHEN @Role = 'SHIPPER' THEN 'SHIPPER'
                    WHEN @Role IN ('DISPATCHER', 'COORDINATOR') THEN 'DISPATCHER'
                    WHEN @Role IN ('ADMIN', 'BRANCH_MANAGER') THEN 'ADMIN'
                    ELSE 'USER'
                END;

                -- Nếu có cảnh báo, lấy orderId/tripId
                IF @ResolvedIncidentId IS NOT NULL
                BEGIN
                    SELECT
                        @ResolvedOrderId = COALESCE(@ResolvedOrderId, cb.MaDonHang),
                        @ResolvedTripId = COALESCE(@ResolvedTripId, cb.MaChuyenGiao)
                    FROM dbo.CanhBaoGiaoHang cb
                    WHERE cb.MaCanhBao = @ResolvedIncidentId;

                    -- Chuyển cảnh báo sang ACKNOWLEDGED nếu đang OPEN
                    UPDATE dbo.CanhBaoGiaoHang
                    SET TrangThaiCanhBao = 'ACKNOWLEDGED'
                    WHERE MaCanhBao = @ResolvedIncidentId
                      AND TrangThaiCanhBao = 'OPEN';
                END;

                -- 1. Lưu tin nhắn vào dbo.TinNhanSuCo
                INSERT INTO dbo.TinNhanSuCo (
                    MaCanhBao,
                    MaDonHang,
                    MaChuyenGiao,
                    MaTaiKhoanGui,
                    VaiTroNguoiGui,
                    TenNguoiGui,
                    NoiDung,
                    HinhAnhMinhChung,
                    ThoiGianGui,
                    DaDoc
                )
                VALUES (
                    @ResolvedIncidentId,
                    @ResolvedOrderId,
                    @ResolvedTripId,
                    @ActorId,
                    @ChatRole,
                    @SenderName,
                    @Content,
                    @ImageUrl,
                    @Now,
                    0
                );

                SET @NewMessageId = SCOPE_IDENTITY();

                -- 2. Gửi thông báo đến bên nhận
                IF @ChatRole = 'SHIPPER'
                BEGIN
                    -- Shipper gửi -> Báo cho Điều phối viên / Quản lý chi nhánh
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
                        'INCIDENT_CHAT',
                        CONCAT(N'Tin nhắn sự cố mới từ ', @SenderName),
                        LEFT(@Content, 1000),
                        'INCIDENT',
                        COALESCE(@ResolvedIncidentId, @NewMessageId),
                        0,
                        @Now
                    FROM dbo.TaiKhoan tk
                    JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE tk.TrangThaiTaiKhoan = 'ACTIVE'
                      AND vt.DangHoatDong = 1
                      AND vt.KyHieuVaiTro IN ('DISPATCHER', 'ADMIN', 'COORDINATOR', 'BRANCH_MANAGER')
                      AND (@BranchId IS NULL OR tk.MaBuuCuc IS NULL OR tk.MaBuuCuc = @BranchId);
                END
                ELSE
                BEGIN
                    -- Điều phối viên / Admin gửi -> Báo cho Shipper
                    IF @ResolvedIncidentId IS NOT NULL
                    BEGIN
                        SELECT TOP 1 @RecipientAccountId = tn.MaTaiKhoanGui
                        FROM dbo.TinNhanSuCo tn
                        WHERE tn.MaCanhBao = @ResolvedIncidentId
                          AND tn.VaiTroNguoiGui = 'SHIPPER'
                        ORDER BY tn.ThoiGianGui ASC;
                    END;

                    IF @RecipientAccountId IS NULL AND @ResolvedOrderId IS NOT NULL
                    BEGIN
                        SELECT TOP 1 @RecipientAccountId = nv.MaTaiKhoan
                        FROM dbo.PhanCongGiaoHang pc
                        JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang = pc.MaNhanVienGiaoHang
                        WHERE pc.MaDonHang = @ResolvedOrderId
                        ORDER BY pc.MaPhanCongGiaoHang DESC;
                    END;

                    IF @RecipientAccountId IS NULL AND @ResolvedTripId IS NOT NULL
                    BEGIN
                        SELECT TOP 1 @RecipientAccountId = nv.MaTaiKhoan
                        FROM dbo.ChuyenGiaoHang cg
                        JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang = cg.MaNhanVienGiaoHang
                        WHERE cg.MaChuyenGiao = @ResolvedTripId;
                    END;

                    IF @RecipientAccountId IS NOT NULL
                    BEGIN
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
                            @RecipientAccountId,
                            'INCIDENT_CHAT',
                            N'Điều phối viên đã trả lời sự cố',
                            LEFT(@Content, 1000),
                            'INCIDENT',
                            COALESCE(@ResolvedIncidentId, @NewMessageId),
                            0,
                            @Now
                        );
                    END;
                END;

                COMMIT;

                -- 3. Trả về thông tin tin nhắn vừa tạo
                SELECT (
                    SELECT
                        @NewMessageId AS id,
                        @ResolvedIncidentId AS incidentId,
                        @ActorId AS senderAccountId,
                        @ChatRole AS senderRole,
                        @SenderName AS senderName,
                        1 AS isMe,
                        @Content AS content,
                        @ImageUrl AS imageUrl,
                        @Now AS sentAt,
                        0 AS isRead
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
        command.Parameters.Add("@IncidentId", SqlDbType.BigInt).Value = (object?)request.IncidentId ?? DBNull.Value;
        command.Parameters.Add("@OrderId", SqlDbType.BigInt).Value = (object?)request.OrderId ?? DBNull.Value;
        command.Parameters.Add("@TripId", SqlDbType.BigInt).Value = (object?)request.TripId ?? DBNull.Value;
        command.Parameters.Add("@Content", SqlDbType.NVarChar, 2000).Value = request.Content.Trim();
        command.Parameters.Add("@ImageUrl", SqlDbType.NVarChar, 500).Value = (object?)request.ImageUrl ?? DBNull.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);
            var result = await command.ExecuteScalarAsync(cancellationToken);
            return Content(result?.ToString() ?? "{}", "application/json");
        }
        catch (SqlException ex) when (ex.Number == 59201)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet("conversations")]
    public async Task<IActionResult> GetConversations(CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var actorId))
        {
            return Unauthorized();
        }

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @Role VARCHAR(50),
                @BranchId INT,
                @ShipperId BIGINT;

            SELECT
                @Role = vt.KyHieuVaiTro,
                @BranchId = tk.MaBuuCuc,
                @ShipperId = nv.MaNhanVienGiaoHang
            FROM dbo.TaiKhoan tk
            JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
            LEFT JOIN dbo.NhanVienGiaoHang nv ON nv.MaTaiKhoan = tk.MaTaiKhoan
            WHERE tk.MaTaiKhoan = @ActorId;

            SELECT (
                SELECT
                    cb.MaCanhBao AS incidentId,
                    cb.MaDonHang AS orderId,
                    dh.KyHieuDonHang AS orderCode,
                    cb.MaChuyenGiao AS tripId,
                    cg.KyHieuChuyenGiao AS tripCode,
                    cb.LoaiCanhBao AS incidentType,
                    cb.MucDoCanhBao AS severity,
                    cb.TrangThaiCanhBao AS status,
                    CASE cb.LoaiCanhBao
                        WHEN 'VEHICLE_BREAKDOWN' THEN N'Hỏng xe'
                        WHEN 'ACCIDENT' THEN N'Tai nạn'
                        WHEN 'DAMAGED_PARCEL' THEN N'Hàng hỏng'
                        ELSE N'Sự cố giao hàng'
                    END AS category,
                    CONCAT(
                        CASE cb.LoaiCanhBao
                            WHEN 'VEHICLE_BREAKDOWN' THEN N'Hỏng xe'
                            WHEN 'ACCIDENT' THEN N'Tai nạn'
                            WHEN 'DAMAGED_PARCEL' THEN N'Hàng hỏng'
                            ELSE N'Sự cố'
                        END,
                        CASE WHEN dh.KyHieuDonHang IS NOT NULL THEN CONCAT(N' · Đơn ', dh.KyHieuDonHang) ELSE N'' END,
                        CASE WHEN cg.KyHieuChuyenGiao IS NOT NULL THEN CONCAT(N' · Chuyến ', cg.KyHieuChuyenGiao) ELSE N'' END
                    ) AS title,
                    (
                        SELECT TOP 1 tn.NoiDung
                        FROM dbo.TinNhanSuCo tn
                        WHERE tn.MaCanhBao = cb.MaCanhBao
                        ORDER BY tn.ThoiGianGui DESC, tn.MaTinNhan DESC
                    ) AS lastMessage,
                    (
                        SELECT TOP 1 tn.TenNguoiGui
                        FROM dbo.TinNhanSuCo tn
                        WHERE tn.MaCanhBao = cb.MaCanhBao
                        ORDER BY tn.ThoiGianGui DESC, tn.MaTinNhan DESC
                    ) AS lastSenderName,
                    (
                        SELECT TOP 1 tn.ThoiGianGui
                        FROM dbo.TinNhanSuCo tn
                        WHERE tn.MaCanhBao = cb.MaCanhBao
                        ORDER BY tn.ThoiGianGui DESC, tn.MaTinNhan DESC
                    ) AS lastMessageAt,
                    (
                        SELECT COUNT(1)
                        FROM dbo.TinNhanSuCo tn
                        WHERE tn.MaCanhBao = cb.MaCanhBao
                        AND tn.MaTaiKhoanGui <> @ActorId
                        AND tn.DaDoc = 0
                    ) AS unreadCount
                FROM dbo.CanhBaoGiaoHang cb
                LEFT JOIN dbo.DonHang dh ON dh.MaDonHang = cb.MaDonHang
                LEFT JOIN dbo.ChuyenGiaoHang cg ON cg.MaChuyenGiao = cb.MaChuyenGiao
                WHERE (
                    -- Nếu là Shipper: xem các cảnh báo mình có liên quan
                    (@Role = 'SHIPPER' AND (
                        EXISTS (
                            SELECT 1 FROM dbo.TinNhanSuCo tn
                            WHERE tn.MaCanhBao = cb.MaCanhBao AND tn.MaTaiKhoanGui = @ActorId
                        )
                        OR EXISTS (
                            SELECT 1 FROM dbo.PhanCongGiaoHang pc
                            WHERE pc.MaDonHang = cb.MaDonHang AND pc.MaNhanVienGiaoHang = @ShipperId
                        )
                        OR cg.MaNhanVienGiaoHang = @ShipperId
                    ))
                    -- Nếu là Điều phối / Admin: xem toàn bộ cảnh báo trong bưu cục
                    OR (@Role <> 'SHIPPER' AND (
                        @BranchId IS NULL OR dh.MaBuuCuc = @BranchId OR cg.MaBuuCuc = @BranchId
                    ))
                )
                ORDER BY cb.ThoiGianPhatHien DESC
                FOR JSON PATH
            );
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@ActorId", SqlDbType.BigInt).Value = actorId;

        await connection.OpenAsync(cancellationToken);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Content(result?.ToString() ?? "[]", "application/json");
    }

    [HttpPost("resolve")]
    public async Task<IActionResult> ResolveIncident(
        [FromBody] ResolveIncidentRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var actorId))
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
                    @SenderName NVARCHAR(100);

                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @SenderName = COALESCE(tk.HoTen, tk.TenDangNhap, N'Hệ thống')
                FROM dbo.TaiKhoan tk
                JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE';

                -- 1. Cập nhật cảnh báo thành RESOLVED
                UPDATE dbo.CanhBaoGiaoHang
                SET
                    TrangThaiCanhBao = 'RESOLVED',
                    ThoiGianXuLy = @Now,
                    MaTaiKhoanXuLy = @ActorId
                WHERE MaCanhBao = @IncidentId;

                -- 2. Ghi tin nhắn kết thúc vào luồng chat
                INSERT INTO dbo.TinNhanSuCo (
                    MaCanhBao,
                    MaTaiKhoanGui,
                    VaiTroNguoiGui,
                    TenNguoiGui,
                    NoiDung,
                    ThoiGianGui,
                    DaDoc
                )
                VALUES (
                    @IncidentId,
                    @ActorId,
                    'SYSTEM',
                    N'Hệ thống',
                    CONCAT(N'✅ Sự cố đã được xử lý xong bởi ', @SenderName,
                           CASE WHEN @ResolutionNote IS NOT NULL AND LEN(TRIM(@ResolutionNote)) > 0
                                THEN CONCAT(N'. Hướng giải quyết: ', TRIM(@ResolutionNote))
                                ELSE N'.' END),
                    @Now,
                    0
                );

                COMMIT;

                SELECT (
                    SELECT
                        @IncidentId AS incidentId,
                        'RESOLVED' AS status,
                        1 AS success,
                        N'Sự cố đã được đánh dấu giải quyết thành công.' AS message
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
        command.Parameters.Add("@IncidentId", SqlDbType.BigInt).Value = request.IncidentId;
        command.Parameters.Add("@ResolutionNote", SqlDbType.NVarChar, 500).Value = (object?)request.ResolutionNote?.Trim() ?? DBNull.Value;

        await connection.OpenAsync(cancellationToken);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Content(result?.ToString() ?? "{}", "application/json");
    }
}
