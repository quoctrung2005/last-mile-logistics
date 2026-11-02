using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.SqlClient;
using LastMile.Api.Hubs;

namespace LastMile.Api.Controllers;

public class WarehouseOutboundRequest
{
    [Range(1, long.MaxValue)]
    public long OrderId { get; set; }

    [Range(1, int.MaxValue)]
    public int WarehouseId { get; set; }

    [Range(1, long.MaxValue)]
    public long AssignmentId { get; set; }

    [Range(1, long.MaxValue)]
    public long FromLocationId { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/warehouse-transactions")]
public class WarehouseOutboundController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly IHubContext<ShipperHub> _hub;

    public WarehouseOutboundController(
        IConfiguration configuration,
        IHubContext<ShipperHub> hub)
    {
        _configuration = configuration;
        _hub = hub;
    }

    [HttpPost("outbound")]
    public async Task<IActionResult> Outbound(
        [FromBody] WarehouseOutboundRequest request)
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
                    @ShipperId BIGINT,
                    @VehicleId BIGINT,
                    @AssignmentStatus VARCHAR(20),
                    @AssignmentEndedAt DATETIME2(0),
                    @StockWarehouseId INT,
                    @LocationId BIGINT,
                    @StockStatus VARCHAR(20),
                    @MaxWeight DECIMAL(10,2),
                    @MaxVolume DECIMAL(10,3),
                    @TotalWeight DECIMAL(28,3),
                    @TotalVolume DECIMAL(28,6),
                    @MissingDimensions INT,
                    @TransactionId BIGINT,
                    @HandoverId BIGINT,
                    @TransactionCode VARCHAR(40),
                    @HandoverCode VARCHAR(40),
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
                    THROW 51501,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'KHO_XUAT'
                )
                    THROW 51502,
                        N'Bạn không có quyền xuất kho.',
                        1;

                IF @Role <> 'ADMIN'
                   AND @AccountBranchId IS NULL
                    THROW 51502,
                        N'Tài khoản chưa được gán bưu cục.',
                        1;

                SELECT
                    @OrderBranchId = d.MaBuuCuc,
                    @OrderWarehouseId = d.MaKhoHienTai,
                    @OrderStatus = tt.KyHieuTrangThai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (
                      @Role = 'ADMIN'
                      OR d.MaBuuCuc = @AccountBranchId
                  );

                IF @OrderBranchId IS NULL
                    THROW 51503,
                        N'Không tìm thấy đơn hàng.',
                        1;

                IF @OrderStatus <> 'ASSIGNED'
                    THROW 51504,
                        N'Chỉ đơn ASSIGNED mới được xuất kho bàn giao.',
                        1;

