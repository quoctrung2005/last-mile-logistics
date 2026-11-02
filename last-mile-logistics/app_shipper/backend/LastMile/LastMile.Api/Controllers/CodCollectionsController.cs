using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/cod")]
public class CodCollectionsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CodCollectionsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("collections")]
    public async Task<IActionResult> GetCollections(
        [FromQuery, StringLength(100)] string? keyword = null,
        [FromQuery, Range(1, long.MaxValue)] long? shipperId = null,
        [FromQuery, Range(1, int.MaxValue)] int? branchId = null,
        [FromQuery] DateTimeOffset? from = null,
        [FromQuery] DateTimeOffset? to = null,
        [FromQuery] bool outstandingOnly = false,
        [FromQuery, Range(1, 100000)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 10)
    {
        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        if (from.HasValue && to.HasValue && to <= from)
        {
            return BadRequest(new
            {
                message = "Thời gian to phải lớn hơn from."
            });
        }

        keyword = string.IsNullOrWhiteSpace(keyword)
            ? null
            : keyword.Trim();

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await connection.OpenAsync();

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @Now DATETIME2(0) = SYSUTCDATETIME(),
                @Role VARCHAR(50),
                @RoleId INT,
                @AccountBranchId INT,
                @OwnShipperId BIGINT;

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
                THROW 52901,
                    N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                    1;

            IF @Role = 'SHIPPER'
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'COD_NOPTIEN'
                )
                    THROW 52902,
                        N'Bạn không có quyền xem tiền COD để nộp.',
                        1;

                SELECT @OwnShipperId = MaNhanVienGiaoHang
                FROM dbo.NhanVienGiaoHang
                WHERE MaTaiKhoan = @AccountId
                  AND DangHoatDong = 1;

                IF @OwnShipperId IS NULL
                    THROW 52902,
                        N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                        1;

                IF @ShipperId IS NOT NULL
                   AND @ShipperId <> @OwnShipperId
                    THROW 52902,
                        N'Bạn chỉ được xem tiền COD của mình.',
                        1;
            END
            ELSE
            BEGIN
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.VaiTroQuyen vtq
                    INNER JOIN dbo.Quyen q
                        ON q.MaQuyen = vtq.MaQuyen
                    WHERE vtq.MaVaiTro = @RoleId
                      AND q.KyHieuQuyen = 'COD_DOISOAT'
                )
                    THROW 52902,
                        N'Bạn không có quyền xem dữ liệu COD.',
                        1;

                IF @Role <> 'ADMIN'
                   AND @AccountBranchId IS NULL
                    THROW 52902,
                        N'Tài khoản chưa được gán bưu cục.',
                        1;

                IF @Role <> 'ADMIN'
                   AND @BranchId IS NOT NULL
                   AND @BranchId <> @AccountBranchId
                    THROW 52902,
                        N'Bạn chỉ được xem COD thuộc bưu cục của mình.',
                        1;
            END;

            SELECT
                c.MaThuTienCOD AS id,
                d.MaDonHang AS orderId,
                d.KyHieuDonHang AS orderCode,
                d.MaVanDon AS trackingNumber,
                d.MaBuuCuc AS branchId,
                b.TenBuuCuc AS branchName,
                c.MaNhanVienGiaoHang AS shipperId,
                tk.HoTen AS shipperName,
                c.SoTienPhaiThu AS expectedAmount,
                c.SoTienThucThu AS collectedAmount,
                c.TrangThaiThuTien AS collectionStatus,
                c.ThoiGianThuTien AS collectedAt,
                c.GhiChu AS notes,
                amounts.confirmedAmount AS depositedAmount,
                amounts.pendingAmount AS pendingDepositAmount,
                c.SoTienThucThu
                    - amounts.confirmedAmount AS remainingAmount,
                CASE
                    WHEN c.SoTienThucThu
                        - amounts.confirmedAmount
                        - amounts.pendingAmount > 0
                    THEN c.SoTienThucThu
                        - amounts.confirmedAmount
                        - amounts.pendingAmount
                    ELSE 0
                END AS availableForDeposit,
                CAST(
                    CASE
                        WHEN amounts.confirmedAmount
                            + amounts.pendingAmount
                            > c.SoTienThucThu
                        THEN 1 ELSE 0
                    END
                    AS BIT
                ) AS isOverAllocated
            INTO #Collections
            FROM dbo.ThuTienCOD c
            INNER JOIN dbo.DonHang d
                ON d.MaDonHang = c.MaDonHang
            INNER JOIN dbo.BuuCuc b
                ON b.MaBuuCuc = d.MaBuuCuc
            INNER JOIN dbo.NhanVienGiaoHang nv
                ON nv.MaNhanVienGiaoHang = c.MaNhanVienGiaoHang
            INNER JOIN dbo.TaiKhoan tk
                ON tk.MaTaiKhoan = nv.MaTaiKhoan
            OUTER APPLY (
                SELECT
                    COALESCE(SUM(
                        CASE WHEN n.TrangThaiNop = 'CONFIRMED'
                             THEN ct.SoTienPhanBo ELSE 0 END
                    ), 0) AS confirmedAmount,
                    COALESCE(SUM(
                        CASE WHEN n.TrangThaiNop = 'PENDING'
                             THEN ct.SoTienPhanBo ELSE 0 END
                    ), 0) AS pendingAmount
                FROM dbo.ChiTietNopTienCOD ct
                INNER JOIN dbo.NopTienCOD n
                    ON n.MaNopTienCOD = ct.MaNopTienCOD
                WHERE ct.MaDonHang = c.MaDonHang
                  AND n.TrangThaiNop IN ('PENDING', 'CONFIRMED')
            ) amounts
            WHERE c.TrangThaiThuTien IN ('COLLECTED', 'PARTIAL')
              AND c.SoTienThucThu > 0
              AND (
                  (
                      @Role = 'SHIPPER'
                      AND c.MaNhanVienGiaoHang = @OwnShipperId
                  )
                  OR (
                      @Role <> 'SHIPPER'
                      AND (
                          @Role = 'ADMIN'
                          OR d.MaBuuCuc = @AccountBranchId
                      )
                  )
              )
              AND (
                  @ShipperId IS NULL
                  OR c.MaNhanVienGiaoHang = @ShipperId
              )
              AND (
                  @BranchId IS NULL
                  OR d.MaBuuCuc = @BranchId
              )
              AND (
                  @From IS NULL
                  OR c.ThoiGianThuTien >= @From
              )
              AND (
                  @To IS NULL
                  OR c.ThoiGianThuTien < @To
              )
              AND (
                  @OutstandingOnly = 0
                  OR c.SoTienThucThu > amounts.confirmedAmount
              )
              AND (
                  @Keyword IS NULL
                  OR CHARINDEX(@Keyword, d.KyHieuDonHang) > 0
                  OR CHARINDEX(@Keyword, d.MaVanDon) > 0
                  OR CHARINDEX(@Keyword, tk.HoTen) > 0
              );

            SELECT (
                SELECT
                    @Page AS page,
                    @PageSize AS pageSize,
                    (
                        SELECT COUNT_BIG(*)
                        FROM #Collections
                    ) AS totalItems,
                    JSON_QUERY((
                        SELECT
                            COALESCE(SUM(collectedAmount), 0)
                                AS totalCollected,
                            COALESCE(SUM(depositedAmount), 0)
                                AS totalDeposited,
                            COALESCE(SUM(pendingDepositAmount), 0)
                                AS totalPendingDeposit,
                            COALESCE(SUM(remainingAmount), 0)
                                AS totalRemaining,
                            COALESCE(SUM(availableForDeposit), 0)
                                AS totalAvailableForDeposit
                        FROM #Collections
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )) AS summary,
                    JSON_QUERY((
                        SELECT *
                        FROM #Collections
                        ORDER BY collectedAt DESC, id DESC
                        OFFSET @Offset ROWS
                        FETCH NEXT @PageSize ROWS ONLY
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    )) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            DROP TABLE #Collections;
            """;

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
                (object?)keyword ?? DBNull.Value;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value =
                (object?)shipperId ?? DBNull.Value;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
                (object?)branchId ?? DBNull.Value;

        command.Parameters.Add(
            "@From", SqlDbType.DateTime2).Value =
                (object?)from?.UtcDateTime ?? DBNull.Value;

        command.Parameters.Add(
            "@To", SqlDbType.DateTime2).Value =
                (object?)to?.UtcDateTime ?? DBNull.Value;

        command.Parameters.Add(
            "@OutstandingOnly", SqlDbType.Bit).Value = outstandingOnly;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value = pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.Int).Value =
                (page - 1) * pageSize;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is 52901 or 52902)
        {
            return StatusCode(
                ex.Number == 52901
                    ? StatusCodes.Status401Unauthorized
                    : StatusCodes.Status403Forbidden,
                new { message = ex.Message });
        }
    }
}