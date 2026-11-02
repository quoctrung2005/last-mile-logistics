using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using LastMile.Api.Services;

namespace LastMile.Api.Controllers;

public class WarehouseInboundRequest
{
    [Range(1, long.MaxValue)]
    public long OrderId { get; set; }

    [Range(1, int.MaxValue)]
    public int WarehouseId { get; set; }

    [Range(1, long.MaxValue)]
    public long LocationId { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }
}

[Authorize]
[ApiController]
[Route("api/v1/warehouse-transactions")]
public class WarehouseInboundController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<WarehouseInboundController> _logger;

    public WarehouseInboundController(
        IConfiguration configuration,
        ILogger<WarehouseInboundController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpPost("inbound")]
    public async Task<IActionResult> Inbound(
        WarehouseInboundRequest request)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        var transactionCode =
            $"NK-{Guid.NewGuid():N}".ToUpperInvariant();

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
                        AND q.KyHieuQuyen = 'KHO_NHAP'
                  );

                IF @Allowed = 0
                   OR (@IsAdmin = 0 AND @AccountBranchId IS NULL)
                    THROW 52501, N'Không có quyền nhập kho.', 1;

                DECLARE
                    @OrderBranchId INT,
                    @Status VARCHAR(40),
                    @CurrentWarehouseId INT;

                SELECT
                    @OrderBranchId = d.MaBuuCuc,
                    @Status = tt.KyHieuTrangThai,
                    @CurrentWarehouseId = d.MaKhoHienTai
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND (@IsAdmin = 1 OR d.MaBuuCuc = @AccountBranchId);

                IF @Status IS NULL
                    THROW 52502, N'Không tìm thấy đơn trong phạm vi được xử lý.', 1;

                IF @Status NOT IN ('CONFIRMED', 'WAITING_INBOUND')
                    THROW 52503, N'Đơn phải ở CONFIRMED hoặc WAITING_INBOUND để nhập kho.', 1;

                IF @CurrentWarehouseId IS NOT NULL
                   OR EXISTS (
                       SELECT 1
                       FROM dbo.TonKhoDonHang WITH (UPDLOCK, HOLDLOCK)
                       WHERE MaDonHang = @OrderId
                   )
                    THROW 52503, N'Đơn đã có dữ liệu tồn kho. Không được nhập lần đầu lần nữa.', 1;

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
                    THROW 52504, N'Kho không hoạt động hoặc không thuộc bưu cục của đơn.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.ViTriLuuKho WITH (HOLDLOCK)
                    WHERE MaViTriLuuKho = @LocationId
                      AND MaKho = @WarehouseId
                      AND DangHoatDong = 1
                )
                    THROW 52504, N'Vị trí không hoạt động hoặc không thuộc kho đã chọn.', 1;

                IF @Status = 'CONFIRMED'
                BEGIN
                    EXEC dbo.sp_ChuyenTrangThaiDonHang
                        @MaDonHang = @OrderId,
                        @KyHieuTrangThaiMoi = 'WAITING_INBOUND',
                        @MaTaiKhoan = @AccountId,
                        @LyDo = NULL,
                        @NguonCapNhat = 'API'
                        WITH RESULT SETS NONE;
                END;

                INSERT INTO dbo.GiaoDichKho (
                    KyHieuGiaoDich, MaKho, LoaiGiaoDich,
                    TrangThaiGiaoDich, MaTaiKhoanThucHien, GhiChu
                )
                VALUES (
                    @TransactionCode, @WarehouseId, 'INBOUND',
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
                    NULL, @LocationId, 'NORMAL', @Notes
                );

                INSERT INTO dbo.TonKhoDonHang (
                    MaDonHang, MaKho, MaViTriLuuKho,
                    TrangThaiTonKho, ThoiGianNhapKho,
                    ThoiGianDiChuyenCuoi, MaTaiKhoanCapNhatCuoi
                )
                VALUES (
                    @OrderId, @WarehouseId, @LocationId,
                    'STORED', SYSUTCDATETIME(),
                    SYSUTCDATETIME(), @AccountId
                );

                UPDATE dbo.DonHang
                SET MaKhoHienTai = @WarehouseId,
                    MaTaiKhoanCapNhatCuoi = @AccountId,
                    ThoiGianCapNhat = SYSUTCDATETIME()
                WHERE MaDonHang = @OrderId;

                EXEC dbo.sp_ChuyenTrangThaiDonHang
                    @MaDonHang = @OrderId,
                    @KyHieuTrangThaiMoi = 'IN_WAREHOUSE',
                    @MaTaiKhoan = @AccountId,
                    @LyDo = NULL,
                    @NguonCapNhat = 'API'
                    WITH RESULT SETS NONE;

                INSERT INTO dbo.NhatKyHoatDong (
                    MaTaiKhoan, LoaiThaoTac, TenDoiTuong,
                    MaDoiTuong, DuLieuCuJson, DuLieuMoiJson
                )
                VALUES (
                    @AccountId,
                    'WAREHOUSE_INBOUND',
                    'DonHang',
                    CONVERT(VARCHAR(100), @OrderId),
                    (
                        SELECT @Status AS status
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    ),
                    (
                        SELECT
                            'IN_WAREHOUSE' AS status,
                            @WarehouseId AS warehouseId,
                            @LocationId AS locationId,
                            @TransactionId AS transactionId
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )
                );

                COMMIT;

                SELECT @TransactionId AS TransactionId;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0
                    ROLLBACK;

                THROW;
            END CATCH;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
        var writeAttempted = false;

        try
        {
            await connection.OpenAsync();

            await using var command = new SqlCommand(sql, connection);

            command.Parameters.Add(
                "@AccountId", SqlDbType.BigInt).Value = accountId;

            command.Parameters.Add(
                "@OrderId", SqlDbType.BigInt).Value = request.OrderId;

            command.Parameters.Add(
                "@WarehouseId", SqlDbType.Int).Value = request.WarehouseId;

            command.Parameters.Add(
                "@LocationId", SqlDbType.BigInt).Value = request.LocationId;

            command.Parameters.Add(
                "@TransactionCode", SqlDbType.VarChar, 40
            ).Value = transactionCode;

            command.Parameters.Add(
                "@Notes", SqlDbType.NVarChar, 500).Value =
                    (object?)request.Notes ?? DBNull.Value;

            writeAttempted = true;
            await using var reader = await command.ExecuteReaderAsync();
            var transactionId = await SqlResult.ReadSingleAsync(reader, ["TransactionId"], row => row.Id("TransactionId"));

            return StatusCode(StatusCodes.Status201Created, new
            {
                transactionId,
                transactionCode,
                orderId = request.OrderId,
                warehouseId = request.WarehouseId,
                locationId = request.LocationId,
                orderStatus = "IN_WAREHOUSE",
                inventoryStatus = "STORED",
                message = "Nhập kho thành công."
            });
        }
        catch (SqlException ex) when (ex.Number == 52501)
        {
            return Forbid();
        }
        catch (SqlException ex) when (ex.Number == 52502)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex)
            when (ex.Number == 52503 || ex.Number == 51001)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex)
            when (ex.Number == 52504
                  || ex.Number == 51002
                  || ex.Number == 51045)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (SqlException ex)
        {
            return SqlResult.Failure(_logger, "POST /api/v1/warehouse-transactions/inbound", request.OrderId, SqlResult.ErrorReason(ex), writeAttempted);
        }
        catch (SqlResultContractException ex)
        {
            return SqlResult.Failure(_logger, "POST /api/v1/warehouse-transactions/inbound", request.OrderId, ex.Message, writeAttempted);
        }
    }
}
