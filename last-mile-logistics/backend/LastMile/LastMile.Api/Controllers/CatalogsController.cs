using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/catalogs")]
public class CatalogsController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public CatalogsController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> Get(
        [FromQuery] string type = "ALL",
        [FromQuery] bool activeOnly = false,
        [FromQuery] int? branchId = null,
        [FromQuery] int? warehouseId = null,
        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        type = (type ?? "").Trim().ToUpperInvariant();

        if (type is not (
            "ALL" or "AREAS" or "BRANCHES"
            or "WAREHOUSES" or "LOCATIONS" or "SERVICES"))
        {
            return BadRequest(new
            {
                message = "Type phải là ALL, AREAS, BRANCHES, WAREHOUSES, LOCATIONS hoặc SERVICES."
            });
        }

        if ((branchId.HasValue && branchId.Value <= 0)
            || (warehouseId.HasValue && warehouseId.Value <= 0))
        {
            return BadRequest(new
            {
                message = "Mã bưu cục và mã kho phải lớn hơn 0."
            });
        }

        const string sql = """
            SET NOCOUNT ON;

            DECLARE
                @Role VARCHAR(50),
                @AccountBranch INT,
                @RoleId INT,
                @Result NVARCHAR(MAX);

            SELECT
                @Role = vt.KyHieuVaiTro,
                @AccountBranch = tk.MaBuuCuc,
                @RoleId = tk.MaVaiTro
            FROM dbo.TaiKhoan tk
            INNER JOIN dbo.VaiTro vt
                ON vt.MaVaiTro = tk.MaVaiTro
            WHERE tk.MaTaiKhoan = @AccountId
              AND tk.TrangThaiTaiKhoan = 'ACTIVE'
              AND vt.DangHoatDong = 1
              AND (
                  tk.KhoaDenLuc IS NULL
                  OR tk.KhoaDenLuc <= SYSUTCDATETIME()
              );

            IF @Role IS NULL
                THROW 56401,
                    N'Tài khoản không còn hợp lệ.', 1;

            IF NOT ((@Type IN ('SERVICES', 'AREAS', 'BRANCHES') AND @Role = 'ADMIN' AND EXISTS (
                SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @RoleId AND q.KyHieuQuyen = 'BANGGIA_QUANLY'
            )) OR (@Type IN ('BRANCHES', 'AREAS') AND EXISTS (
                SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @RoleId AND q.KyHieuQuyen = 'TAIKHOAN_XEM'
            )) OR (@Role = 'ADMIN' AND EXISTS (
                   SELECT 1
                   FROM dbo.VaiTroQuyen vq
                   INNER JOIN dbo.Quyen q
                       ON q.MaQuyen = vq.MaQuyen
                   WHERE vq.MaVaiTro = @RoleId
                     AND q.KyHieuQuyen = 'BUUCUC_QUANLY'
               )))
                THROW 56402,
                    N'API này dành cho admin quản lý danh mục.', 1;

            IF @Role <> 'ADMIN' AND (@AccountBranch IS NULL OR (@BranchId IS NOT NULL AND @BranchId <> @AccountBranch))
                THROW 56402, N'Bạn chỉ được đọc danh mục trong phạm vi bưu cục của mình.', 1;

            SELECT @Result = (
            SELECT
                @Type AS type,

                JSON_QUERY(CASE
                    WHEN @Type IN ('ALL', 'AREAS') THEN COALESCE((
                        SELECT
                            kv.MaKhuVuc AS id,
                            kv.KyHieuKhuVuc AS code,
                            kv.TenKhuVuc AS name,
                            kv.MaKhuVucCha AS parentId,
                            kv.LoaiKhuVuc AS areaType,
                            kv.DangHoatDong AS isActive
                        FROM dbo.KhuVuc kv
                        WHERE @ActiveOnly = 0
                           OR kv.DangHoatDong = 1
                        ORDER BY kv.MaKhuVuc
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')
                END) AS areas,

                JSON_QUERY(CASE
                    WHEN @Type IN ('ALL', 'BRANCHES') THEN COALESCE((
                        SELECT
                            bc.MaBuuCuc AS id,
                            bc.KyHieuBuuCuc AS code,
                            bc.TenBuuCuc AS name,
                            bc.DiaChi AS address,
                            bc.SoDienThoai AS phone,
                            bc.Email AS email,
                            bc.MaKhuVuc AS areaId,
                            bc.ViDo AS latitude,
                            bc.KinhDo AS longitude,
                            bc.DangHoatDong AS isActive
                        FROM dbo.BuuCuc bc
                        WHERE (
                            @ActiveOnly = 0 OR bc.DangHoatDong = 1
                        )
                          AND (@Role = 'ADMIN' OR bc.MaBuuCuc = @AccountBranch)
                          AND (
                              @BranchId IS NULL
                              OR bc.MaBuuCuc = @BranchId
                          )
                        ORDER BY bc.TenBuuCuc, bc.MaBuuCuc
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')
                END) AS branches,

                JSON_QUERY(CASE
                    WHEN @Type IN ('ALL', 'WAREHOUSES') THEN COALESCE((
                        SELECT
                            k.MaKho AS id,
                            k.KyHieuKho AS code,
                            k.TenKho AS name,
                            k.DiaChi AS address,
                            k.MaBuuCuc AS branchId,
                            bc.TenBuuCuc AS branchName,
                            k.DangHoatDong AS isActive
                        FROM dbo.Kho k
                        INNER JOIN dbo.BuuCuc bc
                            ON bc.MaBuuCuc = k.MaBuuCuc
                        WHERE (
                            @ActiveOnly = 0
                            OR (
                                k.DangHoatDong = 1
                                AND bc.DangHoatDong = 1
                            )
                        )
                          AND (
                              @BranchId IS NULL
                              OR k.MaBuuCuc = @BranchId
                          )
                          AND (
                              @WarehouseId IS NULL
                              OR k.MaKho = @WarehouseId
                          )
                        ORDER BY k.MaBuuCuc, k.MaKho
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')
                END) AS warehouses,

                JSON_QUERY(CASE
                    WHEN @Type IN ('ALL', 'LOCATIONS') THEN COALESCE((
                        SELECT
                            vt.MaViTriLuuKho AS id,
                            vt.KyHieuViTri AS code,
                            vt.TenKhuLuu AS storageArea,
                            vt.MaKe AS rack,
                            vt.MaO AS slot,
                            vt.MaKho AS warehouseId,
                            k.TenKho AS warehouseName,
                            k.MaBuuCuc AS branchId,
                            vt.DangHoatDong AS isActive
                        FROM dbo.ViTriLuuKho vt
                        INNER JOIN dbo.Kho k
                            ON k.MaKho = vt.MaKho
                        INNER JOIN dbo.BuuCuc bc
                            ON bc.MaBuuCuc = k.MaBuuCuc
                        WHERE (
                            @ActiveOnly = 0
                            OR (
                                vt.DangHoatDong = 1
                                AND k.DangHoatDong = 1
                                AND bc.DangHoatDong = 1
                            )
                        )
                          AND (
                              @BranchId IS NULL
                              OR k.MaBuuCuc = @BranchId
                          )
                          AND (
                              @WarehouseId IS NULL
                              OR vt.MaKho = @WarehouseId
                          )
                        ORDER BY vt.MaKho, vt.MaViTriLuuKho
                        FOR JSON PATH, INCLUDE_NULL_VALUES
                    ), N'[]')
                END) AS locations,

                JSON_QUERY(CASE
                    WHEN @Type IN ('ALL', 'SERVICES') THEN COALESCE((
                        SELECT
                            dv.MaLoaiDichVu AS id,
                            dv.KyHieuDichVu AS code,
                            dv.TenDichVu AS name,
                            dv.DangHoatDong AS isActive
                        FROM dbo.LoaiDichVu dv
                        WHERE @ActiveOnly = 0
                           OR dv.DangHoatDong = 1
                        ORDER BY dv.MaLoaiDichVu
                        FOR JSON PATH
                    ), N'[]')
                END) AS services

            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            SELECT @Result;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Type", SqlDbType.VarChar, 20).Value = type;

        command.Parameters.Add(
            "@ActiveOnly", SqlDbType.Bit).Value = activeOnly;

        command.Parameters.Add(
            "@BranchId", SqlDbType.Int).Value =
            (object?)branchId ?? DBNull.Value;

        command.Parameters.Add(
            "@WarehouseId", SqlDbType.Int).Value =
            (object?)warehouseId ?? DBNull.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 56401)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 56402)
        {
            return StatusCode(403, new { message = ex.Message });
        }
    }
}
