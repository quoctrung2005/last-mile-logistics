using LastMile.Api.Services;
using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class SetShipperVehicleRequest
{
    [Range(1, long.MaxValue)]
    public long? VehicleId { get; set; }

    [Range(1, long.MaxValue)]
    public long? ExpectedAssignmentId { get; set; }

    [Required]
    [StringLength(500)]
    public string Notes { get; set; } = "";
}

[ApiController]
[Authorize]
[Route("api/v1/shippers")]
public class ShipperVehicleController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public ShipperVehicleController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPut("{id:long}/vehicle")]
    public async Task<IActionResult> SetVehicle(
        long id,
        SetShipperVehicleRequest request,
        CancellationToken cancellationToken)
    {
        if (id <= 0)
            return BadRequest(new { message = "Mã shipper không hợp lệ." });

        if (!long.TryParse(
                User.FindFirstValue(ClaimTypes.NameIdentifier),
                out var accountId))
        {
            return Unauthorized();
        }

        if (string.IsNullOrWhiteSpace(request.Notes))
        {
            return BadRequest(new
            {
                message = "Phải nhập ghi chú phân công, đổi hoặc thu hồi xe."
            });
        }

        var sql = $$"""
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            BEGIN TRY
                BEGIN TRAN;

                DECLARE
                    @Role VARCHAR(50),
                    @RoleId INT,
                    @TargetAccountId BIGINT,
                    @CurrentAssignmentId BIGINT,
                    @OldVehicleId BIGINT,
                    @NewAssignmentId BIGINT,
                    @OldJson NVARCHAR(MAX),
                    @Result NVARCHAR(MAX);

                SELECT
                    @Role = vt.KyHieuVaiTro,
                    @RoleId = tk.MaVaiTro
                FROM dbo.TaiKhoan tk WITH (HOLDLOCK)
                JOIN dbo.VaiTro vt
                    ON vt.MaVaiTro = tk.MaVaiTro
                WHERE tk.MaTaiKhoan = @ActorId
                  AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                  AND vt.DangHoatDong = 1
                  AND (
                      tk.KhoaDenLuc IS NULL
                      OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                  );

                IF @Role IS NULL
                    THROW 55301,
                        N'Tài khoản không còn hợp lệ.', 1;

                IF @Role <> 'ADMIN'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vq
                       JOIN dbo.Quyen q ON q.MaQuyen = vq.MaQuyen
                       WHERE vq.MaVaiTro = @RoleId
                         AND q.KyHieuQuyen = 'TAIKHOAN_QUANLY'
                   )
                    THROW 55302,
                        N'API này dành cho admin quản lý phân công xe.', 1;

                SELECT @TargetAccountId = MaTaiKhoan
                FROM dbo.NhanVienGiaoHang WITH (UPDLOCK, HOLDLOCK)
                WHERE MaNhanVienGiaoHang = @ShipperId;

                IF @TargetAccountId IS NULL
                    THROW 55303,
                        N'Không tìm thấy shipper.', 1;

                SELECT
                    @CurrentAssignmentId = MaPhanCongPhuongTien,
                    @OldVehicleId = MaPhuongTien
                FROM dbo.PhanCongPhuongTien WITH (UPDLOCK, HOLDLOCK)
                WHERE MaNhanVienGiaoHang = @ShipperId
                  AND ThoiGianKetThuc IS NULL;

                IF ISNULL(@CurrentAssignmentId, -1)
                   <> ISNULL(@ExpectedAssignmentId, -1)
                    THROW 55304,
                        N'Phân công xe đã thay đổi. Hãy tải lại thông tin shipper.', 1;

                IF @VehicleId IS NULL AND @CurrentAssignmentId IS NULL
                    THROW 55304,
                        N'Shipper chưa có xe để kết thúc phân công.', 1;

                IF @VehicleId IS NOT NULL
                   AND @VehicleId = @OldVehicleId
                    THROW 55304,
                        N'Shipper đang sử dụng chính xe này.', 1;

                -- Khóa xe cũ và xe mới.
                SELECT MaPhuongTien
                INTO #LockedVehicles
                FROM dbo.PhuongTien WITH (UPDLOCK, HOLDLOCK)
                WHERE MaPhuongTien = @OldVehicleId
                   OR MaPhuongTien = @VehicleId;

                IF @VehicleId IS NOT NULL
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM #LockedVehicles
                        WHERE MaPhuongTien = @VehicleId
                    )
                        THROW 55303,
                            N'Không tìm thấy xe mới.', 1;

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.NhanVienGiaoHang nv
                        JOIN dbo.TaiKhoan tk WITH (UPDLOCK, HOLDLOCK)
                            ON tk.MaTaiKhoan = nv.MaTaiKhoan
                        JOIN dbo.VaiTro vt WITH (HOLDLOCK)
                            ON vt.MaVaiTro = tk.MaVaiTro
                        JOIN dbo.BuuCuc bc WITH (HOLDLOCK)
                            ON bc.MaBuuCuc = tk.MaBuuCuc
                        WHERE nv.MaNhanVienGiaoHang = @ShipperId
                          AND nv.DangHoatDong = 1
                          AND (
                              nv.NgayHetHanBangLai IS NULL
                              OR nv.NgayHetHanBangLai >=
                                  {{VietnamDate.SqlDate("SYSUTCDATETIME()")}}
                          )
                          AND tk.TrangThaiTaiKhoan = 'ACTIVE'
                          AND (
                              tk.KhoaDenLuc IS NULL
                              OR tk.KhoaDenLuc <= SYSUTCDATETIME()
                          )
                          AND vt.KyHieuVaiTro = 'SHIPPER'
                          AND vt.DangHoatDong = 1
                          AND bc.DangHoatDong = 1
                    )
                        THROW 55305,
                            N'Hồ sơ, tài khoản, bưu cục hoặc bằng lái của shipper không hợp lệ.', 1;

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.PhuongTien
                        WHERE MaPhuongTien = @VehicleId
                          AND DangHoatDong = 1
                          AND TrangThaiPhuongTien = 'AVAILABLE'
                    )
                        THROW 55305,
                            N'Xe mới phải đang hoạt động và có trạng thái AVAILABLE.', 1;

                    IF EXISTS (
                        SELECT 1
                        FROM dbo.PhanCongPhuongTien
                            WITH (UPDLOCK, HOLDLOCK)
                        WHERE MaPhuongTien = @VehicleId
                          AND ThoiGianKetThuc IS NULL
                    )
                        THROW 55304,
                            N'Xe mới đã được giao cho shipper khác.', 1;
                END;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.PhanCongGiaoHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE ThoiGianKetThuc IS NULL
                      AND (
                          MaNhanVienGiaoHang = @ShipperId
                          OR MaPhuongTien = @OldVehicleId
                          OR MaPhuongTien = @VehicleId
                      )
                )
                    THROW 55304,
                        N'Shipper hoặc xe còn phân công giao hàng đang hoạt động.', 1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.ChuyenGiaoHang WITH (UPDLOCK, HOLDLOCK)
                    WHERE TrangThaiChuyen IN (
                        'PLANNED', 'ASSIGNED', 'ACCEPTED', 'IN_PROGRESS'
                    )
                      AND (
                          MaNhanVienGiaoHang = @ShipperId
                          OR MaPhuongTien = @OldVehicleId
                          OR MaPhuongTien = @VehicleId
                      )
                )
                    THROW 55304,
                        N'Shipper hoặc xe còn thuộc chuyến chưa kết thúc.', 1;

                IF EXISTS (
                    SELECT 1
                    FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                    JOIN dbo.TrangThaiDonHang tt
                        ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                    CROSS APPLY (
                        SELECT TOP (1)
                            pc.MaNhanVienGiaoHang,
                            pc.MaPhuongTien
                        FROM dbo.PhanCongGiaoHang pc WITH (HOLDLOCK)
                        WHERE pc.MaDonHang = d.MaDonHang
                        ORDER BY
                            pc.ThoiGianPhanCong DESC,
                            pc.MaPhanCongGiaoHang DESC
                    ) latest
                    WHERE tt.KyHieuTrangThai = 'RETURNING'
                      AND (
                          latest.MaNhanVienGiaoHang = @ShipperId
                          OR latest.MaPhuongTien = @OldVehicleId
                          OR latest.MaPhuongTien = @VehicleId
                      )
                )
                    THROW 55304,
                        N'Shipper hoặc xe còn nhiệm vụ hoàn hàng.', 1;

                SELECT @OldJson = (
                    SELECT
                        @ShipperId AS shipperId,
                        @CurrentAssignmentId AS assignmentId,
                        @OldVehicleId AS vehicleId
                    FOR JSON PATH,
                        INCLUDE_NULL_VALUES,
                        WITHOUT_ARRAY_WRAPPER
                );

                DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

                IF @CurrentAssignmentId IS NOT NULL
                BEGIN
                    UPDATE dbo.PhanCongPhuongTien
                    SET ThoiGianKetThuc = @Now
                    WHERE MaPhanCongPhuongTien = @CurrentAssignmentId
                      AND ThoiGianKetThuc IS NULL;

                    UPDATE dbo.PhuongTien
                    SET TrangThaiPhuongTien = 'AVAILABLE'
                    WHERE MaPhuongTien = @OldVehicleId
                      AND DangHoatDong = 1
                      AND TrangThaiPhuongTien = 'IN_USE';
                END;

                IF @VehicleId IS NOT NULL
                BEGIN
                    INSERT INTO dbo.PhanCongPhuongTien (
                        MaNhanVienGiaoHang,
                        MaPhuongTien,
                        ThoiGianPhanCong,
                        MaTaiKhoanPhanCong,
                        GhiChu
                    )
                    VALUES (
                        @ShipperId,
                        @VehicleId,
                        @Now,
                        @ActorId,
                        @Notes
                    );

                    SET @NewAssignmentId =
                        CONVERT(BIGINT, SCOPE_IDENTITY());
                END;

                SELECT @Result = (
                    SELECT
                        @ShipperId AS shipperId,
                        @CurrentAssignmentId AS previousAssignmentId,
                        @OldVehicleId AS previousVehicleId,
                        @NewAssignmentId AS assignmentId,
                        @VehicleId AS vehicleId,
                        pt.BienSo AS licensePlate,
                        @Now AS performedAt,
                        @Notes AS notes,
                        CASE
                            WHEN @VehicleId IS NULL
                                THEN N'Kết thúc phân công xe thành công.'
                            WHEN @OldVehicleId IS NULL
                                THEN N'Phân công xe thành công.'
                            ELSE N'Đổi xe thành công.'
                        END AS message
                    FROM (VALUES (1)) seed(n)
                    LEFT JOIN dbo.PhuongTien pt
                        ON pt.MaPhuongTien = @VehicleId
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
                    @ActorId,
                    'SET_SHIPPER_VEHICLE',
                    'NhanVienGiaoHang',
                    CONVERT(VARCHAR(100), @ShipperId),
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
            "@ActorId", SqlDbType.BigInt).Value = accountId;

        command.Parameters.Add(
            "@ShipperId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@VehicleId", SqlDbType.BigInt).Value =
            (object?)request.VehicleId ?? DBNull.Value;

        command.Parameters.Add(
            "@ExpectedAssignmentId", SqlDbType.BigInt).Value =
            (object?)request.ExpectedAssignmentId ?? DBNull.Value;

        command.Parameters.Add(
            "@Notes", SqlDbType.NVarChar, 500).Value =
            request.Notes.Trim();

        try
        {
            await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(
                cancellationToken);

            return Content(
                result?.ToString() ?? "{}",
                "application/json");
        }
        catch (SqlException ex) when (ex.Number == 55301)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55302)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55303)
        {
            return NotFound(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55304)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (SqlException ex) when (ex.Number == 55305)
        {
            return UnprocessableEntity(new { message = ex.Message });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627 or 1205)
        {
            return Conflict(new
            {
                message = "Phân công xe đang được cập nhật đồng thời. Hãy tải lại và thử lại."
            });
        }
    }
}