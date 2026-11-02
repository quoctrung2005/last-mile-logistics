using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class WarehouseMoveRequest
{
    [Range(1, long.MaxValue)]
    public long OrderId { get; set; }

    [Range(1, long.MaxValue)]
    public long FromLocationId { get; set; }

    [Range(1, long.MaxValue)]
    public long ToLocationId { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }
}

[Authorize]
[ApiController]
[Route("api/v1/warehouse-transactions")]
public class WarehouseMoveController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<WarehouseMoveController> _logger;

    public WarehouseMoveController(
        IConfiguration configuration,
        ILogger<WarehouseMoveController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPost("move")]
    public async Task<IActionResult> Move(WarehouseMoveRequest request)
    {
        if (request.FromLocationId == request.ToLocationId)
            return BadRequest(new
            {
                message = "Vị trí nguồn và đích phải khác nhau."
            });

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        var transactionCode =
            $"DC-{Guid.NewGuid():N}".ToUpperInvariant();

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Allowed BIT = 0,
                    @IsAdmin BIT = 0,
                    @AccountBranchId INT;

                SELECT
                    @Allowed = 1,
                    @IsAdmin = CASE
                        WHEN vt.KyHieuVaiTro = 'ADMIN' THEN 1 ELSE 0 END,
                    @AccountBranchId = tk.MaBuuCuc
                FROM dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.VaiTro vt WITH (HOLDLOCK)
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
                      FROM dbo.VaiTroQuyen vq WITH (HOLDLOCK)
                      JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                      WHERE vq.MaVaiTro = tk.MaVaiTro
                        AND q.KyHieuQuyen = 'KHO_KIEMKE'
                  );

                IF @Allowed = 0
                   OR (@IsAdmin = 0 AND @AccountBranchId IS NULL)
                    THROW 52601, N'Không có quyền di chuyển hàng trong kho.', 1;

                DECLARE
                    @OrderBranchId INT,
                    @CurrentWarehouseId INT;

                SELECT
                    @OrderBranchId = d.MaBuuCuc,
                    @CurrentWarehouseId = d.MaKhoHienTai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                WHERE d.MaDonHang = @OrderId
                  AND (@IsAdmin = 1 OR d.MaBuuCuc = @AccountBranchId);

                IF @OrderBranchId IS NULL
                    THROW 52602, N'Không tìm thấy đơn trong phạm vi được xử lý.', 1;

                DECLARE
                    @WarehouseId INT,
                    @CurrentLocationId BIGINT,
                    @InventoryStatus VARCHAR(20);

                SELECT
                    @WarehouseId = t.MaKho,
                    @CurrentLocationId = t.MaViTriLuuKho,
                    @InventoryStatus = t.TrangThaiTonKho
                FROM dbo.TonKhoDonHang t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.MaDonHang = @OrderId;

                IF @WarehouseId IS NULL
                   OR @CurrentWarehouseId IS NULL
                   OR @WarehouseId <> @CurrentWarehouseId
                   OR @InventoryStatus NOT IN (
                       'RECEIVED', 'STORED', 'ALLOCATED', 'RETURNED'
                   )
                    THROW 52603, N'Đơn không còn nằm trong kho để di chuyển.', 1;

                IF @CurrentLocationId IS NULL
                   OR @CurrentLocationId <> @FromLocationId
                    THROW 52603, N'Vị trí nguồn không khớp. Hãy tải lại tồn kho.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.Kho k WITH (HOLDLOCK)
                    JOIN dbo.BuuCuc bc WITH (HOLDLOCK)
                        ON bc.MaBuuCuc = k.MaBuuCuc
                    WHERE k.MaKho = @WarehouseId
                      AND k.MaBuuCuc = @OrderBranchId
                      AND k.DangHoatDong = 1
                      AND bc.DangHoatDong = 1
                )
                    THROW 52604, N'Kho hoặc bưu cục không hoạt động.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.ViTriLuuKho WITH (HOLDLOCK)
                    WHERE MaViTriLuuKho = @FromLocationId
                      AND MaKho = @WarehouseId
                )
                    THROW 52604, N'Vị trí nguồn không thuộc kho hiện tại.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.ViTriLuuKho WITH (HOLDLOCK)
                    WHERE MaViTriLuuKho = @ToLocationId
                      AND MaKho = @WarehouseId
                      AND DangHoatDong = 1
                )
                    THROW 52604, N'Vị trí đích không hoạt động hoặc thuộc kho khác.', 1;

                INSERT INTO dbo.GiaoDichKho (
                    KyHieuGiaoDich, MaKho, LoaiGiaoDich,
                    TrangThaiGiaoDich, MaTaiKhoanThucHien, GhiChu
                )
                VALUES (
                    @TransactionCode, @WarehouseId, 'MOVE',
                    'COMPLETED', @AccountId, @Notes
                );

                DECLARE @TransactionId BIGINT =
                    CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.ChiTietGiaoDichKho (
                    MaGiaoDichKho, MaDonHang,
                    MaViTriNguon, MaViTriDich, TinhTrangHang, GhiChu
                )
                VALUES (
                    @TransactionId, @OrderId,
                    @FromLocationId, @ToLocationId, 'NORMAL', @Notes
                );

                UPDATE dbo.TonKhoDonHang
                SET MaViTriLuuKho = @ToLocationId,
                    TrangThaiTonKho = CASE
                        WHEN TrangThaiTonKho = 'RECEIVED'
                        THEN 'STORED'
                        ELSE TrangThaiTonKho
                    END,
                    ThoiGianDiChuyenCuoi = SYSUTCDATETIME(),
                    MaTaiKhoanCapNhatCuoi = @AccountId
                WHERE MaDonHang = @OrderId;

                UPDATE dbo.DonHang
                SET MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = SYSUTCDATETIME()
                WHERE MaDonHang = @OrderId;

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan, LoaiThaoTac, TenDoiTuong,
                    MaDoiTuong, DuLieuCuJson, DuLieuMoiJson
                )
                VALUES (
                    @AccountId, 'WAREHOUSE_MOVE', 'TonKhoDonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    (
                        SELECT
                            @WarehouseId AS warehouseId,
                            @FromLocationId AS locationId
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    ),
                    (
                        SELECT
                            @WarehouseId AS warehouseId,
                            @ToLocationId AS locationId,
                            @TransactionId AS transactionId,
                            @Notes AS notes
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )
                );

                COMMIT;

                SELECT @TransactionId AS TransactionId,
                       @WarehouseId AS WarehouseId;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0
                    ROLLBACK;

                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        try
        {
            await connection.OpenAsync();

            await using var command = new SqlCommand(sql, connection);

            command.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value = accountId;

            command.Parameters.Add(
                "@OrderId", SqlDbType.BigInt).Value = request.OrderId;

            command.Parameters.Add(
                "@FromLocationId", SqlDbType.BigInt
            ).Value = request.FromLocationId;

            command.Parameters.Add(
                "@ToLocationId", SqlDbType.BigInt
            ).Value = request.ToLocationId;

            command.Parameters.Add(
                "@TransactionCode", SqlDbType.VarChar, 40
            ).Value = transactionCode;

            command.Parameters.Add(
                "@Notes", SqlDbType.NVarChar, 500).Value =
                    (object?)request.Notes ?? DBNull.Value;

            await using var reader = await command.ExecuteReaderAsync();
            await reader.ReadAsync();

            return StatusCode(StatusCodes.Status201Created, new
            {
                transactionId = Convert.ToInt64(reader["TransactionId"]),
                transactionCode,
                orderId = request.OrderId,
                warehouseId = Convert.ToInt32(reader["WarehouseId"]),
                fromLocationId = request.FromLocationId,
                toLocationId = request.ToLocationId,
                message = "Di chuyển vị trí lưu hàng thành công."
            });
        }
        catch (SqlException ex) when (ex.Number == 52601)
        {
            return Forbid();
        }
        catch (SqlException ex) when (ex.Number == 52602)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 52603)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex)
            when (ex.Number == 52604 || ex.Number == 51045)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (SqlException ex)
        {
            _logger.LogError(
                ex, "Không di chuyển được đơn {OrderId}.", request.OrderId);

            return StatusCode(500, new
            {
                message = "Không di chuyển được hàng. Xem log Visual Studio."
            });
        }
    }
}