                IF @OrderWarehouseId IS NULL
                   OR @OrderWarehouseId <> @WarehouseId
                    THROW 51504,
                        N'Kho yêu cầu không khớp kho hiện tại của đơn.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.Kho k
                    INNER JOIN dbo.BuuCuc b
                        ON b.MaBuuCuc = k.MaBuuCuc
                    WHERE k.MaKho = @WarehouseId
                      AND k.MaBuuCuc = @OrderBranchId
                      AND k.DangHoatDong = 1
                      AND b.DangHoatDong = 1
                )
                    THROW 51504,
                        N'Kho hoặc bưu cục không còn hoạt động.',
                        1;

                SELECT
                    @ShipperId = pc.MaNhanVienGiaoHang,
                    @VehicleId = pc.MaPhuongTien,
                    @AssignmentStatus = pc.TrangThaiPhanCong,
                    @AssignmentEndedAt = pc.ThoiGianKetThuc
                FROM dbo.PhanCongGiaoHang pc
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                  AND pc.MaDonHang = @OrderId;

                IF @ShipperId IS NULL
                    THROW 51503,
                        N'Không tìm thấy phân công của đơn.',
                        1;

                IF @AssignmentEndedAt IS NOT NULL
                   OR @AssignmentStatus <> 'ACCEPTED'
                    THROW 51504,
                        N'Shipper phải nhận nhiệm vụ trước khi xuất kho.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.NhanVienGiaoHang nv
                        WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.TaiKhoan tk
                        ON tk.MaTaiKhoan = nv.MaTaiKhoan
                    INNER JOIN dbo.VaiTro vt
                        ON vt.MaVaiTro = tk.MaVaiTro
                    WHERE nv.MaNhanVienGiaoHang = @ShipperId
                      AND nv.DangHoatDong = 1
                      AND nv.TrangThaiSanSang IN (
                          'AVAILABLE', 'DELIVERING'
                      )
                      AND (
                          nv.NgayHetHanBangLai IS NULL
                          OR nv.NgayHetHanBangLai >= CAST(@Now AS DATE)
                      )
                      AND tk.MaBuuCuc = @OrderBranchId
                      AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                      AND (
                          tk.KhoaDenLuc IS NULL
                          OR tk.KhoaDenLuc <= @Now
                      )
                      AND vt.KyHieuVaiTro = 'SHIPPER'
                      AND vt.DangHoatDong = 1
                )
                    THROW 51504,
                        N'Shipper không còn đủ điều kiện nhận bàn giao.',
                        1;

                SELECT
                    @MaxWeight = KhoiLuongDenKg,
                    @MaxVolume = TheTichToiDaM3
                FROM dbo.PhuongTien WITH (UPDLOCK, HOLDLOCK)
                WHERE MaPhuongTien = @VehicleId
                  AND DangHoatDong = 1
                  AND TrangThaiPhuongTien IN ('AVAILABLE', 'IN_USE');

                IF @MaxWeight IS NULL
                    THROW 51504,
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
                    THROW 51504,
                        N'Phương tiện không còn được phân cho shipper.',
                        1;

                SELECT @TotalWeight = SUM(d.TongKhoiLuongKg)
                FROM dbo.PhanCongGiaoHang pc
                INNER JOIN dbo.DonHang d
                    ON d.MaDonHang = pc.MaDonHang
                WHERE pc.MaPhuongTien = @VehicleId
                  AND pc.ThoiGianKetThuc IS NULL;

                IF @TotalWeight > @MaxWeight
                    THROW 51504,
                        N'Các đơn đang phân công vượt tải trọng xe.',
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
                    FROM dbo.PhanCongGiaoHang pc
                    INNER JOIN dbo.ChiTietDonHang ct
                        ON ct.MaDonHang = pc.MaDonHang
                    WHERE pc.MaPhuongTien = @VehicleId
                      AND pc.ThoiGianKetThuc IS NULL;

                    IF @MissingDimensions = 1
                       OR @TotalVolume > @MaxVolume
                        THROW 51504,
                            N'Không đủ dữ liệu kích thước hoặc hàng vượt thể tích xe.',
                            1;
                END;

                SELECT
                    @StockWarehouseId = t.MaKho,
                    @LocationId = t.MaViTriLuuKho,
                    @StockStatus = t.TrangThaiTonKho
                FROM dbo.TonKhoDonHang t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.MaDonHang = @OrderId;

                IF @StockWarehouseId IS NULL
                   OR @StockWarehouseId <> @WarehouseId
                   OR @StockStatus NOT IN ('STORED', 'ALLOCATED')
                   OR @LocationId IS NULL
                    THROW 51504,
                        N'Đơn không còn trong tồn kho phù hợp để xuất.',
                        1;

                IF @LocationId <> @FromLocationId
                    THROW 51504,
                        N'Vị trí nguồn không khớp. Hãy tải lại tồn kho.',
                        1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.ViTriLuuKho
                    WHERE MaViTriLuuKho = @LocationId
                      AND MaKho = @WarehouseId
                      AND DangHoatDong = 1
                )
                    THROW 51504,
                        N'Vị trí lưu kho không còn hoạt động.',
                        1;

                SET @OldJson = (
                    SELECT
                        @OrderId AS orderId,
                        @OrderStatus AS orderStatus,
                        @WarehouseId AS warehouseId,
                        @LocationId AS locationId,
                        @StockStatus AS stockStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                SET @Now = SYSUTCDATETIME();

                SET @TransactionCode =
                    'XK-' + REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');

                SET @HandoverCode =
                    'BG-' + REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');

                INSERT INTO dbo.GiaoDichKho (
                    KyHieuGiaoDich, MaKho, LoaiGiaoDich,
                    TrangThaiGiaoDich, MaTaiKhoanThucHien,
                    ThoiGianThucHien, GhiChu
                )
                VALUES (
                    @TransactionCode, @WarehouseId, 'OUTBOUND',
                    'COMPLETED', @AccountId, @Now, @Notes
                );

                SET @TransactionId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.ChiTietGiaoDichKho (
                    MaGiaoDichKho, MaDonHang,
                    MaViTriNguon, MaViTriDich,
                    TinhTrangHang, GhiChu
                )
                VALUES (
                    @TransactionId, @OrderId,
                    @LocationId, NULL, 'NORMAL', @Notes
                );

                INSERT INTO dbo.BanGiaoHang (
                    KyHieuBanGiao, MaKho,
                    MaNhanVienGiaoHang, MaTaiKhoanBanGiao,
                    TrangThaiBanGiao, ThoiGianBanGiao, GhiChu
                )
                VALUES (
                    @HandoverCode, @WarehouseId,
                    @ShipperId, @AccountId,
                    'PENDING', @Now, @Notes
                );

                SET @HandoverId =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                -- Phải thêm chi tiết bàn giao khi hàng còn trong kho
                -- để đáp ứng trigger kiểm tra bàn giao.
                -- Một dòng tương ứng một đơn được bàn giao.
                INSERT INTO dbo.ChiTietBanGiaoHang (
                    MaBanGiao, MaDonHang, SoLuong, GhiChuTinhTrang
                )
                VALUES (
                    @HandoverId, @OrderId, 1, @Notes
                );

                UPDATE dbo.TonKhoDonHang
                SET TrangThaiTonKho = 'HANDED_OVER',
                    MaViTriLuuKho = NULL,
                    ThoiGianDiChuyenCuoi = @Now,
                    MaTaiKhoanCapNhatCuoi = @AccountId
                WHERE MaDonHang = @OrderId;

                UPDATE dbo.DonHang
                SET MaKhoHienTai = NULL,
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = @Now
                WHERE MaDonHang = @OrderId;

                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'HANDED_OVER',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = @Notes,
                    @NguonCapNhat = 'API';

                SET @NewJson = (
                    SELECT
                        @OrderId AS orderId,
                        'HANDED_OVER' AS orderStatus,
                        @TransactionId AS transactionId,
                        @HandoverId AS handoverId,
                        @ShipperId AS shipperId,
                        @AssignmentId AS assignmentId,
                        'PENDING' AS handoverStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan, LoaiThaoTac,
                    TenDoiTuong, MaDoiTuong,
                    DuLieuCuJson, DuLieuMoiJson
                )
                VALUES (
                    @AccountId, 'WAREHOUSE_OUTBOUND',
                    'DonHang', CONVERT(VARCHAR(100), @OrderId),
                    @OldJson, @NewJson
                );

                SET @Result = (
                    SELECT
                        @TransactionId AS transactionId,
                        @TransactionCode AS transactionCode,
                        @HandoverId AS handoverId,
                        @HandoverCode AS handoverCode,
                        @OrderId AS orderId,
                        @WarehouseId AS warehouseId,
                        @AssignmentId AS assignmentId,
                        @ShipperId AS shipperId,
                        @VehicleId AS vehicleId,
                        'HANDED_OVER' AS orderStatus,
                        'PENDING' AS handoverStatus,
                        @Now AS handedOverAt,
                        N'Đã xuất kho. Chờ shipper xác nhận nhận hàng.'
                            AS message
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
            "@OrderId", SqlDbType.BigInt).Value = request.OrderId;

        command.Parameters.Add(
            "@WarehouseId", SqlDbType.Int).Value = request.WarehouseId;

        command.Parameters.Add(
            "@AssignmentId", SqlDbType.BigInt).Value =
                request.AssignmentId;

        command.Parameters.Add(
            "@FromLocationId", SqlDbType.BigInt).Value =
                request.FromLocationId;

        command.Parameters.Add(
            "@Notes", SqlDbType.NVarChar, 500).Value =
                (object?)notes ?? DBNull.Value;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            try
            {
                const string accountSql = """
                    SELECT nv.MaTaiKhoan
                    FROM dbo.PhanCongGiaoHang pc
                    INNER JOIN dbo.NhanVienGiaoHang nv
                        ON nv.MaNhanVienGiaoHang = pc.MaNhanVienGiaoHang
                    WHERE pc.MaPhanCongGiaoHang = @AssignmentId
                      AND pc.MaDonHang = @OrderId;
                    """;
                await using var accountCommand = new SqlCommand(
                    accountSql,
                    connection);
                accountCommand.Parameters.Add(
                    "@AssignmentId", SqlDbType.BigInt).Value =
                        request.AssignmentId;
                accountCommand.Parameters.Add(
                    "@OrderId", SqlDbType.BigInt).Value = request.OrderId;
                var shipperAccount = await accountCommand.ExecuteScalarAsync();
                if (shipperAccount is not null
                    && shipperAccount != DBNull.Value)
                {
                    var shipperAccountId = Convert.ToInt64(shipperAccount);
                    await _hub.Clients
                        .Group(ShipperHub.AccountGroup(shipperAccountId))
                        .SendAsync("HandoverReady", new
                        {
                            request.OrderId,
                            request.AssignmentId
                        });
                }
            }
            catch
            {
                // The warehouse commit is authoritative; refresh/pull remains available.
            }

            return new ContentResult
            {
                StatusCode = StatusCodes.Status201Created,
                ContentType = "application/json",
                Content = json
            };
        }
        catch (SqlException ex) when (
            ex.Number is >= 51501 and <= 51504)
        {
            var statusCode = ex.Number switch
            {
                51501 => StatusCodes.Status401Unauthorized,
                51502 => StatusCodes.Status403Forbidden,
                51503 => StatusCodes.Status404NotFound,
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
