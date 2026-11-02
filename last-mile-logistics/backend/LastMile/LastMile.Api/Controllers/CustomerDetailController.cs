using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/customers")]
public class CustomerDetailController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CustomerDetailController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("{id:long}")]
    public async Task<IActionResult> GetDetail(
        long id,
        [FromQuery] bool includeInactiveAddresses = false,
        CancellationToken cancellationToken = default)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã khách hàng không hợp lệ."
            });
        }

        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        const string sql = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @BranchId INT,
                    @Result NVARCHAR(MAX);

                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @RoleId = tk.MaVaiTro,
                    @BranchId = tk.MaBuuCuc
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
                    THROW 54601,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vq
                    JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'DONHANG_XEM'
                )
                    THROW 54602,
                        N'Bạn không có quyền xem chi tiết khách hàng.', 1;

                IF @Role <> 'ADMIN' AND @BranchId IS NULL
                    THROW 54602,
                        N'Tài khoản chưa được gắn với bưu cục.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.KhachHang WITH (HOLDLOCK)
                    WHERE MaKhachHang = @CustomerId
                )
                    THROW 54603,
                        N'Không tìm thấy khách hàng.', 1;

                SELECT
                    d.MaDonHang AS OrderId,
                    d.KyHieuDonHang AS OrderCode,
                    d.MaVanDon AS TrackingNumber,
                    d.MaBuuCuc AS BranchId,
                    bc.TenBuuCuc AS BranchName,
                    tt.KyHieuTrangThai AS OrderStatus,
                    tt.TenTrangThai AS StatusName,
                    d.ThoiGianTao AS CreatedAt,
                    CONVERT(BIT, CASE
                        WHEN d.MaNguoiGui = @CustomerId THEN 1
                        ELSE 0
                    END) AS IsSender,
                    CONVERT(BIT, CASE
                        WHEN d.MaNguoiNhan = @CustomerId THEN 1
                        ELSE 0
                    END) AS IsReceiver
                INTO #Orders
                FROM dbo.DonHang d
                JOIN dbo.BuuCuc bc
                    ON bc.MaBuuCuc = d.MaBuuCuc
                JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE (
                    d.MaNguoiGui = @CustomerId
                    OR d.MaNguoiNhan = @CustomerId
                )
                  AND (
                      @Role = 'ADMIN'
                      OR d.MaBuuCuc = @BranchId
                  );

                SELECT @Result = (
                    SELECT
                        kh.MaKhachHang AS id,
                        kh.KyHieuKhachHang AS customerCode,
                        kh.HoTen AS fullName,
                        kh.SoDienThoai AS phone,
                        kh.Email AS email,
                        kh.LoaiKhachHang AS type,
                        kh.DangHoatDong AS isActive,
                        kh.ThoiGianTao AS createdAt,
                        CONVERT(VARBINARY(8), kh.PhienBan) AS version,

                        JSON_QUERY(COALESCE((
                            SELECT
                                dc.MaDiaChiKhachHang AS id,
                                dc.NhanDiaChi AS label,
                                dc.TenNguoiLienHe AS contactName,
                                dc.SoDienThoaiLienHe AS phone,
                                dc.DiaChi AS address,
                                dc.MaKhuVuc AS areaId,
                                kv.TenKhuVuc AS areaName,
                                dc.ViDo AS latitude,
                                dc.KinhDo AS longitude,
                                dc.LaMacDinh AS isDefault,
                                dc.DangHoatDong AS isActive,
                                CONVERT(VARBINARY(8), dc.PhienBan) AS version
                            FROM dbo.DiaChiKhachHang dc
                            LEFT JOIN dbo.KhuVuc kv
                                ON kv.MaKhuVuc = dc.MaKhuVuc
                            WHERE dc.MaKhachHang = @CustomerId
                              AND (
                                  @IncludeInactive = 1
                                  OR dc.DangHoatDong = 1
                              )
                            ORDER BY
                                dc.LaMacDinh DESC,
                                dc.MaDiaChiKhachHang
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        ), N'[]')) AS addresses,

                        JSON_QUERY((
                            SELECT
                                CASE
                                    WHEN @Role = 'ADMIN'
                                        THEN 'ALL_BRANCHES'
                                    ELSE 'CURRENT_BRANCH'
                                END AS scope,
                                CASE
                                    WHEN @Role = 'ADMIN' THEN NULL
                                    ELSE @BranchId
                                END AS branchId,
                                COUNT(*) AS totalOrders,
                                COALESCE(SUM(CASE
                                    WHEN IsSender = 1 THEN 1
                                    ELSE 0
                                END), 0) AS sentOrders,
                                COALESCE(SUM(CASE
                                    WHEN IsReceiver = 1 THEN 1
                                    ELSE 0
                                END), 0) AS receivedOrders,
                                COALESCE(SUM(CASE
                                    WHEN OrderStatus = 'DELIVERED'
                                        THEN 1
                                    ELSE 0
                                END), 0) AS deliveredOrders,
                                COALESCE(SUM(CASE
                                    WHEN OrderStatus = 'RETURNED'
                                        THEN 1
                                    ELSE 0
                                END), 0) AS returnedOrders,
                                COALESCE(SUM(CASE
                                    WHEN OrderStatus = 'COMPLETED'
                                        THEN 1
                                    ELSE 0
                                END), 0) AS completedOrders,
                                COALESCE(SUM(CASE
                                    WHEN OrderStatus = 'CANCELLED'
                                        THEN 1
                                    ELSE 0
                                END), 0) AS cancelledOrders,
                                COALESCE(SUM(CASE
                                    WHEN OrderStatus NOT IN (
                                        'DELIVERED', 'RETURNED',
                                        'COMPLETED', 'CANCELLED'
                                    ) THEN 1
                                    ELSE 0
                                END), 0) AS processingOrders
                            FROM #Orders
                            FOR JSON PATH,
                                INCLUDE_NULL_VALUES,
                                WITHOUT_ARRAY_WRAPPER
                        )) AS [statistics],

                        JSON_QUERY(COALESCE((
                            SELECT TOP (10)
                                OrderId AS id,
                                OrderCode AS orderCode,
                                TrackingNumber AS trackingNumber,
                                BranchId AS branchId,
                                BranchName AS branchName,
                                OrderStatus AS status,
                                StatusName AS statusName,
                                IsSender AS isSender,
                                IsReceiver AS isReceiver,
                                CreatedAt AS createdAt
                            FROM #Orders
                            ORDER BY CreatedAt DESC, OrderId DESC
                            FOR JSON PATH
                        ), N'[]')) AS recentOrders

                    FROM dbo.KhachHang kh
                    WHERE kh.MaKhachHang = @CustomerId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
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
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@CustomerId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@IncludeInactive", SqlDbType.Bit).Value =
            includeInactiveAddresses;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 54601)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54602)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 54603)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message = "Dữ liệu đang được xử lý đồng thời. Hãy thử lại."
            });
        }
    }
}
