using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public class DeliverySuccessRequest
{
    [Required]
    [StringLength(150)]
    public string ReceiverName { get; set; } = "";

    [Required]
    [Range(
        typeof(decimal), "0", "9999999999999999.99",
        ParseLimitsInInvariantCulture = true,
        ConvertValueInInvariantCulture = true)]
    public decimal? ActualCodAmount { get; set; }

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

    [StringLength(500)]
    public string? CodNotes { get; set; }
}

[ApiController]
[Authorize]
[Route("api/v1/orders")]
public class OrderDeliverySuccessController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public OrderDeliverySuccessController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{id:long}/delivery-success")]
    public async Task<IActionResult> DeliverySuccess(
        long id,
        [FromBody] DeliverySuccessRequest request)
    {
        if (id <= 0)
        {
            return BadRequest(new
            {
                message = "Mã đơn hàng không hợp lệ."
            });
        }

        var receiverName = request.ReceiverName.Trim();

        if (string.IsNullOrWhiteSpace(receiverName))
        {
            return BadRequest(new
            {
                message = "Phải nhập tên người thực tế nhận hàng."
            });
        }

        if (request.Latitude.HasValue != request.Longitude.HasValue)
        {
            return BadRequest(new
            {
                message = "Phải cung cấp cả latitude và longitude hoặc bỏ cả hai."
            });
        }

        var actualCodAmount = request.ActualCodAmount!.Value;

        if (decimal.Round(actualCodAmount, 2) != actualCodAmount)
        {
            return BadRequest(new
            {
                message = "Tiền COD chỉ được có tối đa 2 chữ số thập phân."
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

        if (!long.TryParse(
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            out var accountId))
        {
            return Unauthorized();
        }

        var codNotes = string.IsNullOrWhiteSpace(request.CodNotes)
            ? null
            : request.CodNotes.Trim();

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
                    @ShipperId BIGINT,
                    @OrderStatus VARCHAR(40),
                    @ExpectedCod DECIMAL(18,2),
                    @AssignmentId BIGINT,
                    @DeliveryAttemptId BIGINT,
                    @EvidenceId BIGINT,
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
                    THROW 51801,
                        N'Tài khoản không còn hoạt động hoặc đang bị khóa.',
                        1;

                IF @Role <> 'SHIPPER'
                   OR NOT EXISTS (
                       SELECT 1
                       FROM dbo.VaiTroQuyen vtq
                       INNER JOIN dbo.Quyen q
                           ON q.MaQuyen = vtq.MaQuyen
                       WHERE vtq.MaVaiTro = @RoleId
                         AND q.KyHieuQuyen = 'NHIEMVU_CAPNHAT'
                   )
                    THROW 51802,
                        N'API này dành cho shipper ghi nhận kết quả giao hàng.',
                        1;

                SELECT @ShipperId = MaNhanVienGiaoHang
                FROM dbo.NhanVienGiaoHang
                WHERE MaTaiKhoan = @AccountId
                  AND DangHoatDong = 1;

                IF @ShipperId IS NULL
                    THROW 51802,
                        N'Tài khoản chưa có hồ sơ shipper đang hoạt động.',
                        1;

                SELECT
                    @OrderStatus = tt.KyHieuTrangThai,
                    @ExpectedCod = d.TienCOD
                FROM dbo.DonHang d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TrangThaiDonHang tt
                    ON tt.MaTrangThaiDonHang = d.MaTrangThaiHienTai
                WHERE d.MaDonHang = @OrderId
                  AND d.MaBuuCuc = @AccountBranchId
                  AND EXISTS (
                      SELECT 1
                      FROM dbo.PhanCongGiaoHang pc
                      WHERE pc.MaDonHang = d.MaDonHang
                        AND pc.MaNhanVienGiaoHang = @ShipperId
                  );

                IF @OrderStatus IS NULL
                    THROW 51803,
                        N'Không tìm thấy đơn hàng của bạn.',
                        1;

                IF @OrderStatus <> 'IN_DELIVERY'
                    THROW 51804,
                        N'Chỉ đơn IN_DELIVERY mới được ghi nhận giao thành công.',
                        1;

                SELECT @AssignmentId = pc.MaPhanCongGiaoHang
                FROM dbo.PhanCongGiaoHang pc
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE pc.MaDonHang = @OrderId
                  AND pc.MaNhanVienGiaoHang = @ShipperId
                  AND pc.ThoiGianKetThuc IS NULL
                  AND pc.TrangThaiPhanCong = 'IN_PROGRESS';

                IF @AssignmentId IS NULL
                    THROW 51804,
                        N'Bạn không có phân công IN_PROGRESS hiện hành của đơn.',
                        1;

                IF @ActualCodAmount <> @ExpectedCod
                    THROW 51805,
                        N'Số tiền COD thực thu phải bằng đúng tiền COD của đơn. Đơn không COD nhập 0.',
                        1;

                SET @OldJson = (
                    SELECT
                        @OrderId AS orderId,
                        @AssignmentId AS assignmentId,
                        @OrderStatus AS orderStatus,
                        @ExpectedCod AS codAmount
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                -- Procedure tạo lần giao, bằng chứng, COD,
                -- đổi trạng thái đơn và kết thúc phân công.
                EXEC dbo.sp_XacNhanGiaoHangThanhCong
                    @MaDonHang = @OrderId,
                    @MaNhanVienGiaoHang = @ShipperId,
                    @MaTaiKhoan = @AccountId,
                    @LoaiBangChung = 'RECEIVER_CONFIRMATION',
                    @DuongDanTep = NULL,
                    @MaXacNhanBam = NULL,
                    @TenNguoiNhan = @ReceiverName,
                    @ViDo = @Latitude,
                    @KinhDo = @Longitude,
                    @SoTienThucThu = @ActualCodAmount,
                    @GhiChuCOD = @CodNotes;
                
                UPDATE dbo.YeuCauGiaoLaiHoacHoan
                SET TrangThaiYeuCau = 'COMPLETED',
                    ThoiGianHoanTat = SYSUTCDATETIME()
                WHERE MaDonHang = @OrderId
                  AND LoaiYeuCau = 'RETRY'
                  AND TrangThaiYeuCau = 'IN_PROGRESS';

                SELECT @DeliveryAttemptId = MaLanGiaoHang
                FROM dbo.LanGiaoHang
                WHERE MaDonHang = @OrderId
                  AND MaPhanCongGiaoHang = @AssignmentId
                  AND KetQua = 'SUCCESS';

                SELECT TOP (1) @EvidenceId = MaBangChung
                FROM dbo.BangChungGiaoHang
                WHERE MaDonHang = @OrderId
                  AND MaLanGiaoHang = @DeliveryAttemptId
                ORDER BY MaBangChung DESC;

                SET @Result = (
                    SELECT
                        d.MaDonHang AS orderId,
                        d.KyHieuDonHang AS orderCode,
                        d.MaVanDon AS trackingNumber,
                        @AssignmentId AS assignmentId,
                        @DeliveryAttemptId AS deliveryAttemptId,
                        @EvidenceId AS evidenceId,
                        @ShipperId AS shipperId,
                        @ReceiverName AS receiverName,
                        'RECEIVER_CONFIRMATION' AS evidenceType,
                        tt.KyHieuTrangThai AS orderStatus,
                        pc.TrangThaiPhanCong AS assignmentStatus,
                        d.TienCOD AS codAmount,
                        @ActualCodAmount AS actualCodAmount,
                        CASE
                            WHEN d.TienCOD > 0 THEN 'COLLECTED'
                            ELSE 'NOT_REQUIRED'
                        END AS codStatus,
                        lg.ThoiGianThuGiao AS deliveredAt,
                        d.PhienBan AS version,
                        N'Đã ghi nhận giao hàng thành công.'
                            AS message
                    FROM dbo.DonHang d
                    INNER JOIN dbo.TrangThaiDonHang tt
                        ON tt.MaTrangThaiDonHang =
                           d.MaTrangThaiHienTai
                    INNER JOIN dbo.PhanCongGiaoHang pc
                        ON pc.MaPhanCongGiaoHang = @AssignmentId
                    INNER JOIN dbo.LanGiaoHang lg
                        ON lg.MaLanGiaoHang = @DeliveryAttemptId
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
                    'DELIVERY_SUCCESS',
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
            "@OrderId", SqlDbType.BigInt).Value = id;

        command.Parameters.Add(
            "@ReceiverName", SqlDbType.NVarChar, 150).Value =
                receiverName;

        var codParameter = command.Parameters.Add(
            "@ActualCodAmount", SqlDbType.Decimal);
        codParameter.Precision = 18;
        codParameter.Scale = 2;
        codParameter.Value = actualCodAmount;

        var latitudeParameter = command.Parameters.Add(
            "@Latitude", SqlDbType.Decimal);
        latitudeParameter.Precision = 9;
        latitudeParameter.Scale = 6;
        latitudeParameter.Value =
            (object?)request.Latitude ?? DBNull.Value;

        var longitudeParameter = command.Parameters.Add(
            "@Longitude", SqlDbType.Decimal);
        longitudeParameter.Precision = 10;
        longitudeParameter.Scale = 6;
        longitudeParameter.Value =
            (object?)request.Longitude ?? DBNull.Value;

        command.Parameters.Add(
            "@CodNotes", SqlDbType.NVarChar, 500).Value =
                (object?)codNotes ?? DBNull.Value;

        try
        {
            var json = (string?)await command.ExecuteScalarAsync();

            return Content(json!, "application/json");
        }
        catch (SqlException ex) when (
            ex.Number is >= 51801 and <= 51805)
        {
            var statusCode = ex.Number switch
            {
                51801 => StatusCodes.Status401Unauthorized,
                51802 => StatusCodes.Status403Forbidden,
                51803 => StatusCodes.Status404NotFound,
                51805 => StatusCodes.Status422UnprocessableEntity,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (
            ex.Number is >= 51120 and <= 51129)
        {
            var statusCode = ex.Number switch
            {
                51120 => StatusCodes.Status403Forbidden,
                51121 => StatusCodes.Status404NotFound,
                51124 or 51125 or 51126 or 51128 or 51129 =>
                    StatusCodes.Status422UnprocessableEntity,
                _ => StatusCodes.Status409Conflict
            };

            return StatusCode(statusCode, new
            {
                message = ex.Message
            });
        }
        catch (SqlException ex) when (
            ex.Number is 2601 or 2627)
        {
            return Conflict(new
            {
                message =
                    "Đơn đã có dữ liệu giao thành công hoặc thu COD. Hãy tải lại đơn."
            });
        }
        catch (SqlException ex) when (ex.Number == 1205)
        {
            return Conflict(new
            {
                message =
                    "Có thao tác đồng thời. Hãy tải lại đơn và thử lại."
            });
        }
    }
}