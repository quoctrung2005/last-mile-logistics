using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace LastMile.Api.Controllers;

[ApiController, Authorize, Route("api/v1/cod")]
public class CodFormController(IConfiguration configuration) : ControllerBase
{
    [HttpGet("options")]
    public Task<IActionResult> Options(CancellationToken cancellationToken) => Read("""
        SELECT (SELECT
            JSON_QUERY((SELECT b.MaBuuCuc AS id,b.TenBuuCuc AS name,b.DangHoatDong AS isActive FROM dbo.BuuCuc b
                WHERE @Role='ADMIN' OR b.MaBuuCuc=@AccountBranchId ORDER BY b.TenBuuCuc FOR JSON PATH)) AS branches,
            JSON_QUERY(COALESCE((SELECT n.MaNhanVienGiaoHang AS id,n.MaNhanVien AS code,t.HoTen AS name,t.MaBuuCuc AS branchId,
                CAST(CASE WHEN n.DangHoatDong=1 AND t.TrangThaiTaiKhoan='ACTIVE' AND v.DangHoatDong=1 AND v.KyHieuVaiTro='SHIPPER'
                    AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=SYSUTCDATETIME()) THEN 1 ELSE 0 END AS BIT) AS canOperate
                FROM dbo.NhanVienGiaoHang n JOIN dbo.TaiKhoan t ON t.MaTaiKhoan=n.MaTaiKhoan JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro
                WHERE (@Role<>'SHIPPER' OR n.MaNhanVienGiaoHang=@OwnShipperId)
                  AND (@Role='ADMIN' OR t.MaBuuCuc=@AccountBranchId OR EXISTS (
                    SELECT 1 FROM dbo.ThuTienCOD c JOIN dbo.DonHang d ON d.MaDonHang=c.MaDonHang
                    WHERE c.MaNhanVienGiaoHang=n.MaNhanVienGiaoHang AND d.MaBuuCuc=@AccountBranchId))
                ORDER BY t.HoTen,n.MaNhanVienGiaoHang FOR JSON PATH),N'[]')) AS shippers,
            @OwnShipperId AS ownShipperId,
            CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.VaiTroQuyen v JOIN dbo.Quyen q ON q.MaQuyen=v.MaQuyen
                WHERE v.MaVaiTro=@RoleId AND q.KyHieuQuyen='COD_NOPTIEN') THEN 1 ELSE 0 END AS BIT) AS canCreateDeposit,
            CAST(CASE WHEN @Role<>'SHIPPER' THEN 1 ELSE 0 END AS BIT) AS canReconcile
            FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
        """, null, null, null, null, 1, 10, cancellationToken);

