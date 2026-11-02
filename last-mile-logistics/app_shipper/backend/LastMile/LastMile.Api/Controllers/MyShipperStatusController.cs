using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class UpdateMyShipperStatusRequest
{
    [RegularExpression(
        "^(AVAILABLE|DELIVERING|BREAK|OFFLINE)$",
        ErrorMessage = "Availability phải là AVAILABLE, DELIVERING, BREAK hoặc OFFLINE.")]
    public string? Availability { get; set; }

    [Range(
        typeof(decimal), "-90", "90",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? Latitude { get; set; }

    [Range(
        typeof(decimal), "-180", "180",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? Longitude { get; set; }

    [Range(
        typeof(decimal), "0", "999999.99",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? AccuracyMeters { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/my/shipper-status")]
public class MyShipperStatusController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public MyShipperStatusController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
            return Unauthorized();

        const string sql = """
            SELECT
                nv.MaNhanVienGiaoHang AS shipperId,
                nv.MaNhanVien AS employeeCode,
                nv.TrangThaiSanSang AS availability,
                nv.ViDoHienTai AS latitude,
                nv.KinhDoHienTai AS longitude,
                nv.ThoiGianCapNhatViTri AS locationUpdatedAt
            FROM dbo.NhanVienGiaoHang nv
            WHERE nv.MaTaiKhoan = @AccountId
              AND nv.DangHoatDong = 1
            FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER;
            """;

        await using var connection = new SqlConnection(
            _configuration.GetConnectionString("DefaultConnection"));
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@AccountId", SqlDbType.BigInt).Value = accountId;
        await connection.OpenAsync(cancellationToken);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        if (result is null || result == DBNull.Value)
            return NotFound(new { message = "Không tìm thấy hồ sơ shipper đang hoạt động." });
        return Content(result.ToString()!, "application/json");
    }

    [HttpPatch]
    public async Task<IActionResult> Update(
        UpdateMyShipperStatusRequest request,
        CancellationToken cancellationToken)
    {
        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        if (request.Availability is null && !request.Latitude.HasValue
            && !request.Longitude.HasValue)
        {
            return BadRequest(new
            {
                message = "Phải gửi trạng thái hoặc tọa độ cần cập nhật."
            });
        }

        if (request.Latitude.HasValue != request.Longitude.HasValue)
        {
            return BadRequest(new
            {
                message = "Phải nhập cả latitude và longitude."
            });
        }

        if (request.AccuracyMeters.HasValue
            && !request.Latitude.HasValue)
        {
            return BadRequest(new
            {
                message = "AccuracyMeters phải đi kèm tọa độ."
            });
        }

        if ((request.Latitude.HasValue
             && decimal.Round(request.Latitude.Value, 6)
                != request.Latitude.Value)
            || (request.Longitude.HasValue
                && decimal.Round(request.Longitude.Value, 6)
                   != request.Longitude.Value))
        {
            return BadRequest(new
            {
                message = "Tọa độ chỉ được có tối đa 6 chữ số thập phân."
            });
        }

        if (request.AccuracyMeters.HasValue
            && decimal.Round(request.AccuracyMeters.Value, 2)
               != request.AccuracyMeters.Value)
        {
            return BadRequest(new
            {
                message = "AccuracyMeters chỉ được có tối đa 2 chữ số thập phân."
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
                    @BranchId INT,
                    @ShipperId BIGINT,
                    @OldAvailability VARCHAR(20),
                    @HasWork BIT = 0,
                    @HasDeliveryWork BIT = 0,
                    @LocationHistoryId BIGINT = NULL,
                    @OldJson NVARCHAR(MAX),
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
                    THROW 55001,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF @Role <> 'SHIPPER'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vq
                       JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                       WHERE vq.MaVaiTro = @RoleId
                         AND q.KyHieuQuyen = 'NHIEMVU_CAPNHAT'
                   )
                    THROW 55002,
                        N'API này dành cho shipper cập nhật trạng thái của mình.', 1;

                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.BuuCuc WITH (HOLDLOCK)
                    WHERE MaBuuCuc = @BranchId
                      AND DangHoatDong = 1
                )
                    THROW 55002,
                        N'Tài khoản chưa thuộc bưu cục đang hoạt động.', 1;

                SELECT
                    @ShipperId = nv.MaNhanVienGiaoHang,
                    @OldAvailability = nv.TrangThaiSanSang
                FROM dbo.NhanVienGiaoHang nv WITH (UPDLOCK, HOLDLOCK)
                WHERE nv.MaTaiKhoan = @AccountId
                  AND nv.DangHoatDong = 1;

                IF @ShipperId IS NULL
                    THROW 55003,
                        N'Không tìm thấy hồ sơ shipper đang hoạt động.', 1;

                SELECT @OldJson = (
                    SELECT @OldAvailability AS availability
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                -- Chỉ kiểm tra công việc khi người dùng
                -- yêu cầu thay đổi trạng thái.
                IF @Availability IS NOT NULL
                BEGIN
                    IF EXISTS (
                        SELECT 1
                        FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaNhanVienGiaoHang = @ShipperId
                          AND ThoiGianKetThuc IS NULL
                    )
                        SET @HasWork = 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.ChuyenGiaoHang WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaNhanVienGiaoHang = @ShipperId
                          AND TrangThaiChuyen IN (
                              'ASSIGNED', 'ACCEPTED', 'IN_PROGRESS'
                          )
                    )
                        SET @HasWork = 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.PhanCongGiaoHang pc
                            WITH (UPDLOCK, HOLDLOCK)
                        JOIN dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                            ON d.MaDonHang = pc.MaDonHang
                        JOIN dbo.TrangThaiDonHang tt
                            ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                        WHERE pc.MaNhanVienGiaoHang = @ShipperId
                          AND pc.ThoiGianKetThuc IS NULL
                          AND tt.KyHieuTrangThai IN (
                              'HANDED_OVER', 'EN_ROUTE_PICKUP',
                              'PICKED_UP', 'IN_DELIVERY',
                              'FAILED', 'RETRY_WAITING'
                          )
                    )
                        SET @HasDeliveryWork = 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.ChuyenGiaoHang WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaNhanVienGiaoHang = @ShipperId
                          AND TrangThaiChuyen = 'IN_PROGRESS'
                    )
                        SET @HasDeliveryWork = 1;

                    -- Phân công có thể đã đóng khi bắt đầu hoàn hàng.
                    IF EXISTS (
                        SELECT 1
                        FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                        JOIN dbo.TrangThaiDonHang tt
                            ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                        CROSS APPLY (
                            SELECT TOP (1)
                                pc.MaNhanVienGiaoHang
                            FROM dbo.PhanCongGiaoHang pc WITH (HOLDLOCK)
                            WHERE pc.MaDonHang = d.MaDonHang
                            ORDER BY
                                pc.ThoiGianPhanCong DESC,
                                pc.MaPhanCongGiaoHang DESC
                        ) latest
                        WHERE tt.KyHieuTrangThai = 'RETURNING'
                          AND latest.MaNhanVienGiaoHang = @ShipperId
                    )
                    BEGIN
                        SET @HasWork = 1;
                        SET @HasDeliveryWork = 1;
                    END;

                    IF @Availability IN ('BREAK', 'OFFLINE')
                       AND @HasWork = 1
                        THROW 55004,
                            N'Bạn còn nhiệm vụ hoặc chuyến chưa kết thúc, chưa thể nghỉ hoặc ngoại tuyến.', 1;

                    IF @Availability = 'AVAILABLE'
                       AND @HasDeliveryWork = 1
                        THROW 55004,
                            N'Bạn còn hàng đang giao hoặc đang hoàn, chưa thể chuyển sang AVAILABLE.', 1;

                    IF @Availability = 'DELIVERING'
                       AND @HasWork = 0
                        THROW 55004,
                            N'Bạn chưa có nhiệm vụ hoặc chuyến đang hoạt động.', 1;
                END;

                DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

                UPDATE dbo.NhanVienGiaoHang
                SET TrangThaiSanSang =
                        COALESCE(@Availability, TrangThaiSanSang),
                    ViDoHienTai = CASE
                        WHEN @HasLocation = 1 THEN @Latitude
                        ELSE ViDoHienTai
                    END,
                    KinhDoHienTai = CASE
                        WHEN @HasLocation = 1 THEN @Longitude
                        ELSE KinhDoHienTai
                    END,
                    ThoiGianCapNhatViTri = CASE
                        WHEN @HasLocation = 1 THEN @Now
                        ELSE ThoiGianCapNhatViTri
                    END
                WHERE MaNhanVienGiaoHang = @ShipperId;

                IF @HasLocation = 1
                BEGIN
                    INSERT INTO dbo.LichSuViTriNhanVienGiaoHang (
                        MaNhanVienGiaoHang,
                        ViDo,
                        KinhDo,
                        DoChinhXacMet,
                        ThoiGianGhiNhan
                    )
                    VALUES (
                        @ShipperId,
                        @Latitude,
                        @Longitude,
                        @AccuracyMeters,
                        @Now
                    );

                    SET @LocationHistoryId =
                        CONVERT(BIGINT, SCOPE_IDENTITY());
                END;

                SELECT @Result = (
                    SELECT
                        nv.MaNhanVienGiaoHang AS shipperId,
                        nv.MaNhanVien AS employeeCode,
                        nv.TrangThaiSanSang AS availability,
                        nv.ViDoHienTai AS latitude,
                        nv.KinhDoHienTai AS longitude,
                        nv.ThoiGianCapNhatViTri AS locationUpdatedAt,
                        @LocationHistoryId AS locationHistoryId,
                        N'Cập nhật trạng thái/vị trí thành công.' AS message
                    FROM dbo.NhanVienGiaoHang nv
                    WHERE nv.MaNhanVienGiaoHang = @ShipperId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                -- GPS đã có bảng lịch sử riêng.
                -- Nhật ký hoạt động chỉ ghi khi đổi trạng thái.
                IF @Availability IS NOT NULL
                   AND @Availability <> @OldAvailability
                BEGIN
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
                        'UPDATE_SHIPPER_STATUS',
                        'NhanVienGiaoHang',
                        CONVERT(VARCHAR(100), @ShipperId),
                        @OldJson,
                        @Result
                    );
                END;

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
            "@Availability", SqlDbType.VarChar, 20).Value =
            (object?)request.Availability ?? DBNull.Value;

        command.Parameters.Add(
            "@HasLocation", SqlDbType.Bit).Value =
            request.Latitude.HasValue;

        var latitude = command.Parameters.Add(
            "@Latitude", SqlDbType.Decimal);
        latitude.Precision = 9;
        latitude.Scale = 6;
        latitude.Value =
            (object?)request.Latitude ?? DBNull.Value;

        var longitude = command.Parameters.Add(
            "@Longitude", SqlDbType.Decimal);
        longitude.Precision = 10;
        longitude.Scale = 6;
        longitude.Value =
            (object?)request.Longitude ?? DBNull.Value;

        var accuracy = command.Parameters.Add(
            "@AccuracyMeters", SqlDbType.Decimal);
        accuracy.Precision = 8;
        accuracy.Scale = 2;
        accuracy.Value =
            (object?)request.AccuracyMeters ?? DBNull.Value;

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 55001)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55002)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55003)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55004)
        {
            return Conflict(new { message = ex.Message });
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
