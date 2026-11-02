using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class WarehouseReturnInRequest
{
    [Range(1, long.MaxValue)]
    public long OrderId { get; set; }

    [Range(1, long.MaxValue)]
    public long ReturnRequestId { get; set; }

    [Range(1, int.MaxValue)]
    public int WarehouseId { get; set; }

    [Range(1, long.MaxValue)]
    public long LocationId { get; set; }

    [Required]
    [StringLength(20)]
    public string Condition { get; set; } = "NORMAL";

    [StringLength(500)]
    public string? Notes { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/warehouse-transactions")]
public class WarehouseReturnInController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public WarehouseReturnInController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("return-in")]
    public async Task<IActionResult> ReturnIn(
        [FromBody] WarehouseReturnInRequest request)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        var condition = request.Condition.Trim().ToUpperInvariant();

        if (condition is not ("NORMAL" or "DAMAGED" or "OTHER"))
        {
            return BadRequest(new
            {
                message = "Condition chỉ nhận NORMAL, DAMAGED hoặc OTHER."
            });
        }

        var notes = string.IsNullOrWhiteSpace(request.Notes)
            ? null
            : request.Notes.Trim();

        if (condition != "NORMAL" && notes is null)
        {
            return BadRequest(new
            {
                message = "Phải ghi chú tình trạng khi hàng hư hỏng hoặc có vấn đề khác."
            });
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
                    @OrderBranchId INT,
                    @OrderWarehouseId INT,
                    @OrderStatus VARCHAR(40),
                    @ReturnBranchId INT,
                    @RequestStatus VARCHAR(20),
                    @ReturnReason NVARCHAR(500),
                    @OldStockWarehouseId INT,
                    @OldStockStatus VARCHAR(20),
                    @WarehouseName NVARCHAR(150),
                    @LocationCode VARCHAR(100),
                    @TransactionId BIGINT,
                    @TransactionCode VARCHAR(40),
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
                    THROW 52401,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'KHO_NHAP'
                )
                    THROW 52402,
                        N'Bạn không có quyền nhập kho hàng hoàn.',
                        1;

                IF @Role <> 'ADMIN'
                   AND @AccountBranchId IS NULL
                    THROW 52402,
                        N'Tài khoản chưa được gán bưu cục.',
                        1;

                SELECT
                    @OrderBranchId = d.MaBuuCuc,
                    @OrderWarehouseId = d.MaKhoHienTai,
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
                    THROW 52403,
                        N'Không tìm thấy đơn hàng.',
                        1;

                IF @OrderStatus <> 'RETURNING'
                    THROW 52404,
                        N'Chỉ đơn RETURNING mới được nhập kho hàng hoàn.',
                        1;

                IF @OrderWarehouseId IS NOT NULL
                    THROW 52404,
                        N'Đơn đã có kho hiện tại. Hãy kiểm tra lại tồn kho.',
                        1;

                SELECT
                    @ReturnBranchId = MaBuuCucHoan,
                    @RequestStatus = TrangThaiYeuCau,
                    @ReturnReason = LyDo
                FROM dbo.YeuCauGiaoLaiHoacHoan
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE MaYeuCauGiaoLaiHoacHoan = @ReturnRequestId
                  AND MaDonHang = @OrderId
                  AND LoaiYeuCau = 'RETURN';

                IF @RequestStatus IS NULL
                    THROW 52403,
                        N'Không tìm thấy yêu cầu hoàn của đơn.',
                        1;

                IF @RequestStatus <> 'IN_PROGRESS'
                    THROW 52404,
                        N'Yêu cầu hoàn phải ở trạng thái IN_PROGRESS.',
                        1;

                IF @ReturnBranchId IS NULL
                   OR @ReturnBranchId <> @OrderBranchId
                    THROW 52404,
                        N'Luồng hiện tại chỉ nhận hoàn về bưu cục gốc của đơn.',
                        1;

                SELECT @WarehouseName = k.TenKho
                FROM dbo.Kho k
                INNER JOIN dbo.BuuCuc b
                    ON b.MaBuuCuc = k.MaBuuCuc
                WHERE k.MaKho = @WarehouseId
                  AND k.MaBuuCuc = @ReturnBranchId
                  AND k.DangHoatDong = 1
                  AND b.DangHoatDong = 1;

                IF @WarehouseName IS NULL
                    THROW 52404,
                        N'Kho nhận hoàn không hợp lệ hoặc không thuộc bưu cục nhận hoàn.',
                        1;

                SELECT @LocationCode = KyHieuViTri
                FROM dbo.ViTriLuuKho
                WHERE MaViTriLuuKho = @LocationId
                  AND MaKho = @WarehouseId
                  AND DangHoatDong = 1;

                IF @LocationCode IS NULL
                    THROW 52404,
                        N'Vị trí nhận hoàn không thuộc kho hoặc đã ngừng hoạt động.',
                        1;

                SELECT
                    @OldStockWarehouseId = MaKho,
                    @OldStockStatus = TrangThaiTonKho
                FROM dbo.TonKhoDonHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaDonHang = @OrderId;

                IF @OldStockWarehouseId IS NULL
                   OR @OldStockStatus <> 'HANDED_OVER'
                    THROW 52404,
                        N'Đơn phải có bản ghi tồn kho HANDED_OVER từ lần xuất kho trước.',
                        1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongGiaoHang
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE MaDonHang = @OrderId
                      AND ThoiGianKetThuc IS NULL
                )
                    THROW 52404,
                        N'Phân công giao chưa được kết thúc. Hãy kiểm tra bước bắt đầu hoàn.',
                        1;

                SET @OldJson = (
                    SELECT
                        @OrderId AS orderId,
                        @OrderStatus AS orderStatus,
                        @ReturnRequestId AS returnRequestId,
                        @RequestStatus AS requestStatus,
                        @OldStockWarehouseId AS previousWarehouseId,
                        @OldStockStatus AS stockStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                SET @Now = SYSUTCDATETIME();

                SET @TransactionCode =
                    'NH-' + REPLACE(
                        CONVERT(VARCHAR(36), NEWID()), '-', ''
                    );

                INSERT INTO dbo.GiaoDichKho (
                    KyHieuGiaoDich,
                    MaKho,
                    LoaiGiaoDich,
                    TrangThaiGiaoDich,
                    MaTaiKhoanThucHien,
                    ThoiGianThucHien,
                    GhiChu
                )
                VALUES (
                    @TransactionCode,
                    @WarehouseId,
                    'RETURN_IN',
                    'COMPLETED',
                    @AccountId,
                    @Now,
                    @Notes
                );

                SET @TransactionId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.ChiTietGiaoDichKho (
                    MaGiaoDichKho,
                    MaDonHang,
                    MaViTriNguon,
                    MaViTriDich,
                    TinhTrangHang,
                    GhiChu
                )
                VALUES (
                    @TransactionId,
                    @OrderId,
                    NULL,
                    @LocationId,
                    @Condition,
                    @Notes
                );

                -- Tái sử dụng bản ghi tồn kho của đơn.
                -- Lịch sử xuất/nhập được giữ trong giao dịch kho.
                UPDATE dbo.TonKhoDonHang
                SET MaKho = @WarehouseId,
                    MaViTriLuuKho = @LocationId,
                    TrangThaiTonKho = 'RETURNED',
                    ThoiGianNhapKho = @Now,
                    ThoiGianDiChuyenCuoi = @Now,
                    MaTaiKhoanCapNhatCuoi = @AccountId
                WHERE MaDonHang = @OrderId;

                UPDATE dbo.DonHang
                SET MaKhoHienTai = @WarehouseId,
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = @Now
                WHERE MaDonHang = @OrderId;

                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'RETURNED',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = @ReturnReason,
                    @NguonCapNhat = 'API';

                UPDATE dbo.YeuCauGiaoLaiHoacHoan
                SET TrangThaiYeuCau = 'COMPLETED',
                    ThoiGianHoanTat = @Now
                WHERE MaYeuCauGiaoLaiHoacHoan = @ReturnRequestId;

                -- Ghi nhận thù lao chuyển hoàn cho tài xế
                DECLARE @ReturnWage DECIMAL(18,2) = 8000, @ReturnShipperId BIGINT, @ReturnAssignmentId BIGINT;
                SELECT TOP 1 @ReturnWage = TienCongChuyenHoan
                FROM dbo.CauHinhTienCong WHERE DangHoatDong = 1 ORDER BY MaCauHinh DESC;

                SELECT TOP 1 @ReturnShipperId = p.MaNhanVienGiaoHang, @ReturnAssignmentId = p.MaPhanCongGiaoHang
                FROM dbo.PhanCongGiaoHang p
                WHERE p.MaDonHang = @OrderId
                ORDER BY p.MaPhanCongGiaoHang DESC;

                IF @ReturnShipperId IS NOT NULL 
                   AND NOT EXISTS (SELECT 1 FROM dbo.ThuNhapTaiXe WHERE MaDonHang = @OrderId AND LoaiThuNhap = 'RETURN_COMPLETED')
                BEGIN
                    INSERT INTO dbo.ThuNhapTaiXe (
                        MaNhanVienGiaoHang, MaDonHang, MaPhanCongGiaoHang, LoaiThuNhap, SoTien, TrangThai, ThoiGianGhiNhan, GhiChu
                    )
                    SELECT 
                        @ReturnShipperId, @OrderId, @ReturnAssignmentId, 'RETURN_COMPLETED', @ReturnWage, 'APPROVED', @Now,
                        N'Thù lao hoàn tất thủ tục trả hàng hoàn đơn ' + d.KyHieuDonHang
                    FROM dbo.DonHang d WHERE d.MaDonHang = @OrderId;
                END;

                SET @Result = (
                    SELECT
                        @TransactionId AS transactionId,
                        @TransactionCode AS transactionCode,
                        @OrderId AS orderId,
                        @ReturnRequestId AS returnRequestId,
                        @WarehouseId AS warehouseId,
                        @WarehouseName AS warehouseName,
                        @LocationId AS locationId,
                        @LocationCode AS locationCode,
                        tt.KyHieuTrangThai AS orderStatus,
                        'RETURNED' AS stockStatus,
                        'COMPLETED' AS requestStatus,
                        @Condition AS condition,
                        @Now AS receivedAt,
                        d.PhienBan AS version,
                        N'Đã nhập kho hàng hoàn và hoàn tất yêu cầu hoàn.'
                            AS message
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
                    'WAREHOUSE_RETURN_IN',
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
            "@OrderId", SqlDbType.BigInt).Value = request.OrderId;

        command.Parameters.Add(
            "@ReturnRequestId", SqlDbType.BigInt).Value =
                request.ReturnRequestId;

        command.Parameters.Add(
            "@WarehouseId", SqlDbType.Int).Value = request.WarehouseId;

        command.Parameters.Add(
            "@LocationId", SqlDbType.BigInt).Value = request.LocationId;

        command.Parameters.Add(
            "@Condition", SqlDbType.VarChar, 20).Value = condition;

        command.Parameters.Add(
            "@Notes", SqlDbType.NVarChar, 500).Value =
                (object?)notes ?? DBNull.Value;

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
            ex.Number is >= 52401 and <= 52404)
        {
            var statusCode = ex.Number switch
            {
                52401 => StatusCodes.Status401Unauthorized,
                52402 => StatusCodes.Status403Forbidden,
                52403 => StatusCodes.Status404NotFound,
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
                    "Có thao tác đồng thời. Hãy tải lại tồn kho và thử lại."
            });
        }
    }
}