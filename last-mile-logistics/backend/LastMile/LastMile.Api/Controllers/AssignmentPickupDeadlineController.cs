using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using LastMile.Api.Services;
using LastMile.Api.Services.Routing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace LastMile.Api.Controllers;

public sealed class PickupDeadlineRequest
{
    public DateTimeOffset? PickupDueAt {get;set;}
    public DateTimeOffset? ExpectedPickupDueAt {get;set;}
    [Required,StringLength(500)] public string Reason {get;set;}="";
}

[ApiController,Authorize,TypeFilter(typeof(DispatchExceptionFilter))]
[Route("api/v1/dispatch/assignments")]
public sealed class AssignmentPickupDeadlineController(DispatchData data,ShipperNotifications notifications):ControllerBase
{
    [HttpPatch("{id:long}/pickup-deadline")]
    public async Task<IActionResult> Set(long id,PickupDeadlineRequest request,CancellationToken ct)
    {
        if(id<=0 || string.IsNullOrWhiteSpace(request.Reason))return BadRequest(new{message="Cần mã nhiệm vụ và lý do thay đổi hạn lấy hàng."});
        if(!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out var account))return Unauthorized();
        await using var connection=data.Connection();await connection.OpenAsync(ct);
        var access=await DispatchData.Authorize(connection,null,account,["DIEUPHOI_PHANCONG"],ct);
        await using var schema=DispatchData.Command(connection,null,"SELECT COL_LENGTH(N'dbo.PhanCongGiaoHang',N'HanDenLayHang');");
        if(await schema.ExecuteScalarAsync(ct) is DBNull)throw new DispatchProblem(503,"Chưa chạy migration 20261030_assignment_pickup_deadline.sql.");
        await using var tx=(Microsoft.Data.SqlClient.SqlTransaction)await connection.BeginTransactionAsync(ct);
        await using var read=DispatchData.Command(connection,tx,$$"""
            SELECT {{PickupDeadlineSql.Read}},d.ThoiGianDuKienGiao,pc.MaDonHang
            FROM dbo.PhanCongGiaoHang pc WITH(UPDLOCK,HOLDLOCK)
            JOIN dbo.DonHang d WITH(UPDLOCK,HOLDLOCK) ON d.MaDonHang=pc.MaDonHang
            JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
            JOIN dbo.BuuCuc b ON b.MaBuuCuc=d.MaBuuCuc AND b.DangHoatDong=1
            WHERE pc.MaPhanCongGiaoHang=@id AND pc.ThoiGianKetThuc IS NULL
              AND pc.TrangThaiPhanCong IN ('PENDING','ACCEPTED') AND tt.KyHieuTrangThai='ASSIGNED'
              AND (@admin=1 OR d.MaBuuCuc=@branch);
            """,("@id",id),("@admin",access.Role=="ADMIN"),("@branch",access.BranchId));
        DateTimeOffset? before,delivery;long order;
        await using(var reader=await read.ExecuteReaderAsync(ct)){
            if(!await reader.ReadAsync(ct))throw new DispatchProblem(409,"Phân công không còn ở bước chờ lấy hàng trong phạm vi của bạn. Hãy tải lại.");
            before=reader.IsDBNull(0)?null:new DateTimeOffset(DateTime.SpecifyKind(reader.GetDateTime(0),DateTimeKind.Utc));
            delivery=reader.IsDBNull(1)?null:new DateTimeOffset(DateTime.SpecifyKind(reader.GetDateTime(1),DateTimeKind.Utc));order=reader.GetInt64(2);
        }
        if(before?.ToUnixTimeSeconds()!=request.ExpectedPickupDueAt?.ToUnixTimeSeconds())throw new DispatchProblem(409,"Hạn lấy hàng đã thay đổi. Hãy tải lại trước khi sửa.");
        DateTimeOffset? due=request.PickupDueAt is {} value?DateTimeOffset.FromUnixTimeSeconds(value.ToUnixTimeSeconds()):null;
        if(due.HasValue && (due<=DateTimeOffset.UtcNow || delivery.HasValue && due>delivery))throw new DispatchProblem(422,"Hạn lấy hàng phải trong tương lai và không sau hạn giao của đơn.");
        var result=new{assignmentId=id,orderId=order,pickupDueAt=due,reason=request.Reason.Trim()};
        await using var update=DispatchData.Command(connection,tx,"""
            EXEC sp_executesql N'UPDATE dbo.PhanCongGiaoHang SET HanDenLayHang=@due WHERE MaPhanCongGiaoHang=@id;',N'@due DATETIME2(0),@id BIGINT',@due,@id;
            UPDATE dbo.DonHang SET MaTaiKhoanCapNhatCuoi=@account,ThoiGianCapNhat=SYSUTCDATETIME() WHERE MaDonHang=@order;
            INSERT dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuCuJson,DuLieuMoiJson)
            VALUES(@account,'SET_PICKUP_DEADLINE','PhanCongGiaoHang',CONVERT(VARCHAR(100),@id),@before,@after);
            """,("@id",id),("@due",due?.UtcDateTime),("@account",account),("@order",order),
            ("@before",System.Text.Json.JsonSerializer.Serialize(new{pickupDueAt=before},DispatchData.Json)),("@after",System.Text.Json.JsonSerializer.Serialize(result,DispatchData.Json)));
        await update.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);await notifications.TaskUpdated(id);return Ok(result);
    }
}
