using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

public sealed class DashboardProblem(int status, string message) : Exception(message) { public int Status { get; } = status; }
public sealed class DashboardExceptionFilter(ILogger<DashboardExceptionFilter> logger) : IExceptionFilter
{
    public void OnException(ExceptionContext context)
    {
        if (context.Exception is OperationCanceledException && context.HttpContext.RequestAborted.IsCancellationRequested) return;
        int status; string message;
        if (context.Exception is DashboardProblem problem) { status = problem.Status; message = problem.Message; }
        else
        {
            logger.LogError(context.Exception, "Dashboard query failed");
            status = context.Exception is SqlException ? 503 : 500;
            message = "Chưa tải được dữ liệu tổng quan. Hãy thử lại hoặc kiểm tra máy chủ.";
        }
        context.Result = new ObjectResult(new { message }) { StatusCode = status }; context.ExceptionHandled = true;
    }
}

[ApiController, Authorize, TypeFilter(typeof(DashboardExceptionFilter))]
[Route("api/v1/dashboard")]
public sealed class DashboardController(IConfiguration configuration) : ControllerBase
{
    private sealed record Scope(string Role, int? BranchId, HashSet<string> Grants)
    {
        public bool Can(string code) => Grants.Contains(code);
        public bool Orders => Can("DONHANG_XEM");
        public bool Inbound => Orders && Can("KHO_XEM");
        public bool Dispatch => Orders && Can("DIEUPHOI_GOMDON");
        public bool Delivery => Orders || Can("BAOCAO_XEM");
    }
    private SqlConnection Connection() => new(configuration.GetConnectionString("DefaultConnection"));
    private static SqlCommand Command(SqlConnection connection, string sql) => new(sql, connection) { CommandTimeout = 30 };
    private async Task<Scope> AuthorizeScope(SqlConnection connection, int? branchId, CancellationToken ct)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out long accountId)) throw new DashboardProblem(401, "Cần đăng nhập lại.");
        await using var command = Command(connection, """
            SELECT r.KyHieuVaiTro,t.MaBuuCuc,q.KyHieuQuyen
            FROM dbo.TaiKhoan t JOIN dbo.VaiTro r ON r.MaVaiTro=t.MaVaiTro
            LEFT JOIN dbo.VaiTroQuyen p ON p.MaVaiTro=r.MaVaiTro LEFT JOIN dbo.Quyen q ON q.MaQuyen=p.MaQuyen
            WHERE t.MaTaiKhoan=@account AND t.TrangThaiTaiKhoan='ACTIVE' AND r.DangHoatDong=1
              AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=SYSUTCDATETIME());
            """);
        command.Parameters.Add("@account", SqlDbType.BigInt).Value = accountId;
        Scope? scope = null;
        await using (var reader = await command.ExecuteReaderAsync(ct))
            while (await reader.ReadAsync(ct))
            {
                scope ??= new(reader.GetString(0), reader.IsDBNull(1) ? null : reader.GetInt32(1), []);
                if (!reader.IsDBNull(2)) scope.Grants.Add(reader.GetString(2));
            }
        if (scope is null) throw new DashboardProblem(401, "Tài khoản không còn hoạt động.");
        if (scope.Role == "SHIPPER" || (scope.Role != "ADMIN" && (scope.BranchId is null || (branchId.HasValue && branchId != scope.BranchId))))
            throw new DashboardProblem(403, "Bạn chỉ được xem tổng quan trong phạm vi bưu cục được cấp.");
        scope = scope with { BranchId = scope.Role == "ADMIN" ? branchId : scope.BranchId };
        if (scope.BranchId.HasValue)
        {
            await using var check = Command(connection, "SELECT COUNT(*) FROM dbo.BuuCuc WHERE MaBuuCuc=@branch;");
            check.Parameters.Add("@branch", SqlDbType.Int).Value = scope.BranchId.Value;
            if (Convert.ToInt32(await check.ExecuteScalarAsync(ct)) != 1) throw new DashboardProblem(404, "Không tìm thấy bưu cục.");
        }
        return scope;
    }
    private static void BranchParameter(SqlCommand command, Scope scope) => command.Parameters.Add("@branch", SqlDbType.Int).Value = (object?)scope.BranchId ?? DBNull.Value;

    [HttpGet("context")]
    public async Task<IActionResult> Context([FromQuery, Range(1, int.MaxValue)] int? branchId = null, CancellationToken ct = default)
    {
        await using var connection = Connection(); await connection.OpenAsync(ct);
        var scope = await AuthorizeScope(connection, branchId, ct);
        await using var command = Command(connection, "SELECT MaBuuCuc,TenBuuCuc FROM dbo.BuuCuc WHERE @admin=1 OR MaBuuCuc=@branch ORDER BY MaBuuCuc;");
        BranchParameter(command, scope); command.Parameters.Add("@admin", SqlDbType.Bit).Value = scope.Role == "ADMIN";
        var branches = new List<object>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct)) branches.Add(new { id = reader.GetInt32(0), name = reader.GetString(1) });
        return Ok(new { branchId = scope.BranchId, canChangeBranch = scope.Role == "ADMIN", branches,
            permissions = new { waitingInbound = scope.Inbound, waitingAssignment = scope.Dispatch, inDelivery = scope.Orders, failedNeedsAction = scope.Orders,
                inWarehouse = scope.Inbound, waitingHandover = scope.Inbound, overdue = scope.Orders,
                delivery = scope.Delivery, cod = scope.Can("COD_DOISOAT"), reports = scope.Can("BAOCAO_XEM") }, generatedAtUtc = DateTime.UtcNow });
    }

    [HttpGet("operations")]
    public async Task<IActionResult> Operations([FromQuery, Range(1, int.MaxValue)] int? branchId = null, CancellationToken ct = default)
    {
        await using var connection = Connection(); await connection.OpenAsync(ct); var scope = await AuthorizeScope(connection, branchId, ct);
        if (!scope.Orders) throw new DashboardProblem(403, "Bạn chưa có quyền xem chỉ số đơn hàng.");
        await using var command = Command(connection, $$"""
            SET NOCOUNT ON;
            SELECT d.MaDonHang id,d.MaVanDon code,d.KyHieuDonHang orderCode,d.ThoiGianDuKienGiao deadlineAt,
                d.ThoiGianCapNhat updatedAt,
                CONVERT(BIT,CASE WHEN {{OperationalOrderQuery.WaitingInbound}} THEN 1 ELSE 0 END) waitingInbound,
                CONVERT(BIT,CASE WHEN {{OperationalOrderQuery.WaitingAssignment}} THEN 1 ELSE 0 END) waitingAssignment,
                CONVERT(BIT,CASE WHEN {{OperationalOrderQuery.InWarehouse}} THEN 1 ELSE 0 END) inWarehouse,
                CONVERT(BIT,CASE WHEN {{OperationalOrderQuery.WaitingHandover}} THEN 1 ELSE 0 END) waitingHandover,
                CONVERT(BIT,CASE WHEN {{OperationalOrderQuery.Overdue}} THEN 1 ELSE 0 END) overdue,
                CONVERT(BIT,CASE WHEN {{OperationalOrderQuery.InDelivery}} THEN 1 ELSE 0 END) inDelivery,
                CONVERT(BIT,CASE WHEN {{OperationalOrderQuery.FailedNeedsAction}} THEN 1 ELSE 0 END) failedNeedsAction
            INTO #Operations FROM dbo.DonHang d JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
            WHERE @branch IS NULL OR d.MaBuuCuc=@branch;
            SELECT (SELECT @branch branchId,SYSUTCDATETIME() generatedAtUtc,
              JSON_QUERY((SELECT
                CASE WHEN @inbound=1 THEN COUNT_BIG(CASE WHEN waitingInbound=1 THEN 1 END) END waitingInbound,
                CASE WHEN @dispatch=1 THEN COUNT_BIG(CASE WHEN waitingAssignment=1 THEN 1 END) END waitingAssignment,
                CASE WHEN @inbound=1 THEN COUNT_BIG(CASE WHEN inWarehouse=1 THEN 1 END) END inWarehouse,
                CASE WHEN @inbound=1 THEN COUNT_BIG(CASE WHEN waitingHandover=1 THEN 1 END) END waitingHandover,
                COUNT_BIG(CASE WHEN overdue=1 THEN 1 END) overdue,
                COUNT_BIG(CASE WHEN inDelivery=1 THEN 1 END) inDelivery,
                COUNT_BIG(CASE WHEN failedNeedsAction=1 THEN 1 END) failedNeedsAction
                FROM #Operations FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER)) metrics,
              JSON_QUERY(COALESCE((SELECT TOP(5) o.id,o.code,o.orderCode,
                CASE WHEN o.failedNeedsAction=1 THEN 'FAILED' WHEN o.waitingAssignment=1 THEN 'OVERDUE_DISPATCH' ELSE 'OVERDUE' END kind,
                CASE WHEN o.failedNeedsAction=1 THEN 0 ELSE 1 END priority,
                CASE WHEN o.failedNeedsAction=1 THEN lastAttempt.attemptAt ELSE o.deadlineAt END dueAt,
                COALESCE(shipper.HoTen,recipient.TenNguoiLienHe) person,recipient.TenNguoiLienHe receiverName
                FROM #Operations o
                OUTER APPLY(SELECT TOP(1) g.TenNguoiLienHe FROM dbo.DiemGiaoNhan g WHERE g.MaDonHang=o.id AND g.LoaiDiem='DELIVERY') recipient
                OUTER APPLY(SELECT TOP(1) p.MaNhanVienGiaoHang FROM dbo.PhanCongGiaoHang p WHERE p.MaDonHang=o.id AND p.ThoiGianKetThuc IS NULL ORDER BY p.MaPhanCongGiaoHang DESC) currentAssignment
                LEFT JOIN dbo.NhanVienGiaoHang employee ON employee.MaNhanVienGiaoHang=currentAssignment.MaNhanVienGiaoHang
                LEFT JOIN dbo.TaiKhoan shipper ON shipper.MaTaiKhoan=employee.MaTaiKhoan
                OUTER APPLY(SELECT TOP(1) g.ThoiGianThuGiao attemptAt FROM dbo.LanGiaoHang g WHERE g.MaDonHang=o.id ORDER BY g.SoLanThu DESC) lastAttempt
                WHERE (@dispatch=1 AND o.waitingAssignment=1 AND o.overdue=1)
                  OR (@handleFailed=1 AND o.failedNeedsAction=1)
                  OR (@handleFailed=1 AND o.overdue=1 AND o.waitingAssignment=0)
                ORDER BY priority,dueAt,o.id FOR JSON PATH,INCLUDE_NULL_VALUES),N'[]')) tasks
              FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
            """);
        BranchParameter(command, scope); command.Parameters.Add("@inbound", SqlDbType.Bit).Value = scope.Inbound;
        command.Parameters.Add("@dispatch", SqlDbType.Bit).Value = scope.Dispatch;
        command.Parameters.Add("@handleFailed", SqlDbType.Bit).Value = scope.Can("DONHANG_CAPNHAT");
        return Content((string)(await command.ExecuteScalarAsync(ct))!, "application/json");
    }

    [HttpGet("delivery-today")]
    public async Task<IActionResult> DeliveryToday([FromQuery, Range(1, int.MaxValue)] int? branchId = null, CancellationToken ct = default)
    {
        await using var connection = Connection(); await connection.OpenAsync(ct); var scope = await AuthorizeScope(connection, branchId, ct);
        if (!scope.Delivery) throw new DashboardProblem(403, "Bạn chưa có quyền xem kết quả giao hàng.");
        var day = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(7));
        var from = new DateTimeOffset(day.ToDateTime(TimeOnly.MinValue), TimeSpan.FromHours(7)).UtcDateTime;
        await using var command = Command(connection, """
            SELECT (SELECT @branch branchId,@day [date],@from fromUtc,@to toUtcExclusive,SYSUTCDATETIME() generatedAtUtc,
                COUNT_BIG(*) attemptCount,COUNT_BIG(CASE WHEN g.KetQua='SUCCESS' THEN 1 END) successfulCount,
                COUNT_BIG(CASE WHEN g.KetQua='FAILED' THEN 1 END) failedCount,
                CONVERT(DECIMAL(5,2),100.0*COUNT_BIG(CASE WHEN g.KetQua='SUCCESS' THEN 1 END)/NULLIF(COUNT_BIG(*),0)) successRatePercent
            FROM dbo.LanGiaoHang g JOIN dbo.DonHang d ON d.MaDonHang=g.MaDonHang
            JOIN dbo.PhanCongGiaoHang p ON p.MaPhanCongGiaoHang=g.MaPhanCongGiaoHang AND p.MaDonHang=g.MaDonHang
            WHERE (@branch IS NULL OR d.MaBuuCuc=@branch) AND g.ThoiGianThuGiao>=@from AND g.ThoiGianThuGiao<@to
            FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
            """);
        BranchParameter(command, scope); command.Parameters.Add("@day", SqlDbType.Date).Value = day.ToDateTime(TimeOnly.MinValue);
        command.Parameters.Add("@from", SqlDbType.DateTime2).Value = from; command.Parameters.Add("@to", SqlDbType.DateTime2).Value = from.AddDays(1);
        return Content((string)(await command.ExecuteScalarAsync(ct))!, "application/json");
    }
}
