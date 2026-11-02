using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using LastMile.Api.Services;

namespace LastMile.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/vehicles")]
public class VehiclesController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public VehiclesController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet("types")]
    public async Task<IActionResult> GetTypes(
        [FromServices] LastMile.Api.Services.VehicleTypeCatalog catalog,
        CancellationToken cancellationToken)
    {
        // Reuse the list's live database permission/scope guard. Never trust JWT role alone.
        var access = await Get(pageSize: 1, cancellationToken: cancellationToken);
        if (access is not ContentResult { StatusCode: null or 200 }) return access;
        return Ok(new { items = catalog.GetTypes() });
    }

    [HttpGet]
    public async Task<IActionResult> Get(
        [FromQuery] long? id = null,
        [FromQuery] string? keyword = null,
        [FromQuery] string? status = null,
        [FromQuery] bool activeOnly = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] bool assignableOnly = false,
        [FromQuery] string? vehicleType = null,
        [FromQuery] int? branchId = null,
        [FromQuery] bool includeFilterOptions = false,
        [FromQuery] long? forShipperId = null,
        [FromQuery] bool includeUnavailable = false,
        CancellationToken cancellationToken = default)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        if (id.HasValue && id.Value <= 0)
            return BadRequest(new { message = "Mã phương tiện không hợp lệ." });

        if (forShipperId is <= 0 || (forShipperId.HasValue && !assignableOnly))
            return BadRequest(new { message = "Mã shipper phải lớn hơn 0 và chỉ dùng khi tìm xe đủ điều kiện gán." });

        if (includeUnavailable && (!forShipperId.HasValue || !assignableOnly || id.HasValue))
            return BadRequest(new { message = "Danh sách kèm xe chưa đủ điều kiện phải có shipper nhận xe." });

        if (!id.HasValue)
        {
            if (page < 1 || pageSize < 1 || pageSize > 100)
            {
                return BadRequest(new
                {
                    message = "Page phải từ 1; pageSize từ 1 đến 100."
                });
            }

            if (keyword?.Length > 100)
                return BadRequest(new { message = "Từ khóa tối đa 100 ký tự." });

            vehicleType = string.IsNullOrWhiteSpace(vehicleType) ? null : vehicleType.Trim();
            if (vehicleType?.Length > 30 || branchId is <= 0)
                return BadRequest(new { message = "Loại xe tối đa 30 ký tự; mã bưu cục phải lớn hơn 0." });

            status = string.IsNullOrWhiteSpace(status)
                ? null
                : status.Trim().ToUpperInvariant();

            if (status is not null
                && status is not (
                    "AVAILABLE" or "IN_USE" or "MAINTENANCE" or "INACTIVE"))
            {
                return BadRequest(new
                {
                    message = "Status phải là AVAILABLE, IN_USE, MAINTENANCE hoặc INACTIVE."
                });
            }
        }

        var sql = $$"""
            SET NOCOUNT ON;

            DECLARE
                @Role VARCHAR(50),
                @RoleId INT,
                @BranchId INT,
                @SelectionBranchId INT,
                @SelectionBranchName NVARCHAR(150),
                @OldVehicleId BIGINT,
                @TargetReason NVARCHAR(300),
                @ScopedTotalItems BIGINT,
                @EligibleTotalItems BIGINT,
                @Result NVARCHAR(MAX);

            SELECT
                @Role = vt.KyHieuVaiTro,
                @RoleId = tk.MaVaiTro,
                @BranchId = tk.MaBuuCuc
            FROM dbo.TaiKhoan tk
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
                THROW 55101,
                    N'Tài khoản không còn hợp lệ.', 1;

            IF NOT EXISTS (
                SELECT 1
                FROM dbo.VaiTroQuyen vq
                JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                WHERE vq.MaVaiTro = @RoleId
                  AND q.KyHieuQuyen = 'DIEUPHOI_GIAMSAT'
            )
                THROW 55102,
                    N'Bạn không có quyền xem phương tiện.', 1;

            IF @Role <> 'ADMIN' AND @BranchId IS NULL
                THROW 55102,
                    N'Tài khoản chưa được gắn với bưu cục.', 1;

            IF @Id IS NULL AND @Role <> 'ADMIN' AND @FilterBranchId IS NOT NULL AND @FilterBranchId <> @BranchId
                THROW 55102, N'Bạn chỉ được xem xe liên kết với nhân viên thuộc bưu cục của mình.', 1;

            IF @ForShipperId IS NOT NULL
            BEGIN
                IF @Role <> 'ADMIN' OR (
                    SELECT COUNT(DISTINCT q.KyHieuQuyen)
                    FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                    WHERE vq.MaVaiTro = @RoleId AND q.KyHieuQuyen IN ('TAIKHOAN_QUANLY', 'TAIKHOAN_XEM')
                ) <> 2
                    THROW 55102, N'Bạn không có quyền chọn xe để gán cho shipper.', 1;

                SELECT @SelectionBranchId = tk.MaBuuCuc, @SelectionBranchName = bc.TenBuuCuc
                FROM dbo.NhanVienGiaoHang nv JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan = nv.MaTaiKhoan
                JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = tk.MaBuuCuc
                WHERE nv.MaNhanVienGiaoHang = @ForShipperId;
                IF @SelectionBranchId IS NULL
                    THROW 55103, N'Không tìm thấy shipper có bưu cục hợp lệ để chọn xe.', 1;
                IF @FilterBranchId IS NOT NULL AND @FilterBranchId <> @SelectionBranchId
                    THROW 55104, N'Bưu cục của shipper đã thay đổi. Hãy mở lại form chọn xe.', 1;

                SELECT @OldVehicleId = MaPhuongTien FROM dbo.PhanCongPhuongTien
                WHERE MaNhanVienGiaoHang = @ForShipperId AND ThoiGianKetThuc IS NULL;
                IF NOT EXISTS (
                    SELECT 1 FROM dbo.NhanVienGiaoHang nv
                    JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan = nv.MaTaiKhoan
                    JOIN dbo.VaiTro vt ON vt.MaVaiTro = tk.MaVaiTro
                    JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = tk.MaBuuCuc
                    WHERE nv.MaNhanVienGiaoHang = @ForShipperId AND nv.DangHoatDong = 1
                      AND (nv.NgayHetHanBangLai IS NULL OR nv.NgayHetHanBangLai >= {{VietnamDate.SqlDate("SYSUTCDATETIME()")}})
                      AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                      AND (tk.KhoaDenLuc IS NULL OR tk.KhoaDenLuc <= SYSUTCDATETIME())
                      AND vt.KyHieuVaiTro = 'SHIPPER' AND vt.DangHoatDong = 1 AND bc.DangHoatDong = 1
                ) SET @TargetReason = N'Hồ sơ, tài khoản, bưu cục hoặc bằng lái của shipper không hợp lệ.';
                ELSE IF EXISTS (SELECT 1 FROM dbo.PhanCongGiaoHang WHERE ThoiGianKetThuc IS NULL
                    AND (MaNhanVienGiaoHang = @ForShipperId OR MaPhuongTien = @OldVehicleId))
                    SET @TargetReason = N'Shipper hoặc xe hiện tại còn phân công giao hàng đang hoạt động.';
                ELSE IF EXISTS (SELECT 1 FROM dbo.ChuyenGiaoHang WHERE TrangThaiChuyen IN ('PLANNED','ASSIGNED','ACCEPTED','IN_PROGRESS')
                    AND (MaNhanVienGiaoHang = @ForShipperId OR MaPhuongTien = @OldVehicleId))
                    SET @TargetReason = N'Shipper hoặc xe hiện tại còn thuộc chuyến chưa kết thúc.';
                ELSE IF EXISTS (
                    SELECT 1 FROM dbo.DonHang d JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                    CROSS APPLY (SELECT TOP (1) pc.MaNhanVienGiaoHang, pc.MaPhuongTien FROM dbo.PhanCongGiaoHang pc
                        WHERE pc.MaDonHang = d.MaDonHang ORDER BY pc.ThoiGianPhanCong DESC, pc.MaPhanCongGiaoHang DESC) latest
                    WHERE tt.KyHieuTrangThai = 'RETURNING'
                      AND (latest.MaNhanVienGiaoHang = @ForShipperId OR latest.MaPhuongTien = @OldVehicleId)
                ) SET @TargetReason = N'Shipper hoặc xe hiện tại còn nhiệm vụ hoàn hàng.';
                -- Vehicles have no owning branch in the current schema. Unassigned
                -- vehicles remain the shared ADMIN pool; do not pretend tk.MaBuuCuc
                -- on a nonexistent current vehicle assignment is their home branch.
            END;

            SELECT
                pt.MaPhuongTien AS Id,
                pt.KyHieuPhuongTien AS Code,
                pt.BienSo AS LicensePlate,
                pt.LoaiXe AS VehicleType,
                pt.KhoiLuongDenKg AS MaxWeightKg,
                pt.TheTichToiDaM3 AS MaxVolumeM3,
                pt.TrangThaiPhuongTien AS Status,
                pt.DangHoatDong AS IsActive,
                CONVERT(BINARY(8), pt.PhienBan) AS Version,
                pcp.MaPhanCongPhuongTien AS VehicleAssignmentId,
                nv.MaNhanVienGiaoHang AS ShipperId,
                tk.HoTen AS ShipperName,
                nv.MaNhanVien AS EmployeeCode,
                tk.MaBuuCuc AS ShipperBranchId,
                bc.TenBuuCuc AS ShipperBranchName,
                pcp.ThoiGianPhanCong AS AssignedAt,
                CONVERT(BIT, CASE WHEN eligibility.Reason IS NULL THEN 1 ELSE 0 END) AS CanSelect,
                eligibility.Reason AS UnavailableReason,
                CONVERT(BIT, CASE WHEN nv.MaNhanVienGiaoHang = @ForShipperId THEN 1 ELSE 0 END) AS IsCurrentVehicle
            INTO #Vehicles
            FROM dbo.PhuongTien pt
            LEFT JOIN dbo.PhanCongPhuongTien pcp
                ON pcp.MaPhuongTien = pt.MaPhuongTien
               AND pcp.ThoiGianKetThuc IS NULL
            LEFT JOIN dbo.NhanVienGiaoHang nv
                ON nv.MaNhanVienGiaoHang = pcp.MaNhanVienGiaoHang
            LEFT JOIN dbo.TaiKhoan tk
                ON tk.MaTaiKhoan = nv.MaTaiKhoan
            LEFT JOIN dbo.BuuCuc bc ON bc.MaBuuCuc = tk.MaBuuCuc
            CROSS APPLY (SELECT CASE
                WHEN nv.MaNhanVienGiaoHang = @ForShipperId THEN N'Xe đang gắn với chính shipper này.'
                WHEN pt.DangHoatDong = 0 THEN N'Xe đã ngừng hoạt động.'
                WHEN pt.TrangThaiPhuongTien <> 'AVAILABLE' THEN
                    CASE pt.TrangThaiPhuongTien WHEN 'IN_USE' THEN N'Xe đang sử dụng.'
                        WHEN 'MAINTENANCE' THEN N'Xe đang bảo trì.' ELSE N'Xe chưa ở trạng thái sẵn sàng.' END
                WHEN pcp.MaPhanCongPhuongTien IS NOT NULL THEN N'Xe đã được gán cho shipper khác.'
                WHEN EXISTS (SELECT 1 FROM dbo.PhanCongGiaoHang pc WHERE pc.MaPhuongTien = pt.MaPhuongTien AND pc.ThoiGianKetThuc IS NULL)
                    THEN N'Xe còn phân công giao hàng đang hoạt động.'
                WHEN EXISTS (SELECT 1 FROM dbo.ChuyenGiaoHang cg WHERE cg.MaPhuongTien = pt.MaPhuongTien AND cg.TrangThaiChuyen IN ('PLANNED','ASSIGNED','ACCEPTED','IN_PROGRESS'))
                    THEN N'Xe còn thuộc chuyến chưa kết thúc.'
                WHEN EXISTS (
                    SELECT 1 FROM dbo.DonHang d JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                    CROSS APPLY (SELECT TOP (1) pc.MaPhuongTien FROM dbo.PhanCongGiaoHang pc WHERE pc.MaDonHang = d.MaDonHang
                        ORDER BY pc.ThoiGianPhanCong DESC, pc.MaPhanCongGiaoHang DESC) latest
                    WHERE tt.KyHieuTrangThai = 'RETURNING' AND latest.MaPhuongTien = pt.MaPhuongTien
                ) THEN N'Xe còn nhiệm vụ hoàn hàng.'
                ELSE @TargetReason END AS Reason) eligibility
            WHERE (
                @Role = 'ADMIN'
                OR tk.MaBuuCuc = @BranchId
            )
              AND (@Id IS NULL OR pt.MaPhuongTien = @Id)
              AND (@ForShipperId IS NULL OR pcp.MaPhanCongPhuongTien IS NULL OR tk.MaBuuCuc = @SelectionBranchId)
              AND (
                  @Id IS NOT NULL
                  OR (
                      (@AssignableOnly = 1 OR @VehicleType IS NULL OR pt.LoaiXe = @VehicleType)
                      AND (@ForShipperId IS NOT NULL OR @FilterBranchId IS NULL OR tk.MaBuuCuc = @FilterBranchId)
                      AND
                      (@Status IS NULL
                          OR pt.TrangThaiPhuongTien = @Status)
                      AND (@ActiveOnly = 0 OR pt.DangHoatDong = 1)
                      AND (
                          @AssignableOnly = 1 OR @Keyword IS NULL
                          OR CHARINDEX(@Keyword, pt.KyHieuPhuongTien) > 0
                          OR CHARINDEX(@Keyword, pt.BienSo) > 0
                      )
                  )
              );

            -- Preserve the unfiltered eligible count to distinguish an empty pool
            -- from a keyword/type filter with no matches, before server pagination.
            SELECT @ScopedTotalItems = COUNT_BIG(*),
                @EligibleTotalItems = COUNT_BIG(CASE WHEN CanSelect = 1 THEN 1 END) FROM #Vehicles;
            IF @AssignableOnly = 1 AND @IncludeUnavailable = 0
                DELETE FROM #Vehicles WHERE CanSelect = 0;
            IF @Id IS NULL AND @AssignableOnly = 1
                DELETE FROM #Vehicles
                WHERE (@VehicleType IS NOT NULL AND VehicleType <> @VehicleType)
                   OR (@Keyword IS NOT NULL AND CHARINDEX(@Keyword, Code) = 0 AND CHARINDEX(@Keyword, LicensePlate) = 0);

            IF @Id IS NOT NULL
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM #Vehicles)
                    THROW 55103,
                        N'Không tìm thấy phương tiện.', 1;

                SELECT @Result = (
                    SELECT
                        v.Id AS id,
                        v.Code AS code,
                        v.LicensePlate AS licensePlate,
                        v.VehicleType AS vehicleType,
                        v.MaxWeightKg AS maxWeightKg,
                        v.MaxVolumeM3 AS maxVolumeM3,
                        v.Status AS status,
                        v.IsActive AS isActive,
                        v.Version AS version,

                        JSON_QUERY((
                            SELECT
                                v.VehicleAssignmentId AS assignmentId,
                                v.ShipperId AS shipperId,
                                v.ShipperName AS shipperName,
                                v.EmployeeCode AS employeeCode,
                                v.ShipperBranchId AS branchId,
                                v.ShipperBranchName AS branchName,
                                v.AssignedAt AS assignedAt
                            WHERE v.VehicleAssignmentId IS NOT NULL
                            FOR JSON PATH,
                                INCLUDE_NULL_VALUES,
                                WITHOUT_ARRAY_WRAPPER
                        )) AS currentAssignment,

                        JSON_QUERY(COALESCE((
                            SELECT TOP (10)
                                p.MaPhanCongPhuongTien AS id,
                                p.MaNhanVienGiaoHang AS shipperId,
                                tk.HoTen AS shipperName,
                                p.ThoiGianPhanCong AS assignedAt,
                                p.ThoiGianKetThuc AS endedAt,
                                p.GhiChu AS notes
                            FROM dbo.PhanCongPhuongTien p
                            JOIN dbo.NhanVienGiaoHang nv
                                ON nv.MaNhanVienGiaoHang =
                                    p.MaNhanVienGiaoHang
                            JOIN dbo.TaiKhoan tk
                                ON tk.MaTaiKhoan = nv.MaTaiKhoan
                            WHERE p.MaPhuongTien = v.Id
                              AND (
                                  @Role = 'ADMIN'
                                  OR tk.MaBuuCuc = @BranchId
                              )
                            ORDER BY
                                p.ThoiGianPhanCong DESC,
                                p.MaPhanCongPhuongTien DESC
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        ), N'[]')) AS assignmentHistory,

                        (
                            SELECT COUNT(*)
                            FROM dbo.PhanCongGiaoHang pc
                            JOIN dbo.DonHang d
                                ON d.MaDonHang = pc.MaDonHang
                            WHERE pc.MaPhuongTien = v.Id
                              AND pc.ThoiGianKetThuc IS NULL
                              AND pc.TrangThaiPhanCong IN (
                                  'PENDING', 'ACCEPTED', 'IN_PROGRESS'
                              )
                              AND (
                                  @Role = 'ADMIN'
                                  OR d.MaBuuCuc = @BranchId
                              )
                        ) AS activeAssignmentCount,

                        (
                            SELECT COUNT(*)
                            FROM dbo.ChuyenGiaoHang cg
                            WHERE cg.MaPhuongTien = v.Id
                              AND cg.TrangThaiChuyen IN (
                                  'PLANNED', 'ASSIGNED', 'ACCEPTED', 'IN_PROGRESS'
                              )
                              AND (
                                  @Role = 'ADMIN'
                                  OR cg.MaBuuCuc = @BranchId
                              )
                        ) AS activeTripCount

                    FROM #Vehicles v
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );
            END
            ELSE
            BEGIN
                SELECT @Result = (
                    SELECT
                        @Page AS page,
                        @PageSize AS pageSize,
                        (SELECT COUNT(*) FROM #Vehicles) AS totalItems,
                        CASE WHEN @AssignableOnly = 1 THEN @EligibleTotalItems END AS eligibleTotalItems,
                        CASE WHEN @AssignableOnly = 1 THEN @ScopedTotalItems END AS scopedTotalItems,
                        @ForShipperId AS selectionShipperId,
                        @SelectionBranchId AS selectionBranchId,
                        @SelectionBranchName AS selectionBranchName,
                        JSON_QUERY(CASE WHEN @IncludeFilterOptions = 1 THEN (
                            SELECT
                                JSON_QUERY(COALESCE((
                                    SELECT DISTINCT pt.LoaiXe AS value
                                    FROM dbo.PhuongTien pt
                                    LEFT JOIN dbo.PhanCongPhuongTien p ON p.MaPhuongTien = pt.MaPhuongTien AND p.ThoiGianKetThuc IS NULL
                                    LEFT JOIN dbo.NhanVienGiaoHang n ON n.MaNhanVienGiaoHang = p.MaNhanVienGiaoHang
                                    LEFT JOIN dbo.TaiKhoan t ON t.MaTaiKhoan = n.MaTaiKhoan
                                    WHERE @Role = 'ADMIN' OR t.MaBuuCuc = @BranchId
                                    ORDER BY pt.LoaiXe FOR JSON PATH
                                ), N'[]')) AS vehicleTypes,
                                JSON_QUERY(COALESCE((
                                    SELECT b.MaBuuCuc AS id, b.TenBuuCuc AS name
                                    FROM dbo.BuuCuc b WHERE @Role = 'ADMIN' OR b.MaBuuCuc = @BranchId
                                    ORDER BY b.TenBuuCuc, b.MaBuuCuc FOR JSON PATH
                                ), N'[]')) AS branches
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        ) END) AS filterOptions,
                        JSON_QUERY(COALESCE((
                            SELECT
                                v.Id AS id,
                                v.Code AS code,
                                v.LicensePlate AS licensePlate,
                                v.VehicleType AS vehicleType,
                                v.MaxWeightKg AS maxWeightKg,
                                v.MaxVolumeM3 AS maxVolumeM3,
                                v.Status AS status,
                                v.IsActive AS isActive,
                                v.Version AS version,
                                v.CanSelect AS canSelect,
                                v.UnavailableReason AS unavailableReason,
                                v.IsCurrentVehicle AS isCurrentVehicle,
                                v.ShipperId AS currentShipperId,
                                v.ShipperName AS currentShipperName
                                ,v.ShipperBranchId AS currentShipperBranchId
                                ,v.ShipperBranchName AS currentShipperBranchName
                            FROM #Vehicles v
                            ORDER BY v.LicensePlate, v.Id
                            OFFSET @Offset ROWS
                            FETCH NEXT @PageSize ROWS ONLY
                            FOR JSON PATH, INCLUDE_NULL_VALUES
                        ), N'[]')) AS items
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );
            END;

            SELECT @Result;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));

        await using var command = new SqlCommand(sql, connection);

        command.Parameters.Add(
            "@AccountId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@Id", SqlDbType.BigInt).Value =
            (object?)id ?? DBNull.Value;

        command.Parameters.Add(
            "@Keyword", SqlDbType.NVarChar, 100).Value =
            id.HasValue || string.IsNullOrWhiteSpace(keyword)
                ? DBNull.Value
                : keyword.Trim();

        command.Parameters.Add(
            "@Status", SqlDbType.VarChar, 20).Value =
            id.HasValue ? DBNull.Value : (object?)status ?? DBNull.Value;

        command.Parameters.Add(
            "@ActiveOnly", SqlDbType.Bit).Value = activeOnly;
        command.Parameters.Add("@AssignableOnly", SqlDbType.Bit).Value = assignableOnly;
        command.Parameters.Add("@VehicleType", SqlDbType.VarChar, 30).Value = (object?)vehicleType ?? DBNull.Value;
        command.Parameters.Add("@FilterBranchId", SqlDbType.Int).Value = (object?)branchId ?? DBNull.Value;
        command.Parameters.Add("@IncludeFilterOptions", SqlDbType.Bit).Value = includeFilterOptions;
        command.Parameters.Add("@ForShipperId", SqlDbType.BigInt).Value = (object?)forShipperId ?? DBNull.Value;
        command.Parameters.Add("@IncludeUnavailable", SqlDbType.Bit).Value = includeUnavailable;

        command.Parameters.Add(
            "@Page", SqlDbType.Int).Value = id.HasValue ? 1 : page;

        command.Parameters.Add(
            "@PageSize", SqlDbType.Int).Value =
            id.HasValue ? 10 : pageSize;

        command.Parameters.Add(
            "@Offset", SqlDbType.BigInt).Value =
            id.HasValue ? 0L : ((long)page - 1) * pageSize;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 55101)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55102)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55103)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55104)
        {
            return Conflict(new { message = ex.Message });
        }
    }
}