    [HttpGet("reconciliations/preview")]
    public Task<IActionResult> Preview(
        [FromQuery, Range(1,int.MaxValue)] int branchId,
        [FromQuery, Range(1,long.MaxValue)] long shipperId,
        [FromQuery, Required] DateTimeOffset? from,
        [FromQuery, Required] DateTimeOffset? to,
        [FromQuery, Range(1,100000)] int page=1,
        [FromQuery, Range(1,100)] int pageSize=10,
        CancellationToken cancellationToken=default)
    {
        var error=CodQuerySupport.DateError(from,to);
        if (error is not null) return Task.FromResult<IActionResult>(BadRequest(new {message=error}));
        return Read("""
            IF @Role='SHIPPER' THROW 57702,N'Bạn không có quyền tạo đối soát.',1;
            IF NOT EXISTS(SELECT 1 FROM dbo.NhanVienGiaoHang n JOIN dbo.TaiKhoan t ON t.MaTaiKhoan=n.MaTaiKhoan
                JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro JOIN dbo.BuuCuc b ON b.MaBuuCuc=t.MaBuuCuc
                WHERE n.MaNhanVienGiaoHang=@ShipperId AND t.MaBuuCuc=@BranchId AND n.DangHoatDong=1
                  AND t.TrangThaiTaiKhoan='ACTIVE' AND v.KyHieuVaiTro='SHIPPER' AND v.DangHoatDong=1 AND b.DangHoatDong=1)
                THROW 57704,N'Shipper hoặc bưu cục không còn đủ điều kiện tạo phiên.',1;
            SELECT c.MaDonHang AS orderId,d.KyHieuDonHang AS orderCode,d.MaVanDon AS trackingNumber,
                c.SoTienPhaiThu AS expectedAmount,c.SoTienThucThu AS collectedAmount,c.ThoiGianThuTien AS collectedAt,
                p.depositedAmount,r.reconciliationCode
            INTO #Candidates
            FROM dbo.ThuTienCOD c JOIN dbo.DonHang d ON d.MaDonHang=c.MaDonHang
            OUTER APPLY(SELECT CONVERT(DECIMAL(28,2),COALESCE(SUM(ct.SoTienPhanBo),0)) AS depositedAmount
                FROM dbo.ChiTietNopTienCOD ct JOIN dbo.NopTienCOD n ON n.MaNopTienCOD=ct.MaNopTienCOD
                WHERE ct.MaDonHang=c.MaDonHang AND n.MaNhanVienGiaoHang=@ShipperId AND n.MaBuuCuc=@BranchId AND n.TrangThaiNop='CONFIRMED') p
            OUTER APPLY(SELECT TOP(1) ds.KyHieuDoiSoat AS reconciliationCode FROM dbo.ChiTietDoiSoatCOD ct
                JOIN dbo.DoiSoatCOD ds ON ds.MaDoiSoatCOD=ct.MaDoiSoatCOD
                WHERE ct.MaDonHang=c.MaDonHang AND ds.TrangThaiDoiSoat<>'CANCELLED' ORDER BY ds.MaDoiSoatCOD) r
            WHERE c.MaNhanVienGiaoHang=@ShipperId AND d.MaBuuCuc=@BranchId AND c.TrangThaiThuTien IN ('COLLECTED','PARTIAL')
              AND c.ThoiGianThuTien>=@From AND c.ThoiGianThuTien<@To;
            SELECT (SELECT @Page AS page,@PageSize AS pageSize,(SELECT COUNT_BIG(*) FROM #Candidates) AS totalItems,
                JSON_QUERY((SELECT COALESCE(SUM(expectedAmount),0) AS totalExpected,COALESCE(SUM(collectedAmount),0) AS totalCollected,
                    COALESCE(SUM(depositedAmount),0) AS totalDeposited,COUNT_BIG(CASE WHEN reconciliationCode IS NOT NULL THEN 1 END) AS blockedCount
                    FROM #Candidates FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) AS summary,
                JSON_QUERY(COALESCE((SELECT * FROM #Candidates ORDER BY orderId OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY
                    FOR JSON PATH,INCLUDE_NULL_VALUES),N'[]')) AS items
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
            """,branchId,shipperId,from,to,page,pageSize,cancellationToken);
    }

    private async Task<IActionResult> Read(string sql,int? branchId,long? shipperId,DateTimeOffset? from,DateTimeOffset? to,int page,int pageSize,CancellationToken token)
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out var actor)) return Unauthorized();
        await using var connection=new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
        await using var command=new SqlCommand(CodQuerySupport.ScopeSql+sql,connection);
        command.Parameters.Add("@AccountId",SqlDbType.BigInt).Value=actor;
        command.Parameters.Add("@BranchId",SqlDbType.Int).Value=(object?)branchId??DBNull.Value;
        command.Parameters.Add("@ShipperId",SqlDbType.BigInt).Value=(object?)shipperId??DBNull.Value;
        command.Parameters.Add("@From",SqlDbType.DateTime2).Value=(object?)from?.UtcDateTime??DBNull.Value;
        command.Parameters.Add("@To",SqlDbType.DateTime2).Value=(object?)to?.UtcDateTime??DBNull.Value;
        command.Parameters.Add("@Page",SqlDbType.Int).Value=page;
        command.Parameters.Add("@PageSize",SqlDbType.Int).Value=pageSize;
        command.Parameters.Add("@Offset",SqlDbType.Int).Value=(page-1)*pageSize;
        try { await connection.OpenAsync(token); var result=await command.ExecuteScalarAsync(token); return Content(result?.ToString()??"{}","application/json"); }
        catch(SqlException ex) when(ex.Number is >=57701 and <=57704)
        { return StatusCode(ex.Number==57701?401:ex.Number==57702?403:409,new {message=ex.Message}); }
    }
}
