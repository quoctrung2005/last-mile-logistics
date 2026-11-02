using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class TripActionRequest
{
    [Required]
    [RegularExpression(
        "^(ACCEPT|START|COMPLETE|CANCEL)$",
        ErrorMessage = "Action phải là ACCEPT, START, COMPLETE hoặc CANCEL.")]
    public string Action { get; set; } = "";

    [StringLength(500)]
    public string? Reason { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/trips")]
public class TripActionsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public TripActionsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{id:long}/actions")]
    public async Task<IActionResult> ExecuteAction(
        long id,
        TripActionRequest request,
        CancellationToken cancellationToken)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã chuyến không hợp lệ." });

        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        var reason = request.Reason?.Trim();

        if (request.Action == "CANCEL"
            && string.IsNullOrWhiteSpace(reason))
        {
            return BadRequest(new
            {
                message = "Phải nhập lý do hủy chuyến."
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
                    @AccountBranch INT,
                    @BranchId INT,
                    @ShipperId BIGINT,
                    @VehicleId BIGINT,
                    @TripStatus VARCHAR(20),
                    @PlannedStart DATETIME2(0),
                    @Now DATETIME2(0),
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @RoleId = tk.MaVaiTro,
                    @AccountBranch = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @AccountId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @Role IS NULL
                    THROW 54001,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF @Action = 'CANCEL'
                BEGIN
                    IF @Role = 'SHIPPER'
                       OR NOT EXISTS (
                           SELECT 1
                           FROM dbo.VaiTroQuyen vq
                           JOIN dbo.Quyen q
                               ON q.MaQuyen = vq.MaQuyen
                           WHERE vq.MaVaiTro = @RoleId
                             AND q.KyHieuQuyen = 'DIEUPHOI_PHANCONG'
                       )
                        THROW 54002,
                            N'Bạn không có quyền hủy chuyến.', 1;
                END
                ELSE
                BEGIN
                    IF @Role <> 'SHIPPER'
                       OR NOT EXISTS (
                           SELECT 1
                           FROM dbo.VaiTroQuyen vq
                           JOIN dbo.Quyen q
                               ON q.MaQuyen = vq.MaQuyen
                           WHERE vq.MaVaiTro = @RoleId
                             AND q.KyHieuQuyen = 'NHIEMVU_CAPNHAT'
                       )
                        THROW 54002,
                            N'Thao tác này dành cho shipper của chuyến.', 1;
                END;

                SELECT
                    @BranchId = cg.MaBuuCuc,
                    @ShipperId = cg.MaNhanVienGiaoHang,
                    @VehicleId = cg.MaPhuongTien,
                    @TripStatus = cg.TrangThaiChuyen,
                    @PlannedStart = cg.ThoiGianBatDauDuKien
                FROM dbo.ChuyenGiaoHang cg WITH (UPDLOCK, HOLDLOCK)
                WHERE cg.MaChuyenGiao = @TripId;

                IF @TripStatus IS NULL
                    THROW 54003,
                        N'Không tìm thấy chuyến giao.', 1;

                IF @Role = 'SHIPPER'
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.NhanVienGiaoHang nv WITH (HOLDLOCK)
                        WHERE nv.MaNhanVienGiaoHang = @ShipperId
                          AND nv.MaTaiKhoan = @AccountId
                          AND nv.DangHoatDong = 1
                    )
                        THROW 54003,
                            N'Không tìm thấy chuyến giao.', 1;

                    IF @AccountBranch IS NULL
                       OR @AccountBranch <> @BranchId
                        THROW 54002,
                            N'Chuyến không thuộc bưu cục của bạn.', 1;
                END
                ELSE IF @Role <> 'ADMIN'
                     AND (
                         @AccountBranch IS NULL
                         OR @AccountBranch <> @BranchId
                     )
                    THROW 54003,
                        N'Không tìm thấy chuyến giao.', 1;

                SELECT @OldJson = (
                    SELECT
                        cg.MaChuyenGiao AS id,
                        cg.TrangThaiChuyen AS status,
                        cg.ThoiGianBatDauThucTe AS startedAt,
                        cg.ThoiGianKetThucThucTe AS endedAt
                    FROM dbo.ChuyenGiaoHang cg
                    WHERE cg.MaChuyenGiao = @TripId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                CREATE TABLE #Orders (
                    OrderId BIGINT NOT NULL PRIMARY KEY,
                    OrderStatus VARCHAR(30) NOT NULL,
                    Processed BIT NOT NULL DEFAULT 0
                );

                INSERT INTO #Orders (OrderId, OrderStatus)
                SELECT
                    d.MaDonHang,
                    tt.KyHieuTrangThai
                FROM dbo.ChiTietChuyenGiao ct WITH (HOLDLOCK)
                JOIN dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                    ON d.MaDonHang = ct.MaDonHang
                JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE ct.MaChuyenGiao = @TripId;

                IF NOT EXISTS (SELECT 1 FROM #Orders)
                    THROW 54004,
                        N'Chuyến chưa có đơn hàng.', 1;

                SELECT
                    pc.MaPhanCongGiaoHang AS AssignmentId,
                    pc.MaDonHang AS OrderId,
                    pc.MaNhanVienGiaoHang AS ShipperId,
                    pc.MaPhuongTien AS VehicleId,
                    pc.TrangThaiPhanCong AS AssignmentStatus
                INTO #Assignments
                FROM dbo.PhanCongGiaoHang pc WITH (UPDLOCK, HOLDLOCK)
                JOIN #Orders o ON o.OrderId = pc.MaDonHang
                WHERE pc.MaChuyenGiao = @TripId
                  AND pc.ThoiGianKetThuc IS NULL;

                SET @Now = SYSUTCDATETIME();

                -- Nhận chuyến hoặc bắt đầu chuyến:
                -- kiểm tra lại shipper, bằng lái và xe đang được giao.
                IF @Action IN ('ACCEPT', 'START')
                BEGIN
                    IF @ShipperId IS NULL OR @VehicleId IS NULL
                        THROW 54004,
                            N'Chuyến chưa được phân công shipper và xe.', 1;

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.NhanVienGiaoHang nv
                            WITH (UPDLOCK, HOLDLOCK)
                        JOIN dbo.TaiKhoan tk WITH (HOLDLOCK)
                            ON tk.MaTaiKhoan = nv.MaTaiKhoan
                        JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                            ON vt.MaVaiTro = tk.MaVaiTro
                        WHERE nv.MaNhanVienGiaoHang = @ShipperId
                          AND nv.DangHoatDong = 1
                          AND nv.TrangThaiSanSang
                              IN ('AVAILABLE', 'DELIVERING')
                          AND (
                              nv.NgayHetHanBangLai IS NULL
                              OR nv.NgayHetHanBangLai >=
                                  CONVERT(DATE, @Now)
                          )
                          AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                          AND tk.MaBuuCuc = @BranchId
                          AND (
                              tk.KhoaDenLuc IS NULL
                              OR tk.KhoaDenLuc <= @Now
                          )
                          AND vt.KyHieuVaiTro = 'SHIPPER'
                          AND vt.DangHoatDong = 1
                    )
                        THROW 54004,
                            N'Shipper hiện không đủ điều kiện thực hiện chuyến.', 1;

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.PhuongTien pt
                            WITH (UPDLOCK, HOLDLOCK)
                        JOIN dbo.PhanCongPhuongTien pcp
                            WITH (UPDLOCK, HOLDLOCK)
                            ON pcp.MaPhuongTien = pt.MaPhuongTien
                        WHERE pt.MaPhuongTien = @VehicleId
                          AND pt.DangHoatDong = 1
                          AND pt.TrangThaiPhuongTien
                              IN ('AVAILABLE', 'IN_USE')
                          AND pcp.MaNhanVienGiaoHang = @ShipperId
                          AND pcp.ThoiGianKetThuc IS NULL
                    )
                        THROW 54004,
                            N'Xe không còn hợp lệ hoặc không còn được giao cho shipper.', 1;

                    IF (
                        SELECT COUNT(*) FROM #Assignments
                    ) <> (
                        SELECT COUNT(*) FROM #Orders
                    )
                       OR EXISTS (
                           SELECT 1
                           FROM #Assignments
                           WHERE ShipperId <> @ShipperId
                              OR VehicleId IS NULL
                              OR VehicleId <> @VehicleId
                       )
                        THROW 54004,
                            N'Phân công của các đơn không còn khớp với chuyến.', 1;
                END;

                IF @Action = 'ACCEPT'
                BEGIN
                    IF @TripStatus <> 'ASSIGNED'
                        THROW 54004,
                            N'Chỉ chuyến ASSIGNED mới được nhận.', 1;

                    IF EXISTS (
                        SELECT 1 FROM #Orders
                        WHERE OrderStatus <> 'ASSIGNED'
                    )
                       OR EXISTS (
                           SELECT 1 FROM #Assignments
                           WHERE AssignmentStatus
                               NOT IN ('PENDING', 'ACCEPTED')
                       )
                        THROW 54004,
                            N'Các đơn phải còn ASSIGNED và chưa bàn giao hàng.', 1;

                    UPDATE dbo.PhanCongGiaoHang
                    SET TrangThaiPhanCong = 'ACCEPTED',
                        ThoiGianChapNhan = @Now
                    WHERE MaChuyenGiao = @TripId
                      AND TrangThaiPhanCong = 'PENDING'
                      AND ThoiGianKetThuc IS NULL;

                    UPDATE dbo.ChuyenGiaoHang
                    SET TrangThaiChuyen = 'ACCEPTED'
                    WHERE MaChuyenGiao = @TripId;
                END
                ELSE IF @Action = 'START'
                BEGIN
                    IF @TripStatus <> 'ACCEPTED'
                        THROW 54004,
                            N'Chỉ chuyến ACCEPTED mới được bắt đầu.', 1;

                    IF @PlannedStart IS NOT NULL
                       AND @Now < @PlannedStart
                        THROW 54004,
                            N'Chưa đến thời gian bắt đầu dự kiến.', 1;

                    IF EXISTS (
                        SELECT 1 FROM #Orders
                        WHERE OrderStatus <> 'PICKED_UP'
                    )
                       OR EXISTS (
                           SELECT 1 FROM #Assignments
                           WHERE AssignmentStatus <> 'IN_PROGRESS'
                       )
                        THROW 54004,
                            N'Phải xuất kho và xác nhận nhận đủ hàng của chuyến trước khi bắt đầu.', 1;

                    UPDATE dbo.ChuyenGiaoHang
                    SET TrangThaiChuyen = 'IN_PROGRESS',
                        ThoiGianBatDauThucTe = @Now
                    WHERE MaChuyenGiao = @TripId;

                    UPDATE dbo.NhanVienGiaoHang
                    SET TrangThaiSanSang = 'DELIVERING'
                    WHERE MaNhanVienGiaoHang = @ShipperId;

                    UPDATE dbo.PhuongTien
                    SET TrangThaiPhuongTien = 'IN_USE'
                    WHERE MaPhuongTien = @VehicleId;
                END
                ELSE IF @Action = 'COMPLETE'
                BEGIN
                    IF @TripStatus <> 'IN_PROGRESS'
                        THROW 54004,
                            N'Chỉ chuyến IN_PROGRESS mới được hoàn tất.', 1;

                    IF EXISTS (
                        SELECT 1 FROM #Orders
                        WHERE OrderStatus NOT IN (
                            'DELIVERED', 'RETURNED',
                            'COMPLETED', 'CANCELLED'
                        )
                    )
                        THROW 54004,
                            N'Chuyến còn đơn chưa giao xong hoặc chưa hoàn hàng xong.', 1;

                    IF EXISTS (SELECT 1 FROM #Assignments)
                        THROW 54004,
                            N'Chuyến còn phân công đang hoạt động.', 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.YeuCauGiaoLaiHoacHoan yc
                            WITH (UPDLOCK, HOLDLOCK)
                        JOIN #Orders o ON o.OrderId = yc.MaDonHang
                        WHERE yc.TrangThaiYeuCau IN (
                            'PENDING', 'APPROVED', 'IN_PROGRESS'
                        )
                    )
                        THROW 54004,
                            N'Chuyến còn yêu cầu giao lại hoặc hoàn hàng chưa xử lý xong.', 1;

                    UPDATE dbo.ChuyenGiaoHang
                    SET TrangThaiChuyen = 'COMPLETED',
                        ThoiGianKetThucThucTe = @Now
                    WHERE MaChuyenGiao = @TripId;

                    -- Trạng thái sẵn sàng của shipper và xe được
                    -- quản lý riêng vì có thể còn nhiệm vụ khác.
                END
                ELSE IF @Action = 'CANCEL'
                BEGIN
                    IF @TripStatus NOT IN (
                        'PLANNED', 'ASSIGNED', 'ACCEPTED'
                    )
                        THROW 54004,
                            N'Chỉ được hủy chuyến trước khi bắt đầu và trước khi bàn giao hàng.', 1;

                    IF @TripStatus = 'PLANNED'
                    BEGIN
                        IF EXISTS (
                            SELECT 1 FROM #Orders
                            WHERE OrderStatus <> 'WAITING_ASSIGNMENT'
                        )
                           OR EXISTS (
                               SELECT 1
                               FROM dbo.PhanCongGiaoHang pc
                                   WITH (UPDLOCK, HOLDLOCK)
                               JOIN #Orders o
                                   ON o.OrderId = pc.MaDonHang
                               WHERE pc.ThoiGianKetThuc IS NULL
                           )
                            THROW 54004,
                                N'Các đơn của chuyến nháp không còn sẵn sàng để hủy chuyến.', 1;
                    END
                    ELSE
                    BEGIN
                        IF EXISTS (
                            SELECT 1 FROM #Orders
                            WHERE OrderStatus <> 'ASSIGNED'
                        )
                           OR (
                               SELECT COUNT(*) FROM #Assignments
                           ) <> (
                               SELECT COUNT(*) FROM #Orders
                           )
                           OR EXISTS (
                               SELECT 1 FROM #Assignments
                               WHERE AssignmentStatus
                                   NOT IN ('PENDING', 'ACCEPTED')
                           )
                            THROW 54004,
                                N'Không thể hủy: đơn đã bàn giao hoặc phân công đã thay đổi.', 1;

                        UPDATE dbo.PhanCongGiaoHang
                        SET TrangThaiPhanCong = 'CANCELLED',
                            ThoiGianKetThuc = @Now
                        WHERE MaChuyenGiao = @TripId
                          AND ThoiGianKetThuc IS NULL;

                        DECLARE @OrderId BIGINT;

                        WHILE EXISTS (
                            SELECT 1 FROM #Orders
                            WHERE Processed = 0
                        )
                        BEGIN
                            SELECT TOP (1)
                                @OrderId = OrderId
                            FROM #Orders
                            WHERE Processed = 0
                            ORDER BY OrderId;

                            EXEC dbo.sp_ChuyenTrangThaiDonHang
                                @MaDonHang = @OrderId,
                                @KyHieuTrangThaiMoi = 'WAITING_ASSIGNMENT',
                                @MaTaiKhoan = @AccountId,
                                @LyDo = @Reason,
                                @NguonCapNhat = 'API';

                            UPDATE #Orders
                            SET Processed = 1
                            WHERE OrderId = @OrderId;
                        END;
                    END;

                    UPDATE dbo.ChuyenGiaoHang
                    SET TrangThaiChuyen = 'CANCELLED'
                    WHERE MaChuyenGiao = @TripId;

                    -- Giữ chi tiết chuyến và phân công cũ để lưu lịch sử.
                    -- Không hủy các đơn hàng.
                END;

                SELECT @Result = (
                    SELECT
                        cg.MaChuyenGiao AS id,
                        cg.KyHieuChuyenGiao AS tripCode,
                        @Action AS action,
                        cg.TrangThaiChuyen AS status,
                        cg.MaNhanVienGiaoHang AS shipperId,
                        cg.MaPhuongTien AS vehicleId,
                        cg.ThoiGianBatDauThucTe AS startedAt,
                        cg.ThoiGianKetThucThucTe AS endedAt,
                        (
                            SELECT COUNT(*)
                            FROM dbo.ChiTietChuyenGiao ct
                            WHERE ct.MaChuyenGiao = @TripId
                        ) AS orderCount,
                        CASE @Action
                            WHEN 'ACCEPT' THEN N'Nhận chuyến thành công.'
                            WHEN 'START' THEN N'Bắt đầu chuyến thành công.'
                            WHEN 'COMPLETE' THEN N'Hoàn tất chuyến thành công.'
                            ELSE N'Hủy chuyến thành công.'
                        END AS message
                    FROM dbo.ChuyenGiaoHang cg
                    WHERE cg.MaChuyenGiao = @TripId
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
                    CONCAT('TRIP_', @Action),
                    'ChuyenGiaoHang',
                    CONVERT(VARCHAR(100), @TripId),
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

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@TripId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Action", SqlDbType.VarChar, 20).Value = request.Action;

        command.Parameters.Add(
            "@Reason", SqlDbType.NVarChar, 500).Value =
            string.IsNullOrWhiteSpace(reason)
                ? DBNull.Value
                : reason;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 54001)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54002)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54003)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (
            ex.Number >= 51000 && ex.Number <= 54004)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy tải lại và thử lại."
            });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627 or 547)
        {
            return Conflict(new
            {
                message = "Dữ liệu chuyến hoặc phân công không còn phù hợp. Hãy tải lại."
            });
        }
    }
}