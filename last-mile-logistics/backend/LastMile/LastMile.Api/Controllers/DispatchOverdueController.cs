using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using LastMile.Api.Services.Routing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public sealed class ResolveOverdueRequest
{
    [Required, RegularExpression("^(KEEP|CANCEL)$")] public string Decision { get; set; } = "";
    [Required, StringLength(500, MinimumLength = 1)] public string ContactNote { get; set; } = "";
    public DateTimeOffset? DeliveryDeadline { get; set; }
    [Range(1, long.MaxValue)] public long? LocationId { get; set; }
}

[ApiController, Authorize, Route("api/v1/dispatch/orders")]
public sealed class DispatchOverdueController(DispatchData data) : ControllerBase
{
    [HttpPost("{id:long}/resolve-overdue")]
    public async Task<IActionResult> Resolve(long id, ResolveOverdueRequest request, CancellationToken ct)
    {
        if (id <= 0 || string.IsNullOrWhiteSpace(request.ContactNote)) return BadRequest(new { message = "Cần mã đơn và nội dung CSKH xác nhận với khách." });
        if (request.Decision == "KEEP" && (!request.DeliveryDeadline.HasValue || request.DeliveryDeadline <= DateTimeOffset.UtcNow))
            return BadRequest(new { message = "Khách vẫn nhận: cần hạn giao mới trong tương lai." });
        if (request.Decision == "CANCEL" && !request.LocationId.HasValue)
            return BadRequest(new { message = "Khách hủy: cần vị trí chờ xử lý trong cùng kho." });
        var writeStarted = false;
        try
        {
            await using var connection = data.Connection(); await connection.OpenAsync(ct);
            await using var tx = (SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            var access = await DispatchData.Authorize(connection, tx, long.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!),
                request.Decision == "KEEP" ? ["DONHANG_CAPNHAT"] : ["DONHANG_HUY", "KHO_KIEMKE"], ct);
            await using var command = DispatchData.Command(connection, tx, Sql,
                ("@Id", id), ("@Account", long.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!)),
                ("@Admin", access.Role == "ADMIN"), ("@Branch", access.BranchId),
                ("@Decision", request.Decision), ("@Note", request.ContactNote.Trim()),
                ("@Deadline", request.DeliveryDeadline?.UtcDateTime), ("@Location", request.LocationId));
            writeStarted = true;
            var json = (string?)await command.ExecuteScalarAsync(ct);
            await tx.CommitAsync(ct);
            return Content(json!, "application/json");
        }
        catch (DispatchProblem e) { return StatusCode(e.Status, new { message = e.Message }); }
        catch (SqlException e) when (e.Number is 52070 or 52071 or 52072)
        { return StatusCode(e.Number == 52070 ? 404 : 409, new { message = e.Message }); }
        catch (Exception e) when (writeStarted && e is SqlException or OperationCanceledException)
        { return StatusCode(500, new { message = "Chưa xác định được kết quả xử lý. Hãy kiểm tra đơn và lịch sử kho trước khi thực hiện lại.", code = "OVERDUE_RESULT_UNKNOWN", resultUnknown = true }); }
    }

    internal const string Sql = """
        SET NOCOUNT ON;
        DECLARE @Now DATETIME2(0)=SYSUTCDATETIME(),@Warehouse INT,@From BIGINT,@Status VARCHAR(40),@OldDeadline DATETIME2(0),@Txn BIGINT;
        SELECT @Warehouse=d.MaKhoHienTai,@From=t.MaViTriLuuKho,@Status=s.KyHieuTrangThai,@OldDeadline=d.ThoiGianDuKienGiao
        FROM dbo.DonHang d WITH(UPDLOCK,HOLDLOCK)
        JOIN dbo.TrangThaiDonHang s ON s.MaTrangThaiDonHang=d.MaTrangThaiHienTai
        LEFT JOIN dbo.TonKhoDonHang t WITH(UPDLOCK,HOLDLOCK) ON t.MaDonHang=d.MaDonHang AND t.MaKho=d.MaKhoHienTai AND t.TrangThaiTonKho='STORED'
        WHERE d.MaDonHang=@Id AND (@Admin=1 OR d.MaBuuCuc=@Branch);
        IF @Status IS NULL THROW 52070,N'Không tìm thấy đơn trong phạm vi được phép.',1;
        IF @Decision NOT IN('KEEP','CANCEL') OR NULLIF(LTRIM(RTRIM(@Note)),N'') IS NULL THROW 52071,N'Cần quyết định và nội dung xác nhận của khách.',1;
        IF @Status<>'WAITING_ASSIGNMENT' OR @OldDeadline IS NULL OR @OldDeadline>=@Now OR @Warehouse IS NULL OR @From IS NULL
          THROW 52071,N'Chỉ xử lý đơn chờ phân công đã quá hạn và còn trong kho.',1;
        IF EXISTS(SELECT 1 FROM dbo.PhanCongGiaoHang WITH(UPDLOCK,HOLDLOCK) WHERE MaDonHang=@Id AND ThoiGianKetThuc IS NULL)
          OR EXISTS(SELECT 1 FROM dbo.ChiTietChuyenGiao c WITH(UPDLOCK,HOLDLOCK) JOIN dbo.ChuyenGiaoHang t WITH(UPDLOCK,HOLDLOCK) ON t.MaChuyenGiao=c.MaChuyenGiao WHERE c.MaDonHang=@Id AND t.TrangThaiChuyen NOT IN('COMPLETED','CANCELLED'))
          THROW 52071,N'Đơn đang có nhiệm vụ hoặc chuyến hoạt động. Hãy xử lý phân công trước.',1;
        IF @Decision='KEEP'
        BEGIN
          IF @Deadline IS NULL OR @Deadline<=@Now THROW 52071,N'Hạn giao mới phải trong tương lai.',1;
          UPDATE dbo.DonHang SET MucDoUuTien=1,ThoiGianYeuCauGiao=@Now,ThoiGianDuKienGiao=@Deadline,
            ThoiGianSanSang=CASE WHEN ThoiGianSanSang>@Now THEN @Now ELSE ThoiGianSanSang END,
            MaTaiKhoanCapNhatCuoi=@Account,ThoiGianCapNhat=@Now WHERE MaDonHang=@Id;
        END
        ELSE
        BEGIN
          IF @Location=@From OR NOT EXISTS(SELECT 1 FROM dbo.ViTriLuuKho v WITH(HOLDLOCK) JOIN dbo.Kho k ON k.MaKho=v.MaKho AND k.DangHoatDong=1 WHERE v.MaViTriLuuKho=@Location AND v.MaKho=@Warehouse AND v.DangHoatDong=1)
            THROW 52072,N'Chọn vị trí chờ xử lý khác nguồn trong cùng kho đang hoạt động.',1;
          INSERT dbo.GiaoDichKho(KyHieuGiaoDich,MaKho,LoaiGiaoDich,TrangThaiGiaoDich,MaTaiKhoanThucHien,GhiChu)
          VALUES('QH-'+REPLACE(CONVERT(VARCHAR(36),NEWID()),'-',''),@Warehouse,'MOVE','COMPLETED',@Account,@Note);
          SET @Txn=SCOPE_IDENTITY();
          INSERT dbo.ChiTietGiaoDichKho(MaGiaoDichKho,MaDonHang,MaViTriNguon,MaViTriDich,TinhTrangHang,GhiChu)
          VALUES(@Txn,@Id,@From,@Location,'NORMAL',@Note);
          UPDATE dbo.TonKhoDonHang SET MaViTriLuuKho=@Location,ThoiGianDiChuyenCuoi=@Now,MaTaiKhoanCapNhatCuoi=@Account WHERE MaDonHang=@Id;
          EXEC dbo.sp_ChuyenTrangThaiDonHang @MaDonHang=@Id,@KyHieuTrangThaiMoi='CANCELLED',@MaTaiKhoan=@Account,@LyDo=@Note,@NguonCapNhat='API';
        END;
        INSERT dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuCuJson,DuLieuMoiJson)
        VALUES(@Account,'RESOLVE_OVERDUE','DonHang',CONVERT(VARCHAR(100),@Id),
          (SELECT @OldDeadline deadline,@From locationId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
          (SELECT @Decision decision,@Note contactNote,@Deadline deadline,@Location locationId,@Txn transactionId FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER));
        SELECT (SELECT @Id orderId,@Decision decision,@Txn transactionId,
          CASE WHEN @Decision='KEEP' THEN N'Đã ghi nhận khách vẫn nhận, ưu tiên cao nhất và hạn giao mới.' ELSE N'Đã hủy theo xác nhận của khách và lập phiếu chuyển hàng sang vị trí chờ xử lý.' END message
          FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
        """;
}
